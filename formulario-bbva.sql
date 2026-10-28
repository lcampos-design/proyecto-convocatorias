-- ============================================================
--  EL FORMULARIO: ESTUDIOS, IDIOMAS, NACIMIENTO Y LA CUENTA BBVA
--  Correr en Supabase → SQL Editor → Run, ANTES de que se suba el
--  formulario nuevo (si no, la inscripción de Argentina no se guarda).
--  Se puede volver a correr sin problema. No toca ningún dato.
--
--  Lo que pidió Mer para Argentina:
--   · Fecha de nacimiento (la columna ya estaba: la usaba España).
--   · Nivel de estudios e idiomas, para poder filtrar después.
--   · "¿Tenés una cuenta bancaria a tu nombre?". Si dice que no, se le
--     abre una en el BBVA, y para eso el banco pide: apellido y nombre como
--     en el DNI, nacionalidad, domicilio y código postal (el resto ya está
--     en el formulario). El panel arma la planilla para el banco.
-- ============================================================

alter table public.solicitudes add column if not exists fecha_nacimiento date;
alter table public.solicitudes add column if not exists estudios       text;
alter table public.solicitudes add column if not exists idiomas        text;
alter table public.solicitudes add column if not exists tiene_cuenta   boolean;   -- null: se inscribió antes de la pregunta
alter table public.solicitudes add column if not exists apellido       text;      -- como en el DNI (para el banco)
alter table public.solicitudes add column if not exists nombres        text;      -- como en el DNI (para el banco)
alter table public.solicitudes add column if not exists nacionalidad   text;
alter table public.solicitudes add column if not exists domicilio      text;
alter table public.solicitudes add column if not exists codigo_postal  text;

-- ── CÓMO QUEDÓ ──
--  Tienen que aparecer las nueve columnas.
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'solicitudes'
  and column_name in ('fecha_nacimiento', 'estudios', 'idiomas', 'tiene_cuenta', 'apellido', 'nombres', 'nacionalidad', 'domicilio', 'codigo_postal')
order by column_name;
