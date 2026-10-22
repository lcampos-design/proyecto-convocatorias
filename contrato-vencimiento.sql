-- ============================================================
--  QUE EL LINK DE FIRMA VENZA
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  EL PROBLEMA
--  El link que se le manda a cada persona para firmar no caduca nunca. Uno
--  mandado hace seis meses todavía firma hoy. Y si ese mail se reenvía, lo
--  comparten o queda en un celular prestado, cualquiera puede abrirlo y
--  firmar en nombre de esa persona: el link es la única llave.
--
--  LA SOLUCIÓN
--  Cada contrato vence a los 7 días (configurable). Después de eso:
--     · la página de firma dice que venció y no deja firmar;
--     · desde el panel se renueva con un botón, sin rehacer el contrato.
--
--  LO QUE NO CAMBIA
--  Un contrato YA FIRMADO no vence: la persona puede seguir entrando al
--  mismo link para bajarse su PDF cuando quiera. El vencimiento es sólo
--  para firmar, que es lo que hay que proteger.
--
--  A los contratos que ya están cargados se les pone el vencimiento contando
--  desde que se enviaron, así que los viejos sin firmar quedan vencidos. Es
--  a propósito: son justamente los links que no deberían seguir sirviendo.
-- ============================================================

-- ── 1) CUÁNTOS DÍAS DURA ──
--  Se guarda en config, al lado del resto de la configuración del panel.
insert into public.config (key, value)
values ('contrato_link', jsonb_build_object('dias', 7))
on conflict (key) do nothing;

create or replace function public.contrato_dias_link()
returns int
language sql stable security definer set search_path = public as $$
  select greatest(1, coalesce((select (value->>'dias')::int from public.config where key = 'contrato_link'), 7));
$$;

-- ── 2) LA FECHA DE VENCIMIENTO ──
alter table public.contratos add column if not exists vence_el timestamptz;

--  Los que ya estaban: se cuenta desde que se enviaron, o desde que se
--  crearon si nunca se mandaron.
update public.contratos
   set vence_el = coalesce(fecha_envio, fecha_creacion) + (public.contrato_dias_link() || ' days')::interval
 where vence_el is null;

--  Y los nuevos nacen con el vencimiento puesto.
alter table public.contratos
  alter column vence_el set default (now() + (public.contrato_dias_link() || ' days')::interval);

-- ── 3) VER: AVISAR QUE VENCIÓ, EN VEZ DE MOSTRAR EL CONTRATO ──
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
    'vence_el',            c.vence_el
  );
end;
$$;

-- ── 4) FIRMAR: NO DEJAR, SI YA VENCIÓ ──
--  La validación va adentro de la función que firma, no sólo en la pantalla:
--  si estuviera nada más en la pantalla, bastaría con llamar a la función
--  por fuera para firmar igual un link vencido.
--  Es la misma función que ya existía, con ese chequeo agregado arriba.
create or replace function public.contrato_firmar(p_token uuid, p_firma_png text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c        public.contratos;
  ip       text;
  ua       text;
  eventos  jsonb;
begin
  select * into c from public.contratos where token = p_token;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); end if;

  --  ← lo único nuevo respecto de la versión anterior
  if c.estado <> 'firmado' and c.vence_el is not null and now() > c.vence_el then
    return jsonb_build_object('ok', false, 'motivo', 'vencido', 'vence_el', c.vence_el);
  end if;

  ip := nullif(current_setting('request.headers', true)::json->>'x-forwarded-for', '');
  ua := nullif(current_setting('request.headers', true)::json->>'user-agent', '');

  -- Si ya estaba firmado (por ejemplo, se cortó la señal y reintenta), no se
  -- vuelve a firmar: se devuelve el mismo certificado para que pueda bajar su PDF.
  if c.estado <> 'firmado' then
    insert into public.contrato_eventos (contrato_id, tipo, ip, user_agent)
    values (c.id, 'consentimiento', ip, ua);

    update public.contratos
       set estado = 'firmado',
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

-- ── 5) RENOVAR EL LINK, DESDE EL PANEL ──
--  No rehace el contrato ni cambia el token: sólo corre la fecha. El que ya
--  lo tiene en su mail lo puede usar de nuevo, sin reenviar nada.
create or replace function public.contrato_renovar(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.contratos;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  if not public.es_admin() then
    return jsonb_build_object('ok', false, 'error', 'Sólo un administrador puede renovar el link');
  end if;
  select * into c from public.contratos where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'No se encontró el contrato'); end if;
  if c.estado = 'firmado' then
    return jsonb_build_object('ok', false, 'error', 'Ese contrato ya está firmado');
  end if;

  update public.contratos
     set vence_el = now() + (public.contrato_dias_link() || ' days')::interval
   where id = p_id
   returning * into c;

  insert into public.contrato_eventos (contrato_id, tipo)
  values (c.id, 'renovado');

  return jsonb_build_object('ok', true, 'vence_el', c.vence_el);
end;
$$;

grant execute on function public.contrato_dias_link()   to anon, authenticated;
grant execute on function public.contrato_renovar(uuid) to authenticated;
revoke execute on function public.contrato_renovar(uuid) from anon, public;

-- ── CÓMO QUEDÓ ──
select count(*) filter (where estado = 'firmado')                              as firmados_no_vencen,
       count(*) filter (where estado <> 'firmado' and now() <= vence_el)        as al_dia,
       count(*) filter (where estado <> 'firmado' and now() >  vence_el)        as vencidos
from public.contratos;

--  Para cambiar los días:
--    update public.config set value = jsonb_build_object('dias', 10) where key = 'contrato_link';

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--   update public.contratos set vence_el = now() + interval '100 years' where estado <> 'firmado';
