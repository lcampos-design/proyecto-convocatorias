-- ============================================================
--  EL DOMICILIO DEL TRABAJADOR, COMPLETADO AL FIRMAR
--
--  El modelo de contrato trae "cuyo domicilio es: ____________" para
--  completar a mano. En el contrato digital nadie podía completarlo: el
--  panel no tiene el domicilio de la gente, y el texto se sella al crearse.
--
--  Ahora lo completa el trabajador en la página de firma, antes de firmar.
--  El servidor pone el domicilio en el lugar de la línea, recalcula la
--  huella SHA-256 (es el texto que de verdad se firma) y recién entonces
--  registra la firma. Si el texto tiene la línea y no mandan domicilio, no
--  deja firmar. Un contrato ya firmado no se toca.
--
--  Correr en Supabase -> SQL Editor.
-- ============================================================

alter table public.contratos add column if not exists domicilio text;

-- La versión anterior tenía dos parámetros: se saca para que no queden dos.
drop function if exists public.contrato_firmar(uuid, text);

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

revoke execute on function public.contrato_firmar(uuid, text, text) from public;
grant  execute on function public.contrato_firmar(uuid, text, text) to anon, authenticated;

-- ── Comprobación (no escribe nada): {"ok": false, "motivo": "no_encontrado"} ──
select public.contrato_firmar('00000000-0000-0000-0000-000000000000', '', 'Calle Falsa 123');
