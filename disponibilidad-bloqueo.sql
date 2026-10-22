-- ============================================================
--  QUE NADIE SE ANOTE DISPONIBLE PARA UN DÍA EN EL QUE YA ESTÁ CONVOCADO
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  ⚠ CORRER DESPUÉS DE QUE EL CAMBIO DE disponibilidad.html ESTÉ ARRIBA.
--
--  LO QUE PIDIÓ MERCEDES
--  "Que bloquee por CUIT: cuando una persona está convocada en un evento,
--  que avise y no deje que esté disponible para otro."
--  El panel ya lo hace al agregar gente a un puesto. Faltaba la otra
--  puerta: la página pública de disponibilidad, donde la persona marca
--  sola las fechas que puede.
--
--  QUÉ CAMBIA
--  guardar_disponibilidad es la misma función que había, con un chequeo
--  más: por cada fecha marcada, mira si esa persona —por documento— ya
--  está convocada ese día en OTRA convocatoria (postulación no rechazada).
--  Si alguna choca, no guarda nada y devuelve cuáles, para que la página
--  se lo diga y la persona las desmarque.
--
--  Y un arreglo de paso: la función buscaba a la persona por CUIL con
--  igualdad exacta, y en la nómina muchos están cargados con guiones
--  (27-46558119-6). Ahora compara sólo los números.
-- ============================================================

create or replace function public.guardar_disponibilidad(p_cuit text, p_conv_id uuid, p_fechas jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_abierta boolean;
  v_nombre  text;
  v_cuit    text := regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g');
  v_nucleo  text;
  v_turnos  jsonb;
  v_choques jsonb;
begin
  if length(v_cuit) <> 11 then return jsonb_build_object('ok', false, 'motivo', 'cuil_invalido'); end if;
  v_nucleo := ltrim(substr(v_cuit, 3, 8), '0');

  select disp_abierta, turnos into v_abierta, v_turnos from public.convocatorias where id = p_conv_id;
  if v_abierta is not true then return jsonb_build_object('ok', false, 'motivo', 'cerrada'); end if;

  -- Registrada: en la nómina o con inscripción. Por los números del documento.
  if not (exists (select 1 from public.personas
                  where regexp_replace(coalesce(cuit, ''), '\D', '', 'g') = v_cuit)
       or exists (select 1 from public.solicitudes
                  where regexp_replace(coalesce(cuit, ''), '\D', '', 'g') = v_cuit and conv_id is null))
  then return jsonb_build_object('ok', false, 'motivo', 'no_registrado'); end if;

  select nombre into v_nombre from public.personas
   where regexp_replace(coalesce(cuit, ''), '\D', '', 'g') = v_cuit limit 1;
  if v_nombre is null then
    select nombre into v_nombre from public.solicitudes
     where regexp_replace(coalesce(cuit, ''), '\D', '', 'g') = v_cuit order by created_at limit 1;
  end if;

  -- ── Lo nuevo: las fechas marcadas, contra lo que ya tiene convocado ──
  -- Cada fecha marcada es el id de un turno. Si la convocatoria tiene
  -- "turnos" cargados, el id se traduce a su fecha; si no, el id ES la fecha
  -- (así lo arma la página, igual que el panel).
  with marcadas as (
    select distinct
      coalesce((select t->>'fecha' from jsonb_array_elements(coalesce(v_turnos, '[]'::jsonb)) t where t->>'id' = f.id), f.id) as fecha
    from jsonb_array_elements_text(coalesce(p_fechas, '[]'::jsonb)) f(id)
  ),
  -- Las postulaciones de esta persona en otras convocatorias, por documento.
  suyas as (
    select po.conv_id
    from public.postulaciones po
    left join public.personas pe on pe.id = po.persona_id
    where coalesce(po.estado, '') <> 'rechazado'
      and po.conv_id <> p_conv_id
      and ltrim(case when length(regexp_replace(coalesce(coalesce(pe.cuit, po.cuit), ''), '\D', '', 'g')) = 11
                     then substr(regexp_replace(coalesce(coalesce(pe.cuit, po.cuit), ''), '\D', '', 'g'), 3, 8)
                     else regexp_replace(coalesce(coalesce(pe.cuit, po.cuit), ''), '\D', '', 'g') end, '0') = v_nucleo
  )
  select coalesce(jsonb_agg(jsonb_build_object('fecha', m.fecha, 'conv', c.nombre) order by m.fecha), '[]'::jsonb)
    into v_choques
  from marcadas m
  join suyas s on true
  join public.convocatorias c on c.id = s.conv_id
  where m.fecha = any (string_to_array(replace(coalesce(c.fecha, ''), ' ', ''), ','));

  if jsonb_array_length(v_choques) > 0 then
    return jsonb_build_object('ok', false, 'motivo', 'convocado', 'nombre', v_nombre, 'choques', v_choques);
  end if;

  insert into public.disponibilidad (conv_id, cuit, nombre, fechas, updated_at)
  values (p_conv_id, v_cuit, v_nombre, coalesce(p_fechas, '[]'::jsonb), now())
  on conflict (conv_id, cuit) do update set fechas = excluded.fechas, nombre = excluded.nombre, updated_at = now();
  return jsonb_build_object('ok', true, 'nombre', v_nombre);
end $$;

grant execute on function public.guardar_disponibilidad(text, uuid, jsonb) to anon, authenticated;

-- De paso: sup_convocatorias había quedado ejecutable sin usuario. Sin usuario
-- devuelve vacío, pero no tiene por qué estar abierta.
revoke execute on function public.sup_convocatorias() from anon, public;

-- ── CÓMO QUEDÓ ──
select p.proname,
       has_function_privilege('anon', p.oid, 'execute') as sin_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('guardar_disponibilidad', 'sup_convocatorias')
order by p.proname;
--  guardar_disponibilidad true (la usa la página pública); sup_convocatorias false.

-- ── PARA VOLVER ATRÁS ──
--  La versión anterior de la función está guardada en
--  "Supabase Snippet Untitled query (1).csv" en Descargas (22/10/2026).
