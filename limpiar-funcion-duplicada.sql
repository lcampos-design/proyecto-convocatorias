-- ============================================================
--  check_solicitud_existe ESTÁ DOS VECES
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  Hay dos versiones de la función con el mismo nombre y distintos
--  parámetros. El formulario la llama siempre con (p_cuit, p_nombre), así
--  que esa es la que se usa; la otra quedó de una versión anterior y no la
--  llama nadie. Dos funciones con el mismo nombre no rompen nada, pero
--  cada vez que se revisan los permisos aparecen las dos y hay que
--  acordarse cuál es cuál.
--
--  Esto primero muestra las dos, y después borra sólo la que NO tiene esos
--  dos parámetros. Si por alguna razón no hay exactamente una con
--  (p_cuit, p_nombre), no borra nada y avisa.
-- ============================================================

-- ── 1) LAS QUE HAY ──
select p.proname as funcion,
       pg_get_function_identity_arguments(p.oid) as parametros
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'check_solicitud_existe'
order by 2;

-- ── 2) BORRAR LA QUE SOBRA ──
do $$
declare
  f record;
  buenas int;
  borradas int := 0;
begin
  select count(*) into buenas
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'check_solicitud_existe'
    and pg_get_function_identity_arguments(p.oid) = 'p_cuit text, p_nombre text';

  if buenas <> 1 then
    raise notice 'No se borró nada: hay % función(es) con (p_cuit text, p_nombre text), y tendría que haber exactamente una.', buenas;
    return;
  end if;

  for f in
    select p.oid::regprocedure as firma
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'check_solicitud_existe'
      and pg_get_function_identity_arguments(p.oid) <> 'p_cuit text, p_nombre text'
  loop
    execute 'drop function ' || f.firma;
    borradas := borradas + 1;
    raise notice 'Borrada: %', f.firma;
  end loop;

  raise notice 'Listo: % función(es) de más borrada(s). Queda la de (p_cuit, p_nombre).', borradas;
end $$;

-- ── CÓMO QUEDÓ ──
--  Tiene que devolver una sola fila, con "p_cuit text, p_nombre text".
select p.proname as funcion,
       pg_get_function_identity_arguments(p.oid) as parametros,
       has_function_privilege('anon', p.oid, 'execute') as la_usa_el_formulario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'check_solicitud_existe';

-- ── PARA VOLVER ATRÁS ──
--  No hace falta: la que se borra no la llama nadie. Si igual se quisiera
--  recuperar, está en el historial de Supabase (Database → Functions).
