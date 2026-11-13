-- ============================================================
--  LOS SHOWS DE NOVIEMBRE EN EL CENTRO DE CONTROL (13-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: no
--  duplica (si un show ya está, con el mismo nombre y su primera fecha, lo
--  saltea).
--
--  Los shows del Arena del 13 al 30 de noviembre todavía no estaban en el
--  panel. Esto crea una convocatoria por show, con sus fechas:
--   · Ya sumada al Centro de Control: la gerencia y el panel la ven, y las
--     cuentas de zona la reciben solas (lo hace el disparador de
--     cuentas-zona.sql).
--   · Sin publicar y sin ronda de disponibilidad: no aparece en Postulate
--     ni en la disponibilidad, y no tiene puestos ni postulaciones.
--   · Cada fecha es un show aparte en la lista, con su tablero y su informe
--     (María Becerra son 8 fechas en una convocatoria).
--
--  Calamaro (23-nov) va como "Calamaro — Prueba piloto" (pedido de Thomas):
--  con ese nombre se ve en el panel, la gerencia, la app y el informe.
--
--  Para sacar uno: en el panel, Centro de Control → el show → "Sacar del
--  Centro de Control"; o borrar la convocatoria desde Convocatorias.
-- ============================================================

-- ── Si ya se había corrido la primera versión: Calamaro pasa al nombre nuevo ──
update public.convocatorias
   set nombre = 'Calamaro — Prueba piloto'
 where nombre = 'Calamaro' and fecha = '2026-11-23'
   and descripcion like 'Show del Arena para el Centro de Control%';

with shows(nombre, fechas) as (values
  ('María Becerra',                array['2026-11-13','2026-11-14','2026-11-15','2026-11-17','2026-11-18','2026-11-19','2026-11-26','2026-11-27']),
  ('Las Pastillas del Abuelo',     array['2026-11-20','2026-11-21']),
  ('Serú Girán por Lebón y Aznar', array['2026-11-22']),
  ('Calamaro — Prueba piloto',     array['2026-11-23']),
  ('ZZ Top',                       array['2026-11-24']),
  ('Ulises Bueno',                 array['2026-11-25']),
  ('Paulo Londra',                 array['2026-11-28']),
  ('Power Up Orchestra',           array['2026-11-29']),
  ('Omar Courtz',                  array['2026-11-30'])
)
insert into public.convocatorias (id, nombre, fecha, area, venue, descripcion, turnos, publicada, disp_abierta, centro_control)
select gen_random_uuid(), s.nombre, array_to_string(s.fechas, ','), 'movistar_arena', 'Movistar Arena',
       'Show del Arena para el Centro de Control (prueba piloto AX). Sin puestos ni postulaciones.',
       (select jsonb_agg(jsonb_build_object('id', gen_random_uuid()::text, 'fecha', f, 'horario', '') order by f) from unnest(s.fechas) f),
       false, false, true
from shows s
where not exists (
  select 1 from public.convocatorias c
  where lower(c.nombre) = lower(s.nombre) and coalesce(c.fecha, '') like '%' || s.fechas[1] || '%'
);

-- ── Para ver cómo quedó ──
--  Los shows del Centro de Control con alguna fecha de hoy en adelante, y
--  cuántas cuentas de zona tienen cada uno (tienen que ser las 7).
select c.nombre,
       replace(c.fecha, ',', ' · ') as fechas,
       c.publicada,
       (select count(*) from public.supervisor_convocatorias sc
          join public.user_profiles up on up.id = sc.supervisor_id
         where sc.conv_id = c.id and up.zona is not null) as cuentas_de_zona
from public.convocatorias c
where c.centro_control
  and exists (select 1 from unnest(string_to_array(c.fecha, ',')) f where trim(f) >= '2026-11-13')
order by (select min(trim(f)) from unnest(string_to_array(c.fecha, ',')) f where trim(f) >= '2026-11-13');
