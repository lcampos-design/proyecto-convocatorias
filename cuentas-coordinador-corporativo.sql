-- ============================================================
--  DOS CUENTAS MÁS EN LA APP DE SUPERVISORES: COORDINADOR Y CORPORATIVO
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr sin problema.
--  (Necesita cuentas-zona.sql, que ya está corrido.)
--
--  Pedido de Thomas (13-nov): "crear 2 usuarios en la app de supervisores,
--  uno para Coordinador y otro para Corporativo". Son como las de zona: una
--  cuenta compartida (usuario "coordinador" y "corporativo"), quien la usa
--  pone su nombre y apellido al entrar a cada show, y ven solas los shows del
--  Centro de Control. No tienen un sector propio: cargan en cualquier lugar.
--
--  Después de correrlo: panel → Supervisores → "Crear las que faltan (2)".
-- ============================================================

-- ── 1) LAS ZONAS QUE PUEDE TENER UNA CUENTA ──
alter table public.user_profiles drop constraint if exists user_profiles_zona_valida;
alter table public.user_profiles add constraint user_profiles_zona_valida
  check (zona is null or zona in ('calle', 'cortatickets', 'anillo', 'bowl', 'platea_baja', 'platea_alta', 'vip', 'coordinador', 'corporativo'));

-- ── 2) SUS NOMBRES ──
create or replace function public.zona_nombre(p text)
returns text language sql immutable as $$
  select case p when 'calle' then 'Calle' when 'cortatickets' then 'Cortatickets' when 'anillo' then 'Anillo'
                when 'bowl' then 'Bowl' when 'platea_baja' then 'Platea baja' when 'platea_alta' then 'Platea alta'
                when 'vip' then 'VIP' when 'coordinador' then 'Coordinador' when 'corporativo' then 'Corporativo' end;
$$;

-- ── 3) EN CADA INCIDENCIA ──
--  "Ana López (Coordinador)" como las demás; si nadie puso su nombre todavía,
--  "Coordinador" o "Corporativo" (las de zona siguen diciendo "Supervisor Calle").
create or replace function public.supervisor_del_dia(p_cuenta uuid, p_conv uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select t.nombre || ' ' || t.apellido || ' (' || public.zona_nombre(up.zona) || ')'
       from public.supervisor_turnos t where t.cuenta = p_cuenta and t.conv_id = p_conv
      order by t.created_at desc limit 1),
    case when up.zona in ('coordinador', 'corporativo') then public.zona_nombre(up.zona) else 'Supervisor ' || public.zona_nombre(up.zona) end)
  from public.user_profiles up where up.id = p_cuenta and up.zona is not null;
$$;
revoke execute on function public.supervisor_del_dia(uuid, uuid) from public, anon, authenticated;

-- ── CÓMO QUEDÓ ──
select pg_get_constraintdef(oid) like '%coordinador%' and pg_get_constraintdef(oid) like '%corporativo%' as se_pueden_crear,
       public.zona_nombre('coordinador') = 'Coordinador' and public.zona_nombre('corporativo') = 'Corporativo' as con_su_nombre
from pg_constraint where conname = 'user_profiles_zona_valida';
