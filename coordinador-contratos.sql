-- ============================================================
--  EL COORDINADOR VE LOS CONTRATOS SIN FIRMAR DE CADA SHOW
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr sin problema.
--  (Necesita cuentas-coordinador-corporativo.sql y contratos-presentes.sql, ya corridos.)
--
--  Pedido de Thomas (13-nov): "que el Coordinador pueda ver los contratos que
--  no están firmados, pendientes de firma, para que le diga a esos chicos que
--  no firmaron". En la app del supervisor, la cuenta del Coordinador (y nadie
--  más, salvo el panel) ve, por fecha del show, quiénes tienen el contrato sin
--  firmar: nombre, sector, puesto y si abrieron el link. Sin CUIL ni mail.
-- ============================================================

create or replace function public.sup_contratos_sin_firmar(p_conv_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  with permiso as (
    -- El panel, o la cuenta del Coordinador en un show que tiene asignado (las de zona los ven todos).
    select coalesce(public.es_admin(), false)
        or exists (select 1 from public.user_profiles up
                     join public.supervisor_convocatorias sc on sc.supervisor_id = up.id and sc.conv_id = p_conv_id
                    where up.id = auth.uid() and up.zona = 'coordinador') as ok
  ), c as (
    select k.* from public.contratos k, permiso
     where permiso.ok is true and k.conv_id = p_conv_id and k.estado is distinct from 'anulado'
  ), f as (
    select fecha_show, count(*) as total, count(*) filter (where estado = 'firmado') as firmados,
           coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'puesto', puesto, 'sector', sector, 'estado', estado,
                                                 'enviado', fecha_envio, 'visto', fecha_visto, 'vence', vence_el)
                              order by sector nulls last, nombre) filter (where estado is distinct from 'firmado'), '[]'::jsonb) as pendientes
      from c group by fecha_show
  )
  select case when not coalesce((select ok from permiso), false)
    then jsonb_build_object('ok', false, 'error', 'Esto lo ve sólo la cuenta del Coordinador')
    else jsonb_build_object('ok', true, 'fechas', coalesce((
      select jsonb_agg(jsonb_build_object('fecha', fecha_show, 'total', total, 'firmados', firmados, 'pendientes', pendientes)
                       order by fecha_show desc nulls last) from f), '[]'::jsonb))
  end;
$$;
revoke execute on function public.sup_contratos_sin_firmar(uuid) from public, anon;
grant  execute on function public.sup_contratos_sin_firmar(uuid) to authenticated;

-- ── CÓMO QUEDÓ ──
select has_function_privilege('authenticated', 'public.sup_contratos_sin_firmar(uuid)', 'execute') as la_app_la_puede_usar,
       not has_function_privilege('anon', 'public.sup_contratos_sin_firmar(uuid)', 'execute') as sin_usuario_no;
