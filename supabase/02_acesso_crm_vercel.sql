-- ============================================================
-- STARNEX · Acesso do CRM fora do Claude (Vercel)
--
-- Antes: qualquer usuário logado no Supabase lia, editava e apagava leads.
-- Agora: só quem está logado E está na lista crm_usuarios.
--
-- Não afeta:
--   - o CRM aberto dentro do Claude (o conector usa a chave de administrador);
--   - a LP de odonto (grava pela função ingest-lead, no servidor);
--   - o funil (grava pela função registrar_interesse_diagnostico).
--
-- Para liberar alguém:  insert into public.crm_usuarios (email) values ('email@dominio.com');
-- ============================================================

create table if not exists public.crm_usuarios (email text primary key);
alter table public.crm_usuarios enable row level security;   -- a lista não é lida pela API

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
revoke all on function public.is_crm_user() from public;
grant execute on function public.is_crm_user() to authenticated;

-- Substitui as regras antigas ("qualquer autenticado") pela regra da equipe
do $$
declare t text; pol record;
begin
  foreach t in array array['leads','pipelines','pipeline_estagios','atividades','canais'] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      for pol in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
        execute format('drop policy %I on public.%I', pol.policyname, t);
      end loop;
      execute format(
        'create policy "crm equipe" on public.%I for all to authenticated using (public.is_crm_user()) with check (public.is_crm_user())', t);
    end if;
  end loop;
end $$;

-- O CRM pode ler os eventos do funil
drop policy if exists "crm le eventos" on public.funil_reativacao_eventos;
create policy "crm le eventos" on public.funil_reativacao_eventos
  for select to authenticated using (public.is_crm_user());
