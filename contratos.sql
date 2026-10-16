-- ============================================================
--  CONTRATOS CON FIRMA ELECTRÓNICA
--  Correr completo en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no borra nada ni duplica.
--
--  Qué crea:
--   · contratos          → un contrato por persona (texto congelado + estado)
--   · contrato_eventos   → trazabilidad: creado / enviado / visto / consentimiento / firmado
--   · 3 funciones que usa la página de firma (contrato.html)
--
--  Nota: la columna contratos_habilitados de convocatorias ya está creada.
--  Los contratos siguen apagados hasta que se tilde esa casilla en una convocatoria.
-- ============================================================

create extension if not exists pgcrypto;

-- ── Tabla principal ───────────────────────────────────────────
-- Los datos se guardan como "foto" del momento de la creación: si después
-- cambia el nombre o el mail de la persona, el contrato ya enviado no cambia.
create table if not exists public.contratos (
  id                  uuid primary key default gen_random_uuid(),
  token               uuid not null unique default gen_random_uuid(),  -- identifica el link, no es adivinable
  transaccion_id      text,          -- ID legible que figura en el informe de auditoría
  hash_texto          text,          -- huella SHA-256 del texto: detecta cualquier alteración posterior

  conv_id             uuid references public.convocatorias(id),
  persona_id          uuid references public.personas(id),
  postulacion_id      uuid references public.postulaciones(id),
  puesto_id           uuid references public.puestos(id),

  nombre              text,
  cuil                text,
  email               text,
  puesto              text,
  venue               text,
  fecha_inicio        text,
  fecha_fin           text,
  anio                text,
  monto_letras        text,
  monto_numero        text,
  fecha_firma_doc     text,          -- la fecha que figura escrita en el contrato
  texto_contrato      text not null, -- el contrato completo, ya con los datos puestos
  firma_empleador_img text,          -- qué firma del empleador lleva (arena o externos)

  estado              text not null default 'pendiente',  -- pendiente | enviado | visto | firmado
  fecha_creacion      timestamptz not null default now(),
  fecha_envio         timestamptz,
  fecha_visto         timestamptz,
  fecha_firma         timestamptz,

  firma_png           text,          -- la firma dibujada
  pdf_firmado         text,          -- el PDF final con el informe de auditoría
  firma_ip            text,
  firma_user_agent    text,
  creado_por          uuid
);

create index if not exists contratos_token_idx      on public.contratos(token);
create index if not exists contratos_persona_id_idx on public.contratos(persona_id);
create index if not exists contratos_conv_id_idx    on public.contratos(conv_id);

-- ── Trazabilidad ──────────────────────────────────────────────
create table if not exists public.contrato_eventos (
  id          bigint generated always as identity primary key,
  contrato_id uuid not null references public.contratos(id) on delete restrict,
  tipo        text not null,   -- creado | enviado | reenviado | visto | consentimiento | firmado
  fecha       timestamptz not null default clock_timestamp(),
  ip          text,
  user_agent  text,
  meta        jsonb
);

create index if not exists contrato_eventos_contrato_id_idx on public.contrato_eventos(contrato_id);

-- ── Huella y ID de transacción, calculados por la base ────────
-- Se calculan acá y no en el navegador para que valgan como prueba:
-- el servidor es el que fija la huella del texto que se firmó.
create or replace function public.contratos_sellar()
returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  new.hash_texto     := encode(digest(new.texto_contrato, 'sha256'), 'hex');
  new.transaccion_id := upper(replace(new.id::text, '-', ''));
  return new;
end;
$$;

drop trigger if exists contratos_sellar_trg on public.contratos;
create trigger contratos_sellar_trg before insert on public.contratos
  for each row execute function public.contratos_sellar();

-- ── El contrato firmado no se puede modificar ─────────────────
-- Una vez firmado, el texto, la firma y las fechas quedan congelados.
-- Lo único que todavía puede escribirse es el PDF (se guarda segundos después).
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
       or new.estado        is distinct from old.estado then
      raise exception 'Un contrato firmado no se puede modificar (contrato %)', old.id;
    end if;
    if old.pdf_firmado is not null and new.pdf_firmado is distinct from old.pdf_firmado then
      raise exception 'El PDF firmado ya está guardado y no se puede reemplazar (contrato %)', old.id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists contratos_inmutable_trg on public.contratos;
create trigger contratos_inmutable_trg before update on public.contratos
  for each row execute function public.contratos_inmutable();

-- ── La trazabilidad no se edita ni se borra ───────────────────
-- Un registro de auditoría que se puede modificar no prueba nada.
create or replace function public.contrato_eventos_solo_alta()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Los eventos de un contrato no se pueden modificar ni borrar';
end;
$$;

drop trigger if exists contrato_eventos_no_update on public.contrato_eventos;
create trigger contrato_eventos_no_update before update on public.contrato_eventos
  for each row execute function public.contrato_eventos_solo_alta();

drop trigger if exists contrato_eventos_no_delete on public.contrato_eventos;
create trigger contrato_eventos_no_delete before delete on public.contrato_eventos
  for each row execute function public.contrato_eventos_solo_alta();

-- ── Permisos ──────────────────────────────────────────────────
alter table public.contratos         enable row level security;
alter table public.contrato_eventos  enable row level security;

drop policy if exists contratos_admin        on public.contratos;
drop policy if exists contratos_admin_select on public.contratos;
drop policy if exists contratos_admin_insert on public.contratos;
drop policy if exists contratos_admin_update on public.contratos;
create policy contratos_admin_select on public.contratos for select to authenticated using (true);
create policy contratos_admin_insert on public.contratos for insert to authenticated with check (true);
create policy contratos_admin_update on public.contratos for update to authenticated using (true) with check (true);

drop policy if exists contrato_eventos_admin        on public.contrato_eventos;
drop policy if exists contrato_eventos_admin_select on public.contrato_eventos;
drop policy if exists contrato_eventos_admin_insert on public.contrato_eventos;
create policy contrato_eventos_admin_select on public.contrato_eventos for select to authenticated using (true);
create policy contrato_eventos_admin_insert on public.contrato_eventos for insert to authenticated with check (true);

-- Nadie puede borrar contratos ni eventos desde la aplicación.
revoke delete on public.contratos        from anon, authenticated;
revoke update, delete on public.contrato_eventos from anon, authenticated;

-- ============================================================
--  FUNCIONES QUE USA LA PÁGINA DE FIRMA (contrato.html)
--  El trabajador entra sin usuario: se identifica con el token del link.
-- ============================================================

-- ── 1) Abrir el contrato ──────────────────────────────────────
create or replace function public.contrato_ver(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c   public.contratos;
  ip  text;
  ua  text;
begin
  select * into c from public.contratos where token = p_token;
  if not found then return null; end if;

  -- Se registra la primera apertura (equivale al "Documento abierto por" de la auditoría)
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
    'firma_empleador_img', c.firma_empleador_img
  );
end;
$$;

-- ── 2) Firmar ─────────────────────────────────────────────────
-- Registra consentimiento y firma con su propia hora, IP y dispositivo,
-- y devuelve la trazabilidad completa para que el navegador arme el informe.
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
    -- Datos propios del contrato: la página de firma los usa para resaltarlos
    -- en negrita dentro del PDF, igual que el modelo en Word.
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

-- ── 3) Guardar el PDF ─────────────────────────────────────────
-- Se llama apenas el navegador termina de armar el PDF con el informe adentro.
-- Si ya había uno guardado, no se reemplaza (el original manda).
create or replace function public.contrato_guardar_pdf(p_token uuid, p_pdf_firmado text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.contratos;
begin
  select * into c from public.contratos where token = p_token;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); end if;
  if c.pdf_firmado is not null then return jsonb_build_object('ok', true, 'motivo', 'ya_guardado'); end if;

  update public.contratos set pdf_firmado = p_pdf_firmado where id = c.id;
  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.contrato_ver(uuid)                 to anon, authenticated;
grant execute on function public.contrato_firmar(uuid, text)        to anon, authenticated;
grant execute on function public.contrato_guardar_pdf(uuid, text)   to anon, authenticated;

-- ============================================================
--  Listo. Para probar: en una convocatoria, Editar → tildar
--  "Contratos habilitados" → mandar una confirmación con
--  "Adjuntar contrato de trabajo" tildado.
-- ============================================================
