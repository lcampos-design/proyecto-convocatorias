-- ============================================================
--  QUE EL SUPERVISOR PASE LISTA DESDE EL CELULAR
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  ⚠ CORRER DESPUÉS DE QUE EL CAMBIO DE supervisor-mobile.html ESTÉ ARRIBA.
--
--  Hasta ahora el presente se tomaba en papel y alguien lo cargaba al otro
--  día, o lo marcaba RRHH desde el panel. El supervisor es el que está en
--  el lugar: desde su celular marca Vino / Faltó y queda en el acto en el
--  panel y en la planilla.
--
--  Como todo lo del supervisor, no toca tablas: tres funciones que
--  devuelven y guardan exactamente lo necesario, y validan que el recital
--  sea suyo y que la persona esté convocada ahí.
-- ============================================================

-- ── 1) Sus recitales, ahora con los turnos y los sectores ──
--  Los turnos se resuelven igual que en el panel: si la convocatoria tiene
--  "turnos" cargados se usan esos; si no, cada fecha es un turno y su id es
--  la fecha. Así el presente que marca el supervisor y el que marca RRHH
--  caen en la misma casilla.
create or replace function public.sup_convocatorias()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'fecha' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', c.id, 'nombre', c.nombre, 'fecha', c.fecha, 'area', c.area,
      'venue', c.venue, 'horario', c.horario,
      'turnos', c.turnos, 'horarios_por_fecha', c.horarios_por_fecha,
      'puestos', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nombre', p.nombre) order by p.created_at), '[]'::jsonb)
                  from public.puestos p where p.conv_id = c.id),
      'personas', (select count(*) from public.postulaciones po
                   where po.conv_id = c.id and po.estado = 'aprobado' and po.persona_id is not null),
      'con_feedback', (select count(distinct f.persona_id) from public.feedbacks f
                       where f.conv_id = c.id and f.supervisor_id = auth.uid())
    ) as x
    from public.supervisor_convocatorias sc
    join public.convocatorias c on c.id = sc.conv_id
    where sc.supervisor_id = auth.uid()
  ) t;
$$;

-- ── 2) La lista para pasar: una fila por postulación no rechazada ──
--  Es el mismo criterio con el que el panel cuenta los cupos y arma la
--  planilla. De cada persona, sólo el nombre y el sector: para pasar lista
--  no hace falta más.
create or replace function public.sup_lista(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not exists (select 1 from public.supervisor_convocatorias
                     where supervisor_id = auth.uid() and conv_id = p_conv_id) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'post_id', po.id,
        'persona_id', po.persona_id,
        'nombre', coalesce(pe.nombre, po.nombre),
        'puesto_id', po.puesto_id,
        'puesto', pu.nombre,
        'estado', po.estado,
        'presentes', coalesce(po.presentes, '{}'::jsonb)
      ) order by pu.nombre, coalesce(pe.nombre, po.nombre))
      from public.postulaciones po
      left join public.personas pe on pe.id = po.persona_id
      left join public.puestos  pu on pu.id = po.puesto_id
      where po.conv_id = p_conv_id and coalesce(po.estado, '') <> 'rechazado'
    ), '[]'::jsonb)
  end;
$$;

-- ── 3) Marcar: Vino, Faltó, o sacar la marca ──
--  Valida que el recital sea suyo y que esa postulación sea de ese recital.
--  Tocar lo mismo dos veces lo deja sin marcar: equivocarse tiene vuelta atrás.
--  El campo "asistencia" queda como resumen (presente si vino a alguna fecha,
--  ausente si faltó a todas), que es lo que miran la penalización por faltar
--  y el aviso de la nómina: la misma regla que aplica el panel.
create or replace function public.sup_presente(p_post_id uuid, p_conv_id uuid, p_slot_id text, p_valor text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb; v_res text;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  if not exists (select 1 from public.supervisor_convocatorias
                 where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese recital no está asignado a vos');
  end if;
  if coalesce(p_slot_id, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'Falta el turno');
  end if;
  if p_valor is not null and p_valor not in ('presente', 'ausente') then
    return jsonb_build_object('ok', false, 'error', 'La marca tiene que ser presente o ausente');
  end if;

  select coalesce(presentes, '{}'::jsonb) into v
  from public.postulaciones
  where id = p_post_id and conv_id = p_conv_id and coalesce(estado, '') <> 'rechazado';
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Esa persona no está convocada en este recital');
  end if;

  if p_valor is null then v := v - p_slot_id;
  else v := jsonb_set(v, array[p_slot_id], to_jsonb(p_valor), true);
  end if;

  select case when exists (select 1 from jsonb_each_text(v) where value = 'presente') then 'presente'
              when exists (select 1 from jsonb_each_text(v) where value = 'ausente')  then 'ausente'
              else null end
  into v_res;

  update public.postulaciones set presentes = v, asistencia = v_res where id = p_post_id;
  return jsonb_build_object('ok', true, 'presentes', v, 'asistencia', v_res);
end $$;

grant execute on function public.sup_convocatorias()                       to authenticated;
grant execute on function public.sup_lista(uuid)                           to authenticated;
grant execute on function public.sup_presente(uuid, uuid, text, text)      to authenticated;
revoke execute on function public.sup_lista(uuid)                          from anon, public;
revoke execute on function public.sup_presente(uuid, uuid, text, text)     from anon, public;

-- ── CÓMO QUEDÓ ──
select p.proname, has_function_privilege('authenticated', p.oid, 'execute') as con_usuario,
       has_function_privilege('anon', p.oid, 'execute') as sin_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('sup_convocatorias', 'sup_lista', 'sup_presente')
order by p.proname;
--  con_usuario true en las tres; sin_usuario false en las tres.

-- ── PARA VOLVER ATRÁS ──
--   drop function if exists public.sup_lista(uuid);
--   drop function if exists public.sup_presente(uuid, uuid, text, text);
--   (sup_convocatorias queda: sólo devuelve más datos que antes)
