-- ============================================================
--  TURNOS DE ACREDITACIONES (24-nov-2026)
--  Supabase → SQL Editor → pegar todo → Run. Se puede volver a correr.
--
--  La propuesta de RR. HH. (video "Turnos de acreditaciones, paso a paso", aprobado el 24-nov):
--  una grilla por evento, día × turno (Operador TM, TT, TN), donde RR. HH. y Operaciones asignan a
--  los operadores que pueden esa franja; el operador confirma desde el celular; con la P sale el
--  contrato de la jornada y la liquidación sale sola.
--
--  Los turnos (cada día y franja, con su horario, cupo y monto) se guardan en convocatorias.turnos,
--  como hasta ahora; la disponibilidad por franja, en la de siempre. Lo nuevo:
--    · postulaciones.asignaciones: a qué turnos está asignada cada persona y cómo va
--      ({ "<id del turno>": "propuesto" | "avisado" | "confirmado" | "rechazado" });
--    · la firma del link para confirmar un turno (como la de la confirmación de siempre) y la
--      función que lo registra desde el celular, sin usuario;
--    · contratos.turno_id: con la P de un turno sale el contrato de esa jornada (origen 'turno'), uno solo por
--      persona y turno.
-- ============================================================

alter table public.postulaciones add column if not exists asignaciones jsonb not null default '{}'::jsonb;

alter table public.contratos add column if not exists turno_id text;
create unique index if not exists contratos_turno_unico
  on public.contratos (postulacion_id, turno_id)
  where origen = 'turno' and estado <> 'anulado';

-- La firma de una asignación (persona en un turno), con la misma clave secreta de las confirmaciones.
create or replace function public.turno_firma_calc(p_post uuid, p_slot text)
returns text
language sql stable security definer set search_path = public, extensions as $$
  select left(encode(extensions.hmac('turno:' || coalesce(p_post::text, '') || ':' || coalesce(p_slot, ''),
           (select valor from public.secretos where clave = 'confirmacion'), 'sha256'), 'hex'), 32);
$$;
revoke execute on function public.turno_firma_calc(uuid, text) from public, anon, authenticated;

-- Para el panel, al armar el mail con los botones. Sólo un admin.
create or replace function public.turno_firma(p_post uuid, p_slot text)
returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.es_admin() then return null; end if;
  return public.turno_firma_calc(p_post, p_slot);
end;
$$;
revoke execute on function public.turno_firma(uuid, text) from public, anon;
grant  execute on function public.turno_firma(uuid, text) to authenticated;

-- El operador confirma (o dice que no puede) desde el link del mail. Sólo con la firma justa y sólo si
-- todavía está asignado a ese turno. Devuelve lo que la página muestra (sin datos personales salvo el nombre).
-- Con p_resp 'ver' no cambia nada: es para mostrar el turno y cómo está antes de tocar un botón.
create or replace function public.confirmar_turno(p_post uuid, p_slot text, p_resp text, p_firma text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_post  public.postulaciones;
  v_conv  public.convocatorias;
  v_turno jsonb;
  v_resp  text := lower(coalesce(p_resp, ''));
  v_nuevo text;
begin
  if p_post is null or p_slot is null or v_resp not in ('si', 'no', 'ver') then
    return jsonb_build_object('ok', false, 'motivo', 'datos');
  end if;
  if p_firma is null or p_firma <> public.turno_firma_calc(p_post, p_slot) then
    return jsonb_build_object('ok', false, 'motivo', 'firma');
  end if;
  select * into v_post from public.postulaciones where id = p_post;
  if not found or not (coalesce(v_post.asignaciones, '{}'::jsonb) ? p_slot) then
    return jsonb_build_object('ok', false, 'motivo', 'sin_turno');
  end if;
  select * into v_conv from public.convocatorias where id = v_post.conv_id;
  select t into v_turno from jsonb_array_elements(coalesce(v_conv.turnos, '[]'::jsonb)) t where t ->> 'id' = p_slot limit 1;
  if v_resp = 'ver' then
    v_nuevo := v_post.asignaciones ->> p_slot;
  else
    v_nuevo := case when v_resp = 'si' then 'confirmado' else 'rechazado' end;
    update public.postulaciones
       set asignaciones = jsonb_set(coalesce(asignaciones, '{}'::jsonb), array[p_slot], to_jsonb(v_nuevo))
     where id = p_post;
  end if;
  return jsonb_build_object('ok', true, 'estado', v_nuevo, 'nombre', v_post.nombre, 'evento', v_conv.nombre,
    'fecha', v_turno ->> 'fecha', 'horario', v_turno ->> 'horario', 'turno', coalesce(v_turno ->> 'nombre', v_turno ->> 'franja'));
end;
$$;
revoke execute on function public.confirmar_turno(uuid, text, text, text) from public;
grant  execute on function public.confirmar_turno(uuid, text, text, text) to anon, authenticated;

-- ── CÓMO QUEDÓ ── tiene que dar: asignaciones true · contrato_turno true · firma_sin_usuario false · confirmar_sin_usuario true.
select
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'postulaciones' and column_name = 'asignaciones') as asignaciones,
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'turno_id') as contrato_turno,
  has_function_privilege('anon', 'public.turno_firma(uuid, text)', 'execute') as firma_sin_usuario,
  has_function_privilege('anon', 'public.confirmar_turno(uuid, text, text, text)', 'execute') as confirmar_sin_usuario;
