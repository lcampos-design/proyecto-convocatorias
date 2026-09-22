-- Archivar convocatorias terminadas: se guardan con todos sus datos, no se borran.
-- Correr en Supabase -> SQL Editor.
alter table public.convocatorias add column if not exists archivada boolean default false;
