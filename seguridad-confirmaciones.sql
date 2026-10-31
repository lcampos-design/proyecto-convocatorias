-- ============================================================
--  SEGURIDAD: QUE NADIE PUEDA CONFIRMAR NI RECHAZAR POR OTRO
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--  No toca ningún dato: agrega una clave secreta, dos funciones nuevas y nada más.
--
--  El agujero (30-oct): el link de "Confirmá tu asistencia" del mail es
--  /confirmar?c=CUIT&v=CONVOCATORIA&r=si|no. Con el CUIL de otra persona (sale del
--  DNI) y el id de una convocatoria, cualquiera podía confirmarla o RECHAZARLA
--  (y así sacarla del puesto), y de paso ver su nombre.
--
--  El arreglo: el link lleva además una firma (f=...) que sólo puede calcular la
--  base, con una clave secreta que no sale nunca de la base. Sin la firma justa
--  para ESE CUIL y ESA convocatoria, no registra nada.
--
--  Los mails que ya salieron (sin firma) siguen andando con la función de
--  antes. Cuando ya no queden por responder, se cierra con la línea de abajo
--  de todo ("CERRAR LOS LINKS VIEJOS").
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ── 1) LA CLAVE SECRETA ──
--  En una tabla que no lee nadie (ni con usuario): sólo las funciones de abajo.
create table if not exists public.secretos (
  clave text primary key,
  valor text not null
);
alter table public.secretos enable row level security;
revoke all on public.secretos from public, anon, authenticated;
insert into public.secretos (clave, valor)
values ('confirmacion', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (clave) do nothing;

-- La firma de un CUIL para una convocatoria (32 caracteres).
create or replace function public.conf_firma_calc(p_cuit text, p_conv uuid)
returns text
language sql stable security definer set search_path = public, extensions as $$
  select left(encode(extensions.hmac(
           regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g') || ':' || coalesce(p_conv::text, ''),
           (select valor from public.secretos where clave = 'confirmacion'), 'sha256'), 'hex'), 32);
$$;
revoke execute on function public.conf_firma_calc(text, uuid) from public, anon, authenticated;

-- ── 2) LA FIRMA, PARA EL PANEL ──
--  La pide el panel al armar cada mail con los botones. Sólo un admin.
create or replace function public.conf_firma(p_cuit text, p_conv uuid)
returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.es_admin() then return null; end if;
  return public.conf_firma_calc(p_cuit, p_conv);
end;
$$;
revoke execute on function public.conf_firma(text, uuid) from public, anon;
grant  execute on function public.conf_firma(text, uuid) to authenticated;

-- ── 3) CONFIRMAR CON LA FIRMA ──
--  La usa /confirmar cuando el link trae f=. Con la firma justa hace lo mismo
--  que la función de siempre; si no, no registra nada ni dice de quién es.
create or replace function public.registrar_confirmacion_firmada(p_cuit text, p_conv_id uuid, p_respuesta text, p_firma text)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_firma is null or p_conv_id is null or p_firma <> public.conf_firma_calc(p_cuit, p_conv_id) then
    return jsonb_build_object('ok', false, 'motivo', 'firma');
  end if;
  return public.registrar_confirmacion(p_cuit, p_conv_id, p_respuesta);
end;
$$;
revoke execute on function public.registrar_confirmacion_firmada(text, uuid, text, text) from public;
grant  execute on function public.registrar_confirmacion_firmada(text, uuid, text, text) to anon, authenticated;

-- ── CÓMO QUEDÓ ──
select p.proname as funcion,
       has_function_privilege('anon', p.oid, 'execute') as sin_usuario,
       has_function_privilege('authenticated', p.oid, 'execute') as con_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('conf_firma', 'conf_firma_calc', 'registrar_confirmacion_firmada', 'registrar_confirmacion')
order by 1;

-- ── CERRAR LOS LINKS VIEJOS (cuando ya no queden mails sin responder) ──
--  Desde ahí, sólo andan los links con firma. Correr esta línea sola:
--   revoke execute on function public.registrar_confirmacion(text, uuid, text) from public, anon, authenticated;
