-- ============================================================
--  GASTRONOMÍA FUERA DE MOVISTAR ARENA (3): DOS AJUSTES
--  Correr en Supabase → SQL Editor → Run, ANTES de volver a correr
--  gastronomia-arena-texto-libre.sql (la versión nueva).
--  Se puede volver a correr sin problema.
--
--  Revisando la lista que dejó la corrida de los textos libres:
--
--   · "Camarera, cajera encargada de camareras": la tomó como supervisora
--     del Arena por "encargada", pero es encargada de camareras, o sea
--     gastronomía. Va a Externos, con el texto como lo escribió.
--   · "Acomodadores, acreditaciones y/o gastronomía": el "y/o" se partió mal
--     y quedó "Acomodadores, acreditaciones y". Queda sin la "y".
--
--  Las dos cosas ya están corregidas en la regla del otro script, que
--  además ahora cuenta "mesero/a" como gastronomía.
-- ============================================================

-- ── 1) "ENCARGADA DE CAMARERAS": A EXTERNOS, CON SU TEXTO ──
update public.solicitudes s set area = 'externos', puesto_interes = r.puesto_antes
from respaldo.gastronomia_arena_texto r
where r.tabla = 'solicitudes' and s.id::text = r.id
  and r.puesto_antes = 'Camarera, cajera encargada de camareras'
  and s.area = 'movistar_arena' and s.puesto_interes = 'cajera encargada de camareras';

update public.personas p set area = 'externos',
       cv = jsonb_set(p.cv, '{puestoInteres}', to_jsonb(r.puesto_antes)),
       notas = coalesce(r.notas_antes, p.notas)
from respaldo.gastronomia_arena_texto r
where r.tabla = 'personas' and p.id::text = r.id
  and r.puesto_antes = 'Camarera, cajera encargada de camareras'
  and p.area = 'movistar_arena' and p.cv->>'puestoInteres' = 'cajera encargada de camareras';

update respaldo.gastronomia_arena_texto set paso_a = 'externos', puesto_nuevo = puesto_antes
where puesto_antes = 'Camarera, cajera encargada de camareras';

-- ── 2) LA "Y" QUE QUEDÓ COLGANDO ──
update public.solicitudes set puesto_interes = 'Acomodadores, acreditaciones'
where area = 'movistar_arena' and puesto_interes = 'Acomodadores, acreditaciones y';

update public.personas p
set cv = jsonb_set(p.cv, '{puestoInteres}', to_jsonb('Acomodadores, acreditaciones'::text)),
    notas = case when p.notas = 'Interés: Acomodadores, acreditaciones y' then 'Interés: Acomodadores, acreditaciones' else p.notas end
where p.area = 'movistar_arena' and p.cv->>'puestoInteres' = 'Acomodadores, acreditaciones y';

update respaldo.gastronomia_arena_texto set puesto_nuevo = 'Acomodadores, acreditaciones'
where puesto_nuevo = 'Acomodadores, acreditaciones y';

-- ── CÓMO QUEDÓ ──
select 'solicitudes' as tabla, nombre, area, puesto_interes as puesto
from public.solicitudes
where puesto_interes in ('Camarera, cajera encargada de camareras', 'cajera encargada de camareras',
                         'Acomodadores, acreditaciones', 'Acomodadores, acreditaciones y')
union all
select 'personas', nombre, area, cv->>'puestoInteres'
from public.personas
where cv->>'puestoInteres' in ('Camarera, cajera encargada de camareras', 'cajera encargada de camareras',
                               'Acomodadores, acreditaciones', 'Acomodadores, acreditaciones y')
order by 1, 2;
