-- ============================================================
--  DETALLES Y CARGAS TARDE EN LAS INCIDENCIAS (18-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--  Va después de incidencias-fotos.sql.
--
--  Lupi (SBS, 18-nov): "en la app después de haberse enviado el reporte, ¿se
--  puede seguir editándolo? Para agregar detalles. La super de VIP quiere
--  agregar más cosas y no la deja". Thomas eligió las dos cosas:
--   · Agregar detalle: en cualquier incidencia, en cualquier momento (durante
--     o después del show), un texto que se suma con su nombre y su hora, sin
--     borrar lo que ya estaba (las fotos ya se suman con incidencias-fotos.sql).
--   · Cargar una que faltó: en un show que ya terminó, una incidencia que no se
--     cargó, con la hora en que pasó. Entra en la fecha de ese show, ya
--     resuelta (lo abierto se cierra con el reporte) y marcada como cargada
--     después (cargada_at); no cuenta para la resolución media.
--
--  Lo que hace:
--   1) Las columnas incidencias.detalles ([{texto, por, por_nombre, at}]) y
--      incidencias.cargada_at (cuándo se cargó, si fue después del show).
--   2) inc_json: también saca "por" de cada detalle (pone "mia").
--   3) sup_incidencia_detalle(id, texto) y sup_incidencia_crear_tarde(…).
--  No cambia ninguna incidencia que ya esté.
-- ============================================================

-- ── 1) LAS COLUMNAS ──
alter table public.incidencias add column if not exists detalles jsonb not null default '[]'::jsonb;
alter table public.incidencias add column if not exists cargada_at timestamptz;

-- ── 2) LA INCIDENCIA PARA MOSTRAR (sin ids de cuentas) ──
create or replace function public.inc_json(i public.incidencias)
returns jsonb
language sql stable security definer set search_path = public as $$
  select (to_jsonb(i) - 'creada_por') || jsonb_build_object(
    'archivos', coalesce((
      select jsonb_agg((x.a - 'por') || jsonb_build_object('mia', coalesce(x.a ->> 'por', '') = coalesce(auth.uid()::text, '-')) order by x.o)
      from jsonb_array_elements(case when jsonb_typeof(i.archivos) = 'array' then i.archivos else '[]'::jsonb end) with ordinality as x(a, o)
    ), '[]'::jsonb),
    'detalles', coalesce((
      select jsonb_agg((x.a - 'por') || jsonb_build_object('mia', coalesce(x.a ->> 'por', '') = coalesce(auth.uid()::text, '-')) order by x.o)
      from jsonb_array_elements(case when jsonb_typeof(i.detalles) = 'array' then i.detalles else '[]'::jsonb end) with ordinality as x(a, o)
    ), '[]'::jsonb));
$$;

-- ── 3) AGREGAR UN DETALLE ──
--  Cualquier cuenta del show (y el panel), en cualquier momento. Hasta 30 por incidencia.
create or replace function public.sup_incidencia_detalle(p_id uuid, p_texto text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_fila public.incidencias; v_nombre text; v_txt text := btrim(coalesce(p_texto, ''));
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  select * into v_fila from public.incidencias where id = p_id;
  if not found or not (public.es_admin() or exists (select 1 from public.supervisor_convocatorias
                                                    where supervisor_id = auth.uid() and conv_id = v_fila.conv_id)) then
    return jsonb_build_object('ok', false, 'error', 'Esa incidencia no es de un show tuyo');
  end if;
  if v_txt = '' then
    return jsonb_build_object('ok', false, 'error', 'Escribí el detalle');
  end if;
  if length(v_txt) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'El detalle es demasiado largo (hasta 1000 letras)');
  end if;
  if jsonb_array_length(coalesce(v_fila.detalles, '[]'::jsonb)) >= 30 then
    return jsonb_build_object('ok', false, 'error', 'Esta incidencia ya tiene muchos detalles');
  end if;

  select coalesce(public.supervisor_del_dia(auth.uid(), v_fila.conv_id), nullif(btrim(up.nombre), ''), u.email) into v_nombre
  from auth.users u left join public.user_profiles up on up.id = u.id
  where u.id = auth.uid();

  update public.incidencias
     set detalles = coalesce(detalles, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'texto', v_txt, 'por', auth.uid(), 'por_nombre', v_nombre, 'at', now())),
         updated_at = now()
   where id = p_id
  returning * into v_fila;
  return jsonb_build_object('ok', true, 'incidencia', public.inc_json(v_fila));
end $$;

-- ── 4) CARGAR UNA QUE FALTÓ (show terminado) ──
--  p_fecha: la fecha del show; p_ocurrio: cuándo pasó (de las 6 de la mañana de esa fecha a las 6 del día
--  siguiente, y no después de ahora). Lo demás, como sup_incidencia_crear. Entra resuelta, con cómo terminó
--  (si no lo dicen, "Cargada después del show") y sin hora de cierre.
create or replace function public.sup_incidencia_crear_tarde(
  p_conv_id uuid, p_fecha date, p_ocurrio timestamptz, p_sector text, p_ubicacion text, p_categoria text, p_tipo text,
  p_nivel int, p_acciones jsonb, p_nota text, p_resolucion text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nombre text; v_acc jsonb := coalesce(p_acciones, '[]'::jsonb); v_fila public.incidencias; v_fechas text;
        v_desde timestamptz; v_hoy date := ((now() at time zone 'America/Argentina/Buenos_Aires') - interval '6 hours')::date;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  if not exists (select 1 from public.supervisor_convocatorias
                 where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese show no está asignado a vos');
  end if;
  select c.fecha into v_fechas from public.convocatorias c where c.id = p_conv_id;
  if p_fecha is null or not (p_fecha::text = any (string_to_array(regexp_replace(coalesce(v_fechas, ''), '\s', '', 'g'), ','))) then
    return jsonb_build_object('ok', false, 'error', 'Esa fecha no es del show');
  end if;
  if p_fecha > v_hoy then
    return jsonb_build_object('ok', false, 'error', 'Ese show todavía no fue');
  end if;
  v_desde := (p_fecha::timestamp + time '06:00') at time zone 'America/Argentina/Buenos_Aires';
  if p_ocurrio is null or p_ocurrio < v_desde or p_ocurrio >= v_desde + interval '1 day' or p_ocurrio > now() then
    return jsonb_build_object('ok', false, 'error', 'La hora no es de ese show');
  end if;
  if coalesce(btrim(p_sector), '') = '' or length(p_sector) > 60 then
    return jsonb_build_object('ok', false, 'error', 'Falta el sector');
  end if;
  if coalesce(btrim(p_categoria), '') = '' or length(p_categoria) > 40
     or coalesce(btrim(p_tipo), '') = '' or length(p_tipo) > 80 then
    return jsonb_build_object('ok', false, 'error', 'Falta qué pasó');
  end if;
  if p_nivel is null or p_nivel not between 1 and 3 then
    return jsonb_build_object('ok', false, 'error', 'El nivel va de 1 (leve) a 3 (grave)');
  end if;
  if jsonb_typeof(v_acc) <> 'array' or jsonb_array_length(v_acc) > 20
     or exists (select 1 from jsonb_array_elements(v_acc) a
                where jsonb_typeof(a) <> 'string' or length(a #>> '{}') > 120) then
    return jsonb_build_object('ok', false, 'error', 'El check-list no es válido');
  end if;
  if length(coalesce(p_ubicacion, '')) > 80 or length(coalesce(p_nota, '')) > 1000 or length(coalesce(p_resolucion, '')) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'El texto es demasiado largo');
  end if;

  select coalesce(public.supervisor_del_dia(auth.uid(), p_conv_id), nullif(btrim(up.nombre), ''), u.email) into v_nombre
  from auth.users u left join public.user_profiles up on up.id = u.id
  where u.id = auth.uid();

  insert into public.incidencias (conv_id, sector, ubicacion, categoria, tipo, nivel, acciones, nota,
                                  creada_por, creada_por_nombre, created_at, cargada_at,
                                  estado, resolucion, resuelta_at, resuelta_por_nombre, updated_at)
  values (p_conv_id, btrim(p_sector), nullif(btrim(coalesce(p_ubicacion, '')), ''), btrim(p_categoria), btrim(p_tipo),
          p_nivel, v_acc, nullif(btrim(coalesce(p_nota, '')), ''), auth.uid(), v_nombre, p_ocurrio, now(),
          'resuelta', coalesce(nullif(btrim(coalesce(p_resolucion, '')), ''), 'Cargada después del show'), null, v_nombre, now())
  returning * into v_fila;

  return jsonb_build_object('ok', true, 'incidencia', public.inc_json(v_fila));
end $$;

revoke execute on function public.inc_json(public.incidencias)                                                   from public, anon, authenticated;
revoke execute on function public.sup_incidencia_detalle(uuid, text)                                            from public, anon;
revoke execute on function public.sup_incidencia_crear_tarde(uuid, date, timestamptz, text, text, text, text, int, jsonb, text, text) from public, anon;
grant  execute on function public.sup_incidencia_detalle(uuid, text)                                            to authenticated;
grant  execute on function public.sup_incidencia_crear_tarde(uuid, date, timestamptz, text, text, text, text, int, jsonb, text, text) to authenticated;

-- ── CÓMO QUEDÓ ──
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'incidencias'
                                                          and column_name in ('detalles', 'cargada_at'))     as columnas_nuevas,
       (select count(*) from public.incidencias where cargada_at is not null)                                as cargadas_tarde,
       has_function_privilege('anon', 'public.sup_incidencia_detalle(uuid, text)', 'execute')                as sin_usuario_detalle,
       has_function_privilege('anon', 'public.sup_incidencia_crear_tarde(uuid, date, timestamptz, text, text, text, text, int, jsonb, text, text)', 'execute') as sin_usuario_tarde;
--  Tiene que dar: columnas_nuevas 2, cargadas_tarde 0, sin_usuario_detalle false y sin_usuario_tarde false.
