-- La nómina más rápida, segunda parte (21-nov-2026). Va DESPUÉS de velocidad-nomina.sql (ya corrido).
-- Supabase → SQL Editor → pegar todo → Run. Se puede correr las veces que haga falta.
--
-- Al correr velocidad-nomina.sql quedaron ~10.000 fichas y ~10.600 inscripciones por completar (en 25 segundos
-- alcanzó para una parte). Mientras falten, la lista de la nómina calcula lo liviano de las que faltan y, como el
-- panel la pide de a tandas, cada tanda lo calculaba para TODAS. Esto:
--  1) agrega personas_lista_tanda(desde, cantidad): la lista de a una tanda, que calcula sólo las de esa tanda
--     (el panel nuevo usa ésta; si no está, la de siempre);
--  2) sigue completando, primero las fichas de la nómina (lo que pesa al abrir el panel) y después las
--     inscripciones, unos 25 segundos por vez. Al final dice cuántas completó en esta vuelta y cuántas faltan:
--     correrlo de nuevo hasta que falten 0 · 0.

create or replace function public.personas_lista_tanda(p_desde int, p_cantidad int)
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare cols text;
begin
  if not public.es_admin() then return; end if;
  select string_agg(format('p.%I', attname), ', ' order by attnum) into cols
    from pg_attribute
   where attrelid = 'public.personas'::regclass and attnum > 0 and not attisdropped
     and attname not in ('cv', 'cv_liviano');
  -- Primero los de la tanda (sólo columnas livianas, en el orden de siempre, con desempate por id), y recién ahí
  -- lo liviano del CV de esos.
  return query execute format(
    'with t as materialized (
       select id, created_at from public.personas order by created_at, id offset %s limit %s)
     select (to_jsonb(x) - ''_cv'' - ''_orden'' - ''_id'') || jsonb_build_object(''cv'', x._cv)
       from (select %s, coalesce(p.cv_liviano, public.cv_liviano(p.cv)) as _cv, t.created_at as _orden, t.id as _id
               from t join public.personas p on p.id = t.id) x
      order by x._orden, x._id',
    greatest(coalesce(p_desde, 0), 0), least(greatest(coalesce(p_cantidad, 1000), 1), 1000), cols);
end $$;
revoke execute on function public.personas_lista_tanda(int, int) from public, anon;
grant execute on function public.personas_lista_tanda(int, int) to authenticated;

-- Completar de a tandas: primero las fichas, después las inscripciones (25 segundos por vez).
do $$
declare t0 timestamptz := clock_timestamp(); n int; tp int := 0; ts int := 0;
begin
  loop
    update public.personas p set cv_liviano = public.cv_liviano(p.cv)
     where p.id in (select id from public.personas where cv is not null and cv_liviano is null limit 100);
    get diagnostics n = row_count; tp := tp + n;
    exit when n = 0 or clock_timestamp() - t0 > interval '25 seconds';
  end loop;
  if clock_timestamp() - t0 <= interval '25 seconds' then
    loop
      update public.solicitudes s
         set cv_nombre = coalesce(case when jsonb_typeof(s.archivo_cv) = 'object' then s.archivo_cv ->> 'nombre' end, '')
       where s.id in (select id from public.solicitudes where cv_nombre is null and archivo_cv is not null limit 100);
      get diagnostics n = row_count; ts := ts + n;
      exit when n = 0 or clock_timestamp() - t0 > interval '25 seconds';
    end loop;
  end if;
  raise notice 'Completadas en esta vuelta: % fichas y % inscripciones', tp, ts;
  perform set_config('avance.fichas', tp::text, false);
  perform set_config('avance.inscripciones', ts::text, false);
end $$;

-- Cómo va: completadas en esta vuelta y cuántas faltan (correrlo de nuevo hasta faltan 0 · 0).
select
  nullif(current_setting('avance.fichas', true), '')::int as fichas_ahora,
  nullif(current_setting('avance.inscripciones', true), '')::int as inscripciones_ahora,
  (select count(*) from public.personas where cv is not null and cv_liviano is null) as faltan_fichas,
  (select count(*) from public.solicitudes where cv_nombre is null and archivo_cv is not null) as faltan_inscripciones,
  (select count(*) from pg_proc where proname = 'personas_lista_tanda') as funcion_tanda;
