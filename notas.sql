-- ============================================================
--  NOTAS DE LOS SUPERVISORES, CON FOTOS Y ARCHIVOS (17-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Pedido de Lupi (SBS), hablando con Connie (Premium Services del Arena):
--  "una parte de notas para que los supervisores puedan escribir la situación
--  que haya sucedido y además agregar archivos (imágenes, etc.)", "así dejan
--  de hacer el reporte en el Drive". Thomas eligió (17-nov):
--   · notas sueltas del show (qué pasó, con fotos o archivos), aparte de las
--     incidencias;
--   · en todas las cuentas de la app: cada zona escribe y ve las suyas;
--     Coordinador y Corporativo ven todas;
--   · van en el informe al Arena: el texto en el informe y en el PDF; las
--     fotos, en el link del informe.
--  Cada fecha es un show: cada nota es de la fecha de su función.
--
--  Lo que hace:
--   1) La tabla notas_show (la app no la toca directo: va por las funciones).
--   2) Quién ve cada nota.
--   3) Las funciones de la app (ver, guardar y borrar las suyas mientras el
--      show no terminó) y la de la gerencia y el panel (todas).
--   4) Dónde van los archivos: un depósito privado ("notas") en Storage. Se
--      ven sólo con un link que vence. Hasta 15 MB cada uno: fotos, PDF,
--      Word y Excel.
--  No toca ningún dato que ya exista.
-- ============================================================

-- ── 1) LA TABLA ──
create table if not exists public.notas_show (
  id           uuid primary key default gen_random_uuid(),
  conv_id      uuid not null references public.convocatorias(id) on delete cascade,
  fecha        date not null,                         -- la de la función (cada fecha es un show)
  cuenta       uuid,                                  -- la cuenta que la escribió
  zona         text,                                  -- la zona de esa cuenta (null: la de una persona)
  autor_nombre text,                                  -- "Ana López (VIP)"
  texto        text not null default '',
  archivos     jsonb not null default '[]'::jsonb,    -- [{ path, nombre, tipo, peso }]
  created_at   timestamptz not null default now()     -- la hora la pone el servidor
);
create index if not exists notas_show_conv on public.notas_show (conv_id, fecha, created_at);
alter table public.notas_show enable row level security;
revoke all on public.notas_show from anon, public;
grant select, insert, update, delete on public.notas_show to authenticated;
drop policy if exists notas_show_admin on public.notas_show;
create policy notas_show_admin on public.notas_show
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ── 2) QUIÉN VE CADA NOTA ──
--  La cuenta que la escribió (la de su zona), Coordinador y Corporativo (todas las del
--  show, si lo tienen asignado), y la gerencia y el panel.
create or replace function public.nota_visible(p_conv uuid, p_cuenta uuid, p_zona text)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and (
    public.es_admin() or public.es_gerencia()
    or (exists (select 1 from public.supervisor_convocatorias sc where sc.supervisor_id = auth.uid() and sc.conv_id = p_conv)
        and (p_cuenta = auth.uid()
             or exists (select 1 from public.user_profiles up where up.id = auth.uid()
                         and (up.zona in ('coordinador', 'corporativo') or (up.zona is not null and up.zona = p_zona))))));
$$;

--  El día de la función de hoy: la madrugada (antes de las 6) es de la noche anterior.
create or replace function public.notas_hoy_funcion()
returns date language sql stable as $$
  select ((now() at time zone 'America/Argentina/Buenos_Aires') - interval '6 hours')::date;
$$;

-- ── 3) LAS FUNCIONES ──
--  3.a) Las notas de una fecha del show que ve esta cuenta (la más nueva primero), con "mia".
create or replace function public.sup_notas(p_conv_id uuid, p_fecha date)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg((to_jsonb(n) - 'cuenta') || jsonb_build_object('mia', n.cuenta = auth.uid()) order by n.created_at desc), '[]'::jsonb)
  from public.notas_show n
  where n.conv_id = p_conv_id and (p_fecha is null or n.fecha = p_fecha)
    and exists (select 1 from public.supervisor_convocatorias sc where sc.supervisor_id = auth.uid() and sc.conv_id = p_conv_id)
    and public.nota_visible(n.conv_id, n.cuenta, n.zona);
$$;

--  3.b) Guardar una nota. Los archivos ya se subieron (a <show>/<id de la nota>/…): acá va la lista.
create or replace function public.sup_nota_crear(p_id uuid, p_conv_id uuid, p_fecha date, p_texto text, p_archivos jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_zona text; v_nombre text; v_fechas text; v_fila public.notas_show;
  v_txt  text  := btrim(coalesce(p_texto, ''));
  v_arch jsonb := coalesce(p_archivos, '[]'::jsonb);
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión'); end if;
  if p_id is null then return jsonb_build_object('ok', false, 'error', 'Falta el número de la nota'); end if;
  if not exists (select 1 from public.supervisor_convocatorias where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese show no está asignado a vos');
  end if;
  select c.fecha into v_fechas from public.convocatorias c where c.id = p_conv_id and c.centro_control;
  if not found then return jsonb_build_object('ok', false, 'error', 'Ese show no está en el Centro de Control'); end if;
  if p_fecha is null or not (p_fecha::text = any (string_to_array(regexp_replace(coalesce(v_fechas, ''), '\s', '', 'g'), ','))) then
    return jsonb_build_object('ok', false, 'error', 'Esa fecha no es del show');
  end if;
  if p_fecha < public.notas_hoy_funcion() then
    return jsonb_build_object('ok', false, 'error', 'Este show ya terminó: no se cargan notas');
  end if;
  if length(v_txt) > 4000 then return jsonb_build_object('ok', false, 'error', 'La nota es demasiado larga (hasta 4000 letras)'); end if;
  if jsonb_typeof(v_arch) <> 'array' or jsonb_array_length(v_arch) > 10 or exists (
       select 1 from jsonb_array_elements(v_arch) a
        where jsonb_typeof(a) <> 'object'
           or coalesce(a->>'path', '') not like p_conv_id::text || '/' || p_id::text || '/%'
           or length(a->>'path') > 300 or length(coalesce(a->>'nombre', '')) > 140 or length(coalesce(a->>'tipo', '')) > 100) then
    return jsonb_build_object('ok', false, 'error', 'Los archivos no son válidos (hasta 10 por nota)');
  end if;
  if v_txt = '' and jsonb_array_length(v_arch) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Escribí qué pasó o agregá un archivo');
  end if;
  if exists (select 1 from public.notas_show where id = p_id) then
    return jsonb_build_object('ok', false, 'error', 'Esa nota ya estaba guardada');
  end if;

  select zona into v_zona from public.user_profiles where id = auth.uid();
  -- "Ana López (VIP)": quien está hoy en la zona; si la cuenta es de una persona, su nombre.
  v_nombre := public.supervisor_del_dia(auth.uid(), p_conv_id);
  if v_nombre is null then
    select coalesce(nullif(btrim(up.nombre), ''), u.email) into v_nombre
      from auth.users u left join public.user_profiles up on up.id = u.id where u.id = auth.uid();
  end if;

  insert into public.notas_show (id, conv_id, fecha, cuenta, zona, autor_nombre, texto, archivos)
  values (p_id, p_conv_id, p_fecha, auth.uid(), v_zona, v_nombre, v_txt,
          (select coalesce(jsonb_agg(jsonb_build_object(
                    'path', a->>'path', 'nombre', left(coalesce(a->>'nombre', ''), 140), 'tipo', left(coalesce(a->>'tipo', ''), 100),
                    'peso', case when jsonb_typeof(a->'peso') = 'number' then round((a->>'peso')::numeric)::bigint end) order by x.k), '[]'::jsonb)
             from jsonb_array_elements(v_arch) with ordinality x(a, k)))
  returning * into v_fila;
  return jsonb_build_object('ok', true, 'nota', (to_jsonb(v_fila) - 'cuenta') || jsonb_build_object('mia', true));
end $$;

--  3.c) Borrar una nota suya, mientras el show no terminó (después queda en el informe).
--       Los archivos los borra la app antes (con la nota todavía guardada).
create or replace function public.sup_nota_borrar(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.notas_show;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión'); end if;
  select * into v from public.notas_show where id = p_id;
  if not found then return jsonb_build_object('ok', true); end if;
  if v.cuenta is distinct from auth.uid() then return jsonb_build_object('ok', false, 'error', 'Sólo se borra una nota tuya'); end if;
  if v.fecha < public.notas_hoy_funcion() then return jsonb_build_object('ok', false, 'error', 'Este show ya terminó: la nota queda en el informe'); end if;
  delete from public.notas_show where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

--  3.d) La gerencia y el panel (Centro de Control): todas las notas del show (de todas sus fechas).
create or replace function public.ger_notas(p_conv_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case
    when not (public.es_gerencia() or public.es_admin()) then null
    when not exists (select 1 from public.convocatorias c where c.id = p_conv_id and c.centro_control) then '[]'::jsonb
    else coalesce((select jsonb_agg(to_jsonb(n) - 'cuenta' order by n.created_at desc)
                     from public.notas_show n where n.conv_id = p_conv_id), '[]'::jsonb)
  end;
$$;

-- ── 4) LOS ARCHIVOS: un depósito privado en Storage ──
--  Cada archivo va en <show>/<nota>/<nombre>. Se sube antes de guardar la nota (lo sube quien
--  tiene el show asignado); se ve con el mismo permiso que la nota; lo borra quien la escribió.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('notas', 'notas', false, 15728640, array[
  'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif', 'application/pdf',
  'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.nota_archivo_ok(p_name text, p_accion text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_conv uuid; v_nota uuid; n public.notas_show; v_asignado boolean;
begin
  if auth.uid() is null or coalesce(p_name, '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$' then
    return false;
  end if;
  v_conv := split_part(p_name, '/', 1)::uuid;
  v_nota := split_part(p_name, '/', 2)::uuid;
  v_asignado := exists (select 1 from public.supervisor_convocatorias where supervisor_id = auth.uid() and conv_id = v_conv);
  select * into n from public.notas_show where id = v_nota and conv_id = v_conv;
  if p_accion = 'subir' then
    -- A una nota ya guardada no se le suman archivos.
    return not found and (v_asignado or public.es_admin());
  end if;
  -- Lo que quedó subido de una nota que no se llegó a guardar (se cortó la conexión) no lo ve nadie.
  if not found then return false; end if;
  if p_accion = 'borrar' then return n.cuenta = auth.uid() and n.fecha >= public.notas_hoy_funcion(); end if;
  return public.nota_visible(n.conv_id, n.cuenta, n.zona);
end $$;

drop policy if exists notas_show_subir on storage.objects;
create policy notas_show_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'notas' and public.nota_archivo_ok(name, 'subir'));
drop policy if exists notas_show_ver on storage.objects;
create policy notas_show_ver on storage.objects for select to authenticated
  using (bucket_id = 'notas' and public.nota_archivo_ok(name, 'ver'));
drop policy if exists notas_show_borrar on storage.objects;
create policy notas_show_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'notas' and public.nota_archivo_ok(name, 'borrar'));

revoke execute on function public.nota_visible(uuid, uuid, text)                     from public, anon;
revoke execute on function public.notas_hoy_funcion()                                from public, anon;
revoke execute on function public.sup_notas(uuid, date)                              from public, anon;
revoke execute on function public.sup_nota_crear(uuid, uuid, date, text, jsonb)      from public, anon;
revoke execute on function public.sup_nota_borrar(uuid)                              from public, anon;
revoke execute on function public.ger_notas(uuid)                                    from public, anon;
revoke execute on function public.nota_archivo_ok(text, text)                        from public, anon;
grant  execute on function public.nota_visible(uuid, uuid, text)                     to authenticated;
grant  execute on function public.notas_hoy_funcion()                                to authenticated;
grant  execute on function public.sup_notas(uuid, date)                              to authenticated;
grant  execute on function public.sup_nota_crear(uuid, uuid, date, text, jsonb)      to authenticated;
grant  execute on function public.sup_nota_borrar(uuid)                              to authenticated;
grant  execute on function public.ger_notas(uuid)                                    to authenticated;
grant  execute on function public.nota_archivo_ok(text, text)                        to authenticated;

-- ── CÓMO QUEDÓ ──
select (select count(*) from public.notas_show)                                        as notas,
       (select b.public from storage.buckets b where b.id = 'notas')                    as deposito_publico,
       (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
                                           and policyname like 'notas_show_%')          as permisos_archivos,
       has_function_privilege('anon', 'public.sup_notas(uuid, date)', 'execute')        as sin_usuario;
--  Tiene que dar: notas 0, deposito_publico false, permisos_archivos 3 y sin_usuario false.
