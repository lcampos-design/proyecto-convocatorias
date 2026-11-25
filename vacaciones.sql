-- ============================================================
--  SOLICITUD DE VACACIONES DEL PERSONAL CORPORATIVO, CON FIRMA ELECTRÓNICA (24-nov)
-- ============================================================
--  Thomas (24-nov): la "Solicitud de vacaciones SBS 2026-2027" (el Word de RR. HH.) para que el personal
--  corporativo la complete en pantalla y la firme electrónicamente. Es interno: nada que ver con las
--  convocatorias. El link (convocatorias.show-bs.com/vacaciones) va en un newsletter.
--
--  El circuito (como lo pensó Thomas): la persona entra con su mail (le llega un código), completa sus
--  datos y los tramos, firma y la envía → RR. HH., desde el panel, la deriva al jefe que corresponde (o la
--  firma directamente, si depende de RR. HH.) → el jefe la aprueba y firma con su link → RR. HH. la aprueba y
--  firma → a todos les llega el PDF con las firmas.
--
--  Los mails de RR. HH. y de los jefes NO están acá: se cargan en el panel (Contratos → Vacaciones) y quedan en
--  config ('vacaciones'), fuera del código público. De los links y los códigos sólo se guarda la huella.
--
--  Se puede correr más de una vez. Al final: si quedó todo (sólo cantidades y sí/no).
-- ============================================================

create table if not exists public.vacaciones (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  email        text not null,
  nombre       text not null,
  area         text not null,
  datos        jsonb not null,                       -- los tramos, los días y lo que avisó el formulario
  aprueba_jefe text,                                 -- el jefe al que la derivó RR. HH. (null: firma sólo RR. HH.)
  aprueba_rrhh text not null,
  estado       text not null default 'nueva',
  firmas       jsonb not null default '{}'::jsonb,   -- { empleado, jefe, rrhh }: { png, aclaracion, decision, nota, fecha, email }
  token_hash   text,                                 -- el link de quien tiene que firmar ahora
  token_rol    text,
  token_vence  timestamptz,
  ver_hashes   text[] not null default '{}',         -- los links para ver y bajar el PDF (la persona y quien ya firmó)
  aviso_hecho  text,                                 -- el estado del que ya salió el mail
  derivada_por text,
  pdf          text                                  -- el PDF con todas las firmas (base64), al terminar
);
alter table public.vacaciones drop constraint if exists vacaciones_estado_check;
alter table public.vacaciones add constraint vacaciones_estado_check check (estado in ('nueva', 'jefe', 'rrhh', 'aprobada', 'rechazada'));
alter table public.vacaciones alter column estado set default 'nueva';
alter table public.vacaciones add column if not exists derivada_por text;
create index if not exists vacaciones_token_idx on public.vacaciones (token_hash);
create index if not exists vacaciones_mail_idx on public.vacaciones (email, created_at desc);
alter table public.vacaciones enable row level security;
revoke all on public.vacaciones from anon, authenticated;
-- El panel (RR. HH.) las ve; nadie las cambia de afuera: sólo las funciones de abajo.
grant select on public.vacaciones to authenticated;
drop policy if exists vacaciones_admin on public.vacaciones;
create policy vacaciones_admin on public.vacaciones for select to authenticated using (public.es_admin());

-- Los códigos que llegan al mail para entrar, y la sesión de quien entró (3 horas).
create table if not exists public.vacaciones_codigos (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  codigo_hash text not null,
  vence       timestamptz not null,
  intentos    int not null default 0,
  usado       timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists vacaciones_codigos_mail_idx on public.vacaciones_codigos (email, created_at desc);
create table if not exists public.vacaciones_sesiones (
  token_hash text primary key,
  email      text not null,
  vence      timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.vacaciones_codigos enable row level security;
alter table public.vacaciones_sesiones enable row level security;
revoke all on public.vacaciones_codigos from anon, authenticated;
revoke all on public.vacaciones_sesiones from anon, authenticated;

-- La huella de un link o de un código, y un link nuevo.
create or replace function public.vac_huella(p text) returns text
language sql immutable set search_path = public as $$ select encode(sha256(convert_to(coalesce(p, ''), 'UTF8')), 'hex') $$;
create or replace function public.vac_token() returns text
language sql volatile set search_path = public as $$ select replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '') $$;
revoke execute on function public.vac_huella(text) from public, anon, authenticated;
revoke execute on function public.vac_token() from public, anon, authenticated;
-- El mail de quien tiene la sesión (null si no vale).
create or replace function public.vac_quien(p_sesion text) returns text
language sql stable security definer set search_path = public as $$
  select email from public.vacaciones_sesiones where token_hash = public.vac_huella(p_sesion) and vence > now() and length(coalesce(p_sesion, '')) >= 32
$$;
revoke execute on function public.vac_quien(text) from public, anon, authenticated;

-- ── Las áreas, para el formulario (sólo los nombres: los mails no salen de la base) ──
create or replace function public.vacaciones_areas()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_agg(x.a ->> 'nombre' order by x.n)
                     from public.config c
                     cross join lateral jsonb_array_elements(coalesce(c.value -> 'areas', '[]'::jsonb)) with ordinality as x(a, n)
                    where c.key = 'vacaciones' and coalesce(x.a ->> 'nombre', '') <> ''), '[]'::jsonb);
$$;

-- ── El código para entrar (lo pide el servidor, que lo manda por mail) ──
create or replace function public.vacaciones_codigo(p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mail text := lower(btrim(coalesce(p_email, ''))); v_cod text;
begin
  if v_mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return jsonb_build_object('ok', false, 'error', 'Revisá tu mail.'); end if;
  if (select count(*) from public.vacaciones_codigos where email = v_mail and created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Ya te mandamos varios códigos en la última hora. Revisá tu casilla (y el correo no deseado) o probá más tarde.');
  end if;
  if (select count(*) from public.vacaciones_codigos where created_at > now() - interval '1 hour') >= 300 then
    return jsonb_build_object('ok', false, 'error', 'Estamos recibiendo muchos pedidos. Probá de nuevo en un rato.');
  end if;
  v_cod := lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.vacaciones_codigos (email, codigo_hash, vence) values (v_mail, public.vac_huella(v_mail || ':' || v_cod), now() + interval '30 minutes');
  return jsonb_build_object('ok', true, 'codigo', v_cod, 'email', v_mail);
end;
$$;

-- Lo de una persona: sus solicitudes, de la más nueva a la más vieja (sin las firmas ni el PDF).
create or replace function public.vac_mias(v_mail text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'creada', created_at, 'estado', estado, 'area', area, 'datos', datos) order by created_at desc), '[]'::jsonb)
    from public.vacaciones where email = v_mail
$$;
revoke execute on function public.vac_mias(text) from public, anon, authenticated;

-- ── Entrar con el código: abre una sesión de 3 horas y devuelve sus solicitudes ──
create or replace function public.vacaciones_entrar(p_email text, p_codigo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mail text := lower(btrim(coalesce(p_email, ''))); c record; v_ses text;
begin
  select * into c from public.vacaciones_codigos where email = v_mail and usado is null order by created_at desc limit 1;
  if not found or c.vence < now() then return jsonb_build_object('ok', false, 'error', 'El código venció. Pedí uno nuevo.'); end if;
  if c.intentos >= 5 then return jsonb_build_object('ok', false, 'error', 'Probaste demasiadas veces. Pedí un código nuevo.'); end if;
  if c.codigo_hash <> public.vac_huella(v_mail || ':' || btrim(coalesce(p_codigo, ''))) then
    update public.vacaciones_codigos set intentos = intentos + 1 where id = c.id;
    return jsonb_build_object('ok', false, 'error', 'El código no es el que te mandamos. Revisalo.');
  end if;
  update public.vacaciones_codigos set usado = now() where id = c.id;
  v_ses := public.vac_token();
  insert into public.vacaciones_sesiones (token_hash, email, vence) values (public.vac_huella(v_ses), v_mail, now() + interval '3 hours');
  delete from public.vacaciones_sesiones where vence < now() - interval '1 day';
  return jsonb_build_object('ok', true, 'sesion', v_ses, 'email', v_mail, 'mias', public.vac_mias(v_mail));
end;
$$;

create or replace function public.vacaciones_mias(p_sesion text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_mail text := public.vac_quien(p_sesion);
begin
  if v_mail is null then return jsonb_build_object('ok', false, 'error', 'Tu sesión venció. Entrá de nuevo con tu mail.'); end if;
  return jsonb_build_object('ok', true, 'email', v_mail, 'mias', public.vac_mias(v_mail));
end;
$$;

-- ── Mandar la solicitud firmada ──
--  p_datos: { nombre, area, tramos: [{ desde, hasta, feriado }], avisos: [] }
create or replace function public.vacaciones_crear(p_sesion text, p_datos jsonb, p_firma text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_mail   text := public.vac_quien(p_sesion);
  v_nombre text := btrim(regexp_replace(coalesce(p_datos ->> 'nombre', ''), '\s+', ' ', 'g'));
  v_area   text := btrim(coalesce(p_datos ->> 'area', ''));
  v_cfg    jsonb := (select value from public.config where key = 'vacaciones');
  t jsonb; v_desde date; v_hasta date; v_tramos jsonb := '[]'::jsonb; v_total int := 0; v_ant date; v_ver text; v_id uuid;
begin
  if v_mail is null then return jsonb_build_object('ok', false, 'error', 'Tu sesión venció. Entrá de nuevo con tu mail (lo que completaste queda).'); end if;
  if v_cfg is null or coalesce(v_cfg ->> 'rrhh', '') = '' then return jsonb_build_object('ok', false, 'error', 'Todavía no está configurado RR. HH. Avisale a RR. HH.'); end if;
  if length(v_nombre) < 3 then return jsonb_build_object('ok', false, 'error', 'Completá tu nombre y apellido.'); end if;
  if v_area = '' then return jsonb_build_object('ok', false, 'error', 'Elegí tu área.'); end if;
  if coalesce(p_firma, '') !~ '^data:image/png;base64,' or length(p_firma) > 400000 then return jsonb_build_object('ok', false, 'error', 'Falta tu firma.'); end if;
  if (select count(*) from public.vacaciones where email = v_mail and created_at > now() - interval '1 day') >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Ya mandaste varias solicitudes hoy. Si hace falta corregir algo, escribile a RR. HH.');
  end if;
  -- Los tramos: 1 o 2; cada uno de 7 días corridos o más y que empiece un lunes (o el martes, si el lunes es feriado).
  if jsonb_typeof(p_datos -> 'tramos') <> 'array' or jsonb_array_length(p_datos -> 'tramos') not between 1 and 2 then return jsonb_build_object('ok', false, 'error', 'Completá las fechas.'); end if;
  for t in select * from jsonb_array_elements(p_datos -> 'tramos') loop
    begin v_desde := (t ->> 'desde')::date; v_hasta := (t ->> 'hasta')::date; exception when others then return jsonb_build_object('ok', false, 'error', 'Revisá las fechas.'); end;
    if v_desde is null or v_hasta is null or v_hasta < v_desde then return jsonb_build_object('ok', false, 'error', 'Revisá las fechas: el "hasta" va después del "desde".'); end if;
    if v_hasta - v_desde + 1 < 7 then return jsonb_build_object('ok', false, 'error', 'Cada tramo dura 7 días corridos o más.'); end if;
    if extract(isodow from v_desde) <> 1 and not (extract(isodow from v_desde) = 2 and coalesce((t ->> 'feriado')::boolean, false)) then
      return jsonb_build_object('ok', false, 'error', 'Cada tramo empieza un lunes (o el martes, si el lunes es feriado).'); end if;
    if v_ant is not null and v_desde <= v_ant then return jsonb_build_object('ok', false, 'error', 'Los tramos no se pueden superponer: el segundo va después del primero.'); end if;
    v_ant := v_hasta; v_total := v_total + (v_hasta - v_desde + 1);
    v_tramos := v_tramos || jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'dias', v_hasta - v_desde + 1, 'feriado', coalesce((t ->> 'feriado')::boolean, false));
  end loop;
  v_ver := public.vac_token();
  insert into public.vacaciones (email, nombre, area, datos, aprueba_rrhh, estado, firmas, ver_hashes)
  values (v_mail, v_nombre, v_area,
          jsonb_build_object('tramos', v_tramos, 'total', v_total, 'avisos', coalesce(p_datos -> 'avisos', '[]'::jsonb), 'fecha', current_date),
          lower(btrim(v_cfg ->> 'rrhh')), 'nueva',
          jsonb_build_object('empleado', jsonb_build_object('png', p_firma, 'aclaracion', v_nombre, 'fecha', now(), 'email', v_mail)),
          array[public.vac_huella(v_ver)])
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'ver', v_ver, 'mias', public.vac_mias(v_mail));
end;
$$;

-- ── RR. HH. la deriva (desde el panel): a un jefe (su mail) o, sin jefe, la firma RR. HH. directamente ──
create or replace function public.vacaciones_derivar(p_id uuid, p_jefe text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_jefe text := nullif(lower(btrim(coalesce(p_jefe, ''))), ''); r record;
begin
  if not public.es_admin() then return jsonb_build_object('ok', false, 'error', 'Sin permiso'); end if;
  if v_jefe is not null and v_jefe !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then return jsonb_build_object('ok', false, 'error', 'Revisá el mail del jefe.'); end if;
  select * into r from public.vacaciones where id = p_id for update;
  if not found or r.estado not in ('nueva', 'jefe') then return jsonb_build_object('ok', false, 'error', 'Esa solicitud ya no se puede derivar.'); end if;
  if v_jefe = r.aprueba_rrhh or v_jefe = r.email then v_jefe := null; end if;
  update public.vacaciones set aprueba_jefe = v_jefe, estado = case when v_jefe is null then 'rrhh' else 'jefe' end,
         aviso_hecho = null, token_hash = null, token_rol = null, derivada_por = coalesce(auth.jwt() ->> 'email', 'panel')
   where id = p_id;
  return jsonb_build_object('ok', true, 'estado', case when v_jefe is null then 'rrhh' else 'jefe' end);
end;
$$;

-- ── El aviso de cada paso (lo pide el servidor, que manda el mail) ──
--  nueva: a RR. HH. (para derivarla) y la confirmación a la persona; jefe / rrhh: a quien firma, con su link;
--  al final, a todos. Una vez por paso.
create or replace function public.vacaciones_aviso(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v_tok text; v_ver text;
begin
  select * into r from public.vacaciones where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no_esta'); end if;
  if r.aviso_hecho is not distinct from r.estado then return jsonb_build_object('ok', false, 'motivo', 'ya'); end if;
  if r.estado = 'nueva' then
    v_ver := public.vac_token();
    update public.vacaciones set aviso_hecho = 'nueva', ver_hashes = ver_hashes || public.vac_huella(v_ver) where id = r.id;
    return jsonb_build_object('ok', true, 'paso', 'nueva', 'ver', v_ver, 'para', r.aprueba_rrhh, 'rrhh', r.aprueba_rrhh,
      'email', r.email, 'nombre', r.nombre, 'area', r.area, 'datos', r.datos);
  end if;
  if r.estado in ('jefe', 'rrhh') then
    v_tok := public.vac_token();
    update public.vacaciones set token_hash = public.vac_huella(v_tok), token_rol = r.estado, token_vence = now() + interval '30 days', aviso_hecho = r.estado where id = r.id;
    return jsonb_build_object('ok', true, 'paso', r.estado, 'token', v_tok, 'con_jefe', r.aprueba_jefe is not null,
      'para', case when r.estado = 'jefe' then r.aprueba_jefe else r.aprueba_rrhh end, 'rrhh', r.aprueba_rrhh,
      'email', r.email, 'nombre', r.nombre, 'area', r.area, 'datos', r.datos);
  end if;
  v_ver := public.vac_token();
  update public.vacaciones set aviso_hecho = r.estado, ver_hashes = ver_hashes || public.vac_huella(v_ver) where id = r.id;
  return jsonb_build_object('ok', true, 'paso', 'fin', 'estado', r.estado, 'ver', v_ver, 'para', r.email,
    'copia', to_jsonb(array_remove(array[r.aprueba_jefe, r.aprueba_rrhh], null)), 'rrhh', r.aprueba_rrhh,
    'nombre', r.nombre, 'area', r.area, 'datos', r.datos, 'pdf', r.pdf,
    'decision', coalesce(r.firmas -> 'rrhh' ->> 'decision', r.firmas -> 'jefe' ->> 'decision'),
    'nota', coalesce(nullif(r.firmas -> 'rrhh' ->> 'nota', ''), r.firmas -> 'jefe' ->> 'nota'));
end;
$$;

-- ── Ver una solicitud: con un link (la persona, quien tiene que firmar o quien ya firmó) o con la sesión ──
create or replace function public.vac_ficha(r public.vacaciones, v_rol text) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('ok', true, 'id', r.id, 'rol', v_rol, 'estado', r.estado, 'nombre', r.nombre, 'email', r.email, 'area', r.area,
    'datos', r.datos, 'firmas', r.firmas, 'con_jefe', r.aprueba_jefe is not null, 'creada', r.created_at, 'tiene_pdf', r.pdf is not null)
$$;
revoke execute on function public.vac_ficha(public.vacaciones, text) from public, anon, authenticated;
create or replace function public.vacaciones_ver(p_token text, p_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare h text := public.vac_huella(p_token); r public.vacaciones; v_mail text;
begin
  if p_id is not null then
    v_mail := public.vac_quien(p_token);
    if v_mail is null then return jsonb_build_object('ok', false, 'error', 'Tu sesión venció. Entrá de nuevo con tu mail.'); end if;
    select * into r from public.vacaciones where id = p_id and email = v_mail;
    if not found then return jsonb_build_object('ok', false, 'error', 'No está esa solicitud.'); end if;
    return public.vac_ficha(r, 'ver');
  end if;
  if length(coalesce(p_token, '')) < 32 then return jsonb_build_object('ok', false, 'error', 'El link no es válido.'); end if;
  select * into r from public.vacaciones where token_hash = h or h = any(ver_hashes) limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'El link no es válido o ya no se usa.'); end if;
  if r.token_hash = h and r.estado = r.token_rol and r.token_vence <= now() then return jsonb_build_object('ok', false, 'error', 'El link venció. Pedile a RR. HH. que lo vuelva a mandar.'); end if;
  return public.vac_ficha(r, case when r.token_hash = h and r.estado = r.token_rol then r.token_rol else 'ver' end);
end;
$$;

-- ── Aprobar (o no) y firmar: el jefe directo o RR. HH. ──
create or replace function public.vacaciones_firmar(p_token text, p_decision text, p_aclaracion text, p_firma text, p_nota text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare h text := public.vac_huella(p_token); r record; v_ac text := btrim(regexp_replace(coalesce(p_aclaracion, ''), '\s+', ' ', 'g')); v_estado text;
begin
  select * into r from public.vacaciones where token_hash = h and estado = token_rol for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Esta solicitud ya está firmada o el link no es válido.'); end if;
  if r.token_vence <= now() then return jsonb_build_object('ok', false, 'error', 'El link venció. Pedile a RR. HH. que lo vuelva a mandar.'); end if;
  if p_decision not in ('aprobado', 'no_aprobado') then return jsonb_build_object('ok', false, 'error', 'Marcá si la aprobás o no.'); end if;
  if length(v_ac) < 3 then return jsonb_build_object('ok', false, 'error', 'Completá tu aclaración (nombre y apellido).'); end if;
  if coalesce(p_firma, '') !~ '^data:image/png;base64,' or length(p_firma) > 400000 then return jsonb_build_object('ok', false, 'error', 'Falta tu firma.'); end if;
  v_estado := case when p_decision = 'no_aprobado' then 'rechazada' when r.token_rol = 'jefe' then 'rrhh' else 'aprobada' end;
  update public.vacaciones
     set firmas = firmas || jsonb_build_object(r.token_rol, jsonb_build_object('png', p_firma, 'aclaracion', v_ac, 'decision', p_decision,
                    'nota', left(btrim(coalesce(p_nota, '')), 500), 'fecha', now(), 'email', case when r.token_rol = 'jefe' then r.aprueba_jefe else r.aprueba_rrhh end)),
         estado = v_estado, ver_hashes = ver_hashes || h, token_hash = null, token_rol = null
   where id = r.id;
  return jsonb_build_object('ok', true, 'id', r.id, 'estado', v_estado);
end;
$$;

-- ── El PDF final (lo arma la página de quien firmó último, como en los contratos) ──
create or replace function public.vacaciones_guardar_pdf(p_token text, p_pdf text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare h text := public.vac_huella(p_token); v_id uuid;
begin
  if length(coalesce(p_pdf, '')) < 100 or length(p_pdf) > 3000000 then return jsonb_build_object('ok', false); end if;
  update public.vacaciones set pdf = p_pdf where h = any(ver_hashes) and estado in ('aprobada', 'rechazada') and pdf is null returning id into v_id;
  return jsonb_build_object('ok', v_id is not null);
end;
$$;

-- ── Volver a mandar el aviso del paso en que está (desde el panel, si el mail no llegó) ──
create or replace function public.vacaciones_reenviar(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.es_admin() then return jsonb_build_object('ok', false, 'error', 'Sin permiso'); end if;
  update public.vacaciones set aviso_hecho = null where id = p_id and estado in ('jefe', 'rrhh');
  return jsonb_build_object('ok', found);
end;
$$;

-- Quién puede usar cada una: el formulario (sin usuario), el servidor y el panel.
revoke execute on function public.vacaciones_areas() from public;
revoke execute on function public.vacaciones_codigo(text) from public, anon, authenticated;
revoke execute on function public.vacaciones_entrar(text, text) from public;
revoke execute on function public.vacaciones_mias(text) from public;
revoke execute on function public.vacaciones_crear(text, jsonb, text) from public;
revoke execute on function public.vacaciones_derivar(uuid, text) from public, anon;
revoke execute on function public.vacaciones_aviso(uuid) from public, anon, authenticated;
revoke execute on function public.vacaciones_ver(text, uuid) from public;
revoke execute on function public.vacaciones_firmar(text, text, text, text, text) from public;
revoke execute on function public.vacaciones_guardar_pdf(text, text) from public;
revoke execute on function public.vacaciones_reenviar(uuid) from public, anon;
grant execute on function public.vacaciones_areas() to anon, authenticated;
grant execute on function public.vacaciones_entrar(text, text) to anon, authenticated;
grant execute on function public.vacaciones_mias(text) to anon, authenticated;
grant execute on function public.vacaciones_crear(text, jsonb, text) to anon, authenticated;
grant execute on function public.vacaciones_ver(text, uuid) to anon, authenticated;
grant execute on function public.vacaciones_firmar(text, text, text, text, text) to anon, authenticated;
grant execute on function public.vacaciones_guardar_pdf(text, text) to anon, authenticated;
grant execute on function public.vacaciones_derivar(uuid, text) to authenticated;
grant execute on function public.vacaciones_reenviar(uuid) to authenticated;
grant execute on function public.vacaciones_codigo(text) to service_role;
grant execute on function public.vacaciones_aviso(uuid) to service_role;

-- Cómo quedó (sólo sí/no y cantidades).
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('vacaciones', 'vacaciones_codigos', 'vacaciones_sesiones')) = 3 as tablas,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'vacaciones%') as funciones,
  has_function_privilege('anon', 'public.vacaciones_crear(text, jsonb, text)', 'execute') as formulario_abierto,
  not has_function_privilege('anon', 'public.vacaciones_aviso(uuid)', 'execute') and not has_function_privilege('anon', 'public.vacaciones_derivar(uuid, text)', 'execute') as lo_demas_cerrado,
  exists (select 1 from public.config where key = 'vacaciones') as configurado;
