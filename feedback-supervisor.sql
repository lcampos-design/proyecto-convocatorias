-- ============================================================
--  QUE EL SUPERVISOR EVALÚE CON LOS MISMOS CUATRO CRITERIOS
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  ⚠ CORRER DESPUÉS DE QUE EL CAMBIO DE supervisor-mobile.html ESTÉ ARRIBA.
--
--  EL PROBLEMA
--  Hay dos formas de evaluar conviviendo. En el panel se puntúa del 1 al 5
--  en cuatro criterios —actitud de servicio, cumple consignas, buena
--  presencia, iniciativa— y el color sale del promedio. En el celular, el
--  supervisor elige el color a ojo, que es justamente lo que se había
--  querido dejar atrás.
--
--  Como el supervisor es el que estuvo en el show, su evaluación es la que
--  más vale, y es la que viene con menos información.
--
--  LA SOLUCIÓN
--  La misma pantalla de los cuatro criterios en el celular, y la misma
--  cuenta para sacar el color, hecha por la base:
--     promedio 3,5 o más → verde · más de 2 → amarillo · 2 o menos → rojo
--
--  LO QUE YA ESTÁ CARGADO NO SE TOCA. Los feedbacks viejos tienen sólo el
--  color, sin criterios, y así quedan. Para el semáforo de cada persona
--  mandan los que tienen los cuatro: si no hay ninguno, se usan los viejos,
--  igual que hace el panel hoy.
-- ============================================================

-- ── 1) LA REGLA DEL COLOR, UNA SOLA VEZ Y EN LA BASE ──
--  Hasta ahora esta cuenta vivía sólo en el navegador. Acá la usan las dos
--  pantallas, así que no puede quedar una copia distinta en cada una.
create or replace function public.color_de_promedio(p_prom numeric)
returns int
language sql immutable as $$
  select case
    when p_prom is null or p_prom <= 0 then 1
    when p_prom >= 3.5 then 1
    when p_prom >  2   then 2
    else 3
  end;
$$;

--  El semáforo de una persona, con la misma regla que usa el panel: mandan
--  los feedbacks que tienen los cuatro criterios; si no hay ninguno, se
--  promedian los viejos, que sólo tienen el color.
create or replace function public.semaforo_de(p_persona_id uuid)
returns int
language plpgsql stable security definer set search_path = public as $$
declare v_prom numeric; v_viejo numeric;
begin
  select avg((actitud + consignas + presencia + iniciativa) / 4.0) into v_prom
  from public.feedbacks where persona_id = p_persona_id and actitud is not null;
  if v_prom is not null then return public.color_de_promedio(v_prom); end if;

  select avg(puntaje) into v_viejo
  from public.feedbacks where persona_id = p_persona_id and puntaje is not null;
  if v_viejo is null then return 1; end if;
  return greatest(1, least(3, round(v_viejo)::int));
end $$;

-- ── 2) EL SUPERVISOR CARGA LOS CUATRO CRITERIOS ──
--  Se reemplaza la versión anterior, que recibía un color. El color ya no se
--  elige: sale de la cuenta.
drop function if exists public.sup_feedback(uuid, uuid, int, text);

create or replace function public.sup_feedback(
  p_persona_id uuid, p_conv_id uuid,
  p_actitud int, p_consignas int, p_presencia int, p_iniciativa int,
  p_comentario text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_prom numeric; v_color int; v_sem int;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Hay que iniciar sesión');
  end if;
  if not exists (select 1 from public.supervisor_convocatorias
                 where supervisor_id = auth.uid() and conv_id = p_conv_id) then
    return jsonb_build_object('ok', false, 'error', 'Ese recital no está asignado a vos');
  end if;
  if not exists (select 1 from public.postulaciones
                 where conv_id = p_conv_id and persona_id = p_persona_id and estado = 'aprobado') then
    return jsonb_build_object('ok', false, 'error', 'Esa persona no está en ese recital');
  end if;
  --  Los cuatro, o ninguno: un promedio de tres criterios no es comparable
  --  con uno de cuatro.
  if p_actitud is null or p_consignas is null or p_presencia is null or p_iniciativa is null then
    return jsonb_build_object('ok', false, 'error', 'Faltan criterios por puntuar');
  end if;
  if p_actitud    not between 1 and 5 or p_consignas  not between 1 and 5
  or p_presencia  not between 1 and 5 or p_iniciativa not between 1 and 5 then
    return jsonb_build_object('ok', false, 'error', 'Los puntajes van del 1 al 5');
  end if;

  v_prom  := (p_actitud + p_consignas + p_presencia + p_iniciativa) / 4.0;
  v_color := public.color_de_promedio(v_prom);

  insert into public.feedbacks (id, persona_id, conv_id, supervisor_id, supervisor_nombre,
                                puntaje, comentario, actitud, consignas, presencia, iniciativa)
  values (gen_random_uuid(), p_persona_id, p_conv_id, auth.uid(),
          (select nombre from public.user_profiles where id = auth.uid()),
          v_color, nullif(btrim(coalesce(p_comentario, '')), ''),
          p_actitud, p_consignas, p_presencia, p_iniciativa);

  --  El semáforo lo recalcula la base: dos supervisores cargando al mismo
  --  tiempo no se pisan con un promedio viejo.
  v_sem := public.semaforo_de(p_persona_id);
  update public.personas set semaforo = v_sem where id = p_persona_id;

  return jsonb_build_object('ok', true, 'promedio', round(v_prom, 2), 'color', v_color, 'semaforo', v_sem);
end $$;

-- ── 3) QUE EL CELULAR VEA LOS CRITERIOS DE LO QUE YA CARGÓ ──
create or replace function public.sup_equipo(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case
    when not exists (
      select 1 from public.supervisor_convocatorias
      where supervisor_id = auth.uid() and conv_id = p_conv_id
    ) then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pe.id,
        'nombre', pe.nombre,
        'area', pe.area,
        'semaforo', pe.semaforo,
        'mis_feedbacks', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'puntaje', f.puntaje, 'comentario', f.comentario, 'created_at', f.created_at,
                   'actitud', f.actitud, 'consignas', f.consignas,
                   'presencia', f.presencia, 'iniciativa', f.iniciativa,
                   'promedio', case when f.actitud is not null
                     then round((f.actitud + f.consignas + f.presencia + f.iniciativa) / 4.0, 2) end)
                 order by f.created_at), '[]'::jsonb)
          from public.feedbacks f
          where f.persona_id = pe.id and f.conv_id = p_conv_id and f.supervisor_id = auth.uid()
        )
      ) order by pe.nombre)
      from public.postulaciones po
      join public.personas pe on pe.id = po.persona_id
      where po.conv_id = p_conv_id and po.estado = 'aprobado'
    ), '[]'::jsonb)
  end;
$$;

grant execute on function public.color_de_promedio(numeric) to authenticated;
grant execute on function public.semaforo_de(uuid)          to authenticated;
grant execute on function public.sup_equipo(uuid)           to authenticated;
grant execute on function public.sup_feedback(uuid, uuid, int, int, int, int, text) to authenticated;

-- ── CÓMO QUEDÓ ──
--  Cuántos feedbacks tienen los cuatro criterios y cuántos sólo el color:
select count(*) filter (where actitud is not null) as con_los_cuatro_criterios,
       count(*) filter (where actitud is null)     as solo_el_color,
       count(*)                                    as total
from public.feedbacks;

--  Y que la cuenta del color sea la misma que la del panel:
select public.color_de_promedio(5)    as cinco_deberia_ser_1,
       public.color_de_promedio(3.5)  as tres_y_medio_deberia_ser_1,
       public.color_de_promedio(3)    as tres_deberia_ser_2,
       public.color_de_promedio(2)    as dos_deberia_ser_3,
       public.color_de_promedio(1)    as uno_deberia_ser_3;

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--  (vuelve la versión de un solo color; hay que volver también el archivo
--   supervisor-mobile.html a la versión anterior)
--   drop function if exists public.sup_feedback(uuid, uuid, int, int, int, int, text);
