-- ============================================================
--  SEGURIDAD: funciones abiertas de más (revisión del 14-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--  No toca ningún dato.
--
--  Postgres deja ejecutar a todo el mundo cada función nueva (también a quien
--  entra sin usuario); funciones-permisos.sql lo corrige, pero las que se
--  crearon o rehicieron después quedaron abiertas. Ninguna es grave (las de
--  supervisores revisan adentro que haya sesión y show asignado; el resto son
--  cálculos), pero no las usa ninguna página pública: quedan sólo para quien
--  entra con usuario (y el servidor).
--  Si alguna la usa una regla de una tabla para todos (también sin usuario),
--  no se toca y lo avisa, para no romper la página pública.
-- ============================================================

do $$
declare f record; n int := 0; saltadas text := '';
begin
  for f in
    select p.oid::regprocedure as firma, p.proname
      from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public'
       and p.proname in ('sup_equipo', 'sup_feedback', 'semaforo_de', 'es_admin', 'es_supervisor',
                         'cbu_valido', 'doc_nucleo', 'zona_nombre', 'color_de_promedio', 'contrato_dias_link')
       and has_function_privilege('anon', p.oid, 'execute')
  loop
    if exists (select 1 from pg_policies pol
                where pol.roles && array['public', 'anon']::name[]
                  and (coalesce(pol.qual, '') ~* ('\m' || f.proname || '\s*\(')
                       or coalesce(pol.with_check, '') ~* ('\m' || f.proname || '\s*\('))) then
      saltadas := saltadas || f.proname || ' ';
      continue;
    end if;
    execute 'revoke execute on function ' || f.firma || ' from public, anon';
    execute 'grant execute on function ' || f.firma || ' to authenticated, service_role';
    n := n + 1;
  end loop;
  raise notice 'Cerradas para quien entra sin usuario: %.%', n,
    case when saltadas <> '' then ' No se tocaron (las usa una regla para todos): ' || saltadas else '' end;
end $$;

-- Cómo quedó: las funciones que se pueden usar sin usuario. Tienen que ser sólo las de las páginas
-- públicas (anotarse, disponibilidad, contrato, confirmación, mis datos con el link).
select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as abierta_sin_usuario
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
 order by 1;
