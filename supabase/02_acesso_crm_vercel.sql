-- ============================================================
-- STARNEX · Acesso do CRM fora do Claude (Vercel)
-- Rodar DEPOIS do 01, antes de usar o CRM pelo link do Vercel.
--
-- O que faz:
--   - cria a lista de e-mails que podem usar o CRM;
--   - liga as regras de acesso (RLS) nas tabelas do CRM;
--   - só quem está logado E está na lista lê e edita os leads.
--
-- O CRM aberto dentro do Claude continua funcionando igual,
-- porque o conector usa a chave de administrador.
-- ============================================================

-- 1) Quem pode usar o CRM. TROQUE pelo seu e-mail de login.
create table if not exists public.crm_usuarios (email text primary key);
insert into public.crm_usuarios (email) values ('SEU_EMAIL_AQUI') on conflict do nothing;
alter table public.crm_usuarios enable row level security;   -- ninguém lê essa lista pela API

create or replace function public.is_crm_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.crm_usuarios
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_crm_user() to authenticated;

-- 2) Regras de acesso nas tabelas do CRM
do $$
declare t text;
begin
  foreach t in array array['leads','pipelines','pipeline_estagios','atividades','canais'] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('drop policy if exists "crm equipe" on public.%I', t);
      execute format(
        'create policy "crm equipe" on public.%I for all to authenticated using (public.is_crm_user()) with check (public.is_crm_user())', t);
    end if;
  end loop;
end $$;

-- 3) Mantém a LP de odonto gravando leads (ela usa a chave pública).
--    Só permite INSERIR; ninguém de fora consegue ler a base.
drop policy if exists "lp insere leads" on public.leads;
create policy "lp insere leads" on public.leads for insert to anon with check (true);

-- Leitura do resumo do funil pelo CRM
drop policy if exists "crm le eventos" on public.funil_reativacao_eventos;
create policy "crm le eventos" on public.funil_reativacao_eventos
  for select to authenticated using (public.is_crm_user());
