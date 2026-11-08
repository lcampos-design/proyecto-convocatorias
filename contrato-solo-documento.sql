-- ============================================================
--  SÓLO UN DOCUMENTO, SIN CONTRATO
--
--  Pedido de Thomas (8-nov): hay gente que ya firmó el contrato y tiene que
--  firmar la constancia de capacitación igual. Entonces, además de "junto con
--  el contrato" (contrato-documentos.sql), se puede mandar un documento solo:
--  el mismo link de firma, el mismo código por mail, el PDF con la hoja del
--  documento y el informe de auditoría. En el panel es la cuarta opción de
--  "Qué mandás": "Sólo un documento".
--
--  Qué hace:
--   · contratos.solo_documentos: marca esas filas (texto_contrato vacío, los
--     documentos en anexos). Falso para los contratos de siempre.
--   · contrato_ver, contrato_firmar y contrato_codigo_pedir devuelven la
--     marca, para que la página y el mail del código digan "documento" en vez
--     de "contrato".
--
--  Correr DESPUÉS de contrato-documentos.sql. Se puede volver a correr. Sin
--  esto, "Sólo un documento" avisa que falta el SQL; lo demás sigue igual.
--  Correr en Supabase → SQL Editor → Run.
-- ============================================================

-- ── 1) LA MARCA ──
alter table public.contratos add column if not exists solo_documentos boolean not null default false;

-- ── 2) VER: CON LA MARCA ──
--  La misma de contrato-documentos.sql, más 'solo_documentos'.
create or replace function public.contrato_ver(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c   public.contratos;
  ip  text;
  ua  text;
  venció boolean;
begin
  select * into c from public.contratos where token = p_token;
  if not found then return null; end if;

  --  Firmado: sólo que ya firmó y cuándo. Ni el PDF ni los datos (el PDF lo
  --  tiene la coordinación, en el panel).
  if c.estado = 'firmado' then
    return jsonb_build_object(
      'nombre',      c.nombre,
      'estado',      c.estado,
      'fecha_firma', c.fecha_firma,
      'vencido',     false,
      'solo_documentos', coalesce(c.solo_documentos, false)
    );
  end if;

  venció := c.vence_el is not null and now() > c.vence_el;

  if venció then
    return jsonb_build_object(
      'nombre',   c.nombre,
      'estado',   c.estado,
      'vencido',  true,
      'vence_el', c.vence_el
    );
  end if;

  -- Se registra la primera apertura (el "Documento abierto por" de la auditoría)
  if c.fecha_visto is null then
    ip := nullif(current_setting('request.headers', true)::json->>'x-forwarded-for', '');
    ua := nullif(current_setting('request.headers', true)::json->>'user-agent', '');
    update public.contratos
       set fecha_visto = clock_timestamp(),
           estado = case when estado in ('pendiente','enviado') then 'visto' else estado end
     where id = c.id
     returning * into c;
    insert into public.contrato_eventos (contrato_id, tipo, ip, user_agent)
    values (c.id, 'visto', ip, ua);
  end if;

  return jsonb_build_object(
    'nombre',              c.nombre,
    'cuil',                c.cuil,
    'puesto',              c.puesto,
    'venue',               c.venue,
    'texto_contrato',      c.texto_contrato,
    'estado',              c.estado,
    'fecha_firma',         c.fecha_firma,
    'firma_empleador_img', c.firma_empleador_img,
    'vencido',             false,
    'vence_el',            c.vence_el,
    'pide_codigo',         public.contrato_pide_codigo(),
    'anexos',              coalesce(c.anexos, '[]'::jsonb),
    'solo_documentos',     coalesce(c.solo_documentos, false)
  );
end;
$$;

-- ── 3) FIRMAR: CON LA MARCA ──
--  La misma de contrato-documentos.sql, más 'solo_documentos'.
create or replace function public.contrato_firmar(p_token uuid, p_firma_png text, p_domicilio text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  c          public.contratos;
  ip         text;
  ua         text;
  eventos    jsonb;
  v_dom      text := nullif(btrim(regexp_replace(coalesce(p_domicilio,''), '\s+', ' ', 'g')), '');
  v_texto    text;
  v_hay_linea boolean;
  v_anexos   jsonb;
begin
  select * into c from public.contratos where token = p_token;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); end if;

  if c.estado <> 'firmado' and c.vence_el is not null and now() > c.vence_el then
    return jsonb_build_object('ok', false, 'motivo', 'vencido', 'vence_el', c.vence_el);
  end if;

  -- El código que llegó por mail: tiene que haberlo ingresado en la última media hora.
  if c.estado <> 'firmado' and public.contrato_pide_codigo()
     and (c.codigo_ok_at is null or now() - c.codigo_ok_at > interval '30 minutes') then
    return jsonb_build_object('ok', false, 'motivo', 'codigo');
  end if;

  ip := nullif(current_setting('request.headers', true)::json->>'x-forwarded-for', '');
  ua := nullif(current_setting('request.headers', true)::json->>'user-agent', '');

  -- Si ya estaba firmado (por ejemplo, se cortó la señal y reintenta), no se
  -- vuelve a firmar: se devuelve el mismo certificado para que pueda bajar su PDF.
  if c.estado <> 'firmado' then
    -- La línea para completar: cinco o más guiones bajos seguidos.
    v_hay_linea := c.texto_contrato ~ '_{5,}';
    if v_hay_linea and v_dom is null then
      return jsonb_build_object('ok', false, 'motivo', 'domicilio');
    end if;
    v_texto := c.texto_contrato;
    if v_hay_linea then
      v_texto := regexp_replace(v_texto, '_{5,}', v_dom);   -- sólo la primera
    end if;

    insert into public.contrato_eventos (contrato_id, tipo, ip, user_agent, meta)
    values (c.id, 'consentimiento', ip, ua, case when v_dom is null then null else jsonb_build_object('domicilio', v_dom) end);

    -- El texto definitivo y su huella se fijan acá, antes de pasar a firmado
    -- (después, el candado de contratos_inmutable no deja tocarlos).
    update public.contratos
       set texto_contrato = v_texto,
           hash_texto = encode(digest(v_texto, 'sha256'), 'hex'),
           domicilio = coalesce(v_dom, domicilio),
           estado = 'firmado',
           fecha_firma = clock_timestamp(),
           firma_png = p_firma_png,
           firma_ip = ip,
           firma_user_agent = ua
     where id = c.id
     returning * into c;

    insert into public.contrato_eventos (contrato_id, tipo, ip, user_agent)
    values (c.id, 'firmado', ip, ua);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'tipo', e.tipo, 'fecha', e.fecha, 'ip', e.ip, 'user_agent', e.user_agent, 'meta', e.meta
         ) order by e.fecha, e.id), '[]'::jsonb)
    into eventos
    from public.contrato_eventos e
   where e.contrato_id = c.id;

  -- Los documentos que firmó junto con el contrato, cada uno con su huella.
  select coalesce(jsonb_agg(t.a || jsonb_build_object('huella', encode(digest(coalesce(t.a->>'texto', ''), 'sha256'), 'hex')) order by t.n), '[]'::jsonb)
    into v_anexos
    from jsonb_array_elements(coalesce(c.anexos, '[]'::jsonb)) with ordinality as t(a, n);

  return jsonb_build_object(
    'ok',                  true,
    'texto_contrato',      c.texto_contrato,
    'firma_empleador_img', c.firma_empleador_img,
    'nombre',              c.nombre,
    'cuil',                c.cuil,
    'email',               c.email,
    'domicilio',           c.domicilio,
    'fecha_creacion',      c.fecha_creacion,
    'fecha_firma',         c.fecha_firma,
    'transaccion_id',      c.transaccion_id,
    'hash_texto',          c.hash_texto,
    'puesto',              c.puesto,
    'fecha_inicio',        c.fecha_inicio,
    'fecha_fin',           c.fecha_fin,
    'monto_letras',        c.monto_letras,
    'monto_numero',        c.monto_numero,
    'fecha_firma_doc',     c.fecha_firma_doc,
    'eventos',             eventos,
    'anexos',              v_anexos,
    'solo_documentos',     coalesce(c.solo_documentos, false)
  );
end;
$$;

-- ── 4) PEDIR EL CÓDIGO: CON LA MARCA (el mail dice "documento") ──
--  La misma de contrato-codigo-hora.sql, más 'solo_documentos'.
create or replace function public.contrato_codigo_pedir(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  c         public.contratos;
  v_codigo  text;
  v_pedidos int;
  v_area    text;
begin
  select * into c from public.contratos where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); end if;
  if c.estado = 'firmado' then return jsonb_build_object('ok', false, 'motivo', 'ya_firmado'); end if;
  if c.vence_el is not null and now() > c.vence_el then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;
  if nullif(btrim(coalesce(c.email, '')), '') is null then return jsonb_build_object('ok', false, 'motivo', 'sin_email'); end if;

  -- Uno por minuto y, como mucho, 6 por día.
  if c.codigo_ultimo_pedido is not null and now() - c.codigo_ultimo_pedido < interval '60 seconds' then
    return jsonb_build_object('ok', false, 'motivo', 'espera', 'email', c.email);
  end if;
  v_pedidos := case when c.codigo_ultimo_pedido is null or now() - c.codigo_ultimo_pedido > interval '1 day' then 0 else coalesce(c.codigo_pedidos, 0) end;
  if v_pedidos >= 6 then return jsonb_build_object('ok', false, 'motivo', 'muchos', 'email', c.email); end if;

  -- Seis números al azar (de un generador seguro).
  v_codigo := lpad(((('x' || lpad(encode(gen_random_bytes(4), 'hex'), 16, '0'))::bit(64)::bigint) % 1000000)::text, 6, '0');

  update public.contratos
     set codigo_hash = encode(digest(v_codigo || ':' || c.id::text, 'sha256'), 'hex'),
         codigo_vence = now() + interval '60 minutes',
         codigo_intentos = 0,
         codigo_pedidos = v_pedidos + 1,
         codigo_ultimo_pedido = now()
   where id = c.id;

  insert into public.contrato_eventos (contrato_id, tipo, meta)
  values (c.id, 'codigo_enviado', jsonb_build_object('email', c.email));

  select area into v_area from public.convocatorias where id = c.conv_id;
  return jsonb_build_object('ok', true, 'codigo', v_codigo, 'email', c.email, 'nombre', c.nombre, 'area', v_area, 'minutos', 60, 'solo_documentos', coalesce(c.solo_documentos, false));
end;
$$;
revoke execute on function public.contrato_codigo_pedir(uuid) from public, anon, authenticated;
grant  execute on function public.contrato_codigo_pedir(uuid) to service_role;

-- Para ver que quedó: tiene que dar cuatro true.
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'solo_documentos') = 1 as columna_solo_documentos,
       position('solo_documentos' in pg_get_functiondef('public.contrato_ver(uuid)'::regprocedure)) > 0 as ver_con_marca,
       position('solo_documentos' in pg_get_functiondef('public.contrato_firmar(uuid,text,text)'::regprocedure)) > 0 as firmar_con_marca,
       position('solo_documentos' in pg_get_functiondef('public.contrato_codigo_pedir(uuid)'::regprocedure)) > 0 as codigo_con_marca;
