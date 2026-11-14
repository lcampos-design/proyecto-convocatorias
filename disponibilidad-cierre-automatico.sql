-- ============================================================
--  RONDAS DE DISPONIBILIDAD: que se cierren solas cuando el show ya pasó
--  (14-nov-2026). Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Una ronda abierta de un show que ya pasó se sigue viendo sin usuario (el
--  nombre y la fecha) y deja cargar fechas que ya no sirven. Ahora:
--   1) se cierran ya las de los shows cuya última fecha ya pasó;
--   2) todos los días a las 6 (hora de Argentina) se cierran las que pasaron
--      el día anterior, con la programación de tareas de la base (pg_cron).
--  Un show de varias fechas se cierra después de la última. Sólo cambia
--  "disponibilidad abierta" → cerrada; no toca respuestas ni personas.
-- ============================================================

create or replace function public.cerrar_disponibilidad_pasada()
returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.convocatorias c set disp_abierta = false
   where coalesce(c.disp_abierta, false)
     and (select max(m.f[1]::date) from regexp_matches(coalesce(c.fecha, ''), '(\d{4}-\d{2}-\d{2})', 'g') as m(f))
         < (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  get diagnostics n = row_count;
  return n;
end;
$$;
-- La corre la base (y quien entra al panel, si hiciera falta); nadie sin usuario.
revoke execute on function public.cerrar_disponibilidad_pasada() from public, anon;
grant  execute on function public.cerrar_disponibilidad_pasada() to authenticated, service_role;

-- 1) Las de ahora.
do $$ begin raise notice 'Rondas cerradas ahora: %', public.cerrar_disponibilidad_pasada(); end $$;

-- 2) Todos los días a las 6 de Argentina (9 UTC).
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'No se pudo activar pg_cron (%). Activarlo en Database → Extensions → pg_cron y volver a correr.', sqlerrm;
    return;
  end;
  perform cron.unschedule(jobid) from cron.job where jobname = 'cerrar-disponibilidad-pasada';
  perform cron.schedule('cerrar-disponibilidad-pasada', '0 9 * * *', 'select public.cerrar_disponibilidad_pasada()');
  raise notice 'Programado: todos los días a las 6 (Argentina) se cierran las rondas de shows que ya pasaron.';
end $$;

-- Cómo quedó: las rondas que siguen abiertas (tienen que ser sólo de shows que vienen) y la tarea programada.
select 'Ronda abierta' as que, c.nombre || ' · ' || coalesce(c.fecha, '') as detalle
  from public.convocatorias c where coalesce(c.disp_abierta, false)
union all
select 'Tarea programada', case when to_regclass('cron.job') is null then 'FALTA: activar pg_cron y volver a correr'
                              else 'activada: todos los días a las 6 (Argentina)' end
 order by 1, 2;
