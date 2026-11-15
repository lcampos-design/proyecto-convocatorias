-- ============================================================
--  INCIDENCIAS: la criticidad con un criterio fijo (15-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Thomas, 15-nov: "hubo desmayos en ambos [reportes] y en un reporte
--  figuran con gravedad leve y en otra como media. Quiero que haya un
--  criterio estable." Hasta ahora el supervisor elegía la criticidad al
--  cargar (el tipo traía una sugerida). Desde ahora la pone la base:
--   · cada tipo tiene la suya, fija (la del catálogo de la app y el panel);
--   · pasa a Grave si se tildó "Se derivó en ambulancia (SAME)" o "Se dio
--     aviso a la policía", al cargarla o al resolverla;
--   · un tipo que no está en el catálogo queda con la que tenía (y también
--     sube a Grave con eso).
--  Lo hace un trigger: vale para la app, el panel y cualquier carga.
--
--  Y corrige con el mismo criterio las que ya están cargadas (antes guarda
--  la criticidad que tenía cada una en el esquema respaldo). El link del
--  informe que recibió el Arena muestra lo corregido (se arma en el momento);
--  el PDF adjunto al mail queda como salió. No se manda ningún mail.
--  Si se cambia el catálogo en la app, cambiarlo también acá.
-- ============================================================

create or replace function public.incidencia_nivel(p_tipo text, p_acciones jsonb, p_actual int)
returns smallint
language sql immutable set search_path = public as $$
  select greatest(
    coalesce(
      (select t.n from (values
        ('Desmayo / descompensación', 2), ('Lesión o caída', 2), ('Persona alcoholizada o intoxicada', 2), ('Emergencia médica grave', 3),
        ('Pelea o agresión', 3), ('Persona agresiva o molesta', 2), ('Ingreso indebido / sin entrada', 2), ('Objeto prohibido', 1), ('Robo o hurto', 2),
        ('Fila larga en el ingreso', 1), ('Fila de ingreso desbordada', 2), ('Molinete o lector de entradas que no anda', 2),
        ('Demora en la apertura de puertas', 2), ('Amontonamiento o empujones en el ingreso', 3),
        ('Cambio de ubicación', 1), ('Ubicación ocupada', 1), ('Entrada duplicada', 2), ('Persona fuera de su sector', 1),
        ('Derrame / piso resbaladizo', 1), ('Butaca o baranda rota', 1), ('Baño fuera de servicio', 1), ('Falla eléctrica o de iluminación', 2),
        ('Salida obstruida', 3),
        ('Falta personal en el sector', 2), ('Personal descompuesto', 2), ('Problema de conducta o uniforme', 1),
        ('Acompañamiento a ubicación accesible', 1), ('Salida diferenciada', 1), ('Asistencia a persona con discapacidad', 1),
        ('Otra incidencia', 1)
      ) t(tipo, n) where t.tipo = btrim(coalesce(p_tipo, ''))),
      least(greatest(coalesce(p_actual, 1), 1), 3)),
    case when coalesce(p_acciones, '[]'::jsonb) ?| array['Se derivó en ambulancia (SAME)', 'Se dio aviso a la policía'] then 3 else 1 end
  )::smallint
$$;
revoke execute on function public.incidencia_nivel(text, jsonb, int) from public, anon;
grant  execute on function public.incidencia_nivel(text, jsonb, int) to authenticated, service_role;

create or replace function public.incidencias_nivel_fijo()
returns trigger
language plpgsql set search_path = public as $$
begin
  new.nivel := public.incidencia_nivel(new.tipo, new.acciones, new.nivel);
  return new;
end $$;
revoke execute on function public.incidencias_nivel_fijo() from public, anon;

drop trigger if exists incidencias_nivel_fijo on public.incidencias;
create trigger incidencias_nivel_fijo
  before insert or update of tipo, acciones, nivel on public.incidencias
  for each row execute function public.incidencias_nivel_fijo();

-- La copia: la criticidad que tenía cada una antes de corregir (la primera vez que se corre).
create schema if not exists respaldo;
create table if not exists respaldo.incidencias_nivel_2026_11_15 (id uuid primary key, nivel_antes smallint not null, guardado timestamptz not null default now());
revoke all on respaldo.incidencias_nivel_2026_11_15 from public, anon, authenticated;
insert into respaldo.incidencias_nivel_2026_11_15 (id, nivel_antes)
  select i.id, i.nivel from public.incidencias i
  on conflict (id) do nothing;

-- Las ya cargadas, con el mismo criterio.
do $$
declare n int;
begin
  update public.incidencias i set nivel = public.incidencia_nivel(i.tipo, i.acciones, i.nivel)
   where i.nivel is distinct from public.incidencia_nivel(i.tipo, i.acciones, i.nivel);
  get diagnostics n = row_count;
  raise notice 'Incidencias corregidas ahora: %', n;
end $$;

-- Cómo quedó: lo que cambió, por show y fecha de función (de 6 a 6), y el total.
select c.nombre || ' · ' || to_char((i.created_at at time zone 'America/Argentina/Buenos_Aires') - interval '6 hours', 'DD/MM') as show,
       i.tipo,
       case r.nivel_antes when 1 then 'Leve' when 2 then 'Medio' else 'Grave' end || ' → ' ||
       case i.nivel when 1 then 'Leve' when 2 then 'Medio' else 'Grave' end as criticidad,
       count(*)::text as cuantas
  from public.incidencias i
  join respaldo.incidencias_nivel_2026_11_15 r on r.id = i.id
  join public.convocatorias c on c.id = i.conv_id
 where r.nivel_antes <> i.nivel
 group by 1, 2, 3
union all
select 'Total', 'incidencias con la criticidad corregida', '',
       (select count(*) from public.incidencias i join respaldo.incidencias_nivel_2026_11_15 r on r.id = i.id where r.nivel_antes <> i.nivel)::text
 order by 1, 2;
