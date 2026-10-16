-- ============================================================
-- Botones "Confirmo / No confirmo" en el mail -> notificación en el panel.
-- Correr en Supabase -> SQL Editor (es lo único que falta para activarlo).
-- ============================================================

-- 1) Guardar la respuesta del candidato en su postulación
alter table public.postulaciones add column if not exists confirmacion text;         -- 'si' | 'no'
alter table public.postulaciones add column if not exists confirmacion_at timestamptz;

-- 2) Función pública: el candidato toca un botón del mail -> registra su respuesta
--    y genera una notificación en el panel. SECURITY DEFINER (la página es anónima).
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

  -- Notificación en el panel (aparece en el 🔔 como pendiente)
  insert into public.notificaciones (id, tipo, titulo, cuerpo, destinatario_email, destinatario_nombre, estado)
  values (
    gen_random_uuid()::text,
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

grant execute on function public.registrar_confirmacion(text, uuid, text) to anon, authenticated;
