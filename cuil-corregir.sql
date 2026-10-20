-- ============================================================
--  CORREGIR DOS CUIL MAL CARGADOS
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  Al cruzar la planilla del semáforo contra la nómina aparecieron cinco
--  personas con el mismo nombre y distinto documento. El CUIL tiene dígito
--  verificador, así que no hubo que adivinar: se calculó cuál de los dos
--  puede existir.
--
--   · Maia Altamira      → el del panel está bien, el de la planilla no
--   · Yanel De Nicola    → el del panel está bien, el de la planilla no
--   · Guillermina Sánchez→ no es un error: la planilla trae sólo el DNI
--   · Agustina Araya     → EL DEL PANEL ESTÁ MAL (empieza con 22, no existe)
--   · Casandra García    → EL DEL PANEL ESTÁ MAL (no pasa el verificador)
--
--  Esto corrige los dos últimos. Los otros tres no se tocan.
-- ============================================================

update public.personas
set cuit = '27470715222'
where regexp_replace(coalesce(cuit, ''), '\D', '', 'g') = '22470715222';

update public.personas
set cuit = '20963786175'
where regexp_replace(coalesce(cuit, ''), '\D', '', 'g') = '20963756175';

-- Para confirmar que quedaron bien:
--   select nombre, cuit from public.personas
--   where cuit in ('27470715222', '20963786175');
