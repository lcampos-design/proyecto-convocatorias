-- ============================================================
--  CENTRO DE CONTROL: el acceso de la gerencia del Movistar Arena
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  La gerencia del Arena entra con su usuario a /centro-control y ve
--  SÓLO las incidencias de los shows del Arena: el plano, la lista y el
--  informe. No ve nómina, contratos, CBU, postulantes ni nada de la gente.
--  Y no puede cambiar nada: es de sólo lectura.
--
--  LO IMPORTANTE
--  Hasta hoy "admin" era todo el que entra con usuario y no es supervisor.
--  Con eso, una cuenta de la gerencia habría entrado al panel completo. Acá
--  se cambia la regla: admin es quien entra con usuario y no es supervisor
--  NI gerencia. Como todas las tablas piden ser admin (roles.sql), a la
--  gerencia le quedan cerradas todas; ve lo suyo por dos funciones.
--
--  ⚠ CORRERLO ANTES de crear la primera cuenta de gerencia.
-- ============================================================

-- ── 1) El mail de cada cuenta, en su ficha (para mostrarlo en el panel) ──
alter table public.user_profiles add column if not exists email text;

-- ── 2) QUIÉN ES QUIÉN ──
create or replace function public.es_gerencia()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_profiles up
    where up.id = auth.uid() and coalesce(up.rol, '') = 'gerencia'
  );
$$;

--  Admin: entró con usuario, y no es supervisor ni gerencia.
create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and not public.es_supervisor() and not public.es_gerencia();
$$;

--  El rol de quien está logueado, para que cada página lo mande a la suya
--  (el supervisor a su app, la gerencia al Centro de Control). Sin ficha,
--  como hasta ahora, es 'admin'.
create or replace function public.mi_rol()
returns text
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null then null
              else coalesce((select nullif(up.rol, '') from public.user_profiles up where up.id = auth.uid()), 'admin') end;
$$;

-- ── 3) LO QUE VE LA GERENCIA (y el panel, si lo abre) ──
--  3.a) Los shows del Movistar Arena: los de los últimos 6 meses, los que
--       vienen y cualquiera que tenga incidencias. Con lo abierto por nivel.
create or replace function public.ger_convocatorias()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not (public.es_gerencia() or public.es_admin()) then null
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'nombre', c.nombre, 'fecha', c.fecha, 'venue', c.venue,
        'abiertas_1', (select count(*) from public.incidencias i where i.conv_id = c.id and i.estado = 'abierta' and i.nivel = 1),
        'abiertas_2', (select count(*) from public.incidencias i where i.conv_id = c.id and i.estado = 'abierta' and i.nivel = 2),
        'abiertas_3', (select count(*) from public.incidencias i where i.conv_id = c.id and i.estado = 'abierta' and i.nivel = 3),
        'total',      (select count(*) from public.incidencias i where i.conv_id = c.id),
        'ultima',     (select max(i.created_at) from public.incidencias i where i.conv_id = c.id)
      ) order by c.fecha desc nulls last)
      from public.convocatorias c
      where coalesce(c.area, '') ilike '%arena%'
        and ( exists (select 1 from public.incidencias i where i.conv_id = c.id)
              or exists (select 1 from unnest(string_to_array(coalesce(c.fecha, ''), ',')) f
                         where btrim(f) >= to_char(current_date - 180, 'YYYY-MM-DD')) )
    ), '[]'::jsonb)
  end;
$$;

--  3.b) Las incidencias de un show del Arena. Sin el id de usuario de quien
--       cargó (sólo su nombre). No hay datos del público: nunca se guardan.
create or replace function public.ger_incidencias(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not (public.es_gerencia() or public.es_admin()) then null
    when not exists (select 1 from public.convocatorias c where c.id = p_conv_id and coalesce(c.area, '') ilike '%arena%') then '[]'::jsonb
    else coalesce((
      select jsonb_agg(to_jsonb(i) - 'creada_por' order by i.created_at desc)
      from public.incidencias i where i.conv_id = p_conv_id
    ), '[]'::jsonb)
  end;
$$;

revoke execute on function public.es_gerencia()          from public, anon;
revoke execute on function public.mi_rol()               from public, anon;
revoke execute on function public.ger_convocatorias()    from public, anon;
revoke execute on function public.ger_incidencias(uuid)  from public, anon;
grant  execute on function public.es_gerencia()          to authenticated;
grant  execute on function public.es_admin()             to authenticated;
grant  execute on function public.mi_rol()               to authenticated;
grant  execute on function public.ger_convocatorias()    to authenticated;
grant  execute on function public.ger_incidencias(uuid)  to authenticated;

-- ── CÓMO QUEDÓ ──
--  Las funciones nuevas: con usuario sí, sin usuario no.
select p.proname,
       has_function_privilege('authenticated', p.oid, 'execute') as con_usuario,
       has_function_privilege('anon', p.oid, 'execute')          as sin_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('es_gerencia', 'mi_rol', 'ger_convocatorias', 'ger_incidencias')
order by p.proname;
--  Tiene que dar cuatro filas: con_usuario true, sin_usuario false.
--  (Que vos sigas entrando al panel como siempre se ve abriéndolo: el
--  editor de SQL no corre con tu usuario, así que acá no se puede probar.)
