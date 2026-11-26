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
--  La trazabilidad, como en los contratos: cada paso queda en vacaciones_eventos (cuándo, quién, la IP y el dispositivo):
--  la persona la firma, los mails que salen, la derivación, cuándo el jefe o RR. HH. abren el link y firman, el PDF.
--  La solicitud tiene un ID de transacción y la huella (SHA-256) de su contenido; una vez firmada, el contenido y las
--  firmas no se pueden cambiar. Todo va en el informe de auditoría del PDF.
--
--  Modificar o cancelar (24-nov): mientras no firmó el jefe ni RR. HH., la persona (entrando con su mail) la puede
--  cancelar o modificar. Lo firmado no se cambia: modificarla es mandar una nueva, firmada, que reemplaza a la anterior
--  (la anterior queda cancelada, con su trazabilidad). Si estaba derivada, el link del jefe deja de servir.
--
--  Un mail por persona (25-nov, Thomas: Mercedes es jefa de área y de RR. HH.; "que le llegue una vez por persona,
--  así no tiene un quilombo para firmar"): la solicitud le llega SOLA al jefe del área (ya no hay que derivarla), con
--  "X, de tu equipo, firmó: firmá vos para aprobar"; después, a RR. HH. para firmar. Si el área no tiene jefe, si el
--  jefe es RR. HH. o si quien la pide es el jefe, va directo a RR. HH. Sólo un área que no está en la lista ("Otra")
--  queda para que RR. HH. la derive desde el panel. Al final, el PDF va a la persona, con copia a quien firmó antes;
--  a RR. HH. sólo si no firmó (porque la rechazó el jefe). Si la cancelan o la modifican, el aviso va a quien la
--  tenía para firmar, y sólo si hace falta.
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
  aprueba_jefe text,                                 -- el jefe directo (null: su jefe directo es RR. HH., que firma una vez)
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
alter table public.vacaciones add constraint vacaciones_estado_check check (estado in ('nueva', 'jefe', 'rrhh', 'aprobada', 'rechazada', 'cancelada'));
alter table public.vacaciones alter column estado set default 'nueva';
alter table public.vacaciones add column if not exists derivada_por text;
-- Las vacaciones de quien firma por RR. HH. (la jefa de RR. HH.): las aprueban los socios, que están por arriba de ella
-- (25-nov, Thomas). En ese caso el paso "rrhh" lo firma uno de los socios.
alter table public.vacaciones add column if not exists aprueban_socios boolean not null default false;
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

-- ── LA TRAZABILIDAD ──
alter table public.vacaciones add column if not exists transaccion_id text;
alter table public.vacaciones add column if not exists hash_contenido text;
create table if not exists public.vacaciones_eventos (
  id          bigserial primary key,
  vacacion_id uuid not null references public.vacaciones(id) on delete cascade,
  tipo        text not null,        -- creada, aviso, derivada, abierta, firmada, pdf, reenviada
  quien       text,
  detalle     text,
  ip          text,
  user_agent  text,
  fecha       timestamptz not null default clock_timestamp()
);
create index if not exists vacaciones_eventos_idx on public.vacaciones_eventos (vacacion_id, fecha);
alter table public.vacaciones_eventos enable row level security;
revoke all on public.vacaciones_eventos from anon, authenticated;
grant select on public.vacaciones_eventos to authenticated;
drop policy if exists vacaciones_eventos_admin on public.vacaciones_eventos;
create policy vacaciones_eventos_admin on public.vacaciones_eventos for select to authenticated using (public.es_admin());
-- Un paso, con la IP y el dispositivo de quien lo hizo (los mails los manda el servidor: sin IP).
create or replace function public.vac_evento(p_id uuid, p_tipo text, p_quien text, p_detalle text, p_sistema boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare h json;
begin
  begin h := nullif(current_setting('request.headers', true), '')::json; exception when others then h := null; end;
  insert into public.vacaciones_eventos (vacacion_id, tipo, quien, detalle, ip, user_agent)
  values (p_id, p_tipo, p_quien, p_detalle,
          case when p_sistema then null else nullif(btrim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)), '') end,
          case when p_sistema then 'Sistema (automático)' else left(nullif(h ->> 'user-agent', ''), 300) end);
end;
$$;
revoke execute on function public.vac_evento(uuid, text, text, text, boolean) from public, anon, authenticated;
-- La huella del contenido (quién, qué área, qué fechas): si algo cambiara, no coincidiría.
create or replace function public.vac_hash_contenido(p_nombre text, p_email text, p_area text, p_datos jsonb) returns text
language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(jsonb_build_object('nombre', p_nombre, 'email', p_email, 'area', p_area, 'datos', p_datos)::text, 'UTF8')), 'hex')
$$;
revoke execute on function public.vac_hash_contenido(text, text, text, jsonb) from public, anon, authenticated;
-- Las que ya estaban (las de prueba): su ID, su huella y el paso de cuando se firmaron.
update public.vacaciones set transaccion_id = upper(replace(id::text, '-', '')), hash_contenido = public.vac_hash_contenido(nombre, email, area, datos) where hash_contenido is null;
insert into public.vacaciones_eventos (vacacion_id, tipo, quien, detalle, fecha)
select v.id, 'creada', v.email, 'Completó y firmó la solicitud (antes de la trazabilidad: sin IP)', coalesce((v.firmas -> 'empleado' ->> 'fecha')::timestamptz, v.created_at)
  from public.vacaciones v where not exists (select 1 from public.vacaciones_eventos e where e.vacacion_id = v.id);
-- Una vez firmada, el contenido, la firma de la persona, las firmas que ya están y el PDF no se cambian.
create or replace function public.vacaciones_inmutable() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.nombre is distinct from old.nombre or new.email is distinct from old.email or new.area is distinct from old.area or new.datos is distinct from old.datos
     or (old.hash_contenido is not null and new.hash_contenido is distinct from old.hash_contenido)
     or (old.transaccion_id is not null and new.transaccion_id is distinct from old.transaccion_id)
     or (new.firmas -> 'empleado') is distinct from (old.firmas -> 'empleado')
     or (old.firmas ? 'jefe' and (new.firmas -> 'jefe') is distinct from (old.firmas -> 'jefe'))
     or (old.firmas ? 'rrhh' and (new.firmas -> 'rrhh') is distinct from (old.firmas -> 'rrhh'))
     or (old.pdf is not null and new.pdf is distinct from old.pdf) then
    raise exception 'La solicitud está firmada: no se puede cambiar.';
  end if;
  return new;
end;
$$;
revoke execute on function public.vacaciones_inmutable() from public, anon, authenticated;
drop trigger if exists vacaciones_inmutable on public.vacaciones;
create trigger vacaciones_inmutable before update on public.vacaciones for each row execute function public.vacaciones_inmutable();

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

-- ¿Es jefe de área? (su mail es el jefe de alguna área de la config). Los jefes de área no tienen jefe de área: dependen
-- de RR. HH., que firma sus vacaciones (25-nov, Thomas).
create or replace function public.vac_es_jefe(p_mail text) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from public.config c, jsonb_array_elements(coalesce(c.value -> 'areas', '[]'::jsonb)) a
                  where c.key = 'vacaciones' and nullif(lower(btrim(coalesce(a ->> 'jefe', ''))), '') = lower(btrim(coalesce(p_mail, ''))))
$$;
revoke execute on function public.vac_es_jefe(text) from public, anon, authenticated;

-- Los mails de los socios (config 'socios'), sin repetir. Aprueban las vacaciones de quien firma por RR. HH.
create or replace function public.vac_socios() returns text[]
language sql stable set search_path = public as $$
  select coalesce(array(select distinct lower(btrim(x)) from public.config c, jsonb_array_elements_text(coalesce(c.value -> 'socios', '[]'::jsonb)) x
                         where c.key = 'vacaciones' and btrim(x) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' order by 1), '{}')
$$;
revoke execute on function public.vac_socios() from public, anon, authenticated;

-- Los servicios fijos, por fuera de Corporativo (25-nov, Thomas: Colón Fábrica y Campo de Polo; config 'servicios').
-- Misma página y mismas reglas, con su propio link (/vacaciones/servicios, que muestra sólo estas áreas). Los aprueba
-- RR. HH. directo, sin intermediarios, y el PDF final no va a los socios ("no, sólo Corporativo").
-- 'servicios_antes': nombres viejos de un servicio (26-nov: "se llama Colón Fábrica, no Fábrica Colón"). Las solicitudes
-- que se mandaron con el nombre viejo lo conservan (es lo que firmó la persona) y siguen contando como servicio.
create or replace function public.vac_servicio(p_area text) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from public.config c, jsonb_array_elements_text(coalesce(c.value -> 'servicios', '[]'::jsonb) || coalesce(c.value -> 'servicios_antes', '[]'::jsonb)) x
                  where c.key = 'vacaciones' and btrim(x) <> '' and lower(btrim(x)) = lower(btrim(coalesce(p_area, ''))))
$$;
revoke execute on function public.vac_servicio(text) from public, anon, authenticated;
-- Las áreas del link de los servicios (las del link de Corporativo son las de vacaciones_areas).
create or replace function public.vacaciones_servicios() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_agg(btrim(s.x) order by s.n) from public.config c
                     cross join lateral jsonb_array_elements_text(coalesce(c.value -> 'servicios', '[]'::jsonb)) with ordinality as s(x, n)
                    where c.key = 'vacaciones' and btrim(s.x) <> ''), '[]'::jsonb)
$$;
revoke execute on function public.vacaciones_servicios() from public;
grant execute on function public.vacaciones_servicios() to anon, authenticated;

-- Se puede modificar o cancelar: todavía no firmó ni el jefe ni RR. HH.
create or replace function public.vac_modificable(p_estado text, p_firmas jsonb) returns boolean
language sql immutable set search_path = public as $$ select p_estado in ('nueva', 'jefe', 'rrhh') and not (p_firmas ? 'jefe') and not (p_firmas ? 'rrhh') $$;
revoke execute on function public.vac_modificable(text, jsonb) from public, anon, authenticated;

-- Lo de una persona: sus solicitudes, de la más nueva a la más vieja (sin las firmas ni el PDF).
create or replace function public.vac_mias(v_mail text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'creada', created_at, 'estado', estado, 'area', area, 'datos', datos, 'modificable', public.vac_modificable(estado, firmas), 'socios', aprueban_socios) order by created_at desc), '[]'::jsonb)
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
drop function if exists public.vacaciones_crear(text, jsonb, text);
create or replace function public.vacaciones_crear(p_sesion text, p_datos jsonb, p_firma text, p_reemplaza uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_mail   text := public.vac_quien(p_sesion);
  v_nombre text := btrim(regexp_replace(coalesce(p_datos ->> 'nombre', ''), '\s+', ' ', 'g'));
  v_area   text := btrim(coalesce(p_datos ->> 'area', ''));
  v_cfg    jsonb := (select value from public.config where key = 'vacaciones');
  t jsonb; v_desde date; v_hasta date; v_tramos jsonb := '[]'::jsonb; v_total int := 0; v_ant date; v_ver text; v_id uuid; v_datos jsonb; v_vieja record; v_extra text;
  v_jefe text; v_estado text; v_socios boolean;
begin
  if v_mail is null then return jsonb_build_object('ok', false, 'error', 'Tu sesión venció. Entrá de nuevo con tu mail (lo que completaste queda).'); end if;
  if v_cfg is null or coalesce(v_cfg ->> 'rrhh', '') = '' then return jsonb_build_object('ok', false, 'error', 'Todavía no está configurado RR. HH. Avisale a RR. HH.'); end if;
  if length(v_nombre) < 3 then return jsonb_build_object('ok', false, 'error', 'Completá tu nombre y apellido.'); end if;
  if v_area = '' then return jsonb_build_object('ok', false, 'error', 'Elegí tu área.'); end if;
  if coalesce(p_firma, '') !~ '^data:image/png;base64,' or length(p_firma) > 400000 then return jsonb_build_object('ok', false, 'error', 'Falta tu firma.'); end if;
  if p_reemplaza is not null then
    select * into v_vieja from public.vacaciones where id = p_reemplaza and email = v_mail for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'No está la solicitud que querés modificar.'); end if;
    if not public.vac_modificable(v_vieja.estado, v_vieja.firmas) then return jsonb_build_object('ok', false, 'error', 'Esa solicitud ya no se puede modificar: ya la firmó tu jefe o RR. HH.'); end if;
  end if;
  if (select count(*) from public.vacaciones where email = v_mail and created_at > now() - interval '1 day') >= 8 then
    return jsonb_build_object('ok', false, 'error', 'Ya mandaste varias solicitudes hoy. Si hace falta corregir algo, escribile a RR. HH.');
  end if;
  -- Los tramos: 1 o 2; cada uno de 7 días corridos o más y que empiece un lunes (o el martes, si el lunes es feriado).
  if jsonb_typeof(p_datos -> 'tramos') <> 'array' or jsonb_array_length(p_datos -> 'tramos') not between 1 and 2 then return jsonb_build_object('ok', false, 'error', 'Completá las fechas.'); end if;
  for t in select * from jsonb_array_elements(p_datos -> 'tramos') loop
    begin v_desde := (t ->> 'desde')::date; v_hasta := (t ->> 'hasta')::date; exception when others then return jsonb_build_object('ok', false, 'error', 'Revisá las fechas.'); end;
    if v_desde is null or v_hasta is null or v_hasta < v_desde then return jsonb_build_object('ok', false, 'error', 'Revisá las fechas: el "hasta" va después del "desde".'); end if;
    -- Los tramos de menos de 7 días se pueden pedir (25-nov: acuerdos internos), sujetos a aprobación; el lunes se exige
    -- sólo en los de 7 días o más.
    if v_hasta - v_desde + 1 >= 7 and extract(isodow from v_desde) <> 1 and not (extract(isodow from v_desde) = 2 and coalesce((t ->> 'feriado')::boolean, false)) then
      return jsonb_build_object('ok', false, 'error', 'Cada tramo empieza un lunes (o el martes, si el lunes es feriado).'); end if;
    if v_ant is not null and v_desde <= v_ant then return jsonb_build_object('ok', false, 'error', 'Los tramos no se pueden superponer: el segundo va después del primero.'); end if;
    v_ant := v_hasta; v_total := v_total + (v_hasta - v_desde + 1);
    v_tramos := v_tramos || jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'dias', v_hasta - v_desde + 1, 'feriado', coalesce((t ->> 'feriado')::boolean, false));
  end loop;
  v_ver := public.vac_token(); v_id := gen_random_uuid();
  v_datos := jsonb_build_object('tramos', v_tramos, 'total', v_total, 'avisos', coalesce(p_datos -> 'avisos', '[]'::jsonb), 'fecha', current_date);
  -- Una nota de la persona (25-nov: acuerdos internos), si escribió algo. Es parte de lo que firma.
  if nullif(btrim(coalesce(p_datos ->> 'nota', '')), '') is not null then v_datos := v_datos || jsonb_build_object('nota', left(btrim(p_datos ->> 'nota'), 500)); end if;
  if p_reemplaza is not null then
    v_datos := v_datos || jsonb_build_object('reemplaza', jsonb_build_object('id', v_vieja.id, 'transaccion_id', v_vieja.transaccion_id, 'fecha', v_vieja.created_at));
    v_extra := '. Modifica la solicitud ' || coalesce(v_vieja.transaccion_id, v_vieja.id::text);
  end if;
  -- A quién le llega: al jefe de su área, sola. Si el área no tiene otro jefe que RR. HH. o si la pide el jefe, su jefe
  -- directo es RR. HH.: le llega directo y firma una sola vez.
  -- Un área que no está en la lista: queda "nueva", para que RR. HH. la derive desde el panel.
  select lower(btrim(coalesce(a ->> 'jefe', ''))) into v_jefe
    from jsonb_array_elements(coalesce(v_cfg -> 'areas', '[]'::jsonb)) a where lower(btrim(coalesce(a ->> 'nombre', ''))) = lower(v_area) limit 1;
  v_estado := case when not found then 'nueva' when v_jefe = '' or v_jefe = lower(btrim(v_cfg ->> 'rrhh')) or v_jefe = v_mail then 'rrhh' else 'jefe' end;
  -- Un jefe de área va siempre a RR. HH., aunque elija otra área.
  if public.vac_es_jefe(v_mail) then v_estado := 'rrhh'; end if;
  -- Un servicio fijo (Colón Fábrica, Campo de Polo): lo aprueba RR. HH. directo, sin intermediarios.
  if public.vac_servicio(v_area) then v_estado := 'rrhh'; end if;
  -- La pide quien firma por RR. HH.: la aprueban los socios (si están cargados; si no, como hasta ahora).
  v_socios := v_mail = lower(btrim(v_cfg ->> 'rrhh')) and cardinality(public.vac_socios()) > 0;
  if v_socios then v_estado := 'rrhh'; end if;
  if v_estado <> 'jefe' then v_jefe := null; end if;
  insert into public.vacaciones (id, email, nombre, area, datos, aprueba_jefe, aprueba_rrhh, estado, derivada_por, firmas, ver_hashes, transaccion_id, hash_contenido, aprueban_socios)
  values (v_id, v_mail, v_nombre, v_area, v_datos, v_jefe, lower(btrim(v_cfg ->> 'rrhh')), v_estado, case when v_estado <> 'nueva' then 'automático' end,
          jsonb_build_object('empleado', jsonb_build_object('png', p_firma, 'aclaracion', v_nombre, 'fecha', now(), 'email', v_mail)),
          array[public.vac_huella(v_ver)], upper(replace(v_id::text, '-', '')), public.vac_hash_contenido(v_nombre, v_mail, v_area, v_datos), v_socios);
  perform public.vac_evento(v_id, 'creada', v_mail, 'Completó y firmó la solicitud. Entró con el código enviado a su mail. Huella de la firma: ' || left(public.vac_huella(p_firma), 16) || coalesce(v_extra, ''));
  if v_estado <> 'nueva' then
    perform public.vac_evento(v_id, 'derivada', 'automático', case when v_estado = 'jefe' then 'Va sola al jefe directo del área (' || v_area || '): ' || v_jefe
      when v_socios then 'Es de RR. HH. (quien firma por RR. HH.): va directo a los socios, que la aprueban (firma uno de ellos)'
      when public.vac_servicio(v_area) then 'Es de ' || v_area || ' (servicio fijo): va directo a RR. HH., que la aprueba (firma una sola vez)'
      else 'Va directo a RR. HH., que es su jefe directo (firma una sola vez)' end, true);
  end if;
  -- La anterior queda cancelada (reemplazada): el link del jefe, si estaba derivada, deja de servir (queda para verla).
  if p_reemplaza is not null then
    update public.vacaciones set estado = 'cancelada', aviso_hecho = null, ver_hashes = case when token_hash is not null then ver_hashes || token_hash else ver_hashes end,
           token_hash = null, token_rol = null where id = v_vieja.id;
    perform public.vac_evento(v_vieja.id, 'reemplazada', v_mail, 'La modificó: la reemplaza la solicitud ' || upper(replace(v_id::text, '-', '')));
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'ver', v_ver, 'mias', public.vac_mias(v_mail), 'reemplazada', p_reemplaza);
end;
$$;

-- ── Cancelarla (la persona, con su sesión), mientras no firmó el jefe ni RR. HH. ──
create or replace function public.vacaciones_cancelar(p_sesion text, p_id uuid, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_mail text := public.vac_quien(p_sesion); r record;
begin
  if v_mail is null then return jsonb_build_object('ok', false, 'error', 'Tu sesión venció. Entrá de nuevo con tu mail.'); end if;
  select * into r from public.vacaciones where id = p_id and email = v_mail for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'No está esa solicitud.'); end if;
  if not public.vac_modificable(r.estado, r.firmas) then return jsonb_build_object('ok', false, 'error', 'Ya no se puede cancelar: ya la firmó tu jefe o RR. HH. Escribile a RR. HH.'); end if;
  update public.vacaciones set estado = 'cancelada', aviso_hecho = null, ver_hashes = case when token_hash is not null then ver_hashes || token_hash else ver_hashes end,
         token_hash = null, token_rol = null where id = r.id;
  perform public.vac_evento(r.id, 'cancelada', v_mail, 'La canceló la persona' || coalesce('. Motivo: ' || nullif(left(btrim(coalesce(p_motivo, '')), 300), ''), ''));
  return jsonb_build_object('ok', true, 'id', r.id, 'mias', public.vac_mias(v_mail));
end;
$$;

-- ── RR. HH. la deriva (desde el panel): a un jefe (su mail) o, si su jefe directo es RR. HH., la firma RR. HH. una vez ──
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
  perform public.vac_evento(p_id, 'derivada', coalesce(auth.jwt() ->> 'email', 'panel'), case when v_jefe is null then 'Su jefe directo es RR. HH.: la firma una sola vez' else 'Derivada al jefe directo: ' || v_jefe end);
  return jsonb_build_object('ok', true, 'estado', case when v_jefe is null then 'rrhh' else 'jefe' end);
end;
$$;

-- ── El aviso de cada paso (lo pide el servidor, que manda el mail) ──
--  nueva (un área que no está en la lista): a RR. HH., para derivarla; jefe / rrhh: a quien firma, con su link (y,
--  la primera vez, la confirmación a la persona); al final, a la persona con copia a quien firmó antes (a RR. HH. sólo
--  si no firmó). Cancelada o modificada: a quien la tenía para firmar, si hace falta. Una vez por paso.
create or replace function public.vacaciones_aviso(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v_tok text; v_ver text; v_para text; v_nueva text; v_copia text[]; v_avance text;
  v_cfg jsonb := (select value from public.config where key = 'vacaciones');
begin
  select * into r from public.vacaciones where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no_esta'); end if;
  if r.aviso_hecho is not distinct from r.estado then return jsonb_build_object('ok', false, 'motivo', 'ya'); end if;
  if r.estado = 'nueva' then
    v_ver := public.vac_token();
    update public.vacaciones set aviso_hecho = 'nueva', ver_hashes = ver_hashes || public.vac_huella(v_ver) where id = r.id;
    perform public.vac_evento(r.id, 'aviso', r.aprueba_rrhh, 'Mail a RR. HH. para derivarla', true);
    perform public.vac_evento(r.id, 'aviso', r.email, 'Mail a la persona: la recibimos, con su link para verla', true);
    return jsonb_build_object('ok', true, 'paso', 'nueva', 'ver', v_ver, 'para', r.aprueba_rrhh, 'rrhh', r.aprueba_rrhh, 'fuera_de_lista', true, 'es_jefe', public.vac_es_jefe(r.email),
      'email', r.email, 'nombre', r.nombre, 'area', r.area, 'datos', r.datos);
  end if;
  if r.estado = 'cancelada' then
    update public.vacaciones set aviso_hecho = 'cancelada' where id = r.id;
    -- Quien la tenía para firmar: el jefe, si se la habían mandado; si no, RR. HH. (para firmar o para derivar).
    v_para := coalesce(r.aprueba_jefe, r.aprueba_rrhh);
    if exists (select 1 from public.vacaciones_eventos e where e.vacacion_id = r.id and e.tipo = 'reemplazada') then
      -- Si la nueva le llega a la misma persona, ese mail ya dice que reemplaza a ésta: no hace falta otro.
      select coalesce(n.aprueba_jefe, n.aprueba_rrhh) into v_nueva from public.vacaciones n where n.datos -> 'reemplaza' ->> 'id' = r.id::text order by n.created_at desc limit 1;
      if v_nueva is not distinct from v_para then return jsonb_build_object('ok', false, 'motivo', 'mismo'); end if;
      perform public.vac_evento(r.id, 'aviso', v_para, 'Mail: la modificó y el link para firmar ésta quedó sin efecto', true);
      return jsonb_build_object('ok', true, 'paso', 'cancelada', 'reemplazada', true, 'para', v_para, 'copia', '[]'::jsonb, 'rrhh', r.aprueba_rrhh,
        'a_jefe', r.aprueba_jefe is not null, 'email', r.email, 'nombre', r.nombre, 'area', r.area, 'datos', r.datos);
    end if;
    -- Si la aprobaban los socios, el aviso les llega a ellos.
    if r.aprueban_socios and r.aprueba_jefe is null then v_para := 'socios'; end if;
    perform public.vac_evento(r.id, 'aviso', v_para, 'Mail ' || case when r.aprueba_jefe is not null then 'al jefe' when v_para = 'socios' then 'a los socios' else 'a RR. HH.' end || ': la canceló', true);
    return jsonb_build_object('ok', true, 'paso', 'cancelada', 'reemplazada', false, 'para', v_para, 'para_lista', case when v_para = 'socios' then to_jsonb(public.vac_socios()) end, 'copia', '[]'::jsonb, 'rrhh', r.aprueba_rrhh,
      'a_jefe', r.aprueba_jefe is not null, 'email', r.email, 'nombre', r.nombre, 'area', r.area, 'datos', r.datos,
      'motivo', (select substring(e.detalle from 'Motivo: (.*)$') from public.vacaciones_eventos e where e.vacacion_id = r.id and e.tipo = 'cancelada' order by e.fecha desc limit 1));
  end if;
  if r.estado in ('jefe', 'rrhh') then
    v_tok := public.vac_token();
    update public.vacaciones set token_hash = public.vac_huella(v_tok), token_rol = r.estado, token_vence = now() + interval '30 days', aviso_hecho = r.estado where id = r.id;
    -- Quien firma ahora: el jefe, RR. HH. o, si es de quien firma por RR. HH., los socios (el mismo link a todos; firma uno).
    v_para := case when r.estado = 'jefe' then r.aprueba_jefe when r.aprueban_socios then 'socios' else r.aprueba_rrhh end;
    perform public.vac_evento(r.id, 'aviso', v_para,
      'Mail con el link personal para aprobar y firmar (' || case when r.estado = 'jefe' then 'jefe directo' when v_para = 'socios' then 'socios: ' || array_to_string(public.vac_socios(), ', ') else 'RR. HH.' end || ')', true);
    -- La primera vez, también la confirmación a la persona, con su link para verla.
    if not exists (select 1 from public.vacaciones_eventos e where e.vacacion_id = r.id and e.tipo = 'aviso' and e.quien = r.email) then
      v_ver := public.vac_token();
      update public.vacaciones set ver_hashes = ver_hashes || public.vac_huella(v_ver) where id = r.id;
      perform public.vac_evento(r.id, 'aviso', r.email, 'Mail a la persona: la recibimos, con su link para verla', true);
    end if;
    -- Cómo va (25-nov, Thomas): si ya la aprobó el jefe, a la persona "tu jefe la aprobó; ahora le toca a RR. HH.". Una vez.
    if r.estado = 'rrhh' and r.firmas ? 'jefe' and not exists (select 1 from public.vacaciones_eventos e where e.vacacion_id = r.id and e.tipo = 'aviso'
         and e.quien = r.email and e.detalle like 'Mail a la persona: su jefe la aprobó%') then
      v_avance := public.vac_token();
      update public.vacaciones set ver_hashes = ver_hashes || public.vac_huella(v_avance) where id = r.id;
      perform public.vac_evento(r.id, 'aviso', r.email, 'Mail a la persona: su jefe la aprobó y ahora le toca a RR. HH.', true);
    end if;
    -- equipo: quien firma es su jefe directo (el del área o RR. HH.): "Es de tu equipo y ya firmó".
    return jsonb_build_object('ok', true, 'paso', r.estado, 'token', v_tok, 'con_jefe', r.aprueba_jefe is not null, 'ver', v_ver, 'avance', v_avance,
      'equipo', r.estado = 'jefe' or r.aprueba_jefe is null, 'jefe_nombre', r.firmas -> 'jefe' ->> 'aclaracion', 'es_jefe', public.vac_es_jefe(r.email),
      'socios', v_para = 'socios', 'servicio', public.vac_servicio(r.area), 'para', v_para, 'para_lista', case when v_para = 'socios' then to_jsonb(public.vac_socios()) end, 'rrhh', r.aprueba_rrhh,
      'email', r.email, 'nombre', r.nombre, 'area', r.area, 'datos', r.datos);
  end if;
  v_ver := public.vac_token();
  update public.vacaciones set aviso_hecho = r.estado, ver_hashes = ver_hashes || public.vac_huella(v_ver) where id = r.id;
  -- La copia: a quien firmó antes que la decisión final (el jefe, si después firmó RR. HH.); a RR. HH., sólo si no firmó.
  v_copia := array_remove(array[case when r.aprueba_jefe is not null and r.firmas ? 'rrhh' then r.aprueba_jefe end,
                                case when not (r.firmas ? 'rrhh') then r.aprueba_rrhh end], null);
  -- Y las casillas fijas, sin repetir: 'copias' (p. ej. legales) en todas las que se cierran; 'socios', sólo en las
  -- aprobadas (25-nov, Thomas: "a los socios, cuando está todo aprobado, no los rechazados"); 'copias_servicios', en todas
  -- las de los servicios fijos, aprobadas o no (25-nov: "copia de todo lo que completan los de Colón y Campo, no los corporativos").
  v_copia := array(select distinct m from unnest(v_copia || array(select lower(btrim(x))
                                                                    from jsonb_array_elements_text(coalesce(v_cfg -> 'copias', '[]'::jsonb)
                                                                           || case when (r.estado = 'aprobada' and not public.vac_servicio(r.area)) or r.aprueban_socios then coalesce(v_cfg -> 'socios', '[]'::jsonb) else '[]'::jsonb end
                                                                           || case when public.vac_servicio(r.area) then coalesce(v_cfg -> 'copias_servicios', '[]'::jsonb) else '[]'::jsonb end) x
                                                              where btrim(x) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')) m
                    where m <> r.email and m is distinct from (case when r.firmas ? 'rrhh' then r.aprueba_rrhh end) order by m);
  perform public.vac_evento(r.id, 'aviso', r.email, 'Mail final (' || case when r.estado = 'aprobada' then 'aprobada' else 'no aprobada' end || ')' || case when r.pdf is not null then ', con el PDF firmado' else '' end
    || coalesce(', con copia a ' || nullif(array_to_string(v_copia, ', '), ''), ''), true);
  return jsonb_build_object('ok', true, 'paso', 'fin', 'estado', r.estado, 'ver', v_ver, 'para', r.email,
    'copia', to_jsonb(v_copia), 'rrhh', r.aprueba_rrhh, 'con_jefe', r.aprueba_jefe is not null, 'socios', r.aprueban_socios, 'servicio', public.vac_servicio(r.area),
    'nombre', r.nombre, 'area', r.area, 'datos', r.datos, 'pdf', r.pdf,
    'decision', coalesce(r.firmas -> 'rrhh' ->> 'decision', r.firmas -> 'jefe' ->> 'decision'),
    'nota', coalesce(nullif(r.firmas -> 'rrhh' ->> 'nota', ''), r.firmas -> 'jefe' ->> 'nota'));
end;
$$;

-- ── Ver una solicitud: con un link (la persona, quien tiene que firmar o quien ya firmó) o con la sesión ──
create or replace function public.vac_ficha(r public.vacaciones, v_rol text) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('ok', true, 'id', r.id, 'rol', v_rol, 'estado', r.estado, 'nombre', r.nombre, 'email', r.email, 'area', r.area,
    'datos', r.datos, 'firmas', r.firmas, 'con_jefe', r.aprueba_jefe is not null, 'creada', r.created_at, 'tiene_pdf', r.pdf is not null, 'modificable', public.vac_modificable(r.estado, r.firmas),
    'transaccion_id', r.transaccion_id, 'hash', r.hash_contenido, 'es_jefe', public.vac_es_jefe(r.email), 'socios', r.aprueban_socios, 'servicio', public.vac_servicio(r.area),
    'eventos', coalesce((select jsonb_agg(jsonb_build_object('tipo', e.tipo, 'quien', e.quien, 'detalle', e.detalle, 'ip', e.ip, 'user_agent', e.user_agent, 'fecha', e.fecha) order by e.fecha, e.id)
                           from public.vacaciones_eventos e where e.vacacion_id = r.id), '[]'::jsonb))
$$;
revoke execute on function public.vac_ficha(public.vacaciones, text) from public, anon, authenticated;
create or replace function public.vacaciones_ver(p_token text, p_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
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
  if r.token_hash = h and r.estado = r.token_rol and not exists (select 1 from public.vacaciones_eventos e where e.vacacion_id = r.id and e.tipo = 'abierta'
       and e.quien is not distinct from (case when r.token_rol = 'jefe' then r.aprueba_jefe when r.aprueban_socios then 'socios' else r.aprueba_rrhh end) and e.fecha > now() - interval '10 minutes') then
    perform public.vac_evento(r.id, 'abierta', case when r.token_rol = 'jefe' then r.aprueba_jefe when r.aprueban_socios then 'socios' else r.aprueba_rrhh end,
      'Abrió su link para aprobar y firmar (' || case when r.token_rol = 'jefe' then 'jefe directo' when r.aprueban_socios then 'socios' else 'RR. HH.' end || ')');
    select * into r from public.vacaciones where id = r.id;
  end if;
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
                    'nota', left(btrim(coalesce(p_nota, '')), 500), 'fecha', now(), 'email', case when r.token_rol = 'jefe' then r.aprueba_jefe when r.aprueban_socios then 'socios' else r.aprueba_rrhh end)),
         estado = v_estado, ver_hashes = ver_hashes || h, token_hash = null, token_rol = null
   where id = r.id;
  -- Los socios comparten el link: queda quién firmó por su aclaración.
  perform public.vac_evento(r.id, 'firmada', case when r.token_rol = 'jefe' then r.aprueba_jefe when r.aprueban_socios then 'socios' else r.aprueba_rrhh end,
    case when r.token_rol = 'jefe' then 'Jefe directo' when r.aprueban_socios then 'Socios' else 'RR. HH.' end || ': ' || case when p_decision = 'aprobado' then 'aprobó' else 'no aprobó' end
    || ' y firmó. Aclaración: ' || v_ac || '. Huella de la firma: ' || left(public.vac_huella(p_firma), 16));
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
  if v_id is not null then perform public.vac_evento(v_id, 'pdf', null, 'PDF final con las firmas guardado. Huella del PDF: ' || left(public.vac_huella(p_pdf), 16)); end if;
  return jsonb_build_object('ok', v_id is not null);
end;
$$;

-- ── Volver a mandar el aviso del paso en que está (desde el panel, si el mail no llegó) ──
create or replace function public.vacaciones_reenviar(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.es_admin() then return jsonb_build_object('ok', false, 'error', 'Sin permiso'); end if;
  update public.vacaciones set aviso_hecho = null where id = p_id and estado in ('jefe', 'rrhh');
  if found then perform public.vac_evento(p_id, 'reenviada', coalesce(auth.jwt() ->> 'email', 'panel'), 'RR. HH. pidió reenviar el link (el anterior deja de servir)'); return jsonb_build_object('ok', true); end if;
  return jsonb_build_object('ok', false);
end;
$$;

-- Quién puede usar cada una: el formulario (sin usuario), el servidor y el panel.
revoke execute on function public.vacaciones_areas() from public;
revoke execute on function public.vacaciones_codigo(text) from public, anon, authenticated;
revoke execute on function public.vacaciones_entrar(text, text) from public;
revoke execute on function public.vacaciones_mias(text) from public;
revoke execute on function public.vacaciones_crear(text, jsonb, text, uuid) from public;
revoke execute on function public.vacaciones_cancelar(text, uuid, text) from public;
revoke execute on function public.vacaciones_derivar(uuid, text) from public, anon;
revoke execute on function public.vacaciones_aviso(uuid) from public, anon, authenticated;
revoke execute on function public.vacaciones_ver(text, uuid) from public;
revoke execute on function public.vacaciones_firmar(text, text, text, text, text) from public;
revoke execute on function public.vacaciones_guardar_pdf(text, text) from public;
revoke execute on function public.vacaciones_reenviar(uuid) from public, anon;
grant execute on function public.vacaciones_areas() to anon, authenticated;
grant execute on function public.vacaciones_entrar(text, text) to anon, authenticated;
grant execute on function public.vacaciones_mias(text) to anon, authenticated;
grant execute on function public.vacaciones_crear(text, jsonb, text, uuid) to anon, authenticated;
grant execute on function public.vacaciones_cancelar(text, uuid, text) to anon, authenticated;
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
  has_function_privilege('anon', 'public.vacaciones_crear(text, jsonb, text, uuid)', 'execute') and has_function_privilege('anon', 'public.vacaciones_cancelar(text, uuid, text)', 'execute') as formulario_abierto,
  not has_function_privilege('anon', 'public.vacaciones_aviso(uuid)', 'execute') and not has_function_privilege('anon', 'public.vacaciones_derivar(uuid, text)', 'execute') as lo_demas_cerrado,
  exists (select 1 from public.config where key = 'vacaciones') as configurado,
  exists (select 1 from pg_trigger where tgname = 'vacaciones_inmutable' and not tgisinternal) and (select count(*) from public.vacaciones where hash_contenido is null) = 0 as trazabilidad;
