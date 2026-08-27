-- ============================================================
-- BLOQUEADOS: los rechazados/eliminados no pueden volver a inscribirse.
-- Bloqueo GLOBAL por CUIL. Correr TODO en Supabase -> SQL Editor.
-- ============================================================

-- 1) Tabla de CUIL bloqueados
create table if not exists public.bloqueados (
  cuit       text primary key,
  nombre     text,
  email      text,
  area       text,
  motivo     text,
  created_at timestamptz default now()
);
alter table public.bloqueados enable row level security;
drop policy if exists bloq_auth_all on public.bloqueados;
create policy bloq_auth_all on public.bloqueados
  for all to authenticated using (true) with check (true);

-- 2) ¿Está bloqueado este CUIL? (lo usa el registro público)
create or replace function public.esta_bloqueado(p_cuit text)
returns boolean
language sql security definer set search_path = public as $$
  select exists(
    select 1 from public.bloqueados
    where cuit = regexp_replace(coalesce(p_cuit,''), '\D', '', 'g')
  );
$$;
grant execute on function public.esta_bloqueado(text) to anon, authenticated;

-- 3) Bloquear un CUIL y borrar TODAS sus solicitudes
create or replace function public.bloquear_cuit(
  p_cuit text, p_nombre text, p_email text, p_area text, p_motivo text)
returns void
language plpgsql security definer set search_path = public as $$
declare v text := regexp_replace(coalesce(p_cuit,''), '\D', '', 'g');
begin
  if v = '' then return; end if;
  insert into public.bloqueados (cuit, nombre, email, area, motivo)
    values (v, p_nombre, p_email, p_area, p_motivo)
    on conflict (cuit) do update set
      nombre = coalesce(excluded.nombre, bloqueados.nombre),
      email  = coalesce(excluded.email,  bloqueados.email),
      area   = coalesce(excluded.area,   bloqueados.area),
      motivo = coalesce(excluded.motivo, bloqueados.motivo);
  delete from public.solicitudes
    where regexp_replace(coalesce(cuit,''), '\D', '', 'g') = v;
end;
$$;
grant execute on function public.bloquear_cuit(text,text,text,text,text) to authenticated;

-- 4) Desbloquear un CUIL
create or replace function public.desbloquear_cuit(p_cuit text)
returns void
language sql security definer set search_path = public as $$
  delete from public.bloqueados
   where cuit = regexp_replace(coalesce(p_cuit,''), '\D', '', 'g');
$$;
grant execute on function public.desbloquear_cuit(text) to authenticated;

-- 5) Backstop server-side: rechazar inserts de CUIL bloqueados en solicitudes
--    (por si alguien intenta saltear la validación del formulario)
create or replace function public.trg_check_bloqueado()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists(
    select 1 from public.bloqueados
    where cuit = regexp_replace(coalesce(new.cuit,''), '\D', '', 'g')
  ) then
    raise exception 'CUIT bloqueado';
  end if;
  return new;
end;
$$;
drop trigger if exists bloqueado_no_insert on public.solicitudes;
create trigger bloqueado_no_insert
  before insert on public.solicitudes
  for each row execute function public.trg_check_bloqueado();
