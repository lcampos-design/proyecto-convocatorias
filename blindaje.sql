-- ============================================================
--  BLINDAJE: QUE DESDE AFUERA NO SE PUEDA VER NI TOCAR NADA
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  Hasta acá fuimos cerrando agujeros de a uno. Esto da vuelta el
--  planteo: se le saca TODO a quien entra sin usuario, y después se le
--  devuelve sólo lo que las páginas públicas usan de verdad. Así, lo que
--  nos olvidemos queda cerrado, no abierto.
--
--  QUÉ NECESITAN LAS PÁGINAS PÚBLICAS, Y NADA MÁS
--    ver  · convocatorias  (la regla ya limita a las publicadas)
--    ver  · puestos        (sólo los de convocatorias publicadas)
--    ver  · config         (sólo los días para darse de baja)
--    crear· solicitudes    (el formulario de inscripción)
--    crear· respuestas     (los mails que llegan a las casillas)
--
--  Todo lo demás que hacen —anotarse, darse de baja, ver y firmar el
--  contrato, cargar disponibilidad, confirmar asistencia— pasa por las
--  funciones de funciones-permisos.sql, que corren por cuenta de la base
--  y no dependen de estos permisos. Por eso se puede cerrar tan fuerte
--  sin romper nada.
--
--  DESPUÉS DE ESTO, SIN USUARIO NO SE PUEDE:
--    · leer la nómina, las solicitudes, los contratos, los feedbacks,
--      las respuestas ni las postulaciones;
--    · modificar ninguna fila de ninguna tabla;
--    · borrar nada, ni vaciar una tabla.
--
--  ⚠ LO QUE ESTO **NO** RESUELVE
--  Cualquiera que tenga usuario del panel —incluidos los supervisores—
--  hoy puede leer y cambiar todo, porque las reglas dicen "a cualquiera
--  logueado". Separar admin de supervisor es el paso siguiente y va
--  aparte: toca la app del supervisor.
-- ============================================================

-- ── 1) SACARLE TODO A QUIEN ENTRA SIN USUARIO ──
revoke all on all tables in schema public from anon;

-- ── 2) DEVOLVERLE SÓLO LO QUE USA ──
grant select on public.convocatorias to anon;   -- la regla limita a las publicadas
grant select on public.puestos      to anon;    -- y acá, a los de esas convocatorias
grant select on public.config       to anon;    -- con la regla de abajo, una sola fila
grant insert on public.solicitudes  to anon;    -- el formulario de inscripción
grant insert on public.respuestas   to anon;    -- los mails entrantes

--  De config, la página sólo necesita cuántos días antes se puede dar de
--  baja. El resto (etiquetas, rotación, lo que venga) no tiene por qué verlo.
drop policy if exists config_publica on public.config;
create policy config_publica on public.config
  for select to anon using (key = 'baja');

-- ── 3) QUE LO QUE SE CREE DE ACÁ EN MÁS NAZCA CERRADO ──
--  Si mañana se agrega una tabla desde el panel de Supabase, hoy nacería
--  abierta para anon. Con esto, no.
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke execute on functions from public, anon;

-- ── CÓMO QUEDÓ ──
--  La foto completa de lo que puede hacer quien entra sin usuario.
--  Tiene que decir exactamente esto, y nada más:
--     config          SELECT
--     convocatorias   SELECT
--     puestos         SELECT
--     respuestas      INSERT
--     solicitudes     INSERT
select table_name as tabla,
       string_agg(privilege_type, ', ' order by privilege_type) as puede
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'anon'
group by table_name
order by table_name;

--  Y que no le quede ningún DELETE ni UPDATE en ningún lado:
select count(*) as deberia_ser_cero
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'anon'
  and privilege_type in ('DELETE', 'UPDATE', 'TRUNCATE');

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--  (no hace falta volver todo: alcanza con agregar el permiso puntual,
--   por ejemplo   grant select on public.LATABLA to anon;  )
--   alter default privileges in schema public grant all on tables to anon;
