-- La nómina más rápida, tercera parte (21-nov-2026): que se complete sola. Va después de velocidad-nomina.sql y
-- velocidad-nomina-2.sql (ya corridos). Supabase → SQL Editor → pegar todo → Run, UNA vez.
--
-- Quedan ~9.400 fichas y ~10.400 inscripciones por completar, y cada corrida a mano completa unas 700 fichas (las
-- inscripciones, con el CV adentro, van más lento): harían falta unas 45 corridas. Esto deja una tarea programada en
-- la base (pg_cron) que cada minuto trabaja 30 segundos, primero las fichas y después las inscripciones, y que se
-- borra sola cuando no queda nada. En unos 35-40 minutos tendría que estar todo.
-- Para ver cómo va: volver a correr sólo el último select (o todo: no se duplica).

create extension if not exists pg_cron;

create or replace function public.completar_livianos(p_segundos int default 30)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare t0 timestamptz := clock_timestamp(); n int; tp int := 0; ts int := 0; fp int; fs int;
begin
  loop
    update public.personas p set cv_liviano = public.cv_liviano(p.cv)
     where p.id in (select id from public.personas where cv is not null and cv_liviano is null limit 100);
    get diagnostics n = row_count; tp := tp + n;
    exit when n = 0 or clock_timestamp() - t0 > make_interval(secs => p_segundos);
  end loop;
  if clock_timestamp() - t0 <= make_interval(secs => p_segundos) then
    loop
      update public.solicitudes s
         set cv_nombre = coalesce(case when jsonb_typeof(s.archivo_cv) = 'object' then s.archivo_cv ->> 'nombre' end, '')
       where s.id in (select id from public.solicitudes where cv_nombre is null and archivo_cv is not null limit 50);
      get diagnostics n = row_count; ts := ts + n;
      exit when n = 0 or clock_timestamp() - t0 > make_interval(secs => p_segundos);
    end loop;
  end if;
  select count(*) into fp from public.personas where cv is not null and cv_liviano is null;
  select count(*) into fs from public.solicitudes where cv_nombre is null and archivo_cv is not null;
  -- Terminado: la tarea se borra sola.
  if fp = 0 and fs = 0 then
    perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'completar-livianos';
  end if;
  return jsonb_build_object('fichas', tp, 'inscripciones', ts, 'faltan_fichas', fp, 'faltan_inscripciones', fs);
end $$;
revoke execute on function public.completar_livianos(int) from public, anon, authenticated;

-- Cada minuto (si ya estaba programada, se reemplaza: no se duplica).
select cron.unschedule(jobid) from cron.job where jobname = 'completar-livianos';
select cron.schedule('completar-livianos', '* * * * *', 'select public.completar_livianos(30)');

-- Cómo va: faltan_fichas y faltan_inscripciones van bajando; cuando lleguen a 0 · 0, tarea_programada pasa a 0 sola.
select
  (select count(*) from public.personas where cv is not null and cv_liviano is null) as faltan_fichas,
  (select count(*) from public.solicitudes where cv_nombre is null and archivo_cv is not null) as faltan_inscripciones,
  (select count(*) from cron.job where jobname = 'completar-livianos') as tarea_programada;
