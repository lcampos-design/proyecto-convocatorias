-- ============================================================
--  EL CÓDIGO PARA FIRMAR DURA UNA HORA, Y EL FIRMADO NO SE DESCARGA
--
--  Pedidos de Mer:
--  - Firmando desde el celular, la persona tiene que ir al mail a buscar el
--    código y volver al contrato, y a veces el código ya venció. Ahora el mail
--    trae un botón que vuelve al contrato con el código puesto, y el código
--    dura una hora (antes, 15 minutos). Lo demás sigue igual: 5 intentos por
--    código, uno por minuto y hasta 6 por día, y la base guarda sólo su huella.
--  - Sacar "Descargar mi contrato firmado". La página ya no lo ofrece, y acá
--    el link de un contrato firmado deja de devolver el PDF y los datos: sólo
--    que ya firmó y cuándo. Así un mail reenviado no muestra nada de la
--    persona. El PDF firmado sigue en el panel, como siempre.
--
--  Reemplaza contrato_codigo_pedir y contrato_ver (las mismas de
--  contrato-codigo.sql, con esos dos cambios). Se puede volver a correr.
--
--  Correr en Supabase -> SQL Editor. Antes de correrlo, el código dura 15
--  minutos y la página y el mail lo dicen así; la página ya no muestra el botón.
-- ============================================================

-- ── 1) PEDIR EL CÓDIGO: DURA UNA HORA ──
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
  return jsonb_build_object('ok', true, 'codigo', v_codigo, 'email', c.email, 'nombre', c.nombre, 'area', v_area, 'minutos', 60);
end;
$$;
revoke execute on function public.contrato_codigo_pedir(uuid) from public, anon, authenticated;
grant  execute on function public.contrato_codigo_pedir(uuid) to service_role;

-- ── 2) VER: FIRMADO, SIN EL PDF NI LOS DATOS ──
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
      'vencido',     false
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
    'pide_codigo',         public.contrato_pide_codigo()
  );
end;
$$;

-- Para ver que quedó: tiene que dar dos true.
select position('60 minutes' in pg_get_functiondef('public.contrato_codigo_pedir(uuid)'::regprocedure)) > 0 as codigo_dura_una_hora,
       position('pdf_firmado' in pg_get_functiondef('public.contrato_ver(uuid)'::regprocedure)) = 0 as firmado_sin_pdf;
