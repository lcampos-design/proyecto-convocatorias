-- ============================================================
--  PLANO DEL ARENA: respuestas de Luca (coordinador), 17-nov-2026
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: los
--  cambios se hacen una sola vez (la segunda vez avisa que ya estaba).
--
--   · Concesiones de planta baja: Paty, Pepsi, Kit Kat y 7UP son internas y
--     no llevan número ("se reconocen por el nombre"):
--       Cancha externo 1 (Paty)  → Cancha interno (Paty)
--       Cancha externo 2 (Pepsi) → Cancha interno (Pepsi)
--       Sede externo 1 (Kit Kat) → Sede interno (Kit Kat)
--       Sede externo 2 (7UP)     → Sede interno (7UP)
--   · Molinetes de Dorrego (lado Cancha, a la altura de Camarines) y de
--     Corrientes (lado Sede, a la altura de Acreditaciones), donde los marcó.
--
--  Cambia las incidencias ya cargadas y, si el plano guardado tiene esos
--  puestos, también el plano (sin cambiarle la fecha de guardado: de ella
--  depende que la página le sume los molinetes y las salidas del fondo).
--  Antes guarda una copia en el esquema respaldo. No toca datos de nadie.
-- ============================================================

create schema if not exists respaldo;

do $$
declare n_inc int := 0; n_plano int := 0;
begin
  if to_regclass('respaldo.plano_luca_2026_11_17') is not null then
    raise notice 'Ya estaba hecho: no se cambió nada.';
    return;
  end if;

  -- La copia: el plano guardado y las incidencias que cambian de nombre.
  create table respaldo.plano_luca_2026_11_17 as
    select 'arena_plano'::text as tabla, p.id::text as fila_id, to_jsonb(p) as antes from public.arena_plano p
    union all
    select 'incidencias', i.id::text, to_jsonb(i) from public.incidencias i
     where i.sector in ('Cancha externo 1 (Paty)', 'Cancha externo 2 (Pepsi)', 'Sede externo 1 (Kit Kat)', 'Sede externo 2 (7UP)');
  revoke all on respaldo.plano_luca_2026_11_17 from public, anon, authenticated;

  -- Las incidencias ya cargadas, con el nombre nuevo de su concesión.
  update public.incidencias i set sector = m.nuevo
    from (values ('Cancha externo 1 (Paty)', 'Cancha interno (Paty)'), ('Cancha externo 2 (Pepsi)', 'Cancha interno (Pepsi)'),
                 ('Sede externo 1 (Kit Kat)', 'Sede interno (Kit Kat)'), ('Sede externo 2 (7UP)', 'Sede interno (7UP)')) m(viejo, nuevo)
   where i.sector = m.viejo;
  get diagnostics n_inc = row_count;

  -- El plano guardado, sólo si tiene alguno de esos puestos (si no, los pone la página, ya con lo nuevo).
  update public.arena_plano p set
    lugares = (
      select jsonb_agg(case when m.viejo is null then x.e else x.e || m.cambio end order by x.n)
        from jsonb_array_elements(p.lugares) with ordinality x(e, n)
        left join (values
          ('Cancha externo 1 (Paty)',   '{"id": "Cancha interno (Paty)", "txt": "Paty"}'::jsonb),
          ('Cancha externo 2 (Pepsi)',  '{"id": "Cancha interno (Pepsi)", "txt": "Pep."}'::jsonb),
          ('Sede externo 1 (Kit Kat)',  '{"id": "Sede interno (Kit Kat)", "txt": "Kit."}'::jsonb),
          ('Sede externo 2 (7UP)',      '{"id": "Sede interno (7UP)", "txt": "7UP"}'::jsonb),
          ('Molinetes Dorrego',         '{"cx": 6, "cy": 14, "ang": 90}'::jsonb),
          ('Molinetes Dorrego Premium', '{"cx": 6, "cy": 48, "ang": 90}'::jsonb),
          ('Molinetes Corrientes',      '{"cx": 414, "cy": 36, "ang": 90}'::jsonb)
        ) m(viejo, cambio) on m.viejo = x.e->>'id'),
    updated_por = 'plano-luca-17nov.sql'
   where exists (select 1 from jsonb_array_elements(p.lugares) e
                  where e->>'id' in ('Cancha externo 1 (Paty)', 'Cancha externo 2 (Pepsi)', 'Sede externo 1 (Kit Kat)', 'Sede externo 2 (7UP)',
                                     'Molinetes Dorrego', 'Molinetes Dorrego Premium', 'Molinetes Corrientes'));
  get diagnostics n_plano = row_count;
  raise notice 'Incidencias con el nombre nuevo: %. Plano guardado: %.', n_inc,
    case when n_plano > 0 then 'actualizado' else 'no tenía esos puestos (los pone la página, ya con lo nuevo)' end;
end $$;

-- Cómo quedó.
select 'Incidencias renombradas' as que, (select count(*) from respaldo.plano_luca_2026_11_17 where tabla = 'incidencias')::text as resultado
union all
select 'Plano guardado', case when exists (select 1 from public.arena_plano where updated_por = 'plano-luca-17nov.sql') then 'actualizado'
                              else 'sin cambios (los pone la página)' end
union all
select 'Con el nombre viejo (tiene que dar 0)', (select count(*) from public.incidencias
  where sector in ('Cancha externo 1 (Paty)', 'Cancha externo 2 (Pepsi)', 'Sede externo 1 (Kit Kat)', 'Sede externo 2 (7UP)'))::text
union all
select 'Cargadas en "Recepción" o "Premium Points" (genéricos)', (select count(*) from public.incidencias where sector in ('Recepción', 'Premium Points'))::text;
