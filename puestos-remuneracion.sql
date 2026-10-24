-- ============================================================
--  REMUNERACIÓN POR PUESTO
--
--  En un show se convocan 60 orientadores, 7 supervisores y 1 coordinador,
--  y no cobran lo mismo. Hasta ahora la remuneración era una sola por
--  convocatoria. Cada puesto puede tener la suya; si no la tiene, se usa la
--  de la convocatoria. El envío masivo de contratos la toma de acá, así no
--  hay que escribir el monto a mano.
--
--  Correr en Supabase -> SQL Editor.
-- ============================================================

alter table public.puestos add column if not exists remuneracion text;

-- ── Comprobación: tiene que listar la columna ──
select column_name, data_type from information_schema.columns
 where table_schema = 'public' and table_name = 'puestos' and column_name = 'remuneracion';
