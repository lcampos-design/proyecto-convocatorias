-- ============================================================
--  QUE UN SUPERVISOR VEA SÓLO SU EQUIPO
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  ⚠ CORRER DESPUÉS DE QUE EL CAMBIO DE supervisor-mobile.html ESTÉ ARRIBA.
--
--  EL PROBLEMA
--  Los supervisores entran con usuario, y las reglas de la base dicen "a
--  cualquiera que esté logueado". El celular les muestra poco, pero la base
--  les deja pedir todo: la nómina entera con CUIL, mail y teléfono, los
--  contratos, las solicitudes. Y también cambiarlos. Son muchos y rotan.
--
--  LA SOLUCIÓN
--  El supervisor deja de tocar tablas. Todo lo que hace —ver sus recitales,
--  ver a su gente, cargar el feedback— pasa por tres funciones que devuelven
--  exactamente eso y nada más. De la gente no sale ni el documento, ni el
--  mail, ni el teléfono: sólo el nombre, el área y el semáforo, que es lo
--  que necesita para evaluar.
--
--  Después, una regla extra en cada tabla: además de lo que ya pedía, hay
--  que ser admin. Se suma a las que ya están, no las reemplaza, así nada de
--  lo que funciona hoy se toca.
-- ============================================================

-- ── 0) PRIMERO, MIRAR CÓMO ESTÁN LOS USUARIOS ──
--  Esto no cambia nada: es para ver con qué rol quedó cada uno.
select coalesce(up.rol, '(sin rol)') as rol, count(*) as cuantos
from auth.users u
left join public.user_profiles up on up.id = u.id
group by 1 order by 2 desc;

-- ── 1) QUIÉN ES QUIÉN ──
create or replace function public.es_supervisor()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_profiles up
    where up.id = auth.uid() and coalesce(up.rol, '') = 'supervisor'
  );
$$;

--  Admin es todo el que entró con usuario y NO es supervisor.
--  Se define así a propósito: si alguien del equipo no tiene la ficha
--  cargada, sigue entrando al panel como hasta ahora. Lo que importa es
--  dejar afuera a los supervisores, y eso sí queda cerrado.
--
--  Esto se apoya en que nadie puede crearse una cuenta solo. Verificado el
--  22/10/2026 en Authentication → Sign In / Providers → User Signups:
--  "Allow new users to sign up" y "Allow anonymous sign-ins" están apagados,
--  así que los únicos usuarios son los que crea el equipo. Si algún día se
--  prende el registro libre, hay que pasar a la versión estricta de abajo
--  ANTES, porque si no cualquiera que se registre entra como admin.
--
--  La versión estricta: con la consulta de arriba confirmá que todos los del
--  panel tengan rol 'admin' (nadie en "(sin rol)"), y cambiá el cuerpo por
--     select exists (select 1 from public.user_profiles up
--                    where up.id = auth.uid() and coalesce(up.rol,'') like 'admin%');
create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and not public.es_supervisor();
$$;

grant execute on function public.es_supervisor() to authenticated;
grant execute on function public.es_admin()      to authenticated;

-- ── 2) LAS TRES FUNCIONES DEL SUPERVISOR ──

--  2.a) Los recitales que le asignaron, con cuánto feedback lleva cargado.
create or replace function public.sup_convocatorias()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'fecha' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', c.id, 'nombre', c.nombre, 'fecha', c.fecha, 'area', c.area,
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

--  2.b) La gente de UNO de sus recitales. Sin documento, sin mail, sin
--       teléfono: sólo lo que hace falta para reconocerla y evaluarla.
--       Si el recital no es suyo, devuelve vacío.
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
                   'puntaje', f.puntaje, 'comentario', f.comentario, 'created_at', f.created_at)
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

--  2.c) Cargar el feedback. Valida que el recital sea suyo y que la persona
--       esté convocada ahí: el teléfono no decide nada.
create or replace function public.sup_feedback(
  p_persona_id uuid, p_conv_id uuid, p_puntaje int, p_comentario text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_sem int;
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
  if p_puntaje is null or p_puntaje not between 1 and 3 then
    return jsonb_build_object('ok', false, 'error', 'Falta elegir el semáforo');
  end if;

  insert into public.feedbacks (id, persona_id, conv_id, supervisor_id, supervisor_nombre, puntaje, comentario)
  values (gen_random_uuid(), p_persona_id, p_conv_id, auth.uid(),
          (select nombre from public.user_profiles where id = auth.uid()),
          p_puntaje, nullif(btrim(coalesce(p_comentario, '')), ''));

  -- El semáforo lo recalcula la base, no el teléfono: así dos supervisores
  -- cargando al mismo tiempo no se pisan con un promedio viejo.
  select greatest(1, least(3, round(avg(puntaje))::int)) into v_sem
  from public.feedbacks where persona_id = p_persona_id and puntaje is not null;
  update public.personas set semaforo = v_sem where id = p_persona_id;

  return jsonb_build_object('ok', true, 'semaforo', v_sem);
end $$;

grant execute on function public.sup_convocatorias()                  to authenticated;
grant execute on function public.sup_equipo(uuid)                     to authenticated;
grant execute on function public.sup_feedback(uuid, uuid, int, text)  to authenticated;

-- ── 3) LA NÓMINA ENTERA, SÓLO PARA EL PANEL ──
--  personas_lista corre por cuenta de la base, así que las reglas de abajo no
--  la frenan: el filtro va adentro.
create or replace function public.personas_lista()
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select
    (to_jsonb(p) - 'cv')
    || jsonb_build_object('cv',
         case when p.cv is null then null
              else p.cv #- '{archivo,datos}'
         end)
  from public.personas p
  where public.es_admin()
  order by p.created_at;
$$;

grant execute on function public.personas_lista() to authenticated;

-- ── 4) ADEMÁS DE LO QUE YA PEDÍA CADA REGLA, HAY QUE SER ADMIN ──
--  Es una regla "restrictiva": se suma con Y a las que ya están, no las
--  reemplaza. Por eso no hay que tocar ninguna de las existentes.
--  Sólo afecta a quien entró con usuario; a quien entra sin usuario lo sigue
--  manejando blindaje.sql.
do $$
declare t record; n int := 0;
begin
  for t in
    select c.relname
    from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
    where ns.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
  loop
    execute format('drop policy if exists solo_admin on public.%I', t.relname);
    execute format(
      'create policy solo_admin on public.%I as restrictive to authenticated '
      || 'using (public.es_admin()) with check (public.es_admin())', t.relname);
    n := n + 1;
  end loop;
  raise notice 'Regla de admin puesta en % tabla(s).', n;
end $$;

-- ── CÓMO QUEDÓ ──
--  Las tablas que ya tienen la regla de admin:
select tablename, policyname, permissive
from pg_policies
where schemaname = 'public' and policyname = 'solo_admin'
order by tablename;

--  Y que las tres del supervisor existan:
select p.proname, has_function_privilege('authenticated', p.oid, 'execute') as con_usuario
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('es_admin', 'es_supervisor', 'sup_convocatorias', 'sup_equipo', 'sup_feedback')
order by p.proname;

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--   do $$ declare t record; begin
--     for t in select c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
--              where ns.nspname='public' and c.relkind='r'
--     loop execute format('drop policy if exists solo_admin on public.%I', t.relname); end loop;
--   end $$;
