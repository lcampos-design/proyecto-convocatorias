-- ============================================================
--  LOS CONTRATOS YA NO SON PILOTO
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  6-nov-2026, Thomas: "a partir de ahora vamos a mandar los contratos,
--  ya no es más piloto". El panel ya arranca las convocatorias nuevas con
--  los contratos prendidos; esto los prende en las que ya están cargadas y
--  todavía no pasaron (alguna fecha de hoy en adelante, o sin fecha).
--  Las que ya pasaron no se tocan.
--
--  Al terminar muestra a cuáles se los prendió (si no muestra ninguna,
--  es que ya estaban todas).
-- ============================================================

update public.convocatorias c
   set contratos_habilitados = true
 where coalesce(c.contratos_habilitados, false) = false
   and (coalesce(btrim(c.fecha), '') = ''
        or exists (select 1 from unnest(string_to_array(c.fecha, ',')) f
                   where btrim(f) >= to_char((now() at time zone 'America/Argentina/Buenos_Aires')::date, 'YYYY-MM-DD')))
returning c.nombre as convocatoria, c.fecha as fechas;
