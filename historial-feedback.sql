-- ============================================================
--  HISTORIAL DEL AÑO Y FEEDBACK DE LOS NUEVOS (22-nov-2026)
--  Supabase → SQL Editor → pegar todo → Run. Se puede volver a correr: no borra ni duplica.
--
--  Lo que pidió RR. HH.:
--    · Cargar en qué shows estuvo cada uno este año (a mano o subiendo las planillas), para
--      tener todo el historial en la plataforma. Va en una tabla aparte (historial_shows):
--      no toca convocatorias, contratos ni presentes.
--    · Que el supervisor vea quién es nuevo: "Primera vez" (nunca fue a un show) y "Nuevo"
--      (su primer show en el área fue este mes: en el Arena, a los nuevos se los evalúa en
--      todas las fechas del mes). A los nuevos el feedback es obligatorio; a los que ya
--      vinieron, opcional, con lugar para dejar sólo un comentario si pasó algo.
--    · Cada feedback con la fecha del show (un show de varias fechas tiene uno por fecha) y
--      con el nombre de quien supervisó ese día (las cuentas de zona las usan varios).
--
--  La cuenta de "cuántos shows antes" junta todo lo que hay: lo cargado acá, los contratos
--  (sin los anulados), las planillas de presentes (P o E) y las convocatorias del panel en
--  las que quedó.
-- ============================================================

-- ── 0) El DNI que lleva adentro el CUIL (ya existe; se repite igual, por si acaso) ──
create or replace function public.doc_nucleo(p text)
returns text language sql immutable as $$
  select case
    when length(d) = 11 then nullif(ltrim(substr(d, 3, 8), '0'), '')
    when length(d) in (7, 8) then nullif(ltrim(d, '0'), '')
    else nullif(d, '') end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$$;

--  El área, siempre igual (en las convocatorias viejas puede estar escrita de otra forma).
create or replace function public.area_norm(p text)
returns text language sql immutable as $$
  select case
    when lower(coalesce(p, '')) like 'ext%' then 'externos'
    when lower(coalesce(p, '')) like 'esp%' or lower(coalesce(p, '')) in ('es', 'madrid') then 'espana'
    when lower(coalesce(p, '')) in ('ambas', 'ambas areas', 'todas') then 'ambas'
    else 'movistar_arena' end;
$$;

-- ── 1) Quién fue a qué show (cargado a mano o desde una planilla) ──
create table if not exists public.historial_shows (
  id          uuid primary key default gen_random_uuid(),
  area        text not null,                  -- movistar_arena | externos | espana
  evento      text not null,
  fecha       date not null,
  persona_id  uuid references public.personas(id) on delete set null,
  cuil        text,                           -- sólo los números, como vino
  doc         text,                           -- el DNI de adentro (para unir con la nómina)
  nombre      text,                           -- como vino (por si todavía no está en la nómina)
  puesto      text,
  origen      text not null default 'manual', -- manual | planilla
  archivo     text,                           -- el nombre de la planilla de la que salió
  creado_por  uuid,
  created_at  timestamptz not null default now(),
  constraint historial_shows_area check (area in ('movistar_arena', 'externos', 'espana'))
);
-- Una vez por persona, día y área: volver a subir la misma planilla no duplica.
create unique index if not exists historial_shows_unica on public.historial_shows (fecha, area, (coalesce(doc, persona_id::text)));
create index if not exists historial_shows_persona on public.historial_shows (persona_id);
create index if not exists historial_shows_doc on public.historial_shows (doc);
alter table public.historial_shows enable row level security;
revoke all on public.historial_shows from anon, public;
grant select, delete on public.historial_shows to authenticated;
drop policy if exists historial_shows_admin on public.historial_shows;
create policy historial_shows_admin on public.historial_shows
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- Cargar (desde el panel): una lista de filas { area, evento, fecha, persona_id, cuil, nombre,
-- puesto, origen, archivo }. Lo que ya estaba no se repite; quien vino sólo con el CUIL queda
-- unido a su ficha si está en la nómina.
create or replace function public.historial_cargar(p_filas jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_n int := 0; v_total int; v_filas jsonb;
begin
  if not public.es_admin() then return jsonb_build_object('ok', false, 'error', 'Sin permiso'); end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then return jsonb_build_object('ok', false, 'error', 'Sin filas'); end if;
  v_total := jsonb_array_length(p_filas);
  with f as (
    select nullif(btrim(x ->> 'area'), '') as area,
           nullif(btrim(x ->> 'evento'), '') as evento,
           case when coalesce(x ->> 'fecha', '') ~ '^\d{4}-\d{2}-\d{2}$' then (x ->> 'fecha')::date end as fecha,
           case when coalesce(x ->> 'persona_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (x ->> 'persona_id')::uuid end as persona_id,
           nullif(regexp_replace(coalesce(x ->> 'cuil', ''), '\D', '', 'g'), '') as cuil,
           nullif(btrim(x ->> 'nombre'), '') as nombre,
           nullif(btrim(x ->> 'puesto'), '') as puesto,
           case when x ->> 'origen' = 'planilla' then 'planilla' else 'manual' end as origen,
           nullif(btrim(x ->> 'archivo'), '') as archivo
      from jsonb_array_elements(p_filas) x
  ), g as (
    select f.*, p.id as pid,
           coalesce(public.doc_nucleo(f.cuil), public.doc_nucleo(p.cuit)) as d,
           coalesce(f.nombre, p.nombre) as nom
      from f left join public.personas p on p.id = f.persona_id
  ), ins as (
    insert into public.historial_shows (area, evento, fecha, persona_id, cuil, doc, nombre, puesto, origen, archivo, creado_por)
    select area, left(evento, 200), fecha, pid, cuil, d, left(nom, 200), left(puesto, 120), origen, left(archivo, 200), auth.uid()
      from g
     where area in ('movistar_arena', 'externos', 'espana') and evento is not null and fecha is not null
       and (pid is not null or d is not null)
    on conflict do nothing
    returning id
  )
  select count(*)::int, coalesce(jsonb_agg(id), '[]'::jsonb) into v_n, v_filas from ins;
  -- Quien vino sólo con el CUIL: unido a su ficha, si está en la nómina.
  update public.historial_shows h set persona_id = p.id
    from (select distinct on (public.doc_nucleo(cuit)) id, public.doc_nucleo(cuit) as d
            from public.personas where public.doc_nucleo(cuit) is not null
           order by public.doc_nucleo(cuit), created_at) p
   where h.persona_id is null and h.doc = p.d;
  -- Lo que entró, para que el panel lo sume sin volver a pedir todo.
  select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'area', h.area, 'evento', h.evento, 'fecha', h.fecha, 'persona_id', h.persona_id,
           'doc', h.doc, 'nombre', h.nombre, 'puesto', h.puesto, 'origen', h.origen, 'archivo', h.archivo, 'created_at', h.created_at)), '[]'::jsonb)
    into v_filas
    from public.historial_shows h where h.id in (select (x #>> '{}')::uuid from jsonb_array_elements(v_filas) x);
  return jsonb_build_object('ok', true, 'cargadas', v_n, 'recibidas', v_total, 'ya_estaban', v_total - v_n, 'filas', v_filas);
end $$;
revoke execute on function public.historial_cargar(jsonb) from public, anon;
grant  execute on function public.historial_cargar(jsonb) to authenticated;

-- ── 2) La fecha del show en cada feedback (y que una observación pueda ir sin puntaje) ──
alter table public.feedbacks add column if not exists fecha date;
alter table public.feedbacks alter column puntaje drop not null;

-- ── 3) La trayectoria de cada uno antes de una fecha ──
--  antes: en cuántos días de show estuvo antes de esa fecha (en cualquier área);
--  antes_area y primera_area: lo mismo en el área del show, y desde cuándo.
create or replace function public.trayectoria(p_personas uuid[], p_area text, p_hasta date, p_conv uuid default null)
returns table (persona_id uuid, antes int, antes_area int, primera_area date)
language sql stable security definer set search_path = public as $$
  with gente as (
    select p.id, public.doc_nucleo(p.cuit) as doc from public.personas p where p.id = any(p_personas)
  ), fechas as (
    -- lo cargado a mano o desde las planillas del año
    select g.id, h.area, h.fecha
      from public.historial_shows h join gente g on h.persona_id = g.id or (g.doc is not null and h.doc = g.doc)
    union
    -- los contratos (sin los anulados): la fecha del show o, si es de toda una convocatoria, su primera fecha
    select g.id, public.area_norm(c.area),
           coalesce(ct.fecha_show, (select min(btrim(f)::date) from unnest(string_to_array(coalesce(c.fecha, ''), ',')) f
                                     where btrim(f) ~ '^\d{4}-\d{2}-\d{2}$'))
      from public.contratos ct
      join gente g on ct.persona_id = g.id or (g.doc is not null and coalesce(ct.doc_nucleo, public.doc_nucleo(ct.cuil)) = g.doc)
      left join public.convocatorias c on c.id = ct.conv_id
     where coalesce(ct.estado, '') <> 'anulado'
    union
    -- las planillas de presentes (con P o E)
    select g.id, case when pp.area = 'externos' then 'externos' else 'movistar_arena' end, pp.fecha
      from public.planilla_presentes pp join gente g on g.doc is not null and public.doc_nucleo(pp.cuil) = g.doc
     where upper(coalesce(pp.marca, '')) in ('P', 'E')
    union
    -- las convocatorias del panel en las que quedó (no la de este show: de ésa cuentan los contratos y los presentes)
    select po.persona_id, public.area_norm(c.area), btrim(f)::date
      from public.postulaciones po
      join public.convocatorias c on c.id = po.conv_id
      cross join lateral unnest(string_to_array(coalesce(c.fecha, ''), ',')) f
     where po.persona_id = any(p_personas) and po.estado in ('aprobado', 'confirmado')
       and coalesce(po.asistencia, '') <> 'ausente' and po.conv_id is distinct from p_conv
       and btrim(f) ~ '^\d{4}-\d{2}-\d{2}$'
  )
  select g.id,
         (count(distinct f.fecha) filter (where f.fecha < p_hasta))::int,
         (count(distinct f.fecha) filter (where f.fecha < p_hasta and (f.area = p_area or f.area = 'ambas')))::int,
         min(f.fecha) filter (where f.fecha < p_hasta and (f.area = p_area or f.area = 'ambas'))
    from gente g left join fechas f on f.id = g.id
   group by g.id;
$$;
revoke execute on function public.trayectoria(uuid[], text, date, uuid) from public, anon, authenticated;

-- ── 4) El equipo en la app: quién es nuevo y qué feedback ya tiene ese día ──
--  Ahora recibe la fecha del show abierto (sin fecha, la de hoy).
drop function if exists public.sup_equipo(uuid);
create or replace function public.sup_equipo(p_conv_id uuid, p_fecha date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_dia  date := coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  v_area text;
  v_ids  uuid[];
begin
  if not exists (select 1 from public.supervisor_convocatorias
                 where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return '[]'::jsonb;
  end if;
  select case when public.area_norm(area) = 'ambas' then 'movistar_arena' else public.area_norm(area) end into v_area
    from public.convocatorias where id = p_conv_id;
  select array_agg(distinct po.persona_id) into v_ids
    from public.postulaciones po
   where po.conv_id = p_conv_id and po.estado in ('aprobado', 'confirmado') and po.persona_id is not null;
  if v_ids is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', pe.id,
      'nombre', pe.nombre,
      'area', pe.area,
      'semaforo', pe.semaforo,
      'antes', coalesce(t.antes, 0),
      'antes_area', coalesce(t.antes_area, 0),
      'primera_area', t.primera_area,
      'primera_vez', coalesce(t.antes, 0) = 0,
      'nuevo', coalesce(t.antes_area, 0) = 0 or t.primera_area >= date_trunc('month', v_dia)::date,
      -- lo que cargó esta cuenta en este show (con la fecha: el de cada día se ve en su día)
      'mis_feedbacks', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'puntaje', f.puntaje, 'comentario', f.comentario, 'created_at', f.created_at, 'fecha', f.fecha,
                 'actitud', f.actitud, 'consignas', f.consignas, 'presencia', f.presencia, 'iniciativa', f.iniciativa,
                 'supervisor', f.supervisor_nombre,
                 'promedio', case when f.actitud is not null
                   then round((f.actitud + f.consignas + f.presencia + f.iniciativa) / 4.0, 2) end)
               order by f.created_at), '[]'::jsonb)
          from public.feedbacks f
         where f.persona_id = pe.id and f.conv_id = p_conv_id and f.supervisor_id = auth.uid()),
      -- cuántos feedbacks tiene ese día, de cualquier supervisor
      'feedbacks_dia', (select count(*) from public.feedbacks f
                         where f.persona_id = pe.id and f.conv_id = p_conv_id and (f.fecha = v_dia or f.fecha is null))
    ) order by pe.nombre)
      from public.personas pe
      left join public.trayectoria(v_ids, v_area, v_dia, p_conv_id) t on t.persona_id = pe.id
     where pe.id = any(v_ids)
  ), '[]'::jsonb);
end $$;
revoke execute on function public.sup_equipo(uuid, date) from public, anon;
grant  execute on function public.sup_equipo(uuid, date) to authenticated;

-- ── 5) Guardar el feedback: con la fecha, el nombre de quien supervisa y, si no hay
--  puntajes, sólo el comentario (una observación: no cuenta para el semáforo) ──
drop function if exists public.sup_feedback(uuid, uuid, int, int, int, int, text);
create or replace function public.sup_feedback(
  p_persona_id uuid, p_conv_id uuid,
  p_actitud int, p_consignas int, p_presencia int, p_iniciativa int,
  p_comentario text, p_fecha date default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_prom numeric; v_color int; v_sem int; v_nombre text;
  v_com  text := nullif(btrim(coalesce(p_comentario, '')), '');
  v_obs  boolean := p_actitud is null and p_consignas is null and p_presencia is null and p_iniciativa is null;
  v_dia  date := coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  if not exists (select 1 from public.supervisor_convocatorias
                 where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese show no está asignado a vos');
  end if;
  if not exists (select 1 from public.postulaciones
                 where conv_id = p_conv_id and persona_id = p_persona_id and estado in ('aprobado', 'confirmado')) then
    return jsonb_build_object('ok', false, 'error', 'Esa persona no está en ese show');
  end if;
  if v_obs and v_com is null then
    return jsonb_build_object('ok', false, 'error', 'Puntuá los cuatro criterios o dejá un comentario');
  end if;
  if not v_obs then
    if p_actitud is null or p_consignas is null or p_presencia is null or p_iniciativa is null then
      return jsonb_build_object('ok', false, 'error', 'Faltan criterios por puntuar');
    end if;
    if p_actitud   not between 1 and 5 or p_consignas  not between 1 and 5
    or p_presencia not between 1 and 5 or p_iniciativa not between 1 and 5 then
      return jsonb_build_object('ok', false, 'error', 'Los puntajes van del 1 al 5');
    end if;
    v_prom  := (p_actitud + p_consignas + p_presencia + p_iniciativa) / 4.0;
    v_color := public.color_de_promedio(v_prom);
  end if;
  -- Quien supervisó: en una cuenta de zona, el que empezó ese show ("Ana López (Bowl)"); si no, la cuenta.
  begin
    v_nombre := public.supervisor_del_dia(auth.uid(), p_conv_id);
  exception when undefined_function then v_nombre := null;
  end;
  v_nombre := coalesce(v_nombre, (select nombre from public.user_profiles where id = auth.uid()));

  insert into public.feedbacks (id, persona_id, conv_id, supervisor_id, supervisor_nombre,
                                puntaje, comentario, actitud, consignas, presencia, iniciativa, fecha)
  values (gen_random_uuid(), p_persona_id, p_conv_id, auth.uid(), v_nombre,
          v_color, v_com, p_actitud, p_consignas, p_presencia, p_iniciativa, v_dia);

  if not v_obs then
    v_sem := public.semaforo_de(p_persona_id);
    update public.personas set semaforo = v_sem where id = p_persona_id;
  end if;
  return jsonb_build_object('ok', true, 'observacion', v_obs, 'promedio', round(v_prom, 2), 'color', v_color, 'semaforo', v_sem);
end $$;
revoke execute on function public.sup_feedback(uuid, uuid, int, int, int, int, text, date) from public, anon;
grant  execute on function public.sup_feedback(uuid, uuid, int, int, int, int, text, date) to authenticated;

-- ── CÓMO QUEDÓ ──
--  Tiene que dar: historial_shows true · feedbacks_con_fecha true · sup_equipo_con_fecha true ·
--  sup_feedback_con_fecha true · trayectoria_sin_usuario true (sólo la usa la app por adentro).
select
  exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'historial_shows') as historial_shows,
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'feedbacks' and column_name = 'fecha') as feedbacks_con_fecha,
  has_function_privilege('authenticated', 'public.sup_equipo(uuid, date)', 'execute') as sup_equipo_con_fecha,
  has_function_privilege('authenticated', 'public.sup_feedback(uuid, uuid, int, int, int, int, text, date)', 'execute') as sup_feedback_con_fecha,
  not has_function_privilege('authenticated', 'public.trayectoria(uuid[], text, date, uuid)', 'execute') as trayectoria_sin_usuario;
