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
--   4) presentes_buscar_personas: busca a la persona por el DNI que lleva
--      adentro el CUIL, en la nómina y, si no está, en las inscripciones (de
--      ahí también el mail, si en la nómina no tiene). La usa sólo el servidor.
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
alter table public.contratos add column if not exists doc_nucleo     text;   -- el DNI de 8 números (el CUIL lo lleva adentro)

-- ── 2) Uno por persona y por fecha ──
--  Por el DNI (no por la ficha de la nómina): hay quien sólo está en las
--  inscripciones, y quien está en la nómina con el DNI y en la planilla con el CUIL.
drop index if exists public.contratos_planilla_unico;
create unique index if not exists contratos_planilla_doc
  on public.contratos (doc_nucleo, fecha_show)
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

-- ── 4) Buscar a la persona (sólo el servidor) ──
--  Por el DNI de 8 números que lleva adentro el CUIL: así la encuentra aunque en
--  la nómina esté sólo con el DNI, o en la planilla con otro prefijo. Primero en
--  la nómina (con el mail de su inscripción si en la nómina no tiene) y, si no
--  está, en las inscripciones del formulario. Un CUIL de 10 números se prueba de
--  las dos maneras posibles ("aproximado"): el servidor sólo lo acepta si el
--  apellido de la planilla coincide.
drop function if exists public.presentes_buscar_personas(text[]);
create function public.presentes_buscar_personas(p_cuils text[])
returns table (buscado text, como text, fuente text, id uuid, nombre text, email text, cuit text, nucleo text)
language sql stable security definer set search_path = public as $$
  with b as (
    select distinct d,
      case when length(d) = 11 then array[substr(d, 3, 8)]
           when length(d) between 7 and 8 then array[lpad(d, 8, '0')]
           when length(d) = 10 then array[substr(d, 3, 8), lpad(substr(d, 3, 7), 8, '0')]
           else array[]::text[] end as nucleos
    from (select regexp_replace(x, '\D', '', 'g') as d from unnest(p_cuils) x) t
  ),
  per as (
    select q.id, q.nombre, q.email, q.d,
           case when length(q.d) = 11 then substr(q.d, 3, 8) when length(q.d) between 7 and 8 then lpad(q.d, 8, '0') end as nucleo
    from (select pe.id, pe.nombre, pe.email, regexp_replace(coalesce(pe.cuit, ''), '\D', '', 'g') as d from public.personas pe) q
  ),
  ins as (
    select distinct on (n.nucleo) q.id, q.nombre, q.email, q.d, n.nucleo
    from (select s.id, s.nombre, s.email, s.created_at, regexp_replace(coalesce(s.cuit, ''), '\D', '', 'g') as d from public.solicitudes s) q
    cross join lateral (select case when length(q.d) = 11 then substr(q.d, 3, 8) when length(q.d) between 7 and 8 then lpad(q.d, 8, '0') end as nucleo) n
    where n.nucleo is not null
    order by n.nucleo, (nullif(q.email, '') is null), q.created_at desc nulls last
  )
  select b.d,
         case when length(b.d) = 11 and per.d = b.d then 'exacto' when length(b.d) = 10 then 'aproximado' else 'dni' end,
         'nomina', per.id, per.nombre,
         coalesce(nullif(per.email, ''), (select nullif(i.email, '') from ins i where i.nucleo = per.nucleo)), per.d, per.nucleo
  from b join per on per.nucleo = any(b.nucleos)
  union all
  select b.d,
         case when length(b.d) = 11 and ins.d = b.d then 'exacto' when length(b.d) = 10 then 'aproximado' else 'dni' end,
         'inscripcion', null::uuid, ins.nombre, nullif(ins.email, ''), ins.d, ins.nucleo
  from b join ins on ins.nucleo = any(b.nucleos)
  where not exists (select 1 from per where per.nucleo = ins.nucleo);
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
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'contratos_planilla_doc')                                 as uno_por_fecha,
  exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'planilla_presentes')                as planilla,
  not has_function_privilege('anon', 'public.presentes_buscar_personas(text[])', 'execute')                                           as busqueda_privada,
  exists (select 1 from public.config where key = 'contratos_presentes')                                                                as montos;
