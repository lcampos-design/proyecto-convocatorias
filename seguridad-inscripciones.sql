-- ============================================================
--  SEGURIDAD: QUE NADIE VEA NI BAJE LAS INSCRIPCIONES DE OTRO
--  Correr en Supabase → SQL Editor → Run, DESPUÉS de que esté publicada la
--  página nueva (la que pide el link por mail). Se puede volver a correr.
--  No toca ningún dato.
--
--  El agujero (31-oct): en "Ver mis inscripciones" alcanzaba con un CUIL (sale
--  del DNI) para ver en qué shows está una persona y DARLA DE BAJA
--  (mis_postulaciones devolvía el número de cada postulación y dar_de_baja la
--  soltaba con el CUIL).
--
--  Lo que eligió Thomas (la "B"): para ver tus inscripciones y darte de baja te
--  llega un link al mail (el mismo de /mis-datos, que ahora las muestra);
--  anotarse a un puesto y la disponibilidad siguen con el CUIL.
--   1) mis_inscripciones y baja_con_link: con el link del mail.
--   2) puedo_anotarme: para el formulario de anotarse, dice sólo sí o no
--      (si ya está en ese puesto o en otro de lo abierto), sin mostrar shows.
--   3) mis_postulaciones y dar_de_baja quedan cerradas para todos.
-- ============================================================

-- ── 1) CON EL LINK DEL MAIL ──
--  Sus inscripciones (por el documento del link), de la más nueva a la más vieja.
create or replace function public.mis_inscripciones(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_nuc text := public.mis_datos_nucleo(p_token);
begin
  if v_nuc is null then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  return jsonb_build_object('ok', true, 'inscripciones', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'estado', p.estado,
             'conv_nombre', c.nombre, 'conv_fecha', c.fecha, 'puesto_nombre', q.nombre
           ) order by c.fecha desc nulls last)
      from public.postulaciones p
      left join public.convocatorias c on c.id = p.conv_id
      left join public.puestos q on q.id = p.puesto_id
     where public.doc_nucleo(p.cuit) = v_nuc
        or p.persona_id in (select pe.id from public.personas pe where public.doc_nucleo(pe.cuit) = v_nuc)
  ), '[]'::jsonb));
end;
$$;

--  Darse de baja: sólo de una inscripción suya (la del documento del link). El
--  plazo y lo demás lo sigue decidiendo dar_de_baja, como siempre.
create or replace function public.baja_con_link(p_token text, p_postulacion_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_nuc  text := public.mis_datos_nucleo(p_token);
  v_cuit text;
begin
  if v_nuc is null then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  select coalesce(nullif(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), ''),
                  (select regexp_replace(coalesce(pe.cuit, ''), '\D', '', 'g') from public.personas pe where pe.id = p.persona_id))
    into v_cuit
    from public.postulaciones p
   where p.id = p_postulacion_id
     and (public.doc_nucleo(p.cuit) = v_nuc
          or p.persona_id in (select pe.id from public.personas pe where public.doc_nucleo(pe.cuit) = v_nuc));
  if v_cuit is null then return jsonb_build_object('ok', false, 'motivo', 'no_es_tuya'); end if;
  return (public.dar_de_baja(v_cuit, p_postulacion_id))::jsonb;
end;
$$;

-- ── 2) PARA ANOTARSE: SÓLO SÍ O NO ──
--  ¿Ya está en ese puesto? ¿Está en otro de las convocatorias publicadas? Sin
--  nombres ni fechas: lo que antes daba mis_postulaciones, sin mostrar nada.
create or replace function public.puedo_anotarme(p_cuit text, p_conv_id uuid, p_puesto_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with suyas as (
    select p.conv_id, p.puesto_id
      from public.postulaciones p
      join public.convocatorias c on c.id = p.conv_id and c.publicada = true
     where length(regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g')) = 11
       and regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') = regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g')
       and coalesce(p.estado, '') <> 'rechazado'
  )
  select jsonb_build_object(
    'ya_en_este', exists (select 1 from suyas where conv_id = p_conv_id and puesto_id = p_puesto_id),
    'otra_activa', exists (select 1 from suyas));
$$;

-- ── PERMISOS ──
revoke execute on function public.mis_inscripciones(text) from public;
grant  execute on function public.mis_inscripciones(text) to anon, authenticated;
revoke execute on function public.baja_con_link(text, uuid) from public;
grant  execute on function public.baja_con_link(text, uuid) to anon, authenticated;
revoke execute on function public.puedo_anotarme(text, uuid, uuid) from public;
grant  execute on function public.puedo_anotarme(text, uuid, uuid) to anon, authenticated;

-- ── 3) LAS DE ANTES, CERRADAS ──
--  Ya no las usa ninguna página (la de anotarse usa puedo_anotarme; la de ver y
--  bajarse, el link del mail). Las siguen usando por dentro las de arriba.
revoke execute on function public.mis_postulaciones(text) from public, anon, authenticated;
revoke execute on function public.dar_de_baja(text, uuid) from public, anon, authenticated;

-- ── CÓMO QUEDÓ ──
select p.proname as funcion,
       has_function_privilege('anon', p.oid, 'execute') as sin_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('mis_inscripciones', 'baja_con_link', 'puedo_anotarme', 'mis_postulaciones', 'dar_de_baja')
order by 1;
--  Tiene que dar: baja_con_link true, dar_de_baja false, mis_inscripciones true,
--  mis_postulaciones false, puedo_anotarme true.

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--   grant execute on function public.mis_postulaciones(text) to anon, authenticated;
--   grant execute on function public.dar_de_baja(text, uuid)  to anon, authenticated;
