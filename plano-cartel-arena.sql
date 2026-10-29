-- ============================================================
--  PLANO DEL ARENA: los nombres del cartel de evacuación
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: los
--  cambios se hacen una sola vez (la segunda vez avisa que ya estaba).
--
--  Según el cartel "Usted está aquí" del Arena:
--   · Las puertas de los costados son la 6, 7, 8 y 9. Lado Cancha: la 8
--     (cerca del escenario) y la 6. Lado Sede: la 9 y la 7. En el plano se
--     llamaban 1 y 2 (Cancha) y 7 y 6 (Sede).
--   · Detrás del escenario la calle sigue siendo Av. Dorrego (el cartel
--     marca las vías del FFCC San Martín; la primera versión de este archivo
--     la renombraba, pero no había nada con ese nombre y no cambió nada).
--   · Del lado Cancha está la calle Muñecas (se suma al plano guardado).
--   · Los corners se llaman Diamante (el 101, lado Cancha) y Trébol (el 119,
--     lado Sede).
--
--  Cambia los nombres a la vez en el plano guardado y en las incidencias ya
--  cargadas, así cada una sigue en su lugar: la "Puerta 6" vieja, del lado
--  Sede, pasa a ser la 7; no queda en la 6 nueva, que es del lado Cancha.
--  Antes guarda una copia de lo que cambia en el esquema respaldo.
--  No toca datos de nadie: sólo nombres de lugares.
-- ============================================================

create schema if not exists respaldo;

do $$
begin
  if to_regclass('respaldo.plano_cartel_2026_10') is not null then
    raise notice 'Ya estaba hecho: no se cambió nada.';
    return;
  end if;

  -- Si alguien ya agregó a mano una "Puerta 8" o una "Puerta 9", renombrar
  -- juntaría dos puertas distintas: no se toca nada y se avisa.
  if exists (select 1 from public.incidencias where sector in ('Puerta 8', 'Puerta 9'))
     or exists (select 1 from public.arena_plano p, jsonb_array_elements(p.lugares) e where e->>'id' in ('Puerta 8', 'Puerta 9')) then
    raise exception 'Ya hay una "Puerta 8" o una "Puerta 9" en el plano o en las incidencias: no se cambió nada. Avisá antes de seguir.';
  end if;

  -- La copia: el plano guardado y las incidencias que cambian de nombre.
  create table respaldo.plano_cartel_2026_10 as
    select 'arena_plano'::text as tabla, p.id::text as fila_id, to_jsonb(p) as antes from public.arena_plano p
    union all
    select 'incidencias', i.id::text, to_jsonb(i) from public.incidencias i
     where i.sector in ('Puerta 1', 'Puerta 2', 'Puerta 6', 'Puerta 7', 'Corner · Cancha', 'Corner · Sede');
  revoke all on respaldo.plano_cartel_2026_10 from public, anon, authenticated;

  -- Las incidencias, cada una a su nombre nuevo, todas a la vez (sin
  -- encadenar: la 6 vieja va a la 7 y no sigue de largo a la 9).
  update public.incidencias set sector = case sector
      when 'Puerta 1' then 'Puerta 8'
      when 'Puerta 2' then 'Puerta 6'
      when 'Puerta 6' then 'Puerta 7'
      when 'Puerta 7' then 'Puerta 9'
      when 'Corner · Cancha' then 'Corner Diamante'
      when 'Corner · Sede' then 'Corner Trébol' end
   where sector in ('Puerta 1', 'Puerta 2', 'Puerta 6', 'Puerta 7', 'Corner · Cancha', 'Corner · Sede');

  -- El plano guardado (si hay): lo mismo en cada puesto, el nombre y el
  -- cartel; y la calle Muñecas, si ya tenía calles y no está (si no tenía
  -- ninguna, el panel le suma todas las de siempre, Muñecas incluida).
  update public.arena_plano p set
    lugares = (
      select coalesce(jsonb_agg(case x.e->>'id'
          when 'Puerta 1' then x.e || '{"id": "Puerta 8", "txt": "P8"}'::jsonb
          when 'Puerta 2' then x.e || '{"id": "Puerta 6", "txt": "P6"}'::jsonb
          when 'Puerta 6' then x.e || '{"id": "Puerta 7", "txt": "P7"}'::jsonb
          when 'Puerta 7' then x.e || '{"id": "Puerta 9", "txt": "P9"}'::jsonb
          else x.e end order by x.n), '[]'::jsonb)
      from jsonb_array_elements(p.lugares) with ordinality x(e, n))
      || case when exists (select 1 from jsonb_array_elements(p.lugares) e where e->>'t' = 'calle')
               and not exists (select 1 from jsonb_array_elements(p.lugares) e where e->>'id' = 'Calle Muñecas')
              then '[{"id": "Calle Muñecas", "t": "calle", "txt": "MUÑECAS", "cx": -10, "cy": 137, "w": 384, "h": 18, "ang": 90}]'::jsonb
              else '[]'::jsonb end,
    updated_at = now(),
    updated_por = 'plano-cartel-arena.sql';
end $$;

-- Para ver cómo quedó: las puertas y calles del plano guardado, y cuántas
-- incidencias cambiaron de nombre.
select (select string_agg(e->>'id', ', ' order by e->>'id')
          from public.arena_plano p, jsonb_array_elements(p.lugares) e
         where e->>'t' in ('puerta', 'calle')) as puertas_y_calles,
       (select count(*) from respaldo.plano_cartel_2026_10 where tabla = 'incidencias') as incidencias_renombradas;
