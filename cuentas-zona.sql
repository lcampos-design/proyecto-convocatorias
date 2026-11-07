-- ============================================================
--  UNA CUENTA POR ZONA PARA LOS SUPERVISORES
--  Correr en Supabase → SQL Editor → Run, ANTES de crear las cuentas en
--  el panel. Se puede volver a correr sin problema. No toca ningún dato.
--
--  Lo que pidió Thomas (6-nov-2026): en vez de una cuenta por supervisor,
--  una por zona —Calle, Cortatickets, Anillo, Bowl, Platea baja, Platea
--  alta y VIP—, con su usuario y su contraseña. El supervisor de ese día
--  entra con la de su zona y, antes de empezar, pone su nombre y su
--  apellido (una vez por show; si cambia la persona, "No soy yo").
--
--  Lo que hace esto:
--   · La zona de cada cuenta (una cuenta por zona).
--   · Quién estuvo a cargo de cada zona en cada show (supervisor_turnos):
--     lo ven la gerencia y el panel.
--   · En cada incidencia que carga o resuelve una cuenta de zona, el nombre
--     del supervisor de ese día ("Ana López (Platea baja)"), en vez del de
--     la cuenta.
--   · Las cuentas de zona ven solas todos los shows del Centro de Control:
--     no hay que asignarlas a mano.
-- ============================================================

-- ── 1) LA ZONA DE CADA CUENTA ──
alter table public.user_profiles add column if not exists zona text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'user_profiles_zona_valida' and conrelid = 'public.user_profiles'::regclass) then
    alter table public.user_profiles add constraint user_profiles_zona_valida
      check (zona is null or zona in ('calle', 'cortatickets', 'anillo', 'bowl', 'platea_baja', 'platea_alta', 'vip'));
  end if;
end $$;
create unique index if not exists user_profiles_una_por_zona on public.user_profiles (zona) where zona is not null;

create or replace function public.zona_nombre(p text)
returns text language sql immutable as $$
  select case p when 'calle' then 'Calle' when 'cortatickets' then 'Cortatickets' when 'anillo' then 'Anillo'
                when 'bowl' then 'Bowl' when 'platea_baja' then 'Platea baja' when 'platea_alta' then 'Platea alta'
                when 'vip' then 'VIP' end;
$$;

-- ── 2) QUIÉN ESTUVO EN CADA ZONA, EN CADA SHOW ──
--  Una fila cada vez que alguien empieza (o "No soy yo" y entra otro).
--  Nadie la toca directo: la llena sup_turno y la leen ger_supervisores y el panel.
create table if not exists public.supervisor_turnos (
  id         uuid primary key default gen_random_uuid(),
  conv_id    uuid not null references public.convocatorias(id) on delete cascade,
  fecha      date not null,                    -- el día en que entró (en Buenos Aires)
  zona       text not null,
  nombre     text not null,
  apellido   text not null,
  cuenta     uuid,                             -- la cuenta de la zona con la que entró
  created_at timestamptz not null default now()
);
create index if not exists supervisor_turnos_conv on public.supervisor_turnos (conv_id, created_at desc);
alter table public.supervisor_turnos enable row level security;
revoke all on public.supervisor_turnos from anon;
drop policy if exists supervisor_turnos_ver on public.supervisor_turnos;
create policy supervisor_turnos_ver on public.supervisor_turnos for select to authenticated using (true);
drop policy if exists solo_admin on public.supervisor_turnos;
create policy solo_admin on public.supervisor_turnos as restrictive to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ── 3) LA APP DEL SUPERVISOR ──
--  De qué zona es la cuenta (null si es la de una persona, como hasta ahora).
create or replace function public.sup_mi_zona()
returns text language sql stable security definer set search_path = public as $$
  select zona from public.user_profiles where id = auth.uid();
$$;

--  Empezar: el nombre y el apellido de quien supervisa la zona en este show.
create or replace function public.sup_turno(p_conv_id uuid, p_nombre text, p_apellido text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_zona text;
  v_nom  text := initcap(btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g')));
  v_ape  text := initcap(btrim(regexp_replace(coalesce(p_apellido, ''), '\s+', ' ', 'g')));
  v_hoy  date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión'); end if;
  select zona into v_zona from public.user_profiles where id = auth.uid();
  if v_zona is null then return jsonb_build_object('ok', false, 'error', 'Esta cuenta no es la de una zona'); end if;
  if not exists (select 1 from public.supervisor_convocatorias where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese show no está en el Centro de Control');
  end if;
  if length(v_nom) < 2 or length(v_ape) < 2 or length(v_nom) > 40 or length(v_ape) > 40 or (v_nom || v_ape) ~ '[0-9@<>]' then
    return jsonb_build_object('ok', false, 'error', 'Poné tu nombre y tu apellido');
  end if;
  insert into public.supervisor_turnos (conv_id, fecha, zona, nombre, apellido, cuenta)
  values (p_conv_id, v_hoy, v_zona, v_nom, v_ape, auth.uid());
  return jsonb_build_object('ok', true, 'zona', v_zona, 'zona_nombre', public.zona_nombre(v_zona), 'nombre', v_nom, 'apellido', v_ape, 'fecha', v_hoy);
end;
$$;

-- ── 4) EN CADA INCIDENCIA, EL NOMBRE DE QUIEN ESTÁ HOY ──
--  "Ana López (Platea baja)": el último que empezó con esa cuenta en ese show.
--  null si la cuenta no es de una zona (ahí queda el nombre de siempre).
create or replace function public.supervisor_del_dia(p_cuenta uuid, p_conv uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select t.nombre || ' ' || t.apellido || ' (' || public.zona_nombre(up.zona) || ')'
       from public.supervisor_turnos t where t.cuenta = p_cuenta and t.conv_id = p_conv
      order by t.created_at desc limit 1),
    'Supervisor ' || public.zona_nombre(up.zona))
  from public.user_profiles up where up.id = p_cuenta and up.zona is not null;
$$;
create or replace function public.incidencias_nombre_zona()
returns trigger language plpgsql security definer set search_path = public as $$
declare v text;
begin
  if tg_op = 'INSERT' then
    v := public.supervisor_del_dia(new.creada_por, new.conv_id);
    if v is not null then new.creada_por_nombre := v; end if;
  elsif new.estado = 'resuelta' and old.estado is distinct from 'resuelta' then
    v := public.supervisor_del_dia(auth.uid(), new.conv_id);
    if v is not null then new.resuelta_por_nombre := v; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists incidencias_nombre_zona on public.incidencias;
create trigger incidencias_nombre_zona before insert or update on public.incidencias
  for each row execute function public.incidencias_nombre_zona();

-- ── 5) LAS CUENTAS DE ZONA VEN SOLAS LOS SHOWS DEL CENTRO DE CONTROL ──
--  Al sumar un show al Centro de Control, se les asigna; al sacarlo, se les saca.
--  Y una cuenta de zona nueva, a todos los que ya están.
create or replace function public.zonas_asignar_show()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.centro_control then
    insert into public.supervisor_convocatorias (supervisor_id, conv_id)
    select up.id, new.id from public.user_profiles up
    where up.zona is not null
      and not exists (select 1 from public.supervisor_convocatorias sc where sc.supervisor_id = up.id and sc.conv_id = new.id);
  elsif tg_op = 'UPDATE' and old.centro_control then
    delete from public.supervisor_convocatorias sc using public.user_profiles up
    where sc.conv_id = new.id and sc.supervisor_id = up.id and up.zona is not null;
  end if;
  return null;
end;
$$;
drop trigger if exists zonas_asignar_show on public.convocatorias;
create trigger zonas_asignar_show after insert or update of centro_control on public.convocatorias
  for each row execute function public.zonas_asignar_show();

create or replace function public.zonas_asignar_cuenta()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.zona is not null then
    insert into public.supervisor_convocatorias (supervisor_id, conv_id)
    select new.id, c.id from public.convocatorias c
    where c.centro_control
      and not exists (select 1 from public.supervisor_convocatorias sc where sc.supervisor_id = new.id and sc.conv_id = c.id);
  end if;
  return null;
end;
$$;
drop trigger if exists zonas_asignar_cuenta on public.user_profiles;
create trigger zonas_asignar_cuenta after insert or update of zona on public.user_profiles
  for each row execute function public.zonas_asignar_cuenta();

--  Si se vuelve a correr con cuentas ya creadas: que estén en todos los shows del Centro.
insert into public.supervisor_convocatorias (supervisor_id, conv_id)
select up.id, c.id from public.user_profiles up cross join public.convocatorias c
where up.zona is not null and c.centro_control
  and not exists (select 1 from public.supervisor_convocatorias sc where sc.supervisor_id = up.id and sc.conv_id = c.id);

-- ── 6) LA GERENCIA Y EL PANEL: QUIÉN ESTÁ A CARGO DE CADA ZONA ──
--  Todas las entradas del show, en orden (la página se queda con la última de cada zona y día).
create or replace function public.ger_supervisores(p_conv_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case
    when not (public.es_gerencia() or public.es_admin()) then null
    when not exists (select 1 from public.convocatorias c where c.id = p_conv_id and c.centro_control) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object('zona', t.zona, 'zona_nombre', public.zona_nombre(t.zona), 'nombre', t.nombre,
                                          'apellido', t.apellido, 'fecha', t.fecha, 'desde', t.created_at) order by t.created_at)
      from public.supervisor_turnos t where t.conv_id = p_conv_id), '[]'::jsonb)
  end;
$$;

-- ── 7) QUIÉN PUEDE USAR CADA COSA ──
revoke execute on function public.sup_mi_zona()                      from public, anon;
revoke execute on function public.sup_turno(uuid, text, text)        from public, anon;
revoke execute on function public.supervisor_del_dia(uuid, uuid)     from public, anon, authenticated;
revoke execute on function public.incidencias_nombre_zona()          from public, anon, authenticated;
revoke execute on function public.zonas_asignar_show()               from public, anon, authenticated;
revoke execute on function public.zonas_asignar_cuenta()             from public, anon, authenticated;
revoke execute on function public.ger_supervisores(uuid)             from public, anon;
grant  execute on function public.sup_mi_zona()                      to authenticated;
grant  execute on function public.sup_turno(uuid, text, text)        to authenticated;
grant  execute on function public.ger_supervisores(uuid)             to authenticated;

-- ── CÓMO QUEDÓ ──
--  Tiene que dar todo true.
select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'zona') as zona_en_las_cuentas,
       exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'supervisor_turnos') as quien_estuvo,
       has_function_privilege('authenticated', 'public.sup_turno(uuid, text, text)', 'execute')
         and not has_function_privilege('anon', 'public.sup_turno(uuid, text, text)', 'execute') as empezar_con_usuario,
       not has_table_privilege('anon', 'public.supervisor_turnos', 'select') as sin_usuario_no_se_ve,
       exists (select 1 from pg_trigger where tgname = 'incidencias_nombre_zona') as nombre_en_incidencias,
       exists (select 1 from pg_trigger where tgname = 'zonas_asignar_show') and exists (select 1 from pg_trigger where tgname = 'zonas_asignar_cuenta') as shows_solos;
