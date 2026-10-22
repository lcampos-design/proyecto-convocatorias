-- ============================================================
--  REGLAS DE ACCESO SIN USUARIO
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  "anon" es cualquiera que abra una página del sistema sin estar logueado:
--  quien entra a postularse, y también cualquiera que tenga la dirección.
--  La clave pública está a la vista en el código de la página, así que lo
--  que anon puede leer, lo puede leer cualquiera.
--
--  Hoy hay cuatro reglas abiertas de más. Tres se pueden sacar sin tocar
--  nada, porque ninguna página las usa: están duplicando permisos que ya
--  existen bien acotados. La cuarta (leer postulaciones) necesita cambiar
--  antes tres consultas de postulate.html, y no se toca acá.
-- ============================================================

-- ── 1) CONVOCATORIAS ──
--  Había dos reglas: una deja ver sólo las publicadas, la otra deja ver
--  todas. Como se aplican con "o", la abierta anulaba a la otra: se veían
--  también las que no están publicadas y las archivadas.
--  postulate.html pide .eq('publicada', true), así que con la acotada alcanza.
drop policy if exists anon_read_convocatorias on public.convocatorias;

-- ── 2) PUESTOS ──
--  Lo mismo: public_read_puestos ya limita a los puestos de convocatorias
--  publicadas, y es la que necesita la página.
drop policy if exists anon_read_puestos on public.puestos;

-- ── 3) CREAR POSTULACIONES ──
--  Esta regla deja que cualquiera inserte una postulación en cualquier
--  puesto, con el estado que quiera: se podría anotar como "aprobado" en
--  una convocatoria sin pasar por nadie.
--  La página no la usa: se postula por la función crear_postulacion, que
--  valida los datos y corre con permisos propios.
drop policy if exists anon_insert on public.postulaciones;
revoke insert on public.postulaciones from anon;

-- ── CÓMO QUEDÓ ──
--  Esto tendría que devolver sólo las reglas acotadas: public_read_convs
--  (publicada = true), public_read_puestos (el EXISTS), public_submit de
--  solicitudes, y anon_select de postulaciones, que es la que falta cambiar.
select tablename, policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public' and roles && array['anon', 'public']::name[]
order by tablename, policyname;

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--   create policy anon_read_convocatorias on public.convocatorias for select to anon using (true);
--   create policy anon_read_puestos      on public.puestos        for select to anon using (true);
--   grant insert on public.postulaciones to anon;
--   create policy anon_insert on public.postulaciones for insert to anon with check (true);
