-- ============================================================
--  ARREGLO: los botones "CONFIRMO / NO CONFIRMO" del mail daban
--  "Hubo un error al registrar tu respuesta".
--
--  La función guardaba bien la respuesta en la postulación, pero al crear
--  la notificación del panel generaba el id como texto
--  (gen_random_uuid()::text) y la columna notificaciones.id es uuid:
--      column "id" is of type uuid but expression is of type text  (42804)
--  Así que la base rechazaba todo y la persona veía el error.
--
--  Correr en Supabase -> SQL Editor. Es la misma función que
--  confirmacion-botones.sql, con el id bien.
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

  -- Marcar la(s) postulación(es) de esa persona en esa convocatoria
  update public.postulaciones
     set confirmacion = v_resp, confirmacion_at = now()
   where regexp_replace(coalesce(cuit,''), '\D','','g') = v_cuit
     and conv_id = p_conv_id
     and coalesce(estado,'') <> 'rechazado';
  get diagnostics v_count = row_count;

  -- Nombre del candidato (de la postulación o, si no, de la solicitud)
  select nombre into v_nombre from public.postulaciones
    where regexp_replace(coalesce(cuit,''),'\D','','g') = v_cuit and conv_id = p_conv_id
    order by created_at desc limit 1;
  if v_nombre is null then
    select nombre into v_nombre from public.solicitudes
      where regexp_replace(coalesce(cuit,''),'\D','','g') = v_cuit
      order by created_at desc limit 1;
  end if;

  -- Notificación en el panel (aparece en el 🔔 como pendiente).
  -- El id va como uuid, que es el tipo de la columna (antes iba ::text).
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

  return jsonb_build_object('ok', true, 'nombre', v_nombre, 'convocatoria', v_conv, 'respuesta', v_resp);
end;
$$;

-- La puede llamar quien entra desde el mail, sin usuario (igual que antes).
revoke execute on function public.registrar_confirmacion(text, uuid, text) from public;
grant  execute on function public.registrar_confirmacion(text, uuid, text) to anon, authenticated;

-- ── Comprobación: tiene que devolver {"ok": false, "motivo": "respuesta"} ──
select public.registrar_confirmacion('20111111112', '00000000-0000-0000-0000-000000000000', 'x');
