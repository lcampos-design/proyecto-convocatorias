-- ============================================================
--  QUE CADA UNO ACTUALICE SUS DATOS (convocatorias.show-bs.com/mis-datos)
--  Correr en Supabase → SQL Editor → Run, ANTES de usar la página.
--  Se puede volver a correr sin problema. No toca ningún dato.
--
--  Lo que pidió Mer: después de inscribirse, la gente no podía cambiar nada
--  (el CBU, el CV). Ahora pone su CUIL en /mis-datos y le llega un link al
--  mail que dejó al inscribirse; con ese link cambia sus datos, se guardan
--  directo y al panel le llega una notificación con qué cambió.
--
--  Por qué el link por mail y no sólo el CUIL: con el CUIL de otro, cualquiera
--  podría cambiarle el CBU y cobrar por él. El link llega sólo a su casilla,
--  vence en 24 horas, y del link se guarda sólo la huella (no el link).
--
--  Cada cambio queda anotado con el valor de antes en datos_cambios (lo ve
--  sólo el panel), por si alguien cambia un CBU y hay que saber cuál tenía.
--
--  Por ahora, para Argentina (Movistar Arena y Externos).
-- ============================================================

-- ── 1) EL DOCUMENTO, COMO LO COMPARA EL PANEL ──
--  "27-46990788-4", "27469907884" y "46990788" son la misma persona.
create or replace function public.doc_nucleo(p text)
returns text language sql immutable as $$
  select case
    when length(d) = 11 then nullif(ltrim(substr(d, 3, 8), '0'), '')
    when length(d) in (7, 8) then nullif(ltrim(d, '0'), '')
    else nullif(d, '') end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$$;

--  Los dos dígitos verificadores del CBU (el 8.º y el 22.º).
create or replace function public.cbu_valido(p text)
returns boolean language plpgsql immutable as $$
declare
  c text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
  w1 int[] := array[7, 1, 3, 9, 7, 1, 3];
  w2 int[] := array[3, 9, 7, 1, 3, 9, 7, 1, 3, 9, 7, 1, 3];
  s int := 0;
begin
  if length(c) <> 22 then return false; end if;
  for i in 1..7 loop s := s + w1[i] * substr(c, i, 1)::int; end loop;
  if (10 - s % 10) % 10 <> substr(c, 8, 1)::int then return false; end if;
  s := 0;
  for i in 1..13 loop s := s + w2[i] * substr(c, 8 + i, 1)::int; end loop;
  return (10 - s % 10) % 10 = substr(c, 22, 1)::int;
end;
$$;

-- ── 2) LOS LINKS ──
--  Nadie la lee de afuera: sólo las funciones de abajo.
create table if not exists public.datos_links (
  token_hash  text primary key,                     -- la huella del link, no el link
  nucleo      text not null,
  creado      timestamptz not null default now(),
  vence       timestamptz not null default now() + interval '24 hours',
  pedido_por  text not null default 'persona',      -- 'persona' o el mail del admin que se lo mandó
  usado       timestamptz
);
alter table public.datos_links enable row level security;
revoke all on public.datos_links from anon, authenticated;

-- ── 3) LO QUE CAMBIÓ CADA UNO (con el valor de antes) ──
create table if not exists public.datos_cambios (
  id      uuid primary key default gen_random_uuid(),
  nucleo  text not null,
  nombre  text,
  campo   text not null,
  antes   text,
  despues text,
  cuando  timestamptz not null default now()
);
alter table public.datos_cambios enable row level security;
revoke all on public.datos_cambios from anon, authenticated;
grant select on public.datos_cambios to authenticated;
drop policy if exists datos_cambios_admin on public.datos_cambios;
create policy datos_cambios_admin on public.datos_cambios for select to authenticated using (public.es_admin());
create index if not exists datos_cambios_nucleo on public.datos_cambios (nucleo, cuando desc);

-- ── 4) PEDIR EL LINK (la usa sólo el servidor, que manda el mail) ──
--  Devuelve el link y a qué casilla mandarlo. Hasta 3 por hora por persona,
--  y no más de 300 por hora en total: nadie puede llenarle la casilla a otro.
create or replace function public.mis_datos_link(p_cuit text, p_pedido_por text default 'persona')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_nuc    text := public.doc_nucleo(p_cuit);
  v_email  text;
  v_nombre text;
  v_area   text;
  v_token  text;
begin
  if v_nuc is null or length(regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g')) <> 11 then
    return jsonb_build_object('ok', false, 'motivo', 'cuil');
  end if;
  -- El mail: el de la nómina o, si no está, el de su inscripción más nueva.
  select email, nombre, area into v_email, v_nombre, v_area from public.personas
   where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' and coalesce(btrim(email), '') <> ''
   order by created_at desc nulls last limit 1;
  if v_email is null then
    select email, nombre, area into v_email, v_nombre, v_area from public.solicitudes
     where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' and coalesce(btrim(email), '') <> ''
     order by created_at desc limit 1;
  end if;
  if v_email is null then return jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); end if;
  if (select count(*) from public.datos_links where nucleo = v_nuc and creado > now() - interval '1 hour') >= 3 then
    return jsonb_build_object('ok', false, 'motivo', 'muchos', 'email', v_email);
  end if;
  if (select count(*) from public.datos_links where creado > now() - interval '1 hour') >= 300 then
    return jsonb_build_object('ok', false, 'motivo', 'ocupado');
  end if;
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.datos_links (token_hash, nucleo, pedido_por)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_nuc, coalesce(nullif(btrim(p_pedido_por), ''), 'persona'));
  return jsonb_build_object('ok', true, 'token', v_token, 'email', v_email, 'nombre', v_nombre, 'area', v_area);
end;
$$;
revoke execute on function public.mis_datos_link(text, text) from public, anon, authenticated;
grant  execute on function public.mis_datos_link(text, text) to service_role;

-- El núcleo del documento de un link vigente (o null).
create or replace function public.mis_datos_nucleo(p_token text)
returns text
language sql stable security definer set search_path = public as $$
  select nucleo from public.datos_links
   where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') and vence > now();
$$;
revoke execute on function public.mis_datos_nucleo(text) from public, anon, authenticated;

-- ── 5) VER LOS DATOS (con el link) ──
create or replace function public.mis_datos_ver(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_nuc text := public.mis_datos_nucleo(p_token);
  p public.personas%rowtype;
  s public.solicitudes%rowtype;
begin
  if v_nuc is null then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  select * into p from public.personas where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' order by created_at desc nulls last limit 1;
  select * into s from public.solicitudes where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' order by created_at desc limit 1;
  return jsonb_build_object('ok', true,
    'nombre', coalesce(p.nombre, s.nombre), 'area', coalesce(p.area, s.area),
    'email', coalesce(nullif(p.email, ''), s.email), 'tel', coalesce(nullif(p.tel, ''), s.tel),
    'localidad', coalesce(nullif(s.localidad, ''), p.localidad),
    'fecha_nacimiento', s.fecha_nacimiento, 'estudios', s.estudios, 'idiomas', s.idiomas,
    'disponibilidad', coalesce(nullif(p.cv->>'disponibilidad', ''), s.disponibilidad),
    'con_inscripcion', s.id is not null,
    'tiene_cuenta', case when s.cbu is not null and s.cbu <> '' then true else s.tiene_cuenta end,
    'cbu', s.cbu, 'numero_cuenta', s.numero_cuenta, 'banco', s.banco,
    'apellido', s.apellido, 'nombres', s.nombres, 'nacionalidad', s.nacionalidad, 'domicilio', s.domicilio, 'codigo_postal', s.codigo_postal,
    'cv', coalesce(p.cv->'archivo'->>'nombre', s.archivo_cv->>'nombre'));
end;
$$;
revoke execute on function public.mis_datos_ver(text) from public;
grant  execute on function public.mis_datos_ver(text) to anon, authenticated;

-- ── 6) GUARDAR (con el link) ──
--  Controla todo de nuevo (no se confía en la página), anota lo que cambió con
--  el valor de antes, actualiza su inscripción y su ficha de la nómina, y deja
--  la notificación en el panel.
create or replace function public.mis_datos_guardar(p_token text, p_datos jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_nuc  text := public.mis_datos_nucleo(p_token);
  d      jsonb := coalesce(p_datos, '{}'::jsonb);
  p      public.personas%rowtype;
  s      public.solicitudes%rowtype;
  v_nombre text;
  v_email text := btrim(coalesce(d->>'email', ''));
  v_tel   text := btrim(coalesce(d->>'tel', ''));
  v_loc   text := btrim(coalesce(d->>'localidad', ''));
  v_nac   date;
  v_est   text := btrim(coalesce(d->>'estudios', ''));
  v_idi   text := nullif(btrim(coalesce(d->>'idiomas', '')), '');
  v_disp  text := btrim(coalesce(d->>'disponibilidad', ''));
  v_cta   boolean := (d->>'tiene_cuenta')::boolean;
  v_cbu   text := regexp_replace(coalesce(d->>'cbu', ''), '\D', '', 'g');
  v_nro   text := btrim(coalesce(d->>'numero_cuenta', ''));
  v_banco text := btrim(coalesce(d->>'banco', ''));
  v_ape   text := btrim(coalesce(d->>'apellido', ''));
  v_nom   text := btrim(coalesce(d->>'nombres', ''));
  v_nacio text := btrim(coalesce(d->>'nacionalidad', ''));
  v_dom   text := btrim(coalesce(d->>'domicilio', ''));
  v_cp    text := upper(regexp_replace(coalesce(d->>'codigo_postal', ''), '\s', '', 'g'));
  v_cv    jsonb := d->'cv';
  v_cambios text[] := '{}';
  falla  text;
begin
  if v_nuc is null then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  select * into p from public.personas where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' order by created_at desc nulls last limit 1;
  select * into s from public.solicitudes where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' order by created_at desc limit 1;
  v_nombre := coalesce(p.nombre, s.nombre);

  -- Los controles (los mismos que el formulario).
  begin v_nac := nullif(d->>'fecha_nacimiento', '')::date; exception when others then v_nac := null; end;
  falla := case
    when v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then 'Revisá el mail.'
    when length(regexp_replace(v_tel, '\D', '', 'g')) < 8 then 'Revisá el teléfono.'
    when v_loc = '' then 'Indicá tu localidad.'
    when v_nac is null or v_nac > current_date or v_nac < date '1900-01-01' then 'Revisá la fecha de nacimiento.'
    when v_est not in ('Secundario incompleto', 'Secundario en curso', 'Secundario completo', 'Terciario en curso', 'Terciario completo', 'Universitario en curso', 'Universitario completo', 'Posgrado') then 'Elegí tu nivel de estudios.'
    when v_disp = '' then 'Indicá tu disponibilidad.'
    when v_cta is null then 'Contanos si tenés una cuenta bancaria a tu nombre.'
    when v_cta and length(v_cbu) <> 22 then 'El CBU tiene que tener 22 números.'
    when v_cta and left(v_cbu, 7) in ('0000003', '0000086', '0000005', '3220001', '0000007', '0000004') then 'No se aceptan billeteras virtuales: poné el CBU de una cuenta bancaria.'
    when v_cta and not public.cbu_valido(v_cbu) then 'El CBU no es válido: revisá los números.'
    when v_cta and (v_nro = '' or v_banco = '') then 'Completá el número de cuenta y el banco.'
    when not v_cta and (v_ape = '' or v_nom = '') then 'Completá tu apellido y tu nombre como figuran en el DNI.'
    when not v_cta and v_nacio = '' then 'Indicá tu nacionalidad.'
    when not v_cta and v_dom = '' then 'Indicá tu domicilio.'
    when not v_cta and v_cp !~ '^(\d{4}|[A-Z]\d{4}[A-Z]{3})$' then 'Revisá el código postal.'
    when v_cv is not null and (coalesce(v_cv->>'datos', '') !~ '^data:' or length(v_cv->>'datos') > 1500000) then 'El CV tiene que ser un archivo de hasta 1 MB.'
  end;
  -- Sin inscripción (la cargó el equipo) no hay dónde guardar estos datos.
  if s.id is null then return jsonb_build_object('ok', false, 'motivo', 'sin_inscripcion', 'mensaje', 'Tu ficha la cargó nuestro equipo: escribinos y actualizamos tus datos nosotros.'); end if;
  if falla is not null then return jsonb_build_object('ok', false, 'motivo', 'datos', 'mensaje', falla); end if;
  if not v_cta then v_cbu := ''; v_nro := ''; v_banco := ''; else v_ape := ''; v_nom := ''; v_nacio := ''; v_dom := ''; v_cp := ''; end if;

  -- Lo que cambió, con el valor de antes.
  with campos(campo, etiqueta, antes, despues) as (values
    ('email', 'mail', coalesce(nullif(p.email, ''), s.email), v_email),
    ('tel', 'teléfono', coalesce(nullif(p.tel, ''), s.tel), v_tel),
    ('localidad', 'localidad', coalesce(nullif(s.localidad, ''), p.localidad), v_loc),
    ('fecha_nacimiento', 'fecha de nacimiento', s.fecha_nacimiento::text, v_nac::text),
    ('estudios', 'estudios', s.estudios, v_est),
    ('idiomas', 'idiomas', s.idiomas, v_idi),
    ('disponibilidad', 'disponibilidad', coalesce(nullif(p.cv->>'disponibilidad', ''), s.disponibilidad), v_disp),
    ('tiene_cuenta', 'si tiene cuenta', (case when coalesce(s.cbu, '') <> '' then true else s.tiene_cuenta end)::text, v_cta::text),
    ('cbu', 'CBU', s.cbu, nullif(v_cbu, '')),
    ('numero_cuenta', 'número de cuenta', s.numero_cuenta, nullif(v_nro, '')),
    ('banco', 'banco', s.banco, nullif(v_banco, '')),
    ('apellido', 'apellido', s.apellido, nullif(v_ape, '')),
    ('nombres', 'nombre', s.nombres, nullif(v_nom, '')),
    ('nacionalidad', 'nacionalidad', s.nacionalidad, nullif(v_nacio, '')),
    ('domicilio', 'domicilio', s.domicilio, nullif(v_dom, '')),
    ('codigo_postal', 'código postal', s.codigo_postal, nullif(v_cp, '')),
    ('cv', 'CV', coalesce(p.cv->'archivo'->>'nombre', s.archivo_cv->>'nombre'), case when v_cv is not null then v_cv->>'nombre' end)
  ), cambiados as (
    -- Un CV subido cuenta siempre (aunque el archivo se llame igual que el de antes).
    select * from campos
    where case when campo = 'cv' then despues is not null
               else coalesce(nullif(antes, ''), '') is distinct from coalesce(nullif(despues, ''), '') end
  ), anotados as (
    insert into public.datos_cambios (nucleo, nombre, campo, antes, despues)
    select v_nuc, v_nombre, campo, antes, despues from cambiados
    returning campo
  )
  select coalesce(array_agg(c.etiqueta order by c.etiqueta), '{}') into v_cambios
  from cambiados c;

  if array_length(v_cambios, 1) is null then
    return jsonb_build_object('ok', true, 'cambios', 0);
  end if;

  -- La inscripción (todas las de esa persona en Argentina, para que no quede una vieja con otro CBU).
  update public.solicitudes x set
    email = v_email, tel = v_tel, localidad = v_loc, fecha_nacimiento = v_nac, estudios = v_est, idiomas = v_idi,
    disponibilidad = v_disp, tiene_cuenta = v_cta,
    cbu = nullif(v_cbu, ''), numero_cuenta = nullif(v_nro, ''), banco = nullif(v_banco, ''),
    apellido = nullif(v_ape, ''), nombres = nullif(v_nom, ''), nacionalidad = nullif(v_nacio, ''),
    domicilio = nullif(v_dom, ''), codigo_postal = nullif(v_cp, ''),
    archivo_cv = case when v_cv is null then x.archivo_cv
                      else jsonb_build_object('nombre', v_cv->>'nombre', 'tipo', v_cv->>'tipo', 'datos', v_cv->>'datos')
                           || case when jsonb_typeof(x.archivo_cv->'extras') = 'array' then jsonb_build_object('extras', x.archivo_cv->'extras') else '{}'::jsonb end end
  where public.doc_nucleo(x.cuit) = v_nuc and x.area <> 'espana';

  -- Su ficha en la nómina (si ya está): contacto, disponibilidad y CV.
  update public.personas x set
    email = v_email, tel = v_tel, localidad = v_loc,
    cv = case when x.cv is null and v_cv is null then x.cv
              else jsonb_set(coalesce(x.cv, '{}'::jsonb), '{disponibilidad}', to_jsonb(v_disp))
                   || case when v_cv is not null then jsonb_build_object('archivo', jsonb_build_object('nombre', v_cv->>'nombre', 'tipo', v_cv->>'tipo', 'datos', v_cv->>'datos')) else '{}'::jsonb end end
  where public.doc_nucleo(x.cuit) = v_nuc and x.area <> 'espana';

  update public.datos_links set usado = now() where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex');

  -- La notificación en el panel (el 🔔).
  insert into public.notificaciones (id, tipo, titulo, cuerpo, destinatario_email, destinatario_nombre, estado)
  values (gen_random_uuid(), 'datos', '✏️ Actualizó sus datos — ' || coalesce(v_nombre, v_nuc),
          'Cambió: ' || array_to_string(v_cambios, ', ') || '.', null, v_nombre, 'pendiente');

  return jsonb_build_object('ok', true, 'cambios', array_length(v_cambios, 1), 'que', to_jsonb(v_cambios));
end;
$$;
revoke execute on function public.mis_datos_guardar(text, jsonb) from public;
grant  execute on function public.mis_datos_guardar(text, jsonb) to anon, authenticated;

-- ── CÓMO QUEDÓ ──
--  Las dos tienen que dar false (sin usuario no se pide un link ni se ve el historial)
--  y la última true (el link se pide desde el servidor).
select has_function_privilege('anon', 'public.mis_datos_link(text, text)', 'execute') as pedir_link_sin_usuario,
       has_table_privilege('anon', 'public.datos_cambios', 'select') as ver_cambios_sin_usuario,
       has_function_privilege('service_role', 'public.mis_datos_link(text, text)', 'execute') as pedir_link_desde_el_servidor;
