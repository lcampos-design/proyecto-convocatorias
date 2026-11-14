-- ============================================================
--  EL CAMPO ÚNICO: un tercer armado del campo (14-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Thomas: "muchos no pusieron incidencias en campo, pusieron Otro,
--  porque fue campo único, no delantero o trasero (lo decía la ficha
--  técnica)". Además de "de pie con delantero y trasero" y "con asientos
--  (A a N)", ahora está "campo único": de pie, un solo sector "Campo".
--  Se elige en el panel, en el menú ⋯ del show.
--
--  Y los shows de María Becerra de noviembre quedan con campo único.
-- ============================================================

-- ── 1) El armado nuevo, permitido ──
alter table public.convocatorias drop constraint if exists convocatorias_armado_campo_check;
alter table public.convocatorias add constraint convocatorias_armado_campo_check
  check (armado_campo is null or armado_campo in ('unico', 'campos', 'asientos'));

-- ── 2) Cambiarlo: también a "unico" ──
create or replace function public.cc_poner_armado(p_conv_id uuid, p_armado text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_armado is null or p_armado not in ('unico', 'campos', 'asientos') then return false; end if;
  if not (public.es_admin() or public.es_gerencia()
          or exists (select 1 from public.supervisor_convocatorias sc where sc.conv_id = p_conv_id and sc.supervisor_id = auth.uid())) then
    return false;
  end if;
  update public.convocatorias set armado_campo = p_armado where id = p_conv_id and centro_control;
  return found;
end;
$$;
revoke execute on function public.cc_poner_armado(uuid, text) from public, anon;
grant  execute on function public.cc_poner_armado(uuid, text) to authenticated;

-- ── 3) María Becerra (noviembre): campo único, como dice la ficha técnica ──
update public.convocatorias
   set armado_campo = 'unico'
 where centro_control
   and nombre ilike '%becerra%'
   and fecha like '%2026-11-%';

-- ── CÓMO QUEDÓ ──
select nombre, fecha, armado_campo
  from public.convocatorias
 where centro_control and nombre ilike '%becerra%'
 order by fecha;
