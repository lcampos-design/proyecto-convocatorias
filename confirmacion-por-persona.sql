-- ============================================================
--  ARREGLO 2: llegaba la notificación "Confirmó", pero la postulación no
--  quedaba marcada y la cabecera decía "Confirmaron: 0".
--
--  Las postulaciones que se crean desde el panel ("Agregar desde nómina")
--  no guardan el CUIT en la fila: sólo apuntan a la persona (persona_id).
--  La función buscaba la postulación por CUIT, no encontraba ninguna y la
--  notificación salía con "(sin postulación registrada)". Ahora busca por
--  CUIT o por la persona cuyo CUIT es ese.
--
--  Correr en Supabase -> SQL Editor (reemplaza a confirmacion-arreglo.sql).
-- ============================================================

create or replace function public.registrar_confirmacion(p_cuit text, p_conv_id uuid, p_respuesta text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_cuit   text := regexp_replace(coalesce(p_cuit,''), '\D', '', 'g');
  v_resp   text := lower(coalesce(p_respuesta,''));
  v_nombre text;
  v_conv   text;
  v_count  int;
begin
  if v_cuit = '' or p_conv_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'datos');
  end if;
  if v_resp not in ('si','no') then
    return jsonb_build_object('ok', false, 'motivo', 'respuesta');
  end if;

  select nombre into v_conv from public.convocatorias where id = p_conv_id;

  -- Marcar la(s) postulación(es) de esa persona en esa convocatoria: por el
  -- CUIT de la fila o, si la fila no lo tiene, por el CUIT de la persona.
  update public.postulaciones po
     set confirmacion = v_resp, confirmacion_at = now()
   where po.conv_id = p_conv_id
     and coalesce(po.estado,'') <> 'rechazado'
     and ( regexp_replace(coalesce(po.cuit,''), '\D','','g') = v_cuit
           or po.persona_id in (select pe.id from public.personas pe
                                 where regexp_replace(coalesce(pe.cuit,''), '\D','','g') = v_cuit) );
  get diagnostics v_count = row_count;

  -- Nombre del candidato: de la postulación, de la persona o de la solicitud.
  select po.nombre into v_nombre from public.postulaciones po
    where po.conv_id = p_conv_id
      and ( regexp_replace(coalesce(po.cuit,''),'\D','','g') = v_cuit
            or po.persona_id in (select pe.id from public.personas pe
                                  where regexp_replace(coalesce(pe.cuit,''), '\D','','g') = v_cuit) )
    order by po.created_at desc limit 1;
  if v_nombre is null then
    select nombre into v_nombre from public.personas
      where regexp_replace(coalesce(cuit,''),'\D','','g') = v_cuit limit 1;
  end if;
  if v_nombre is null then
    select nombre into v_nombre from public.solicitudes
      where regexp_replace(coalesce(cuit,''),'\D','','g') = v_cuit
      order by created_at desc limit 1;
  end if;

  -- Notificación en el panel (aparece en el 🔔 como pendiente).
  insert into public.notificaciones (id, tipo, titulo, cuerpo, destinatario_email, destinatario_nombre, estado)
  values (
    gen_random_uuid(),
    'confirmacion',
    (case when v_resp = 'si' then '✅ Confirmó — ' else '❌ NO confirmó — ' end) || coalesce(v_nombre, v_cuit),
    coalesce(v_conv,'') || (case when v_count = 0 then ' · (sin postulación registrada)' else '' end),
    null,
    v_nombre,
    'pendiente'
  );

  return jsonb_build_object('ok', true, 'nombre', v_nombre, 'convocatoria', v_conv, 'respuesta', v_resp, 'marcadas', v_count);
end;
$$;

revoke execute on function public.registrar_confirmacion(text, uuid, text) from public;
grant  execute on function public.registrar_confirmacion(text, uuid, text) to anon, authenticated;

-- ── Comprobación (no escribe nada): {"ok": false, "motivo": "respuesta"} ──
select public.registrar_confirmacion('20111111112', '00000000-0000-0000-0000-000000000000', 'x');
