-- ============================================================
-- STARNEX · Funil Diagnóstico → CRM
-- Já aplicado em 28/10/2026. Rodar UMA vez no SQL Editor do projeto "Starnex lp e CRM".
-- É aditivo: não apaga nada e não muda as regras de acesso atuais.
-- ============================================================

-- 5) Permite o tipo de atividade "diagnostico" (usado pela função do funil)
alter table public.atividades drop constraint if exists atividades_tipo_check;
alter table public.atividades add constraint atividades_tipo_check
  check (tipo = any (array['nota','mudanca_estagio','whatsapp','ligacao','diagnostico']));

-- 1) Diagnóstico do quiz guardado no próprio lead
alter table public.leads add column if not exists diagnostico    jsonb;
alter table public.leads add column if not exists diagnostico_em timestamptz;

-- 2) Pipeline "Funil Diagnóstico" e suas etapas
do $$
declare
  v_pipe public.pipelines.id%type;
begin
  select id into v_pipe from public.pipelines where nome = 'Funil Diagnóstico' limit 1;
  if v_pipe is null then
    insert into public.pipelines (nome) values ('Funil Diagnóstico') returning id into v_pipe;
  end if;

  insert into public.pipeline_estagios (pipeline_id, nome, ordem, is_ganho, is_perdido)
  select v_pipe, s.nome, s.ordem, s.ganho, s.perdido
  from (values
    ('Interessado no diagnóstico', 1, false, false),
    ('Call agendada',              2, false, false),
    ('Call realizada',             3, false, false),
    ('Plano enviado',              4, false, false),
    ('Proposta',                   5, false, false),
    ('Fechado',                    6, true,  false),
    ('Perdido',                    7, false, true)
  ) as s(nome, ordem, ganho, perdido)
  where not exists (
    select 1 from public.pipeline_estagios e where e.pipeline_id = v_pipe and e.nome = s.nome
  );
end $$;

-- 3) Função chamada pelo funil público.
--    Roda com permissão do dono (security definer), então a página pública
--    não precisa de acesso nenhum à tabela de leads. Não devolve dados.
create or replace function public.registrar_interesse_diagnostico(
  p_lead_ref    text,
  p_nome        text,
  p_whatsapp    text,
  p_clinica     text,
  p_cidade      text,
  p_segmento    text,
  p_diagnostico jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stage public.pipeline_estagios.id%type;
  v_lead  public.leads.id%type;
  v_wpp   text;
  v_resumo text;
begin
  -- validação básica de tamanho
  if length(coalesce(p_clinica,''))  > 120 or length(coalesce(p_nome,''))     > 120
  or length(coalesce(p_cidade,''))   > 80  or length(coalesce(p_segmento,''))  > 80
  or length(coalesce(p_lead_ref,'')) > 64  or length(coalesce(p_diagnostico::text,'')) > 6000 then
    raise exception 'dados_invalidos';
  end if;
  if length(trim(coalesce(p_clinica,''))) < 2 then
    raise exception 'clinica_obrigatoria';
  end if;

  v_wpp := nullif(regexp_replace(coalesce(p_whatsapp,''), '\D', '', 'g'), '');
  if v_wpp is not null and (length(v_wpp) < 10 or length(v_wpp) > 13) then
    raise exception 'whatsapp_invalido';
  end if;

  select e.id into v_stage
  from public.pipeline_estagios e
  join public.pipelines p on p.id = e.pipeline_id
  where p.nome = 'Funil Diagnóstico' and e.nome = 'Interessado no diagnóstico'
  limit 1;
  if v_stage is null then
    raise exception 'etapa_nao_configurada';
  end if;

  -- 1º: lead que veio pelo link personalizado (?l=ID)
  if p_lead_ref is not null and p_lead_ref ~* '^[0-9a-f-]{32,36}$' then
    select id into v_lead from public.leads where id::text = lower(p_lead_ref) limit 1;
  end if;

  -- 2º: lead que já existe com o mesmo WhatsApp (compara DDD + número)
  if v_lead is null and v_wpp is not null then
    select id into v_lead
    from public.leads
    where length(regexp_replace(coalesce(whatsapp,''), '\D', '', 'g')) >= 10
      and right(regexp_replace(coalesce(whatsapp,''), '\D', '', 'g'), 10) = right(v_wpp, 10)
    order by criado_em desc
    limit 1;
  end if;

  v_resumo := concat_ws(' · ',
    p_diagnostico->>'maior_vazamento',
    case when p_diagnostico #>> '{estimativa,pacientes_min}' is not null
         then (p_diagnostico #>> '{estimativa,pacientes_min}') || ' a ' || (p_diagnostico #>> '{estimativa,pacientes_max}') || ' pacientes/mês' end
  );

  if v_lead is null then
    if v_wpp is null then
      raise exception 'whatsapp_obrigatorio';
    end if;
    insert into public.leads
      (nome_completo, whatsapp, cidade, segmento, especialidade, decisor_provavel, origem, estagio_id, diagnostico, diagnostico_em)
    values
      (trim(p_clinica), v_wpp, nullif(trim(p_cidade),''), nullif(trim(p_segmento),''), nullif(trim(p_segmento),''),
       nullif(trim(p_nome),''), 'Funil Diagnóstico', v_stage, p_diagnostico, now())
    returning id into v_lead;
  else
    update public.leads set
      estagio_id       = v_stage,
      diagnostico      = p_diagnostico,
      diagnostico_em   = now(),
      atualizado_em    = now(),
      whatsapp         = coalesce(nullif(whatsapp,''), v_wpp),
      cidade           = coalesce(nullif(cidade,''), nullif(trim(p_cidade),'')),
      segmento         = coalesce(nullif(segmento,''), nullif(trim(p_segmento),'')),
      decisor_provavel = coalesce(nullif(decisor_provavel,''), nullif(trim(p_nome),''))
    where id = v_lead;
  end if;

  insert into public.atividades (lead_id, tipo, conteudo)
  values (v_lead, 'diagnostico', 'Pediu o Plano de Recuperação pelo funil' || coalesce(' — ' || nullif(v_resumo,''), ''));

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.registrar_interesse_diagnostico(text,text,text,text,text,text,jsonb) from public;
grant execute on function public.registrar_interesse_diagnostico(text,text,text,text,text,text,jsonb) to anon, authenticated;

-- 4) Eventos de navegação do funil (aberturas, quiz, downloads)
create table if not exists public.funil_reativacao_eventos (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  session_id  text not null,
  lead_ref    text,
  evento      text not null,
  payload     jsonb not null default '{}'::jsonb,
  utm         jsonb not null default '{}'::jsonb
);
create index if not exists funil_eventos_lead_idx   on public.funil_reativacao_eventos (lead_ref);
create index if not exists funil_eventos_evento_idx on public.funil_reativacao_eventos (evento, created_at desc);
alter table public.funil_reativacao_eventos enable row level security;

drop policy if exists "funil insere eventos" on public.funil_reativacao_eventos;
create policy "funil insere eventos" on public.funil_reativacao_eventos
  for insert to anon, authenticated
  with check (
    evento in ('pagina_aberta','quiz_iniciado','quiz_concluido','material_baixado','plano_solicitado')
    and length(payload::text) < 6000
    and length(session_id) < 80
  );
