-- ============================================================
--  FOTOS Y ARCHIVOS EN LAS INCIDENCIAS (18-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Thomas (18-nov): "x situación en x lugar y que el supervisor pueda sacar
--  foto y que ya quede guardado; no como algo aparte, sino todo integrado".
--  Eligió: todo en Incidencias (la tarjeta Notas sale de la app) y que las
--  fotos se puedan sumar en cualquier momento (al cargarla, al resolverla o
--  después, desde su ficha).
--
--  Lo que hace:
--   1) La columna incidencias.archivos: [{path, nombre, tipo, peso, por,
--      por_nombre, at}]. "por" es la cuenta que la subió (no sale de la base:
--      la app recibe "mia").
--   2) inc_json: la incidencia como la ven la app y la gerencia (sin el id de
--      quien la cargó ni el de quien subió cada foto). sup_incidencias y
--      ger_incidencias pasan a usarla (lo demás, igual que antes).
--   3) sup_incidencia_fotos: suma fotos ya subidas a una incidencia del show
--      (hasta 10 por incidencia). sup_incidencia_foto_quitar: saca una foto
--      propia.
--   4) El depósito privado "incidencias" en Storage (15 MB por archivo; fotos,
--      PDF, Word y Excel) y quién sube, ve y borra: suben y ven las cuentas
--      del show (y el panel); la gerencia ve; cada uno borra las suyas.
--  Las tablas y las notas que ya había no se tocan.
-- ============================================================

-- ── 1) LA COLUMNA ──
alter table public.incidencias add column if not exists archivos jsonb not null default '[]'::jsonb;

-- ── 2) LA INCIDENCIA PARA MOSTRAR ──
create or replace function public.inc_json(i public.incidencias)
returns jsonb
language sql stable security definer set search_path = public as $$
  select (to_jsonb(i) - 'creada_por') || jsonb_build_object('archivos', coalesce((
    select jsonb_agg((x.a - 'por') || jsonb_build_object('mia', coalesce(x.a ->> 'por', '') = coalesce(auth.uid()::text, '-')) order by x.o)
    from jsonb_array_elements(case when jsonb_typeof(i.archivos) = 'array' then i.archivos else '[]'::jsonb end) with ordinality as x(a, o)
  ), '[]'::jsonb));
$$;

--  Las incidencias del show para la app (como en incidencias.sql, con inc_json).
create or replace function public.sup_incidencias(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not exists (select 1 from public.supervisor_convocatorias
                     where supervisor_id = auth.uid() and conv_id = p_conv_id) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(public.inc_json(i) order by i.created_at desc)
      from public.incidencias i where i.conv_id = p_conv_id
    ), '[]'::jsonb)
  end;
$$;

--  Las de un show sumado, para la gerencia (como en centro-control-shows.sql, con inc_json).
create or replace function public.ger_incidencias(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not (public.es_gerencia() or public.es_admin()) then null
    when not exists (select 1 from public.convocatorias c where c.id = p_conv_id and c.centro_control) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(public.inc_json(i) order by i.created_at desc)
      from public.incidencias i where i.conv_id = p_conv_id
    ), '[]'::jsonb)
  end;
$$;

-- ── 3) SUMAR Y SACAR FOTOS ──
--  La app sube primero cada archivo a <show>/<incidencia>/<nombre> y después
--  lo suma acá. Si la incidencia ya está resuelta, igual se puede.
create or replace function public.sup_incidencia_fotos(p_id uuid, p_archivos jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_fila public.incidencias; v_nombre text; v_nuevos jsonb := '[]'::jsonb; v_a jsonb; v_path text; v_tipo text; v_peso numeric;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  select * into v_fila from public.incidencias where id = p_id;
  if not found or not (public.es_admin() or exists (select 1 from public.supervisor_convocatorias
                                                    where supervisor_id = auth.uid() and conv_id = v_fila.conv_id)) then
    return jsonb_build_object('ok', false, 'error', 'Esa incidencia no es de un show tuyo');
  end if;
  if p_archivos is null or jsonb_typeof(p_archivos) <> 'array' or jsonb_array_length(p_archivos) = 0 then
    return jsonb_build_object('ok', false, 'error', 'No hay fotos para sumar');
  end if;
  if jsonb_array_length(coalesce(v_fila.archivos, '[]'::jsonb)) + jsonb_array_length(p_archivos) > 10 then
    return jsonb_build_object('ok', false, 'error', 'Hasta 10 fotos o archivos por incidencia');
  end if;

  select coalesce(public.supervisor_del_dia(auth.uid(), v_fila.conv_id), nullif(btrim(up.nombre), ''), u.email) into v_nombre
  from auth.users u left join public.user_profiles up on up.id = u.id
  where u.id = auth.uid();

  for v_a in select * from jsonb_array_elements(p_archivos) loop
    v_path := v_a ->> 'path'; v_tipo := lower(coalesce(v_a ->> 'tipo', ''));
    v_peso := case when jsonb_typeof(v_a -> 'peso') = 'number' then (v_a ->> 'peso')::numeric end;
    if jsonb_typeof(v_a) <> 'object'
       or coalesce(v_path, '') !~ ('^' || v_fila.conv_id::text || '/' || v_fila.id::text || '/[A-Za-z0-9._-]{1,120}$')
       or length(coalesce(v_a ->> 'nombre', '')) > 120
       or v_tipo not in ('image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif', 'application/pdf',
                         'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                         'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
       or (v_peso is not null and (v_peso < 0 or v_peso > 15728640)) then
      return jsonb_build_object('ok', false, 'error', 'Una de las fotos no es válida');
    end if;
    if exists (select 1 from jsonb_array_elements(coalesce(v_fila.archivos, '[]'::jsonb) || v_nuevos) x where x ->> 'path' = v_path) then
      return jsonb_build_object('ok', false, 'error', 'Esa foto ya estaba');
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'incidencias' and o.name = v_path) then
      return jsonb_build_object('ok', false, 'error', 'La foto no se terminó de subir. Probá de nuevo.');
    end if;
    v_nuevos := v_nuevos || jsonb_build_array(jsonb_build_object(
      'path', v_path, 'nombre', coalesce(nullif(btrim(v_a ->> 'nombre'), ''), 'Foto'), 'tipo', v_tipo,
      'peso', case when v_peso is null then null else round(v_peso) end,
      'por', auth.uid(), 'por_nombre', v_nombre, 'at', now()));
  end loop;

  update public.incidencias set archivos = coalesce(archivos, '[]'::jsonb) || v_nuevos, updated_at = now()
   where id = p_id
  returning * into v_fila;
  return jsonb_build_object('ok', true, 'incidencia', public.inc_json(v_fila));
end $$;

--  Sacar una foto propia (el panel, cualquiera). La app borra antes el archivo del depósito.
create or replace function public.sup_incidencia_foto_quitar(p_id uuid, p_path text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_fila public.incidencias;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  select * into v_fila from public.incidencias where id = p_id;
  if not found or not exists (select 1 from jsonb_array_elements(coalesce(v_fila.archivos, '[]'::jsonb)) x
                              where x ->> 'path' = p_path and (x ->> 'por' = auth.uid()::text or public.es_admin())) then
    return jsonb_build_object('ok', false, 'error', 'Sólo se saca una foto que subiste vos');
  end if;
  update public.incidencias
     set archivos = coalesce((select jsonb_agg(x.a order by x.o) from jsonb_array_elements(archivos) with ordinality as x(a, o)
                              where x.a ->> 'path' is distinct from p_path), '[]'::jsonb),
         updated_at = now()
   where id = p_id
  returning * into v_fila;
  return jsonb_build_object('ok', true, 'incidencia', public.inc_json(v_fila));
end $$;

-- ── 4) EL DEPÓSITO DE LAS FOTOS (privado) ──
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('incidencias', 'incidencias', false, 15728640, array[
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif', 'application/pdf',
  'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

--  Cada archivo va en <show>/<incidencia>/<nombre>: sube y ve una cuenta del show (y el panel); ve la gerencia
--  (shows del Centro de Control); borra quien lo subió (y el panel).
create or replace function public.inc_archivo_ok(p_name text, p_accion text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_conv uuid; v_id uuid; v_fila public.incidencias;
begin
  if auth.uid() is null or coalesce(p_name, '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$' then
    return false;
  end if;
  v_conv := split_part(p_name, '/', 1)::uuid;
  v_id := split_part(p_name, '/', 2)::uuid;
  select * into v_fila from public.incidencias where id = v_id and conv_id = v_conv;
  if not found then return false; end if;
  if public.es_admin() then return true; end if;
  if p_accion = 'borrar' then
    return exists (select 1 from jsonb_array_elements(coalesce(v_fila.archivos, '[]'::jsonb)) x
                   where x ->> 'path' = p_name and x ->> 'por' = auth.uid()::text);
  end if;
  if exists (select 1 from public.supervisor_convocatorias where supervisor_id = auth.uid() and conv_id = v_conv) then
    return p_accion in ('subir', 'ver');
  end if;
  return p_accion = 'ver' and public.es_gerencia()
     and exists (select 1 from public.convocatorias c where c.id = v_conv and c.centro_control);
end $$;

drop policy if exists incidencias_fotos_subir on storage.objects;
create policy incidencias_fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'incidencias' and public.inc_archivo_ok(name, 'subir'));
drop policy if exists incidencias_fotos_ver on storage.objects;
create policy incidencias_fotos_ver on storage.objects for select to authenticated
  using (bucket_id = 'incidencias' and public.inc_archivo_ok(name, 'ver'));
drop policy if exists incidencias_fotos_borrar on storage.objects;
create policy incidencias_fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'incidencias' and public.inc_archivo_ok(name, 'borrar'));

revoke execute on function public.inc_json(public.incidencias)                 from public, anon, authenticated;
revoke execute on function public.sup_incidencias(uuid)                       from public, anon;
revoke execute on function public.ger_incidencias(uuid)                       from public, anon;
revoke execute on function public.sup_incidencia_fotos(uuid, jsonb)           from public, anon;
revoke execute on function public.sup_incidencia_foto_quitar(uuid, text)      from public, anon;
revoke execute on function public.inc_archivo_ok(text, text)                  from public, anon;
grant  execute on function public.sup_incidencias(uuid)                       to authenticated;
grant  execute on function public.ger_incidencias(uuid)                       to authenticated;
grant  execute on function public.sup_incidencia_fotos(uuid, jsonb)           to authenticated;
grant  execute on function public.sup_incidencia_foto_quitar(uuid, text)      to authenticated;
grant  execute on function public.inc_archivo_ok(text, text)                  to authenticated;

-- ── CÓMO QUEDÓ ──
select (select count(*) from public.incidencias where archivos <> '[]'::jsonb)          as con_fotos,
       (select b.public from storage.buckets b where b.id = 'incidencias')               as deposito_publico,
       (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
                                           and policyname like 'incidencias_fotos_%')    as permisos_fotos,
       has_function_privilege('anon', 'public.sup_incidencia_fotos(uuid, jsonb)', 'execute') as sin_usuario;
--  Tiene que dar: con_fotos 0, deposito_publico false, permisos_fotos 3 y sin_usuario false.
