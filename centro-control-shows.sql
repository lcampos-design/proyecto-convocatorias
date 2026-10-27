-- ============================================================
--  CENTRO DE CONTROL: qué shows entran
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Hasta hoy entraban solos todos los shows del área Movistar Arena, y
--  muchos son eventos externos. Desde ahora entra sólo el show que se suma
--  a mano desde el panel (Centro de Control → "+ Sumar show").
--
--  Al correr esto la lista queda vacía. No se borra nada: las
--  convocatorias siguen igual y las incidencias que ya se cargaron quedan
--  guardadas; sólo dejan de mostrarse hasta que se sume el show.
--
--  Lo que cambia:
--   · La gerencia ve sólo los shows sumados.
--   · El supervisor ve la tarjeta "Incidencias" sólo en los shows sumados
--     (en los demás va directo a su equipo y al feedback, como siempre).
-- ============================================================

-- ── 1) La marca en cada convocatoria ──
alter table public.convocatorias add column if not exists centro_control boolean not null default false;

-- ── 2) LO QUE VE LA GERENCIA (y el panel): sólo los shows sumados ──
--  Con lo abierto por nivel, el total y la última incidencia.
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
      where c.centro_control
    ), '[]'::jsonb)
  end;
$$;

--  Las incidencias de un show sumado. Sin el id de usuario de quien cargó
--  (sólo su nombre). No hay datos del público: nunca se guardan.
create or replace function public.ger_incidencias(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not (public.es_gerencia() or public.es_admin()) then null
    when not exists (select 1 from public.convocatorias c where c.id = p_conv_id and c.centro_control) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(to_jsonb(i) - 'creada_por' order by i.created_at desc)
      from public.incidencias i where i.conv_id = p_conv_id
    ), '[]'::jsonb)
  end;
$$;

-- ── 3) PARA LA APP DEL SUPERVISOR ──
--  Cuáles de SUS shows están en el Centro de Control (sólo los ids).
create or replace function public.sup_control_ids()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(c.id), '[]'::jsonb)
  from public.supervisor_convocatorias sc
  join public.convocatorias c on c.id = sc.conv_id
  where sc.supervisor_id = auth.uid() and c.centro_control;
$$;

revoke execute on function public.ger_convocatorias()    from public, anon;
revoke execute on function public.ger_incidencias(uuid)  from public, anon;
revoke execute on function public.sup_control_ids()      from public, anon;
grant  execute on function public.ger_convocatorias()    to authenticated;
grant  execute on function public.ger_incidencias(uuid)  to authenticated;
grant  execute on function public.sup_control_ids()      to authenticated;

-- ── CÓMO QUEDÓ ──
select (select count(*) from public.convocatorias where centro_control) as shows_en_el_centro,
       (select count(*) from public.convocatorias)                      as convocatorias,
       has_function_privilege('anon', 'public.sup_control_ids()', 'execute') as sup_control_ids_sin_usuario;
--  Tiene que dar 0 shows en el centro (hasta que sumes alguno desde el
--  panel) y sup_control_ids_sin_usuario en false.
