-- ============================================================
--  LAS FICHAS TÉCNICAS DEL ARENA EN CADA SHOW (24-nov-2026)
--  Supabase → SQL Editor → pegar todo → Run. Se puede volver a correr.
--
--  El Arena carga una ficha por show en su app de fichas; el Arena dio el OK para leerlas en automático. Una vez
--  por día (y cuando se abre el panel) cada show del Arena se pone al día con su ficha: el armado del campo (si
--  nadie lo cambió a mano), los horarios que falten y un resumen de la ficha (horarios, orientadores que pide,
--  cargas, acta, capacidad, accesos y notas, prohibidos, menores, alcohol, emergencias; nunca los responsables).
--  Si de una fecha no hay show del Arena, se crea en el Centro de Control (sin publicar). Ver api/_lib/fichas.js.
--
--  Lo nuevo: convocatorias.ficha (el resumen). La última vuelta queda en config (key 'fichas_sync').
-- ============================================================

alter table public.convocatorias add column if not exists ficha jsonb;

-- ── CÓMO QUEDÓ ── tiene que dar true.
select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'convocatorias' and column_name = 'ficha') as ficha_en_cada_show;
