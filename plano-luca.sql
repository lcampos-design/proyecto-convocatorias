-- ============================================================
--  PLANO DEL ARENA: lo que marcó Luca (coordinador) el 13-nov-2026
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: los
--  cambios se hacen una sola vez (la segunda vez avisa que ya estaba).
--
--   · Planta baja: la que figuraba como "Puerta 3" (la esquina de Humboldt,
--     lado Cancha) es la 4; la que figuraba como "Puerta 4" (el medio de
--     Humboldt) pasa a ser "Puerta Humboldt".
--   · Platea baja: Stella Artois y Branca estaban invertidas (cada una va al
--     lugar de la otra).
--
--  Cambia el plano guardado y las incidencias ya cargadas, a la vez, así cada
--  una sigue en su lugar real. Antes guarda una copia en el esquema respaldo.
--  No toca datos de nadie: sólo nombres y posiciones de lugares.
-- ============================================================

create schema if not exists respaldo;

do $$
begin
  if to_regclass('respaldo.plano_luca_2026_11') is not null then
    raise notice 'Ya estaba hecho: no se cambió nada.';
    return;
  end if;
  if exists (select 1 from public.incidencias where sector = 'Puerta Humboldt')
     or exists (select 1 from public.arena_plano p, jsonb_array_elements(p.lugares) e where e->>'id' = 'Puerta Humboldt') then
    raise exception 'Ya hay una "Puerta Humboldt": no se cambió nada. Avisá antes de seguir.';
  end if;

  -- La copia: el plano guardado y las incidencias que cambian de nombre.
  create table respaldo.plano_luca_2026_11 as
    select 'arena_plano'::text as tabla, p.id::text as fila_id, to_jsonb(p) as antes from public.arena_plano p
    union all
    select 'incidencias', i.id::text, to_jsonb(i) from public.incidencias i where i.sector in ('Puerta 3', 'Puerta 4');
  revoke all on respaldo.plano_luca_2026_11 from public, anon, authenticated;

  -- Las incidencias, todas a la vez (la 3 vieja va a la 4, la 4 vieja a Humboldt, sin encadenar).
  update public.incidencias set sector = case sector when 'Puerta 3' then 'Puerta 4' when 'Puerta 4' then 'Puerta Humboldt' end
   where sector in ('Puerta 3', 'Puerta 4');

  -- El plano guardado (si hay): las puertas, y Stella Artois y Branca, cada una con la posición de la otra.
  update public.arena_plano p set
    lugares = (
      select coalesce(jsonb_agg(case x.e->>'id'
          when 'Puerta 3' then x.e || '{"id": "Puerta 4", "txt": "P4"}'::jsonb
          when 'Puerta 4' then x.e || '{"id": "Puerta Humboldt", "txt": "Humb."}'::jsonb
          when 'Stella Artois' then x.e || coalesce((select jsonb_strip_nulls(jsonb_build_object('cx', b->'cx', 'cy', b->'cy', 'w', b->'w', 'h', b->'h', 'ang', b->'ang'))
                                                     from jsonb_array_elements(p.lugares) b where b->>'id' = 'Branca' limit 1), '{}'::jsonb)
          when 'Branca' then x.e || coalesce((select jsonb_strip_nulls(jsonb_build_object('cx', s->'cx', 'cy', s->'cy', 'w', s->'w', 'h', s->'h', 'ang', s->'ang'))
                                              from jsonb_array_elements(p.lugares) s where s->>'id' = 'Stella Artois' limit 1), '{}'::jsonb)
          else x.e end order by x.n), '[]'::jsonb)
      from jsonb_array_elements(p.lugares) with ordinality x(e, n)),
    updated_at = now(),
    updated_por = 'plano-luca.sql';
end $$;

-- Cómo quedó: las puertas de planta baja, Stella y Branca en el plano guardado, y las incidencias que cambiaron.
select (select string_agg(e->>'id', ', ' order by e->>'id')
          from public.arena_plano p, jsonb_array_elements(p.lugares) e
         where e->>'t' = 'puerta' and coalesce(e->>'piso', 'PB') = 'PB') as puertas_planta_baja,
       (select string_agg((e->>'id') || ' en ' || (e->>'cx') || ',' || (e->>'cy'), ' · ')
          from public.arena_plano p, jsonb_array_elements(p.lugares) e
         where e->>'id' in ('Stella Artois', 'Branca')) as stella_y_branca,
       (select count(*) from respaldo.plano_luca_2026_11 where tabla = 'incidencias') as incidencias_renombradas;
