-- ============================================================
--  INSTAGRAM EN EL REGISTRO DEL CANDIDATO
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no borra nada ni duplica.
--
--  El formulario público ya pide el usuario de Instagram; falta la columna
--  donde guardarlo. Hasta que esta columna exista, el dato se descarta en
--  silencio y el resto de la solicitud se guarda igual.
-- ============================================================

alter table public.solicitudes add column if not exists instagram text;

-- Para poder buscar por usuario sin distinguir mayúsculas.
create index if not exists solicitudes_instagram_idx
  on public.solicitudes (lower(instagram));
