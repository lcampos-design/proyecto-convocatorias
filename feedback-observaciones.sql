-- ============================================================
--  OBSERVACIONES: FEEDBACK SIN PUNTAJE
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no borra ni cambia nada cargado.
--
--  Una observación es un comentario sobre alguien en un evento, sin los
--  cuatro criterios ni el color (en la planilla de RRHH, el tipo
--  "Observación"). Queda en su historial y en su ficha, pero no cuenta
--  para el semáforo. Para guardarla, el puntaje tiene que poder quedar
--  vacío. El panel ya no la cuenta para el color.
--
--  Hasta que se corra, al importar la planilla de varios eventos se cargan
--  las evaluaciones y el panel avisa que faltan las observaciones.
-- ============================================================

alter table public.feedbacks alter column puntaje drop not null;

-- ── CÓMO QUEDÓ ──
--  is_nullable tiene que decir YES.
select column_name, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'feedbacks' and column_name = 'puntaje';
