-- ============================================================
--  LA DISPONIBILIDAD GENERAL, MARCADA COMO TAL
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  6-nov-2026, Thomas: "necesito que esté claro lo de disponibilidad: saber
--  dónde acudir, para qué, qué dice cada disponibilidad, si es general o de
--  algo en particular, esté abierta o cerrada, poder leerla igual".
--
--  Una convocatoria puede ser una "disponibilidad general": para varias
--  jornadas o eventos a la vez (como "Visita del Santo Padre — Disponibilidad
--  general"), donde la gente marca qué días puede y después se la suma a la
--  convocatoria de cada jornada. Esto agrega esa marca (se pone y se saca en
--  el panel, al editar la convocatoria) y se la pone a las que ya se llaman
--  "Disponibilidad general". Al terminar muestra a cuáles.
-- ============================================================

alter table public.convocatorias add column if not exists disp_general boolean not null default false;

update public.convocatorias
   set disp_general = true
 where not disp_general and nombre ilike '%disponibilidad general%'
returning nombre as marcada_como_general;
