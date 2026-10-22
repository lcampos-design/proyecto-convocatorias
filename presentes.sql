-- ============================================================
--  PASAR LISTA DESDE LA PLATAFORMA
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no toca lo ya cargado.
--
--  Hasta ahora la asistencia se cargaba subiendo la planilla que se
--  completaba a mano, y era un sí o un no por persona para toda la
--  convocatoria. Un show de varias fechas se paga por jornada, así que
--  "vino" sin decir a cuál no alcanza.
--
--  Esta columna guarda el presente por turno:
--     {"<id del turno>": "presente" | "ausente"}
--  El id del turno es el mismo que ya usa la ronda de disponibilidad, así
--  que las dos cosas hablan de la misma fecha y el mismo horario.
--
--  El campo asistencia que ya existía queda como resumen (presente si vino
--  a alguna fecha, ausente si faltó a todas), porque de ahí salen la
--  penalización por faltar y el aviso de la nómina.
-- ============================================================

alter table public.postulaciones add column if not exists presentes jsonb not null default '{}'::jsonb;

-- Lo que ya estaba cargado no tiene turno: se deja como está. Al pasar lista
-- en el panel se empieza a llenar por fecha, sin pisar nada.

-- Para ver cómo quedó:
--   select count(*) filter (where presentes <> '{}'::jsonb) as con_lista_tomada,
--          count(*) filter (where asistencia is not null)   as con_asistencia_vieja
--   from public.postulaciones;
