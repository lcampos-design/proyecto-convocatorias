-- ============================================================
--  CONFIRMADO / NO VIENE, AUTOMÁTICO
--
--  El circuito: postulan → el panel aprueba → se manda el mail → la persona
--  toca CONFIRMO o NO CONFIRMO. Hasta ahora el botón sólo dejaba una marca;
--  el estado no se movía. Ahora:
--    · CONFIRMO    → la postulación pasa a 'confirmado' (sigue ocupando cupo,
--                    entra en la lista de presentes, puede recibir feedback).
--    · NO CONFIRMO → pasa a 'rechazado' (libera el cupo); en el panel se ve
--                    como "No viene", por la marca de la respuesta.
--  Sólo cambia a 'confirmado' si estaba aprobado: alguien pendiente que toque
--  el botón no se aprueba solo.
--
--  Y las funciones del supervisor (equipo, feedback, cuántas personas) toman
--  'confirmado' como aprobado.
--
--  Correr en Supabase -> SQL Editor.
-- ============================================================

-- ── 1) Los botones del mail mueven el estado ──
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

  -- La postulación de esa persona en esa convocatoria: por el CUIT de la fila
  -- o, si la fila no lo tiene, por el CUIT de la persona.
  update public.postulaciones po
     set confirmacion = v_resp,
         confirmacion_at = now(),
         estado = case
                    when v_resp = 'no' then 'rechazado'
                    when po.estado in ('aprobado', 'confirmado') then 'confirmado'
                    else po.estado
                  end
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

  insert into public.notificaciones (id, tipo, titulo, cuerpo, destinatario_email, destinatario_nombre, estado)
  values (
    gen_random_uuid(),
    'confirmacion',
    (case when v_resp = 'si' then '✅ Confirmó — ' else '❌ NO viene — ' end) || coalesce(v_nombre, v_cuit),
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

-- ── 2) Para el supervisor, confirmado es aprobado ──
create or replace function public.sup_convocatorias()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'fecha' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', c.id, 'nombre', c.nombre, 'fecha', c.fecha, 'area', c.area,
      'venue', c.venue, 'horario', c.horario,
      'turnos', c.turnos, 'horarios_por_fecha', c.horarios_por_fecha,
      'puestos', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre) order by p.created_at), '[]'::jsonb)
                  from public.puestos p where p.conv_id = c.id),
      'personas', (select count(*) from public.postulaciones po
                   where po.conv_id = c.id and po.estado in ('aprobado', 'confirmado') and po.persona_id is not null),
      'con_feedback', (select count(distinct f.persona_id) from public.feedbacks f
                       where f.conv_id = c.id and f.supervisor_id = auth.uid())
    ) as x
    from public.supervisor_convocatorias sc
    join public.convocatorias c on c.id = sc.conv_id
    where sc.supervisor_id = auth.uid()
  ) t;
$$;

create or replace function public.sup_feedback(
  p_persona_id uuid, p_conv_id uuid,
  p_actitud int, p_consignas int, p_presencia int, p_iniciativa int,
  p_comentario text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_prom numeric; v_color int; v_sem int;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  if not exists (select 1 from public.supervisor_convocatorias
                 where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese recital no está asignado a vos');
  end if;
  if not exists (select 1 from public.postulaciones
                 where conv_id = p_conv_id and persona_id = p_persona_id and estado in ('aprobado', 'confirmado')) then
    return jsonb_build_object('ok', false, 'error', 'Esa persona no está en ese recital');
  end if;
  if p_actitud is null or p_consignas is null or p_presencia is null or p_iniciativa is null then
    return jsonb_build_object('ok', false, 'error', 'Faltan criterios por puntuar');
  end if;
  if p_actitud    not between 1 and 5 or p_consignas  not between 1 and 5
  or p_presencia  not between 1 and 5 or p_iniciativa not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'Los puntajes van del 1 al 5');
  end if;

  v_prom  := (p_actitud + p_consignas + p_presencia + p_iniciativa) / 4.0;
  v_color := public.color_de_promedio(v_prom);

  insert into public.feedbacks (id, persona_id, conv_id, supervisor_id, supervisor_nombre,
                                puntaje, comentario, actitud, consignas, presencia, iniciativa)
  values (gen_random_uuid(), p_persona_id, p_conv_id, auth.uid(),
          (select nombre from public.user_profiles where id = auth.uid()),
          v_color, nullif(btrim(coalesce(p_comentario, '')), ''),
          p_actitud, p_consignas, p_presencia, p_iniciativa);

  v_sem := public.semaforo_de(p_persona_id);
  update public.personas set semaforo = v_sem where id = p_persona_id;

  return jsonb_build_object('ok', true, 'promedio', round(v_prom, 2), 'color', v_color, 'semaforo', v_sem);
end $$;

create or replace function public.sup_equipo(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not exists (
      select 1 from public.supervisor_convocatorias
      where supervisor_id = auth.uid() and conv_id = p_conv_id
    ) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pe.id,
        'nombre', pe.nombre,
        'area', pe.area,
        'semaforo', pe.semaforo,
        'mis_feedbacks', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'puntaje', f.puntaje, 'comentario', f.comentario, 'created_at', f.created_at,
                   'actitud', f.actitud, 'consignas', f.consignas,
                   'presencia', f.presencia, 'iniciativa', f.iniciativa,
                   'promedio', case when f.actitud is not null
                     then round((f.actitud + f.consignas + f.presencia + f.iniciativa) / 4.0, 2) end)
                 order by f.created_at), '[]'::jsonb)
          from public.feedbacks f
          where f.persona_id = pe.id and f.conv_id = p_conv_id and f.supervisor_id = auth.uid()
        )
      ) order by pe.nombre)
      from public.postulaciones po
      join public.personas pe on pe.id = po.persona_id
      where po.conv_id = p_conv_id and po.estado in ('aprobado', 'confirmado')
    ), '[]'::jsonb)
  end;
$$;

-- ── Comprobación (no escribe nada): {"ok": false, "motivo": "respuesta"} ──
select public.registrar_confirmacion('20111111112', '00000000-0000-0000-0000-000000000000', 'x');
