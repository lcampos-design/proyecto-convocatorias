-- ============================================================
--  /mis-datos TAMBIÉN PARA LOS QUE TIENEN CONTRATO Y NO SE INSCRIBIERON
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr sin problema.
--  (Después de seguridad-cbu.sql, alimentacion.sql y contratos-presentes.sql, ya corridos.
--   NO volver a correr mis-datos.sql.)
--
--  Pedido de Thomas (13-nov): que la gente del Arena que no tiene usuario (se
--  le armó el contrato con el mail de la disponibilidad, o la cargamos en la
--  nómina) pueda, con su CUIL, recibir el link por mail y registrarse; y si ya
--  está inscripta, actualizar sus datos.
--
--  - El link (mis_datos_link): si no hay mail en la nómina ni en la
--    inscripción, va al mail de su contrato. Lo demás, igual que en
--    seguridad-cbu.sql.
--  - Ver (mis_datos_ver): sin nómina ni inscripción, el nombre, el mail y el
--    área del contrato (la página la saluda y le ofrece registrarse). Suma
--    "en_nomina". Lo demás, igual que en alimentacion.sql.
--  Guardar no cambia: quien no tiene inscripción se registra con el formulario.
-- ============================================================

-- ── 1) EL LINK, TAMBIÉN AL MAIL DEL CONTRATO ──
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
  -- El mail: el de la nómina o, si no está, el de su inscripción MÁS VIEJA
  -- (una más nueva con el mismo documento la pudo haber mandado otro).
  select email, nombre, area into v_email, v_nombre, v_area from public.personas
   where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' and coalesce(btrim(email), '') <> ''
   order by created_at desc nulls last limit 1;
  if v_email is null then
    select email, nombre, area into v_email, v_nombre, v_area from public.solicitudes
     where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' and coalesce(btrim(email), '') <> ''
     order by created_at asc limit 1;
  end if;
  -- Si no, el de su contrato: los del Arena que firman con el mail de la disponibilidad y no están en la
  -- nómina ni se inscribieron (contratos por presente). Así también pueden pedir el link y registrarse.
  if v_email is null then
    select k.email, k.nombre, coalesce(c.area, 'movistar_arena') into v_email, v_nombre, v_area
      from public.contratos k left join public.convocatorias c on c.id = k.conv_id
     where public.doc_nucleo(coalesce(nullif(btrim(k.cuil), ''), k.doc_nucleo)) = v_nuc and coalesce(btrim(k.email), '') <> ''
       and coalesce(c.area, '') <> 'espana'
     order by (k.estado = 'anulado'), k.fecha_creacion desc nulls last limit 1;
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

-- ── 2) VER, CON EL NOMBRE Y EL MAIL DEL CONTRATO ──
create or replace function public.mis_datos_ver(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_nuc text := public.mis_datos_nucleo(p_token);
  p public.personas%rowtype;
  s public.solicitudes%rowtype;
  k_nombre text; k_email text; k_area text;
begin
  if v_nuc is null then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  select * into p from public.personas where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' order by created_at desc nulls last limit 1;
  select * into s from public.solicitudes where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' order by created_at desc limit 1;
  -- Sin nómina ni inscripción: el nombre, el mail y el área de su contrato (para saludarlo y que se registre).
  if p.id is null and s.id is null then
    select k.nombre, k.email, coalesce(c.area, 'movistar_arena') into k_nombre, k_email, k_area
      from public.contratos k left join public.convocatorias c on c.id = k.conv_id
     where public.doc_nucleo(coalesce(nullif(btrim(k.cuil), ''), k.doc_nucleo)) = v_nuc and coalesce(c.area, '') <> 'espana'
     order by (k.estado = 'anulado'), k.fecha_creacion desc nulls last limit 1;
  end if;
  return jsonb_build_object('ok', true,
    'nombre', coalesce(p.nombre, s.nombre, k_nombre), 'area', coalesce(p.area, s.area, k_area),
    'email', coalesce(nullif(p.email, ''), s.email, k_email), 'tel', coalesce(nullif(p.tel, ''), s.tel),
    'localidad', coalesce(nullif(s.localidad, ''), p.localidad),
    'fecha_nacimiento', s.fecha_nacimiento, 'estudios', s.estudios, 'idiomas', s.idiomas,
    'alimentacion', s.alimentacion,
    'disponibilidad', coalesce(nullif(p.cv->>'disponibilidad', ''), s.disponibilidad),
    'con_inscripcion', s.id is not null,
    'en_nomina', p.id is not null,
    'tiene_cuenta', case when s.cbu is not null and s.cbu <> '' then true else s.tiene_cuenta end,
    'cbu', s.cbu, 'numero_cuenta', s.numero_cuenta, 'banco', s.banco,
    'apellido', s.apellido, 'nombres', s.nombres, 'nacionalidad', s.nacionalidad, 'domicilio', s.domicilio, 'codigo_postal', s.codigo_postal,
    'cv', coalesce(p.cv->'archivo'->>'nombre', s.archivo_cv->>'nombre'));
end;
$$;
revoke execute on function public.mis_datos_ver(text) from public;
grant  execute on function public.mis_datos_ver(text) to anon, authenticated;

-- ── CÓMO QUEDÓ ──
select position('public.contratos' in pg_get_functiondef('public.mis_datos_link(text, text)'::regprocedure)) > 0 as el_link_mira_los_contratos,
       position('en_nomina' in pg_get_functiondef('public.mis_datos_ver(text)'::regprocedure)) > 0 as ver_saluda_con_el_contrato,
       not has_function_privilege('anon', 'public.mis_datos_link(text, text)', 'execute') as el_link_sigue_siendo_del_servidor;
