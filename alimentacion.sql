-- ============================================================
--  LA ALIMENTACIÓN, PARA LAS VIANDAS
--  Correr en Supabase → SQL Editor → Run, ANTES de que se suba el
--  formulario nuevo (si no, la inscripción de Argentina no se guarda).
--  Se puede volver a correr sin problema. No toca ningún dato.
--
--  Lo que pidió Mer (5-nov-2026): en el formulario de inscripción, el tipo
--  de alimentación para las viandas (regular, vegetariana, etc.). Se guarda
--  en la inscripción, como los estudios y los idiomas; lo ve el panel en la
--  ficha y en el Excel para supervisores, y cada uno lo puede cambiar desde
--  /mis-datos.
--
--  Opciones: Regular, Vegetariana, Vegana, Sin TACC (celíaca) u "Otra: …"
--  (lo que escriba, hasta 60 letras). Los que se inscribieron antes quedan
--  sin dato hasta que lo carguen en /mis-datos.
--
--  Las dos funciones de /mis-datos son las de mis-datos.sql con la
--  alimentación sumada (no hay que volver a correr mis-datos.sql: pisaría el
--  arreglo de seguridad-cbu.sql del link).
-- ============================================================

-- ── 1) LA COLUMNA, CON SUS OPCIONES ──
alter table public.solicitudes add column if not exists alimentacion text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'solicitudes_alimentacion_valida' and conrelid = 'public.solicitudes'::regclass) then
    alter table public.solicitudes add constraint solicitudes_alimentacion_valida check (
      alimentacion is null
      or alimentacion in ('Regular', 'Vegetariana', 'Vegana', 'Sin TACC (celíaca)')
      or alimentacion ~ '^Otra: \S.{0,59}$');
  end if;
end $$;

-- ── 2) VER LOS DATOS (con el link): la de mis-datos.sql, con la alimentación ──
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
    'alimentacion', s.alimentacion,
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

-- ── 3) GUARDAR (con el link): la de mis-datos.sql, con la alimentación ──
--  Si la página no la manda (la de antes), queda la que tenía: así no importa
--  qué se sube primero, si este SQL o la página.
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
  v_ali   text := btrim(coalesce(d->>'alimentacion', ''));
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
  if not (d ? 'alimentacion') then v_ali := coalesce(s.alimentacion, ''); end if;

  -- Los controles (los mismos que el formulario).
  begin v_nac := nullif(d->>'fecha_nacimiento', '')::date; exception when others then v_nac := null; end;
  falla := case
    when v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then 'Revisá el mail.'
    when length(regexp_replace(v_tel, '\D', '', 'g')) < 8 then 'Revisá el teléfono.'
    when v_loc = '' then 'Indicá tu localidad.'
    when v_nac is null or v_nac > current_date or v_nac < date '1900-01-01' then 'Revisá la fecha de nacimiento.'
    when v_est not in ('Secundario incompleto', 'Secundario en curso', 'Secundario completo', 'Terciario en curso', 'Terciario completo', 'Universitario en curso', 'Universitario completo', 'Posgrado') then 'Elegí tu nivel de estudios.'
    when d ? 'alimentacion' and v_ali not in ('Regular', 'Vegetariana', 'Vegana', 'Sin TACC (celíaca)') and v_ali !~ '^Otra: \S.{0,59}$' then 'Elegí tu alimentación (para las viandas).'
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
    ('alimentacion', 'alimentación', s.alimentacion, nullif(v_ali, '')),
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
    alimentacion = nullif(v_ali, ''),
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
--  Tiene que dar: columna = true, control = true y las dos funciones = true.
select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'solicitudes' and column_name = 'alimentacion') as columna,
       exists (select 1 from pg_constraint where conname = 'solicitudes_alimentacion_valida') as control,
       position('alimentacion' in pg_get_functiondef('public.mis_datos_ver(text)'::regprocedure)) > 0 as ver_con_alimentacion,
       position('alimentacion' in pg_get_functiondef('public.mis_datos_guardar(text, jsonb)'::regprocedure)) > 0 as guardar_con_alimentacion;
