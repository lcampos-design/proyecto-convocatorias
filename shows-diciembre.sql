-- ============================================================
--  LOS SHOWS DE DICIEMBRE EN EL CENTRO DE CONTROL (24-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: no
--  duplica (si un show ya está, con el mismo nombre y su primera fecha, lo
--  saltea).
--
--  La lista del Arena que pasó Thomas (del 1 al 23 de diciembre), como los de
--  noviembre (shows-noviembre.sql): una convocatoria por show, con sus fechas,
--   · ya sumada al Centro de Control: la gerencia y el panel la ven, y las
--     cuentas de zona la reciben solas (el disparador de cuentas-zona.sql);
--   · sin publicar y sin ronda de disponibilidad, sin puestos ni postulaciones;
--   · cada fecha es un show aparte, con su tablero y su informe.
--  Omar Courtz ya está (30 de noviembre): a esa misma convocatoria se le suman
--  el 2, el 3 y el 4 de diciembre (si no la encuentra, la crea con esas fechas).
--  El armado del campo sale de la ficha técnica de cada show.
-- ============================================================

-- ── Omar Courtz: las fechas de diciembre, en la convocatoria del 30 de noviembre ──
update public.convocatorias c
   set fecha = (select string_agg(f, ',' order by f) from (select distinct trim(x) f from unnest(string_to_array(c.fecha, ',') || array['2026-12-02','2026-12-03','2026-12-04']) x where trim(x) <> '') d),
       turnos = coalesce(c.turnos, '[]'::jsonb) || coalesce((
         select jsonb_agg(jsonb_build_object('id', gen_random_uuid()::text, 'fecha', f, 'horario', '') order by f)
           from unnest(array['2026-12-02','2026-12-03','2026-12-04']) f
          where not exists (select 1 from jsonb_array_elements(coalesce(c.turnos, '[]'::jsonb)) t where t ->> 'fecha' = f)), '[]'::jsonb)
 where lower(c.nombre) = 'omar courtz' and c.area = 'movistar_arena' and coalesce(c.fecha, '') like '%2026-11-30%';

with shows(nombre, fechas) as (values
  ('Babymetal',             array['2026-12-01']),
  ('Omar Courtz',           array['2026-12-02','2026-12-03','2026-12-04']),
  ('Rata Blanca',           array['2026-12-05']),
  ('Diego Torres',          array['2026-12-06']),
  ('Desakta2',              array['2026-12-07']),
  ('Ángela Torres',         array['2026-12-08','2026-12-09']),
  ('Deep Purple',           array['2026-12-10']),
  ('Gabriel Rolón',         array['2026-12-11']),
  ('Alejo Igoa',            array['2026-12-12','2026-12-13']),
  ('Slayer',                array['2026-12-14']),
  ('K4OS',                  array['2026-12-15','2026-12-16']),
  ('BOM - Lali y Miranda',  array['2026-12-17','2026-12-18','2026-12-19']),
  ('Disney Celebra',        array['2026-12-21','2026-12-22','2026-12-23'])
)
insert into public.convocatorias (id, nombre, fecha, area, venue, descripcion, turnos, publicada, disp_abierta, centro_control)
select gen_random_uuid(), s.nombre, array_to_string(s.fechas, ','), 'movistar_arena', 'Movistar Arena',
       'Show del Arena para el Centro de Control. Sin puestos ni postulaciones.',
       (select jsonb_agg(jsonb_build_object('id', gen_random_uuid()::text, 'fecha', f, 'horario', '') order by f) from unnest(s.fechas) f),
       false, false, true
from shows s
where not exists (
  select 1 from public.convocatorias c
  where lower(c.nombre) = lower(s.nombre) and coalesce(c.fecha, '') like '%' || s.fechas[1] || '%'
);

-- ── Para ver cómo quedó ──
--  Los shows del Centro de Control con alguna fecha en diciembre, y cuántas
--  cuentas de zona tiene cada uno (tienen que ser las 7).
select c.nombre,
       replace(c.fecha, ',', ' · ') as fechas,
       c.publicada,
       (select count(*) from public.supervisor_convocatorias sc
          join public.user_profiles up on up.id = sc.supervisor_id
         where sc.conv_id = c.id and up.zona is not null) as cuentas_de_zona
from public.convocatorias c
where c.centro_control
  and exists (select 1 from unnest(string_to_array(c.fecha, ',')) f where trim(f) like '2026-12-%')
order by (select min(trim(f)) from unnest(string_to_array(c.fecha, ',')) f where trim(f) like '2026-12-%');
