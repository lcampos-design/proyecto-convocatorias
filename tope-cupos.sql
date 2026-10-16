-- ============================================================
-- TOPE DURO DE CUPOS: no se puede postular/agregar a un puesto que ya está lleno.
-- Cubre la página pública, los agregados desde nómina y anotaciones simultáneas.
-- Correr en Supabase -> SQL Editor.
-- ============================================================

create or replace function public.trg_cupo_lleno()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_cupos  int;
  v_usados int;
begin
  -- Los rechazados no ocupan cupo
  if coalesce(new.estado,'') = 'rechazado' then return new; end if;
  if new.puesto_id is null then return new; end if;

  select cupos into v_cupos from public.puestos where id = new.puesto_id;
  if v_cupos is null then return new; end if;  -- sin cupo definido => no se limita

  select count(*) into v_usados
    from public.postulaciones
   where puesto_id = new.puesto_id
     and coalesce(estado,'') <> 'rechazado';

  if v_usados >= v_cupos then
    raise exception 'CUPO_LLENO' using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists cupo_lleno_check on public.postulaciones;
create trigger cupo_lleno_check
  before insert on public.postulaciones
  for each row execute function public.trg_cupo_lleno();
