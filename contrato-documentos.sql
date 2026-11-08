-- ============================================================
--  DOCUMENTOS QUE SE FIRMAN JUNTO CON EL CONTRATO
--
--  Pedido de Mer (8-nov): a algunas personas (no a todas) hay que hacerles
--  firmar, además del contrato, otro documento: hoy, la constancia de la
--  capacitación del evento "Bienvenidos Todos". Que vaya en el mismo mail,
--  en el mismo PDF, y se firme con la misma firma.
--
--  Qué hace:
--   · contratos.anexos: los documentos de ese contrato ([{titulo, texto}]),
--     congelados como el resto del contrato. Vacío para los de siempre.
--   · contrato_ver devuelve los documentos (la página los muestra debajo del
--     contrato) y contrato_firmar los devuelve firmados, cada uno con su
--     huella SHA-256 (van al PDF firmado y al informe de auditoría).
--   · Firmado, los documentos no se pueden tocar (el mismo candado que el texto).
--   · La lista de documentos para elegir queda en config (documentos_firma),
--     con la constancia de capacitación ya cargada; se edita desde el panel
--     (Contratos → "Documentos para firmar").
--
--  Se puede volver a correr. Sin esto, el panel sigue igual (no muestra
--  documentos para tildar) y la página de firma también.
--  Correr en Supabase → SQL Editor → Run.
-- ============================================================

-- ── 1) LA COLUMNA ──
alter table public.contratos add column if not exists anexos jsonb not null default '[]'::jsonb;

-- ── 2) FIRMADO, LOS DOCUMENTOS TAMPOCO SE TOCAN ──
--  La misma función de contratos.sql, con anexos entre lo que queda congelado.
create or replace function public.contratos_inmutable()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.estado = 'firmado' then
    if new.texto_contrato is distinct from old.texto_contrato
       or new.hash_texto    is distinct from old.hash_texto
       or new.firma_png     is distinct from old.firma_png
       or new.fecha_firma   is distinct from old.fecha_firma
       or new.cuil          is distinct from old.cuil
       or new.nombre        is distinct from old.nombre
       or new.estado        is distinct from old.estado
       or new.anexos        is distinct from old.anexos then
      raise exception 'Un contrato firmado no se puede modificar (contrato %)', old.id;
    end if;
    if old.pdf_firmado is not null and new.pdf_firmado is distinct from old.pdf_firmado then
      raise exception 'El PDF firmado ya está guardado y no se puede reemplazar (contrato %)', old.id;
    end if;
  end if;
  return new;
end;
$$;

-- ── 3) VER: CON LOS DOCUMENTOS ──
--  La misma de contrato-codigo-hora.sql, más 'anexos'.
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
    'pide_codigo',         public.contrato_pide_codigo(),
    'anexos',              coalesce(c.anexos, '[]'::jsonb)
  );
end;
$$;

-- ── 4) FIRMAR: DEVUELVE LOS DOCUMENTOS FIRMADOS, CON SU HUELLA ──
--  La misma de contrato-codigo.sql, más 'anexos' (y el detalle de cada evento,
--  para que el informe diga qué documento se agregó).
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
    'anexos',              v_anexos
  );
end;
$$;

-- ── 5) LA LISTA PARA ELEGIR, CON LA CONSTANCIA YA CARGADA ──
--  Si ya existe (porque se creó desde el panel), no la pisa.
insert into public.config (key, value)
values ('documentos_firma', $doc$[
  {
    "id": "constancia-bienvenidos-todos",
    "titulo": "Constancia de capacitación",
    "texto": "Evento: “Bienvenidos Todos” – Visita del Papa León XIV a la Argentina\nCapacitación: dictada por Show Business Solutions, en coordinación con Cancillería, el 6 de noviembre de 2026 en modalidad virtual (turnos de 10, 15 y 19 hs).\n\nDeclaración\nDeclaro haber participado de la capacitación virtual brindada por Show Business Solutions sobre la operativa general del evento, que abarcó los accesos y la circulación del público, las funciones de orientadores y acomodadores, la atención a personas con movilidad reducida, las normas de seguridad y conducta, la vestimenta y la organización con los supervisores. Me comprometo a cumplir los lineamientos recibidos.",
    "creado": "2026-11-08T00:00:00.000Z"
  }
]$doc$::jsonb)
on conflict (key) do nothing;

-- Para ver que quedó: tiene que dar cuatro true.
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'contratos' and column_name = 'anexos') = 1 as columna_anexos,
       position('anexos' in pg_get_functiondef('public.contrato_ver(uuid)'::regprocedure)) > 0 as ver_con_documentos,
       position('huella' in pg_get_functiondef('public.contrato_firmar(uuid,text,text)'::regprocedure)) > 0 as firmar_con_documentos,
       exists (select 1 from public.config where key = 'documentos_firma') as lista_cargada;
