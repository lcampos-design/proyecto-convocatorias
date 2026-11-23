-- ============================================================
--  CALAMARO (23-NOV): DE "PRUEBA PILOTO" A SHOW DE VERDAD
--  Supabase → SQL Editor → pegar todo → Run. Se puede volver a correr.
--
--  "Calamaro — Prueba piloto" es la convocatoria del show de Calamaro del 23/11 (shows-noviembre.sql):
--  se usó para practicar y por eso salía en "Prueba" (con "Hoy") y los informes la dejaban afuera.
--  Thomas (23-nov): "borremos la prueba piloto que ya no sirve más, y dejemos bien el de Calamaro de hoy".
--  La convocatoria no se borra (puede tener los contratos del 23/11); se borra lo de la prueba:
--    · las 14 incidencias de ejemplo y lo que se cargó para practicar antes de hoy (con una sola fecha,
--      todo lo de este show cuenta para el 23/11 y saldría en el informe de esta noche);
--    · las notas y los "quién supervisa" de antes de hoy (si no, las incidencias de esta noche
--      saldrían con el nombre de quien practicó).
--  Y pasa a llamarse "Calamaro", como los demás: sale en "Hoy" y entra en el informe de la 1:30.
-- ============================================================

-- 1) Lo de la prueba.
delete from public.incidencias i
 using public.convocatorias c
 where i.conv_id = c.id
   and c.nombre ilike 'calamaro%' and coalesce(c.fecha, '') like '%2026-11-23%'
   and (i.creada_por_nombre like 'Ejemplo (%' or i.created_at < timestamptz '2026-11-23 06:00:00-03');

delete from public.notas_show n
 using public.convocatorias c
 where n.conv_id = c.id
   and c.nombre ilike 'calamaro%' and coalesce(c.fecha, '') like '%2026-11-23%'
   and n.created_at < timestamptz '2026-11-23 06:00:00-03';

delete from public.supervisor_turnos t
 using public.convocatorias c
 where t.conv_id = c.id
   and c.nombre ilike 'calamaro%' and coalesce(c.fecha, '') like '%2026-11-23%'
   and t.fecha < date '2026-11-23';

-- 2) El nombre de siempre, y en el Centro de Control.
update public.convocatorias
   set nombre = 'Calamaro', centro_control = true
 where nombre ilike 'calamaro%prueba piloto%' and coalesce(fecha, '') like '%2026-11-23%';

-- ── CÓMO QUEDÓ ──
--  Tiene que dar: Calamaro · 2026-11-23 · en el centro true · de ejemplo 0 · pruebas que quedan 0.
--  "incidencias" son las que se cargaron hoy (las de esta noche); "contratos", los del show.
select c.nombre,
       c.fecha,
       c.centro_control as en_el_centro,
       (select count(*) from public.incidencias i where i.conv_id = c.id) as incidencias,
       (select count(*) from public.incidencias i where i.conv_id = c.id and i.creada_por_nombre like 'Ejemplo (%') as de_ejemplo,
       (select count(*) from public.contratos k where k.conv_id = c.id) as contratos,
       (select count(*) from public.convocatorias x where x.nombre ilike '%prueba piloto%') as pruebas_que_quedan
  from public.convocatorias c
 where c.nombre = 'Calamaro' and coalesce(c.fecha, '') like '%2026-11-23%';
