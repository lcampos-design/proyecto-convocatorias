-- ============================================================
--  UN CÓDIGO POR MAIL PARA FIRMAR EL CONTRATO
--
--  Hasta ahora, con el link alcanzaba para firmar. Si el link llegaba a otras
--  manos (un mail reenviado, un celular prestado), otro podía firmar en nombre
--  de la persona. Ahora, al tocar "Firmar contrato", la persona recibe un
--  código de 6 números en el mail del contrato y lo tiene que escribir: así
--  firma quien tiene acceso a esa casilla en ese momento. Queda en el informe
--  de auditoría (código enviado, código ingresado, con fecha, hora e IP).
--
--  - El código vence a los 15 minutos y admite 5 intentos; se puede pedir
--    otro cada un minuto, hasta 6 por día.
--  - La base guarda sólo la huella del código, no el código.
--  - El código lo pide el servidor (api/contrato-codigo.js, que manda el mail):
--    contrato_codigo_pedir no la puede llamar nadie más.
--  - La validación va adentro de la función que firma: sin el código ingresado
--    (en la última media hora), no firma, aunque la llamen por fuera.
--  - Para apagarlo (por ejemplo, si un día no salen los mails), cambiar el
--    true por false en contrato_pide_codigo() y correr esa función sola.
--
--  Correr en Supabase -> SQL Editor. Antes de correrlo, todo sigue como antes.
-- ============================================================

alter table public.contratos add column if not exists codigo_hash text;
alter table public.contratos add column if not exists codigo_vence timestamptz;
alter table public.contratos add column if not exists codigo_intentos int not null default 0;
alter table public.contratos add column if not exists codigo_pedidos int not null default 0;
alter table public.contratos add column if not exists codigo_ultimo_pedido timestamptz;
alter table public.contratos add column if not exists codigo_ok_at timestamptz;

-- ── 0) PRENDIDO O APAGADO ──
create or replace function public.contrato_pide_codigo()
returns boolean
language sql stable set search_path = public as $$ select true $$;
revoke execute on function public.contrato_pide_codigo() from public, anon, authenticated;

-- ── 1) PEDIR EL CÓDIGO (sólo el servidor) ──
--  Devuelve el código para que el servidor lo mande por mail; acá queda sólo su huella.
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
         codigo_vence = now() + interval '15 minutes',
         codigo_intentos = 0,
         codigo_pedidos = v_pedidos + 1,
         codigo_ultimo_pedido = now()
   where id = c.id;

  insert into public.contrato_eventos (contrato_id, tipo, meta)
  values (c.id, 'codigo_enviado', jsonb_build_object('email', c.email));

  select area into v_area from public.convocatorias where id = c.conv_id;
  return jsonb_build_object('ok', true, 'codigo', v_codigo, 'email', c.email, 'nombre', c.nombre, 'area', v_area);
end;
$$;
revoke execute on function public.contrato_codigo_pedir(uuid) from public, anon, authenticated;
grant  execute on function public.contrato_codigo_pedir(uuid) to service_role;

-- ── 2) INGRESAR EL CÓDIGO (la página de firma) ──
create or replace function public.contrato_codigo_verificar(p_token uuid, p_codigo text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  c  public.contratos;
  v  text := regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g');
  ip text;
  ua text;
begin
  select * into c from public.contratos where token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); end if;
  if c.estado = 'firmado' then return jsonb_build_object('ok', false, 'motivo', 'ya_firmado'); end if;
  if c.vence_el is not null and now() > c.vence_el then return jsonb_build_object('ok', false, 'motivo', 'vencido'); end if;

  -- Ya lo ingresó hace poco (por ejemplo, se cortó la señal al firmar): sigue valiendo.
  if c.codigo_ok_at is not null and now() - c.codigo_ok_at <= interval '30 minutes' and c.codigo_hash is null then
    return jsonb_build_object('ok', true);
  end if;
  if c.codigo_hash is null or c.codigo_vence is null or now() > c.codigo_vence then
    return jsonb_build_object('ok', false, 'motivo', 'codigo_vencido');
  end if;
  if c.codigo_intentos >= 5 then return jsonb_build_object('ok', false, 'motivo', 'intentos'); end if;

  if encode(digest(v || ':' || c.id::text, 'sha256'), 'hex') <> c.codigo_hash then
    update public.contratos set codigo_intentos = codigo_intentos + 1 where id = c.id;
    return jsonb_build_object('ok', false, 'motivo', 'codigo', 'quedan', greatest(0, 4 - c.codigo_intentos));
  end if;

  ip := nullif(current_setting('request.headers', true)::json->>'x-forwarded-for', '');
  ua := nullif(current_setting('request.headers', true)::json->>'user-agent', '');
  update public.contratos set codigo_ok_at = clock_timestamp(), codigo_hash = null where id = c.id;
  insert into public.contrato_eventos (contrato_id, tipo, ip, user_agent, meta)
  values (c.id, 'codigo_ok', ip, ua, jsonb_build_object('email', c.email));
  return jsonb_build_object('ok', true);
end;
$$;
revoke execute on function public.contrato_codigo_verificar(uuid, text) from public;
grant  execute on function public.contrato_codigo_verificar(uuid, text) to anon, authenticated;

-- ── 3) VER: AVISA SI PIDE EL CÓDIGO ──
--  La misma de contrato-vencimiento.sql, con "pide_codigo".
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

  --  Firmado no vence: el link le sigue sirviendo para bajar su PDF.
  venció := c.estado <> 'firmado' and c.vence_el is not null and now() > c.vence_el;

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
    'pdf_firmado',         c.pdf_firmado,
    'firma_empleador_img', c.firma_empleador_img,
    'vencido',             false,
    'vence_el',            c.vence_el,
    'pide_codigo',         public.contrato_pide_codigo()
  );
end;
$$;

-- ── 4) FIRMAR: SIN EL CÓDIGO, NO ──
--  La misma de contrato-domicilio.sql, con el chequeo del código arriba.
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
           'tipo', e.tipo, 'fecha', e.fecha, 'ip', e.ip, 'user_agent', e.user_agent
         ) order by e.fecha, e.id), '[]'::jsonb)
    into eventos
    from public.contrato_eventos e
   where e.contrato_id = c.id;

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
    'eventos',             eventos
  );
end;
$$;

-- ── CÓMO QUEDÓ ──
--  contrato_codigo_pedir: sin usuario no / con usuario no (sólo el servidor).
--  contrato_codigo_verificar, contrato_ver y contrato_firmar: sí / sí.
select p.proname as funcion,
       has_function_privilege('anon', p.oid, 'execute') as sin_usuario,
       has_function_privilege('authenticated', p.oid, 'execute') as con_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('contrato_pide_codigo', 'contrato_codigo_pedir', 'contrato_codigo_verificar', 'contrato_ver', 'contrato_firmar')
order by 1;
