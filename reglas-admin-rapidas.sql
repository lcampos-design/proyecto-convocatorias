-- ============================================================
--  LAS REGLAS DE "SÓLO ADMIN", UNA VEZ POR PEDIDO Y NO FILA POR FILA (26-nov)
-- ============================================================
--  El panel mostraba 0 postulantes: con 11.000 inscripciones, la regla "sólo admin" de la tabla preguntaba si quien pide
--  es admin una vez por cada fila (es_admin() mira user_profiles dos veces). Contarlas tardaba casi 3 segundos con el
--  permiso del panel, el panel pide 12 tandas a la vez y la base corta cada pedido a los 8 segundos: se cortaban todas.
--  Escrita como (select es_admin()), la base lo pregunta una sola vez por pedido. El resultado es el mismo (depende sólo
--  de quién entró), así que nadie ve más ni menos que antes. Se cambian sólo las reglas que son exactamente
--  "es_admin()", en todas las tablas. Se puede correr más de una vez.
-- ============================================================
do $$
declare p record; v_n int := 0; v_re text := '^\(?\s*(public\.)?es_admin\(\)\s*\)?$';
begin
  for p in select schemaname, tablename, policyname, qual, with_check from pg_policies
            where schemaname = 'public' and (coalesce(qual, '') ~ v_re or coalesce(with_check, '') ~ v_re)
  loop
    if coalesce(p.qual, '') ~ v_re and coalesce(p.with_check, '') ~ v_re then
      execute format('alter policy %I on %I.%I using ((select public.es_admin())) with check ((select public.es_admin()))', p.policyname, p.schemaname, p.tablename);
    elsif coalesce(p.qual, '') ~ v_re then
      execute format('alter policy %I on %I.%I using ((select public.es_admin()))', p.policyname, p.schemaname, p.tablename);
    else
      execute format('alter policy %I on %I.%I with check ((select public.es_admin()))', p.policyname, p.schemaname, p.tablename);
    end if;
    v_n := v_n + 1;
  end loop;
  perform set_config('diag.reglas', v_n::text, false);
end $$;

-- Y la prueba: lo mismo que pide el panel, con el permiso de un usuario del panel (sólo lee; sin datos de nadie).
do $$
declare
  v_uid uuid := (select up.id from public.user_profiles up where coalesce(up.rol, '') like 'admin%' order by up.id limit 1);
  r text; t0 timestamptz; n bigint;
begin
  r := 'Reglas cambiadas: ' || current_setting('diag.reglas', true)
    || ' ### Quedan fila por fila: ' || (select count(*) from pg_policies where schemaname = 'public' and (coalesce(qual, '') ~ '^\(?\s*(public\.)?es_admin\(\)\s*\)?$' or coalesce(with_check, '') ~ '^\(?\s*(public\.)?es_admin\(\)\s*\)?$'));
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
  t0 := clock_timestamp();
  begin
    select count(*) into n from public.solicitudes;
    r := r || ' ### Postulantes que ve el panel: ' || n || ' (' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms)';
  exception when others then r := r || ' ### ERROR ' || sqlstate || ': ' || sqlerrm; end;
  t0 := clock_timestamp();
  begin
    select count(*) into n from (select id, nombre, area, email, tel, localidad, cuit, puesto_interes, estado, conv_id, puesto_id, puesto_nombre, created_at,
        antecedentes, beneficio_social, fecha_nacimiento, estudios, idiomas, alimentacion, cv_nombre
      from public.solicitudes order by created_at desc, id limit 1000 offset 0) x;
    r := r || ' ### Primera tanda del panel: ' || n || ' filas (' || round(extract(epoch from clock_timestamp() - t0) * 1000) || ' ms)';
  exception when others then r := r || ' ### ERROR ' || sqlstate || ': ' || sqlerrm; end;
  perform set_config('diag.postulantes', r, false);
end $$;
select regexp_split_to_table(current_setting('diag.postulantes', true), ' ### ') as resultado;
