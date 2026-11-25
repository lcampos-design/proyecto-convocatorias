-- ============================================================
--  VACACIONES: BORRAR SOLICITUDES DESDE EL PANEL (25-nov)
-- ============================================================
--  Thomas (25-nov): "posibilidad de borrar desde admin solicitudes, porque todas las que mande son de prueba".
--  Sólo el panel (es_admin). Se borra la solicitud con sus firmas, su trazabilidad y el PDF; para no perder el
--  rastro, queda anotado en vacaciones_borradas qué se borró (el ID, el nombre, el área, el estado), quién y cuándo.
--  Va después de vacaciones.sql. Se puede correr más de una vez. Al final: si quedó todo (sí/no).
-- ============================================================

create table if not exists public.vacaciones_borradas (
  id             bigserial primary key,
  vacacion_id    uuid not null,
  transaccion_id text,
  nombre         text,
  area           text,
  estado         text,
  creada         timestamptz,
  borrada_por    text,
  fecha          timestamptz not null default now()
);
-- Los mails que habían salido y las firmas (25-nov): la trazabilidad se borra con la solicitud, esto queda.
alter table public.vacaciones_borradas add column if not exists pasos text;
alter table public.vacaciones_borradas enable row level security;
revoke all on public.vacaciones_borradas from anon, authenticated;
grant select on public.vacaciones_borradas to authenticated;
drop policy if exists vacaciones_borradas_admin on public.vacaciones_borradas;
create policy vacaciones_borradas_admin on public.vacaciones_borradas for select to authenticated using (public.es_admin());

-- Borrar una o varias (los eventos se van con la solicitud: on delete cascade).
create or replace function public.vacaciones_borrar(p_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_quien text := coalesce(auth.jwt() ->> 'email', 'panel'); n int;
begin
  if not public.es_admin() then return jsonb_build_object('ok', false, 'error', 'Sin permiso'); end if;
  if p_ids is null or cardinality(p_ids) = 0 then return jsonb_build_object('ok', false, 'error', 'No marcaste ninguna.'); end if;
  insert into public.vacaciones_borradas (vacacion_id, transaccion_id, nombre, area, estado, creada, borrada_por, pasos)
  select v.id, v.transaccion_id, v.nombre, v.area, v.estado, v.created_at, v_quien,
         (select string_agg(to_char(e.fecha at time zone 'America/Argentina/Buenos_Aires', 'DD/MM HH24:MI') || ' · ' || coalesce(e.quien, '') || ' · ' || coalesce(e.detalle, ''), E'\n' order by e.fecha, e.id)
            from public.vacaciones_eventos e where e.vacacion_id = v.id and e.tipo in ('aviso', 'firmada', 'cancelada', 'reemplazada'))
    from public.vacaciones v where v.id = any(p_ids);
  delete from public.vacaciones where id = any(p_ids);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'borradas', n);
end;
$$;
revoke execute on function public.vacaciones_borrar(uuid[]) from public, anon;
grant execute on function public.vacaciones_borrar(uuid[]) to authenticated;

-- Cómo quedó (sólo sí/no).
select
  exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'vacaciones_borradas') as registro,
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'vacaciones_borradas' and column_name = 'pasos') as con_los_mails,
  has_function_privilege('authenticated', 'public.vacaciones_borrar(uuid[])', 'execute') as panel_puede,
  not has_function_privilege('anon', 'public.vacaciones_borrar(uuid[])', 'execute') as sin_usuario_no;
