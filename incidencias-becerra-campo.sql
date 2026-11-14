-- ============================================================
--  MARÍA BECERRA 13/11: lo cargado como "Otro lugar" era el campo
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: el cambio
--  se hace una sola vez (la segunda vez avisa que ya estaba).
--
--  Ese día el campo era único (de pie) y la app sólo ofrecía "Campo delantero"
--  y "Campo trasero", así que los supervisores cargaron "Otro lugar" y lo
--  escribieron a mano ("Dentro de campo", "Campo puerta 6"…). Thomas: "fue
--  todo campo". Pasan a "Campo", con lo que escribieron como ubicación, y así
--  cuentan en las métricas, el plano y el informe del link. El PDF que ya se
--  mandó no cambia. Antes guarda una copia en el esquema respaldo.
-- ============================================================

create schema if not exists respaldo;

do $$
declare n int;
begin
  if to_regclass('respaldo.incidencias_becerra_campo_2026_11_13') is not null then
    raise notice 'Ya estaba hecho: no se cambió nada.';
    return;
  end if;
  create table respaldo.incidencias_becerra_campo_2026_11_13 as
    select i.* from public.incidencias i
      join public.convocatorias c on c.id = i.conv_id
     where c.centro_control and c.nombre ilike '%becerra%'
       and i.sector = 'Otro lugar'
       and i.created_at >= timestamptz '2026-11-13 09:00+00' and i.created_at < timestamptz '2026-11-14 09:00+00';
  revoke all on respaldo.incidencias_becerra_campo_2026_11_13 from public, anon, authenticated;

  update public.incidencias i set sector = 'Campo'
   where i.id in (select id from respaldo.incidencias_becerra_campo_2026_11_13);
  get diagnostics n = row_count;
  raise notice 'Pasaron a Campo: %', n;
end $$;

-- Cómo quedó: lo del 13/11 de María Becerra, por sector.
select i.sector, count(*) as incidencias
  from public.incidencias i join public.convocatorias c on c.id = i.conv_id
 where c.centro_control and c.nombre ilike '%becerra%'
   and i.created_at >= timestamptz '2026-11-13 09:00+00' and i.created_at < timestamptz '2026-11-14 09:00+00'
 group by i.sector order by count(*) desc, i.sector;
