-- ============================================================
--  EL ARMADO DEL CAMPO, DEL SHOW (Y NO DE CADA APARATO)
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  "Campo de pie" o "Con asientos" se guardaba en cada aparato: si en el
--  panel se elegía "Con asientos", la gerencia y la tablet del supervisor
--  seguían viendo el campo de pie. Ahora se guarda en el show y lo ven
--  todos igual. Lo puede cambiar cualquiera que mira el plano de ese show:
--  el panel, la gerencia o un supervisor del show.
--
--  Hasta que esto se corra, las páginas siguen como antes (en el aparato).
-- ============================================================

-- ── 1) DÓNDE SE GUARDA ──
alter table public.convocatorias add column if not exists armado_campo text;
alter table public.convocatorias drop constraint if exists convocatorias_armado_campo_check;
alter table public.convocatorias add constraint convocatorias_armado_campo_check
  check (armado_campo is null or armado_campo in ('campos', 'asientos'));

-- ── 2) LEERLO: el de los shows del Centro de Control que uno puede ver ──
--  { "id del show": "campos" | "asientos" }. Sin usuario, nada.
create or replace function public.cc_armados()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(c.id, c.armado_campo), '{}'::jsonb)
  from public.convocatorias c
  where c.centro_control and c.armado_campo is not null
    and (public.es_admin() or public.es_gerencia()
         or exists (select 1 from public.supervisor_convocatorias sc where sc.conv_id = c.id and sc.supervisor_id = auth.uid()));
$$;

-- ── 3) CAMBIARLO: sólo eso (no toca nada más del show) ──
create or replace function public.cc_poner_armado(p_conv_id uuid, p_armado text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_armado is null or p_armado not in ('campos', 'asientos') then return false; end if;
  if not (public.es_admin() or public.es_gerencia()
          or exists (select 1 from public.supervisor_convocatorias sc where sc.conv_id = p_conv_id and sc.supervisor_id = auth.uid())) then
    return false;
  end if;
  update public.convocatorias set armado_campo = p_armado where id = p_conv_id and centro_control;
  return found;
end;
$$;

revoke execute on function public.cc_armados()                from public, anon;
revoke execute on function public.cc_poner_armado(uuid, text) from public, anon;
grant  execute on function public.cc_armados()                to authenticated;
grant  execute on function public.cc_poner_armado(uuid, text) to authenticated;

-- ── CÓMO QUEDÓ ──
select (select count(*) from public.convocatorias where centro_control) as shows_en_el_centro,
       (select count(*) from public.convocatorias where armado_campo is not null) as con_armado_elegido,
       has_function_privilege('anon', 'public.cc_poner_armado(uuid, text)', 'execute') as se_puede_cambiar_sin_usuario;
