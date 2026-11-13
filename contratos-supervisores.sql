-- ============================================================
--  LA APP DE SUPERVISORES VE, POR SHOW, QUIÉN FIRMÓ EL CONTRATO Y QUIÉN NO
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr sin problema.
--  (Necesita contratos-presentes.sql y cuentas-coordinador-corporativo.sql, ya corridos.)
--
--  Pedido de Thomas (13-nov): "que Coordinador, Supervisor y Corporativo puedan
--  ver por show los contratos firmados y los pendientes de firma; no el contrato
--  en sí, sólo su estado, para poder exigir las firmas". En la app, la sección
--  Contratos (junto a Incidencias y Equipo y feedback).
--
--  La ve cualquier cuenta asignada al show (las de zona, Coordinador y
--  Corporativo están en todos los del Centro de Control) y el panel. Por fecha
--  del show: nombre, puesto, sector y estado (firmado, o pendiente: sin enviar,
--  no lo abrió, lo abrió; y si el link venció). Sin CUIL, mail ni el contrato.
-- ============================================================

-- La de la primera versión (sólo el Coordinador y sólo los sin firmar), si se llegó a correr.
drop function if exists public.sup_contratos_sin_firmar(uuid);

create or replace function public.sup_contratos_show(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with permiso as (
    select coalesce(public.es_admin(), false)
        or exists (select 1 from public.supervisor_convocatorias sc
                    where sc.conv_id = p_conv_id and sc.supervisor_id = auth.uid()) as ok
  ), c as (
    select k.* from public.contratos k, permiso
     where permiso.ok is true and k.conv_id = p_conv_id and k.estado is distinct from 'anulado'
  ), f as (
    select fecha_show, count(*) as total, count(*) filter (where estado = 'firmado') as firmados,
           jsonb_agg(jsonb_build_object('nombre', nombre, 'puesto', puesto, 'sector', sector, 'estado', estado,
                                        'visto', fecha_visto, 'vence', vence_el, 'firmado', fecha_firma)
                     order by sector nulls last, nombre) as personas
      from c group by fecha_show
  )
  select case when not coalesce((select ok from permiso), false)
    then jsonb_build_object('ok', false, 'error', 'No tenés este show asignado')
    else jsonb_build_object('ok', true, 'fechas', coalesce((
      select jsonb_agg(jsonb_build_object('fecha', fecha_show, 'total', total, 'firmados', firmados, 'personas', personas)
                       order by fecha_show desc nulls last) from f), '[]'::jsonb))
  end;
$$;
revoke execute on function public.sup_contratos_show(uuid) from public, anon;
grant  execute on function public.sup_contratos_show(uuid) to authenticated;

-- ── CÓMO QUEDÓ ──
select has_function_privilege('authenticated', 'public.sup_contratos_show(uuid)', 'execute') as la_app_la_puede_usar,
       not has_function_privilege('anon', 'public.sup_contratos_show(uuid)', 'execute') as sin_usuario_no;
