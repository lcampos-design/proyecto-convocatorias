-- ============================================================
--  BORRAR CONTRATOS DESDE EL PANEL
--  Correr completo en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no borra nada ni duplica.
--
--  Hasta ahora un contrato no se podía borrar por ningún medio: la tabla
--  tiene DELETE revocado y la trazabilidad tiene un disparador que lo impide.
--  Eso es lo correcto para un documento firmado, pero deja sin salida a los
--  contratos de prueba y a los que se generan con un dato mal cargado.
--
--  La solución no es abrir el borrado, sino hacerlo pasar por una sola puerta
--  que deja constancia: contrato_borrar() exige motivo, guarda una copia del
--  contrato y de todos sus eventos en contratos_borrados, y recién ahí borra.
--  El contrato desaparece del panel; la prueba de que existió, no.
-- ============================================================

-- ── Dónde queda la constancia ─────────────────────────────────
create table if not exists public.contratos_borrados (
  id               uuid primary key default gen_random_uuid(),
  contrato_id      uuid not null,
  transaccion_id   text,
  hash_texto       text,          -- la huella del texto: permite verificar un PDF que ande dando vueltas
  nombre           text,
  cuil             text,
  email            text,
  puesto           text,
  conv_id          uuid,
  estado           text,          -- en qué estado estaba al borrarlo (pendiente/enviado/visto/firmado)
  fecha_creacion   timestamptz,
  fecha_firma      timestamptz,
  texto_contrato   text,          -- el contrato entero, tal como se había congelado
  pdf_firmado      text,          -- el PDF con el informe de auditoría, si estaba firmado
  eventos          jsonb,         -- toda la trazabilidad que tenía
  motivo           text not null,
  borrado_por      uuid,
  borrado_por_mail text,
  borrado_at       timestamptz not null default now()
);

create index if not exists contratos_borrados_cuil_idx on public.contratos_borrados(cuil);

alter table public.contratos_borrados enable row level security;

drop policy if exists contratos_borrados_select on public.contratos_borrados;
create policy contratos_borrados_select on public.contratos_borrados
  for select to authenticated using (true);

-- Se escribe sólo desde contrato_borrar(), nunca a mano desde la aplicación.
revoke insert, update, delete on public.contratos_borrados from anon, authenticated;

-- ── La única excepción al "los eventos no se borran" ──────────
-- El disparador sigue rechazando todo, salvo cuando el borrado viene de
-- contrato_borrar(), que avisa con una marca de sesión y ya dejó la copia.
create or replace function public.contrato_eventos_solo_alta()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' and current_setting('app.borrando_contrato', true) = 'on' then
    return old;
  end if;
  raise exception 'Los eventos de un contrato no se pueden modificar ni borrar';
end;
$$;

-- ── Borrar un contrato ────────────────────────────────────────
create or replace function public.contrato_borrar(p_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c     public.contratos;
  evs   jsonb;
  mail  text;
begin
  if auth.uid() is null then
    raise exception 'Hay que iniciar sesión para borrar un contrato';
  end if;

  -- Un supervisor no borra contratos: sólo los administradores.
  if not exists (
    select 1 from public.user_profiles up
    where up.id = auth.uid() and coalesce(up.rol, '') like 'admin%'
  ) then
    raise exception 'Sólo un administrador puede borrar contratos';
  end if;

  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Hay que escribir el motivo del borrado';
  end if;

  select * into c from public.contratos where id = p_id;
  if not found then
    raise exception 'Ese contrato ya no existe';
  end if;

  select coalesce(jsonb_agg(to_jsonb(ev) order by ev.fecha), '[]'::jsonb)
    into evs
    from public.contrato_eventos ev
   where ev.contrato_id = p_id;

  select u.email into mail from auth.users u where u.id = auth.uid();

  insert into public.contratos_borrados (
    contrato_id, transaccion_id, hash_texto, nombre, cuil, email, puesto, conv_id,
    estado, fecha_creacion, fecha_firma, texto_contrato, pdf_firmado, eventos,
    motivo, borrado_por, borrado_por_mail
  ) values (
    c.id, c.transaccion_id, c.hash_texto, c.nombre, c.cuil, c.email, c.puesto, c.conv_id,
    c.estado, c.fecha_creacion, c.fecha_firma, c.texto_contrato, c.pdf_firmado, evs,
    btrim(p_motivo), auth.uid(), mail
  );

  -- La marca vale sólo para esta transacción (tercer parámetro en true).
  perform set_config('app.borrando_contrato', 'on', true);
  delete from public.contrato_eventos where contrato_id = p_id;
  delete from public.contratos where id = p_id;
  perform set_config('app.borrando_contrato', '', true);

  return jsonb_build_object('ok', true, 'estado', c.estado, 'nombre', c.nombre);
end;
$$;

revoke all on function public.contrato_borrar(uuid, text) from public, anon;
grant execute on function public.contrato_borrar(uuid, text) to authenticated;
