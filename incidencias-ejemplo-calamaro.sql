-- ============================================================
--  INCIDENCIAS DE EJEMPLO EN "CALAMARO — PRUEBA PILOTO" (13-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: primero
--  saca las de ejemplo que haya y las vuelve a cargar (con la hora de ahora).
--
--  Calamaro es un show nuevo: nadie cargó nada, por eso no tiene
--  incidencias. Las que se ven en las presentaciones y en las capturas son
--  de mentira y viven sólo en esas copias, no en la base. Esto carga las
--  mismas en Calamaro (más una "Salida obstruida" en la puerta 6), para ver
--  el tablero, la app y el informe con datos.
--
--  Son de mentira: dicen "Ejemplo (zona)" en quién la cargó. No hay datos
--  del público ni de nadie. Para sacarlas, el paso 3 (está abajo, comentado).
-- ============================================================

-- ── 1) Las de ejemplo que hubiera, afuera ──
delete from public.incidencias i
using public.convocatorias c
where i.conv_id = c.id and c.nombre = 'Calamaro — Prueba piloto'
  and i.creada_por_nombre like 'Ejemplo (%';

-- ── 2) Las de ejemplo, con la hora de ahora (hace tantos minutos) ──
insert into public.incidencias (conv_id, sector, ubicacion, categoria, tipo, nivel, acciones, nota, estado, resolucion,
                                creada_por_nombre, created_at, resuelta_at, resuelta_por_nombre)
select c.id, e.sector, e.ubicacion, e.categoria, e.tipo, e.nivel, e.acciones::jsonb, e.nota, e.estado, e.resolucion,
       'Ejemplo (' || e.zona || ')', now() - make_interval(mins => e.hace),
       case when e.estado = 'resuelta' then now() - make_interval(mins => e.resuelta) end,
       case when e.estado = 'resuelta' then 'Ejemplo (' || e.zona || ')' end
from public.convocatorias c,
(values
  ('Campo delantero',      null,              'Seguridad',       'Pelea o agresión',                  3, '["Se avisó a seguridad", "Se retiró a la persona del sector"]', null,                                'abierta',  null,                    'Bowl',         4,   null),
  ('Sede externo 2 (7UP)', null,              'Seguridad',       'Pelea o agresión',                  3, '["Se avisó a seguridad"]',                                     null,                                'abierta',  null,                    'Anillo',       3,   null),
  ('Platea 313',           null,              'Seguridad',       'Persona agresiva o molesta',        3, '["Se avisó a seguridad"]',                                     null,                                'abierta',  null,                    'Platea alta',  9,   null),
  ('Puerta 6',             null,              'Infraestructura', 'Salida obstruida',                  3, '["Se avisó a mantenimiento"]',                                 'Carros de gastronomía en el paso',  'abierta',  null,                    'Cortatickets', 7,   null),
  ('Sede externo 2 (7UP)', null,              'Médica',          'Lesión o caída',                    2, '["Se llamó a socorrismo"]',                                    null,                                'abierta',  null,                    'Anillo',       6,   null),
  ('Platea 104',           'Fila 12',         'Médica',          'Desmayo / descompensación',         2, '["Se llamó a socorrismo"]',                                    'Se recuperó, queda en observación', 'abierta',  null,                    'Platea baja',  14,  null),
  ('Platea 110',           null,              'Ubicación',       'Entrada duplicada',                 2, '["Se consultó a boletería"]',                                  null,                                'abierta',  null,                    'Platea baja',  26,  null),
  ('Calle Humboldt',       'Fila de ingreso', 'Ingreso',         'Fila de ingreso desbordada',        2, '["Se abrió otra fila o puerta"]',                              null,                                'abierta',  null,                    'Calle',        12,  null),
  ('Puerta 4',             null,              'Seguridad',       'Objeto prohibido',                  1, '["Se retuvo el objeto"]',                                      null,                                'abierta',  null,                    'Cortatickets', 95,  null),
  ('Campo trasero',        null,              'Médica',          'Persona alcoholizada o intoxicada', 2, '["Se trasladó a enfermería"]',                                 null,                                'resuelta', 'A enfermería',          'Bowl',         18,  8),
  ('Platea 309',           null,              'Ubicación',       'Cambio de ubicación',               1, '["Se reubicó a la persona"]',                                  null,                                'resuelta', 'Se reubicó en la 308',  'Platea alta',  40,  33),
  ('Baños 2',              null,              'Infraestructura', 'Baño fuera de servicio',            1, '["Se avisó a mantenimiento"]',                                 null,                                'resuelta', 'Se destapó',            'Anillo',       55,  30),
  ('Platea 104',           null,              'Médica',          'Lesión o caída',                    2, '["Se asistió en el lugar"]',                                   null,                                'resuelta', 'Se asistió',            'Platea baja',  62,  52),
  ('Platea 116',           null,              'Ubicación',       'Ubicación ocupada',                 1, '["Se reubicó a la persona"]',                                  null,                                'resuelta', 'Se reubicó',            'Platea baja',  100, 96)
) as e(sector, ubicacion, categoria, tipo, nivel, acciones, nota, estado, resolucion, zona, hace, resuelta)
where c.nombre = 'Calamaro — Prueba piloto' and c.centro_control;

-- ── CÓMO QUEDÓ ──
--  Tiene que dar 14 de ejemplo: 9 abiertas (4 graves) y 5 resueltas.
select count(*)                                          as de_ejemplo,
       count(*) filter (where i.estado = 'abierta')     as abiertas,
       count(*) filter (where i.estado = 'abierta' and i.nivel = 3) as graves_abiertas,
       count(*) filter (where i.estado = 'resuelta')    as resueltas
from public.incidencias i join public.convocatorias c on c.id = i.conv_id
where c.nombre = 'Calamaro — Prueba piloto' and i.creada_por_nombre like 'Ejemplo (%';

-- ── 3) PARA SACARLAS (cuando ya no hagan falta): sacar los dos guiones de
--  la línea de abajo y correr sólo esa.
-- delete from public.incidencias i using public.convocatorias c where i.conv_id = c.id and c.nombre = 'Calamaro — Prueba piloto' and i.creada_por_nombre like 'Ejemplo (%';
