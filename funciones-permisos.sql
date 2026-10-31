-- ============================================================
--  QUIÉN PUEDE EJECUTAR CADA FUNCIÓN
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  ⚠ ESTE ES EL IMPORTANTE.
--
--  EL PROBLEMA
--  Cuando se crea una función, Postgres le deja ejecutarla a todo el mundo,
--  y eso incluye a quien entra sin usuario. Poner "grant ... to
--  authenticated" al final no se lo saca a nadie: agrega, no quita.
--
--  Entre las funciones que quedaron abiertas está personas_lista(), que
--  devuelve la nómina completa: nombre, CUIL, mail, teléfono, notas,
--  semáforo y la marca de OUT de las más de 2.300 personas. Como la clave
--  pública está a la vista en el código de las páginas, hoy cualquiera
--  puede pedirla.
--
--  LO QUE HACE ESTE ARCHIVO
--  Le saca el permiso a todo el mundo, y después se lo devuelve sólo a
--  quien lo necesita:
--     · las funciones de las páginas públicas (anotarse, darse de baja,
--       ver y firmar el contrato, cargar disponibilidad) siguen abiertas,
--       porque la gente entra ahí sin usuario;
--     · el resto queda para quien está logueado en el panel;
--     · las funciones de trigger no las ejecuta nadie a mano: quedan sin
--       permiso para todos. Los triggers siguen andando igual, porque
--       corren por cuenta de la tabla.
--
--  No toca funciones que vengan de una extensión de Postgres.
-- ============================================================

do $$
declare
  f record;
  -- Las que la gente usa sin estar logueada. Si mañana se agrega una página
  -- pública con una función nueva, va acá.
  publicas text[] := array[
    'check_solicitud_existe',   -- el formulario avisa si ya te inscribiste
    'crear_postulacion',        -- anotarse a un puesto
    'esta_registrado',          -- ¿estás en la nómina?
    'puedo_anotarme',           -- ¿ya estás en ese puesto o en otro? (sólo sí o no)
    'cupos_ocupados',           -- cuántos lugares quedan
    'mis_inscripciones',        -- ver mis inscripciones, con el link del mail (seguridad-inscripciones.sql)
    'baja_con_link',            -- soltar el lugar, con el link del mail
    'mis_datos_ver',            -- /mis-datos, con el link del mail
    'mis_datos_guardar',
    'guardar_disponibilidad',   -- la ronda de fechas
    'mi_disponibilidad',
    'contrato_ver',             -- la página de firma, con el token del link
    'contrato_firmar',
    'contrato_guardar_pdf',
    'registrar_confirmacion',   -- el "CONFIRMO" de los botones del mail (los links viejos, sin firma)
    'registrar_confirmacion_firmada'   -- el mismo, con la firma de la base (seguridad-confirmaciones.sql)
  ];
  -- Las que no ejecuta nadie a mano: las usan otras funciones por dentro o el
  -- servidor. mis_datos_link devuelve el link de /mis-datos: si la pudiera usar
  -- cualquier usuario (un supervisor), sacaría el de cualquier persona.
  -- mis_postulaciones y dar_de_baja: con el CUIL de otro mostraban y bajaban sus
  -- inscripciones; ahora van por mis_inscripciones y baja_con_link.
  nadie text[] := array[
    'mis_datos_link', 'mis_datos_nucleo', 'conf_firma_calc', 'mis_postulaciones', 'dar_de_baja'
  ];
  abiertas int := 0; panel int := 0; cerradas int := 0;
begin
  for f in
    select p.oid::regprocedure as firma,
           p.proname,
           p.prorettype = 'trigger'::regtype as es_trigger
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      -- lo que trajo una extensión no se toca
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute 'revoke execute on function ' || f.firma || ' from public, anon, authenticated';

    if f.es_trigger or f.proname = any (nadie) then
      cerradas := cerradas + 1;
      if f.proname = 'mis_datos_link' then execute 'grant execute on function ' || f.firma || ' to service_role'; end if;
    elsif f.proname = any (publicas) then
      execute 'grant execute on function ' || f.firma || ' to anon, authenticated';
      abiertas := abiertas + 1;
    else
      execute 'grant execute on function ' || f.firma || ' to authenticated';
      panel := panel + 1;
    end if;
  end loop;

  raise notice 'Para las páginas públicas: %   ·   Sólo con usuario: %   ·   De trigger, para nadie: %',
    abiertas, panel, cerradas;
end $$;

-- ── EL search_path QUE FALTABA ──
--  Una función que corre con permisos propios y sin search_path fijo puede
--  terminar llamando a otra cosa con el mismo nombre. Las demás ya lo tienen.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as firma
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'check_solicitud_existe'
  loop
    execute 'alter function ' || f.firma || ' set search_path = public';
  end loop;
end $$;

-- ── CÓMO QUEDÓ ──
--  Lo que puede ejecutar quien entra SIN usuario. Tienen que estar sólo las
--  de la lista de arriba, y NO tiene que aparecer personas_lista.
select p.proname as funcion
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and has_function_privilege('anon', p.oid, 'execute')
order by p.proname;

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--  (devuelve el permiso a todos, como estaba antes)
--   do $$ declare f record; begin
--     for f in select p.oid::regprocedure as firma from pg_proc p
--       join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
--     loop execute 'grant execute on function ' || f.firma || ' to public'; end loop;
--   end $$;
