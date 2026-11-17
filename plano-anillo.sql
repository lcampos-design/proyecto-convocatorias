-- ============================================================
--  PLANO DEL ARENA: el anillo con los nombres del Arena (17-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr: el
--  cambio se hace una sola vez (la segunda vez avisa que ya estaba).
--
--  Luca (coordinador), 17-nov: "estaría bueno cambiarlos por anillo cancha,
--  anillo sede y anillo humboldt". Los tramos del anillo pasan a llamarse:
--   · Anillo izquierdo → Anillo Cancha
--   · Anillo derecho   → Anillo Sede
--   · Anillo fondo     → Anillo Humboldt
--  Los tramos son fijos del plano (no están en el plano guardado): sólo
--  cambian las incidencias ya cargadas, así cada una sigue en su lugar.
--  Antes guarda una copia en el esquema respaldo. No toca datos de nadie.
-- ============================================================

create schema if not exists respaldo;

do $$
declare n int := 0;
begin
  if to_regclass('respaldo.plano_anillo_2026_11_17') is not null then
    raise notice 'Ya estaba hecho: no se cambió nada.';
    return;
  end if;

  -- La copia: las incidencias que cambian de nombre.
  create table respaldo.plano_anillo_2026_11_17 as
    select 'incidencias'::text as tabla, i.id::text as fila_id, to_jsonb(i) as antes from public.incidencias i
     where i.sector in ('Anillo izquierdo', 'Anillo derecho', 'Anillo fondo');
  revoke all on respaldo.plano_anillo_2026_11_17 from public, anon, authenticated;

  -- Las incidencias ya cargadas, con el nombre nuevo de su tramo.
  update public.incidencias i set sector = m.nuevo
    from (values ('Anillo izquierdo', 'Anillo Cancha'), ('Anillo derecho', 'Anillo Sede'), ('Anillo fondo', 'Anillo Humboldt')) m(viejo, nuevo)
   where i.sector = m.viejo;
  get diagnostics n = row_count;
  raise notice 'Incidencias con el nombre nuevo: %.', n;
end $$;

-- Cómo quedó: cuántas incidencias tiene cada tramo, las que quedaron con el nombre viejo (tiene que dar 0) y las renombradas.
select m.tramo, (select count(*) from public.incidencias i where i.sector = m.tramo) as incidencias
  from (values (1, 'Anillo Cancha'), (2, 'Anillo Humboldt'), (3, 'Anillo Sede')) m(k, tramo)
union all
select 'Con el nombre viejo', (select count(*) from public.incidencias i where i.sector in ('Anillo izquierdo', 'Anillo derecho', 'Anillo fondo'))
union all
select 'Renombradas ahora', (select count(*) from respaldo.plano_anillo_2026_11_17);
