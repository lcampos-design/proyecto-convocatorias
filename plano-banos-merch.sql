-- ============================================================
--  PLANO DEL ARENA: baños, baños accesibles, merch store y Acreditaciones
--  (respuestas del coordinador, 14-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: los
--  cambios se hacen una sola vez (la segunda vez avisa que ya estaba).
--
--   · Baños con su nombre: planta baja 1 → Hombres Cancha, 2 → Mujeres Cancha,
--     3 → Mujeres Sede, 4 → Hombres Sede; platea baja Cancha 1/2 y Sede 1/2 →
--     Hombres/Mujeres de cada lado.
--   · "Producción" pasa a "Acreditaciones" (así se lo reconoce).
--   · Se suman el merch store (donde está la enfermería, del lado Sede) y los
--     baños accesibles: 4 en planta baja (al lado de la enfermería, de
--     Patagonia, de Smirnoff y del merch store), 4 en platea baja (uno de cada
--     lado de los baños, en los dos costados) y 2 en platea alta.
--
--  Cambia el plano guardado y las incidencias ya cargadas, a la vez, así cada
--  una sigue en su lugar real. Antes guarda una copia en el esquema respaldo.
--  No toca datos de nadie: sólo nombres y posiciones de lugares.
--
--  OJO (14-nov, ya corrido): la parte del plano guardado estuvo mal (el guardado
--  sólo tenía los baños de ejemplo de la primera versión, que la página
--  reemplaza por los de siempre) y se deshizo con plano-banos-arreglo.sql. Lo
--  de las incidencias quedó bien. No volver a correr.
-- ============================================================

create schema if not exists respaldo;

do $$
declare n_inc int := 0; n_plano int := 0;
begin
  if to_regclass('respaldo.plano_banos_2026_11_14') is not null then
    raise notice 'Ya estaba hecho: no se cambió nada.';
    return;
  end if;

  -- La copia: el plano guardado y las incidencias que cambian de nombre.
  create table respaldo.plano_banos_2026_11_14 as
    select 'arena_plano'::text as tabla, p.id::text as fila_id, to_jsonb(p) as antes from public.arena_plano p
    union all
    select 'incidencias', i.id::text, to_jsonb(i) from public.incidencias i
     where i.sector in ('Baños 1', 'Baños 2', 'Baños 3', 'Baños 4', 'Baños Cancha 1 (P1)', 'Baños Cancha 2 (P1)',
                        'Baños Sede 1 (P1)', 'Baños Sede 2 (P1)', 'Producción');
  revoke all on respaldo.plano_banos_2026_11_14 from public, anon, authenticated;

  -- Las incidencias ya cargadas, con el nombre nuevo de su lugar.
  update public.incidencias i set sector = m.nuevo
    from (values ('Baños 1', 'Baños Hombres Cancha'), ('Baños 2', 'Baños Mujeres Cancha'),
                 ('Baños 3', 'Baños Mujeres Sede'), ('Baños 4', 'Baños Hombres Sede'),
                 ('Baños Cancha 1 (P1)', 'Baños Hombres Cancha (P1)'), ('Baños Cancha 2 (P1)', 'Baños Mujeres Cancha (P1)'),
                 ('Baños Sede 1 (P1)', 'Baños Hombres Sede (P1)'), ('Baños Sede 2 (P1)', 'Baños Mujeres Sede (P1)'),
                 ('Producción', 'Acreditaciones')) m(viejo, nuevo)
   where i.sector = m.viejo;
  get diagnostics n_inc = row_count;

  -- El plano guardado (si hay): los nombres nuevos (con la posición que tenían) y los lugares que se suman.
  update public.arena_plano p set
    lugares = (
      select coalesce(jsonb_agg(case when m.viejo is null then x.e else x.e || jsonb_build_object('id', m.nuevo, 'txt', m.txt) end order by x.n), '[]'::jsonb)
        from jsonb_array_elements(p.lugares) with ordinality x(e, n)
        left join (values ('Baños 1', 'Baños Hombres Cancha', 'H'), ('Baños 2', 'Baños Mujeres Cancha', 'M'),
                          ('Baños 3', 'Baños Mujeres Sede', 'M'), ('Baños 4', 'Baños Hombres Sede', 'H'),
                          ('Baños Cancha 1 (P1)', 'Baños Hombres Cancha (P1)', 'H'), ('Baños Cancha 2 (P1)', 'Baños Mujeres Cancha (P1)', 'M'),
                          ('Baños Sede 1 (P1)', 'Baños Hombres Sede (P1)', 'H'), ('Baños Sede 2 (P1)', 'Baños Mujeres Sede (P1)', 'M'),
                          ('Producción', 'Acreditaciones', 'Acred.')) m(viejo, nuevo, txt) on m.viejo = x.e->>'id'
    ) || (
      select coalesce(jsonb_agg(nv.l order by nv.k), '[]'::jsonb)
        from (values
          (1,  '{"id": "Merch store", "t": "servicio", "txt": "Merch", "cx": 391.5, "cy": 40, "w": 11, "h": 15, "ang": 0, "piso": "PB"}'::jsonb),
          (2,  '{"id": "Baño accesible Enfermería", "t": "banio", "txt": "Acc", "cx": 43.5, "cy": 42, "w": 11, "h": 12, "ang": 0, "piso": "PB"}'::jsonb),
          (3,  '{"id": "Baño accesible Patagonia", "t": "banio", "txt": "Acc", "cx": 43.5, "cy": 196, "w": 11, "h": 12, "ang": 0, "piso": "PB"}'::jsonb),
          (4,  '{"id": "Baño accesible Smirnoff", "t": "banio", "txt": "Acc", "cx": 376.5, "cy": 196, "w": 11, "h": 12, "ang": 0, "piso": "PB"}'::jsonb),
          (5,  '{"id": "Baño accesible Merch store", "t": "banio", "txt": "Acc", "cx": 376.5, "cy": 42, "w": 11, "h": 12, "ang": 0, "piso": "PB"}'::jsonb),
          (6,  '{"id": "Baño accesible Cancha 1 (P1)", "t": "banio", "txt": "Acc", "cx": 43.5, "cy": 89, "w": 11, "h": 12, "ang": 0, "piso": "P1"}'::jsonb),
          (7,  '{"id": "Baño accesible Cancha 2 (P1)", "t": "banio", "txt": "Acc", "cx": 43.5, "cy": 151, "w": 11, "h": 12, "ang": 0, "piso": "P1"}'::jsonb),
          (8,  '{"id": "Baño accesible Sede 1 (P1)", "t": "banio", "txt": "Acc", "cx": 376.5, "cy": 89, "w": 11, "h": 12, "ang": 0, "piso": "P1"}'::jsonb),
          (9,  '{"id": "Baño accesible Sede 2 (P1)", "t": "banio", "txt": "Acc", "cx": 376.5, "cy": 151, "w": 11, "h": 12, "ang": 0, "piso": "P1"}'::jsonb),
          (10, '{"id": "Baño accesible Cancha (P3)", "t": "banio", "txt": "Acc", "cx": 36, "cy": 14, "w": 22, "h": 10, "ang": 0, "piso": "P3"}'::jsonb),
          (11, '{"id": "Baño accesible Sede (P3)", "t": "banio", "txt": "Acc", "cx": 384, "cy": 14, "w": 22, "h": 10, "ang": 0, "piso": "P3"}'::jsonb)
        ) nv(k, l)
       where not exists (select 1 from jsonb_array_elements(p.lugares) e where lower(e->>'id') = lower(nv.l->>'id'))
    ),
    updated_at = now(),
    updated_por = 'plano-banos-merch.sql';
  get diagnostics n_plano = row_count;
  raise notice 'Incidencias con el nombre nuevo: %. Plano guardado actualizado: %.', n_inc, case when n_plano > 0 then 'sí' else 'no había plano guardado (queda el de siempre, ya con los cambios)' end;
end $$;

-- Cómo quedó: los baños y los puntos de servicio del plano guardado, por piso, y las incidencias que cambiaron.
select coalesce(e->>'piso', 'PB') as piso, e->>'t' as tipo, string_agg(e->>'id', ' · ' order by (e->>'cy')::numeric, e->>'id') as lugares
  from public.arena_plano p, jsonb_array_elements(p.lugares) e
 where e->>'t' in ('banio', 'servicio', 'enfermeria')
 group by 1, 2
union all
select 'Incidencias', 'renombradas', (select count(*) from respaldo.plano_banos_2026_11_14 where tabla = 'incidencias')::text
 order by 1, 2;
