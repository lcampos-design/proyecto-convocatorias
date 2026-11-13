-- ============================================================
--  CONTRATOS POR PRESENTE (Arena, 13-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Pedido de los socios: el contrato se manda sólo a quien tiene el presente.
--  Los presentes se toman en las planillas "SUPERVISORES dd/mm "SHOW"" de
--  Google Sheets; un script de la cuenta de convocatorias del Arena las mira
--  cada 5 minutos y le pasa a la plataforma (api/presentes-planilla) quién
--  tiene "P" y quién "A". Con una "P", la plataforma manda el contrato de
--  esa fecha (uno por fecha); si después la pasan a "A" o le sacan la "P" y
--  todavía no firmó, el contrato se anula.
--
--  Lo que agrega:
--   1) En cada contrato: la fecha del show, de dónde salió (la planilla) y
--      el sector; y cuándo y por qué se anuló. "Anulado" es un estado más:
--      el link vence en ese momento, así que ya no se puede firmar.
--   2) Un contrato por persona y por fecha (los anulados no cuentan).
--   3) planilla_presentes: lo último que dijo la planilla de cada persona en
--      cada fecha y qué hizo la plataforma (enviado, anulado, o por qué no
--      se pudo: no está en la nómina, CUIL incompleto, sin mail, sin monto…).
--      La ve sólo el panel.
--   4) presentes_buscar_personas: busca en la nómina por CUIL (o por DNI,
--      si la planilla trae sólo el DNI). La usa sólo el servidor.
--   5) config.contratos_presentes: qué puesto lleva cada fila y el monto de
--      cada puesto por mes (se cambian desde el panel). Todos son Orientador,
--      menos el bloque de Supervisores (Supervisor; el "Coordinador" de ese
--      bloque, Coordinador on site), el P.Point (Recepciones premium; el que
--      dice "Firmas" en OBSERVACIÓN, Firmas) y Cargas. Ya trae los montos de
--      noviembre de 2026. Un mes sin montos: sus contratos no salen y quedan
--      como "falta el monto".
-- ============================================================

-- ── 1) Los contratos de la planilla ──
alter table public.contratos add column if not exists fecha_show     date;
alter table public.contratos add column if not exists origen         text;   -- 'planilla' (o vacío: desde el panel)
alter table public.contratos add column if not exists sector         text;   -- el de la planilla (ANILLO, BOWL…)
alter table public.contratos add column if not exists anulado_at     timestamptz;
alter table public.contratos add column if not exists anulado_motivo text;

-- ── 2) Uno por persona y por fecha ──
create unique index if not exists contratos_planilla_unico
  on public.contratos (persona_id, fecha_show)
  where origen = 'planilla' and estado <> 'anulado';
create index if not exists contratos_fecha_show_idx on public.contratos (fecha_show) where fecha_show is not null;

-- ── 3) Lo que dijo la planilla ──
create table if not exists public.planilla_presentes (
  id           bigint generated always as identity primary key,
  fecha        date not null,
  show         text,
  archivo_id   text,                 -- la planilla de Google (para abrirla desde el panel)
  sector       text,
  cuil         text not null,        -- tal cual viene (sólo los números)
  apellido     text,
  nombre       text,
  marca        text,                 -- 'P', 'A' o vacío
  persona_id   uuid references public.personas(id) on delete set null,
  contrato_id  uuid references public.contratos(id) on delete set null,
  resultado    text,                 -- enviado | ya_tenia | firmado | anulado | firmado_ausente | sin_persona | cuil_incompleto | sin_mail | sin_monto | sin_show | sin_plantilla | error_mail | pendiente | ausente
  detalle      text,
  actualizado  timestamptz not null default now(),
  unique (fecha, cuil)
);
create index if not exists planilla_presentes_fecha_idx on public.planilla_presentes (fecha);
alter table public.planilla_presentes enable row level security;
revoke all on public.planilla_presentes from anon, public;
grant select on public.planilla_presentes to authenticated;
drop policy if exists planilla_presentes_admin on public.planilla_presentes;
create policy planilla_presentes_admin on public.planilla_presentes
  for select to authenticated using (public.es_admin());

-- ── 4) Buscar en la nómina por CUIL o por DNI (sólo el servidor) ──
create or replace function public.presentes_buscar_personas(p_cuils text[])
returns table (buscado text, id uuid, nombre text, email text, cuit text)
language sql stable security definer set search_path = public as $$
  with b as (select distinct regexp_replace(x, '\D', '', 'g') as d from unnest(p_cuils) x),
       p as (select pe.id, pe.nombre, pe.email, regexp_replace(coalesce(pe.cuit, ''), '\D', '', 'g') as d from public.personas pe)
  select b.d, p.id, p.nombre, p.email, p.d
  from b join p on (length(b.d) = 11 and p.d = b.d)
               or (length(b.d) between 7 and 8 and length(p.d) = 11 and substr(p.d, 3, 8) = lpad(b.d, 8, '0'));
$$;
revoke execute on function public.presentes_buscar_personas(text[]) from public, anon, authenticated;
grant  execute on function public.presentes_buscar_personas(text[]) to service_role;

-- ── 5) Los puestos y los montos (se cambian desde el panel) ──
--  Si ya estaba y tiene montos cargados, no se toca.
insert into public.config (key, value, updated_at)
values ('contratos_presentes', '{
  "venue": "Movistar Arena",
  "porDefecto": "Orientador",
  "sectores": { "Supervisores": "Supervisor", "P.Point": "Recepciones premium", "Recepciones": "Recepciones premium", "Firmas": "Firmas", "Cargas": "Cargas" },
  "roles": { "Firmas": "Firmas", "Firma": "Firmas", "Cargas": "Cargas", "Carga": "Cargas", "Coordinador": "Coordinador on site" },
  "meses": { "2026-11": { "puestos": {
    "Orientador": 34432, "Recepciones premium": 36284, "Firmas": 47833,
    "Supervisor": 48685, "Coordinador on site": 59115, "Cargas": 43250 } } }
}'::jsonb, now())
on conflict (key) do update set value = excluded.value, updated_at = now()
  where coalesce(public.config.value -> 'meses', '{}'::jsonb) = '{}'::jsonb;

-- ── CÓMO QUEDÓ ──
--  Tiene que dar todo true.
select
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'fecha_show') as contratos_con_fecha,
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'contratos_planilla_unico')                              as uno_por_fecha,
  exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'planilla_presentes')                as planilla,
  not has_function_privilege('anon', 'public.presentes_buscar_personas(text[])', 'execute')                                           as busqueda_privada,
  exists (select 1 from public.config where key = 'contratos_presentes')                                                                as montos;
