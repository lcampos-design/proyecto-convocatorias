-- La nómina más rápida y el CV de la inscripción visible desde la nómina (21-nov-2026).
-- Supabase → SQL Editor → pegar todo → Run. Se puede correr más de una vez: si al final "faltan" no da 0 · 0,
-- correrlo de nuevo (completa de a tandas, unos 25 segundos por vez, sin trabar el panel).
--
-- Mercedes: "la tenemos un poco saturada" (la nómina tarda en cargar) y "cuando están en nómina aceptados, no se ven
-- los cv". Las dos cosas tienen la misma causa: para armar la lista de la nómina (personas_lista) y para saber quién
-- mandó CV en su inscripción (el nombre del archivo), la base leía cada vez el CV ENTERO de cada persona y de cada
-- inscripción (el archivo va adentro, en base64). Con muchas inscripciones, la de la inscripción tardaba tanto que se
-- cortaba, y el panel se quedaba sin saber quién tiene CV ("Ver datos" en lugar de "Ver CV").
-- Ahora cada fila guarda aparte lo liviano (la ficha sin el archivo; el nombre del CV), y la lista lee eso.

-- 1) Lo liviano del CV de una persona: todo menos el contenido de los archivos.
create or replace function public.cv_liviano(p jsonb)
returns jsonb
language sql immutable set search_path = public as $$
  select case when p is null or jsonb_typeof(p) <> 'object' then p
    else (p #- '{archivo,datos}')
      || case when jsonb_typeof(p -> 'adjuntos') = 'array'
              then jsonb_build_object('adjuntos', coalesce((
                     select jsonb_agg(case when jsonb_typeof(a) = 'object' then a - 'datos' else a end)
                     from jsonb_array_elements(p -> 'adjuntos') a), '[]'::jsonb))
              else '{}'::jsonb end
  end
$$;

-- 2) Las columnas livianas (agregarlas no reescribe la tabla) y quién las mantiene al día.
alter table public.personas add column if not exists cv_liviano jsonb;
alter table public.solicitudes add column if not exists cv_nombre text;

create or replace function public.personas_cv_liviano()
returns trigger
language plpgsql set search_path = public as $$
begin
  new.cv_liviano := public.cv_liviano(new.cv);
  return new;
end $$;
drop trigger if exists personas_cv_liviano on public.personas;
create trigger personas_cv_liviano before insert or update of cv on public.personas
  for each row execute function public.personas_cv_liviano();

create or replace function public.solicitudes_cv_nombre()
returns trigger
language plpgsql set search_path = public as $$
begin
  -- '' = tiene archivos pero no un CV con nombre (sólo otros archivos): ya está mirada.
  new.cv_nombre := case when new.archivo_cv is null then null
                        when jsonb_typeof(new.archivo_cv) = 'object' then coalesce(new.archivo_cv ->> 'nombre', '')
                        else '' end;
  return new;
end $$;
drop trigger if exists solicitudes_cv_nombre on public.solicitudes;
create trigger solicitudes_cv_nombre before insert or update of archivo_cv on public.solicitudes
  for each row execute function public.solicitudes_cv_nombre();

revoke execute on function public.personas_cv_liviano() from public, anon;
revoke execute on function public.solicitudes_cv_nombre() from public, anon;
grant select (cv_nombre) on public.solicitudes to authenticated;

-- 3) Completar lo que ya está cargado, de a tandas (cada vuelta lee el CV de cada fila una sola vez).
do $$
declare t0 timestamptz := clock_timestamp(); n int;
begin
  loop
    update public.personas p set cv_liviano = public.cv_liviano(p.cv)
     where p.id in (select id from public.personas where cv is not null and cv_liviano is null limit 200);
    get diagnostics n = row_count;
    exit when n = 0 or clock_timestamp() - t0 > interval '12 seconds';
  end loop;
  loop
    update public.solicitudes s
       set cv_nombre = coalesce(case when jsonb_typeof(s.archivo_cv) = 'object' then s.archivo_cv ->> 'nombre' end, '')
     where s.id in (select id from public.solicitudes where cv_nombre is null and archivo_cv is not null limit 200);
    get diagnostics n = row_count;
    exit when n = 0 or clock_timestamp() - t0 > interval '25 seconds';
  end loop;
end $$;

-- 4) La lista de la nómina, sin leer el CV entero: todas las columnas de la persona menos el CV, más su versión
--    liviana (la de las filas que todavía no se completaron se calcula en el momento). Sólo para administradores.
create or replace function public.personas_lista()
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare cols text;
begin
  if not public.es_admin() then return; end if;
  select string_agg(format('p.%I', attname), ', ' order by attnum) into cols
    from pg_attribute
   where attrelid = 'public.personas'::regclass and attnum > 0 and not attisdropped
     and attname not in ('cv', 'cv_liviano');
  return query execute format(
    'select (to_jsonb(x) - ''_cv'' - ''_orden'') || jsonb_build_object(''cv'', x._cv)
       from (select %s, coalesce(p.cv_liviano, public.cv_liviano(p.cv)) as _cv, p.created_at as _orden
               from public.personas p) x
      order by x._orden, x.id', cols);   -- con desempate: el panel la baja de a tandas y no tiene que saltear a nadie
end $$;
grant execute on function public.personas_lista() to authenticated;

-- Cómo quedó: columnas 2 · faltan 0 · 0 (si no, correrlo de nuevo) · con_contenido 0.
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and ((table_name = 'personas' and column_name = 'cv_liviano')
                                    or (table_name = 'solicitudes' and column_name = 'cv_nombre'))) as columnas,
  (select count(*) from public.personas where cv is not null and cv_liviano is null) as faltan_personas,
  (select count(*) from public.solicitudes where cv_nombre is null and archivo_cv is not null) as faltan_inscripciones,
  (select count(*) from public.personas where cv_liviano -> 'archivo' ? 'datos') as con_contenido,
  (select count(*) from public.solicitudes where cv_nombre <> '') as inscripciones_con_cv;
