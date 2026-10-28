-- Funil de reativação Starnex: eventos do quiz
-- Rodar no SQL Editor do projeto "Starnex lp e CRM"

create table if not exists public.funil_reativacao_eventos (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  session_id  text not null,
  lead_ref    text,                       -- valor do ?l= do link enviado ao lead (id do lead no CRM)
  evento      text not null,              -- pagina_aberta | quiz_iniciado | quiz_concluido | material_baixado | agenda_aberta | whatsapp_click
  payload     jsonb not null default '{}'::jsonb,
  utm         jsonb not null default '{}'::jsonb
);

create index if not exists funil_eventos_lead_idx    on public.funil_reativacao_eventos (lead_ref);
create index if not exists funil_eventos_evento_idx  on public.funil_reativacao_eventos (evento, created_at desc);

alter table public.funil_reativacao_eventos enable row level security;

-- A página pública só pode INSERIR, e só eventos conhecidos com payload de tamanho razoável.
drop policy if exists "funil insere eventos" on public.funil_reativacao_eventos;
create policy "funil insere eventos"
  on public.funil_reativacao_eventos
  for insert
  to anon
  with check (
    evento in ('pagina_aberta','quiz_iniciado','quiz_concluido','material_baixado','agenda_aberta','whatsapp_click')
    and length(payload::text) < 4000
    and length(session_id) < 80
  );

-- Leitura só para usuários autenticados (o CRM).
drop policy if exists "crm le eventos" on public.funil_reativacao_eventos;
create policy "crm le eventos"
  on public.funil_reativacao_eventos
  for select
  to authenticated
  using (true);

-- Visão pronta para o CRM: um registro por sessão com a etapa mais avançada atingida.
create or replace view public.funil_reativacao_resumo
with (security_invoker = true) as
select
  session_id,
  max(lead_ref)                                              as lead_ref,
  min(created_at)                                            as primeiro_acesso,
  max(created_at)                                            as ultimo_evento,
  case
    when bool_or(evento = 'agenda_aberta' or evento = 'whatsapp_click') then 'pediu_plano'
    when bool_or(evento = 'quiz_concluido')                                then 'quiz_concluido'
    when bool_or(evento = 'quiz_iniciado')                                 then 'quiz_iniciado'
    else 'abriu_pagina'
  end                                                        as etapa,
  (array_agg(payload order by created_at desc) filter (where evento = 'quiz_concluido'))[1] as respostas
from public.funil_reativacao_eventos
group by session_id;
