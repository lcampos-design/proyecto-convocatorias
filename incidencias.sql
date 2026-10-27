-- ============================================================
--  INCIDENCIAS EN VIVO (Movistar Arena)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Los supervisores reportan desde la tablet lo que pasa durante el show:
--  dónde (sector del plano o lugar), qué (categoría y tipo), qué tan grave
--  (1 leve · 2 moderado · 3 grave), qué se hizo (check-list) y cómo se
--  resolvió. NO se guarda ningún dato del público: ni nombre, ni documento,
--  ni contacto. Sólo la incidencia.
--
--  Igual que con el feedback y la lista, el supervisor no toca la tabla:
--  carga, ve y resuelve por tres funciones que validan que el show esté
--  asignado a él. El panel (admin) la lee y la cambia directo.
--
--  ⚠ PARA CUANDO ENTRE LA GERENCIA DEL ARENA
--  Hoy "admin" es todo el que entra con usuario y no es supervisor
--  (es_admin() en roles.sql). Antes de darle usuario a alguien de la
--  gerencia hay que cambiar esa regla, porque si no entraría al panel
--  completo. Eso va con la etapa 2, junto con su vista de sólo lectura.
-- ============================================================

-- ── 1) LA TABLA ──
create table if not exists public.incidencias (
  id                  uuid primary key default gen_random_uuid(),
  conv_id             uuid not null references public.convocatorias(id) on delete cascade,
  sector              text not null,            -- "Platea 104", "Campo delantero", "Baños"…
  ubicacion           text,                     -- referencia opcional: "fila 12", "puerta 3"
  categoria           text not null,            -- Médica, Seguridad, Ubicación…
  tipo                text not null,            -- Desmayo / descompensación, Cambio de ubicación…
  nivel               smallint not null check (nivel between 1 and 3),
  acciones            jsonb not null default '[]'::jsonb,   -- lo tildado del check-list
  nota                text,
  estado              text not null default 'abierta' check (estado in ('abierta', 'resuelta')),
  resolucion          text,
  creada_por          uuid,
  creada_por_nombre   text,
  created_at          timestamptz not null default now(),   -- la hora la pone el servidor
  resuelta_at         timestamptz,
  resuelta_por_nombre text,
  updated_at          timestamptz not null default now()
);
create index if not exists incidencias_conv_idx on public.incidencias (conv_id, created_at desc);

-- ── 2) QUIÉN LA PUEDE TOCAR ──
--  Sin usuario: nada. Con usuario: sólo el panel (admin). El supervisor,
--  únicamente por las funciones de abajo.
alter table public.incidencias enable row level security;
revoke all on public.incidencias from anon, public;
grant select, insert, update, delete on public.incidencias to authenticated;
drop policy if exists incidencias_admin on public.incidencias;
create policy incidencias_admin on public.incidencias
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ── 3) LAS FUNCIONES DEL SUPERVISOR ──

--  3.a) Las incidencias del show (de todos los supervisores del show, así
--       cada uno ve lo que está abierto en el estadio).
create or replace function public.sup_incidencias(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not exists (select 1 from public.supervisor_convocatorias
                     where supervisor_id = auth.uid() and conv_id = p_conv_id) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(to_jsonb(i) - 'creada_por' order by i.created_at desc)
      from public.incidencias i where i.conv_id = p_conv_id
    ), '[]'::jsonb)
  end;
$$;

--  3.b) Cargar una incidencia.
create or replace function public.sup_incidencia_crear(
  p_conv_id uuid, p_sector text, p_ubicacion text, p_categoria text, p_tipo text,
  p_nivel int, p_acciones jsonb, p_nota text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nombre text; v_acc jsonb := coalesce(p_acciones, '[]'::jsonb); v_fila public.incidencias;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  if not exists (select 1 from public.supervisor_convocatorias
                 where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese show no está asignado a vos');
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
  if length(coalesce(p_ubicacion, '')) > 80 or length(coalesce(p_nota, '')) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'El texto es demasiado largo');
  end if;

  select coalesce(nullif(btrim(up.nombre), ''), u.email) into v_nombre
  from auth.users u left join public.user_profiles up on up.id = u.id
  where u.id = auth.uid();

  insert into public.incidencias (conv_id, sector, ubicacion, categoria, tipo, nivel, acciones, nota,
                                  creada_por, creada_por_nombre)
  values (p_conv_id, btrim(p_sector), nullif(btrim(coalesce(p_ubicacion, '')), ''), btrim(p_categoria), btrim(p_tipo),
          p_nivel, v_acc, nullif(btrim(coalesce(p_nota, '')), ''), auth.uid(), v_nombre)
  returning * into v_fila;

  return jsonb_build_object('ok', true, 'incidencia', to_jsonb(v_fila) - 'creada_por');
end $$;

--  3.c) Resolverla: cómo se resolvió y, si hace falta, lo que se sumó al
--       check-list. Si ya estaba resuelta, la devuelve tal cual.
create or replace function public.sup_incidencia_resolver(p_id uuid, p_acciones jsonb, p_resolucion text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_fila public.incidencias; v_nombre text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  select * into v_fila from public.incidencias where id = p_id;
  if not found or not exists (select 1 from public.supervisor_convocatorias
                              where supervisor_id = auth.uid() and conv_id = v_fila.conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Esa incidencia no es de un show tuyo');
  end if;
  if v_fila.estado = 'resuelta' then
    return jsonb_build_object('ok', true, 'incidencia', to_jsonb(v_fila) - 'creada_por');
  end if;
  if coalesce(btrim(p_resolucion), '') = '' or length(p_resolucion) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'Contá en una línea cómo se resolvió');
  end if;
  if p_acciones is not null and (jsonb_typeof(p_acciones) <> 'array' or jsonb_array_length(p_acciones) > 20
     or exists (select 1 from jsonb_array_elements(p_acciones) a
                where jsonb_typeof(a) <> 'string' or length(a #>> '{}') > 120)) then
    return jsonb_build_object('ok', false, 'error', 'El check-list no es válido');
  end if;

  select coalesce(nullif(btrim(up.nombre), ''), u.email) into v_nombre
  from auth.users u left join public.user_profiles up on up.id = u.id
  where u.id = auth.uid();

  update public.incidencias
     set estado = 'resuelta', resolucion = btrim(p_resolucion),
         acciones = coalesce(p_acciones, acciones),
         resuelta_at = now(), resuelta_por_nombre = v_nombre, updated_at = now()
   where id = p_id
  returning * into v_fila;

  return jsonb_build_object('ok', true, 'incidencia', to_jsonb(v_fila) - 'creada_por');
end $$;

revoke execute on function public.sup_incidencias(uuid)                                       from public, anon;
revoke execute on function public.sup_incidencia_crear(uuid, text, text, text, text, int, jsonb, text) from public, anon;
revoke execute on function public.sup_incidencia_resolver(uuid, jsonb, text)                  from public, anon;
grant  execute on function public.sup_incidencias(uuid)                                       to authenticated;
grant  execute on function public.sup_incidencia_crear(uuid, text, text, text, text, int, jsonb, text) to authenticated;
grant  execute on function public.sup_incidencia_resolver(uuid, jsonb, text)                  to authenticated;

-- ── CÓMO QUEDÓ ──
--  Las tres funciones: con usuario sí, sin usuario no.
select p.proname,
       has_function_privilege('authenticated', p.oid, 'execute') as con_usuario,
       has_function_privilege('anon', p.oid, 'execute')          as sin_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'sup_incidencia%'
order by p.proname;
--  Tiene que dar tres filas: con_usuario true, sin_usuario false.
