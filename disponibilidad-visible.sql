-- ============================================================
--  QUE LA RONDA DE DISPONIBILIDAD SE VUELVA A VER
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  QUÉ PASÓ
--  Al cerrar los permisos, a quien entra sin usuario le quedó una sola
--  regla para ver convocatorias: las publicadas en la página de
--  inscripción. Pero la página de disponibilidad entra por link a UNA
--  convocatoria, y esa convocatoria puede no estar publicada: la ronda se
--  abre para la gente que ya está en la nómina, no para el público. Con la
--  regla nueva, esa convocatoria no se ve, y la página dice "No
--  encontramos esta convocatoria".
--
--  LA SOLUCIÓN
--  La misma regla, con una condición más: se ve si está publicada O si
--  tiene la ronda de disponibilidad abierta. Nada más se abre: una
--  convocatoria ni publicada ni con ronda abierta sigue sin verse.
-- ============================================================

drop policy if exists public_read_convs on public.convocatorias;
create policy public_read_convs on public.convocatorias
  for select to anon
  using (publicada = true or coalesce(disp_abierta, false) = true);

-- ── CÓMO QUEDÓ ──
--  Las que puede ver quien entra sin usuario, y por qué:
select nombre,
       publicada,
       coalesce(disp_abierta, false) as ronda_abierta,
       case when publicada then 'publicada'
            when coalesce(disp_abierta, false) then 'ronda abierta'
            else '— no se ve —' end as se_ve_porque
from public.convocatorias
order by publicada desc, disp_abierta desc, nombre;
--  La convocatoria de la ronda que no funcionaba tiene que aparecer con
--  "ronda abierta".

-- ── PARA VOLVER ATRÁS ──
--   drop policy if exists public_read_convs on public.convocatorias;
--   create policy public_read_convs on public.convocatorias
--     for select to anon using (publicada = true);
