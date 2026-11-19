-- Contratos por presente en Externos (19-nov-2026). Se puede correr más de una vez.
-- Supabase → SQL Editor → pegar todo → Run. Al final muestra cómo quedó.
--
-- 1) Las filas de las planillas de presentes, por área ('arena' o 'externos'): una por área, fecha y CUIL.
--    Antes era una por fecha y CUIL, y una persona que trabaja el mismo día en el Arena y en un evento de
--    Externos se pisaba. Lo que ya estaba queda como 'arena'.
alter table public.planilla_presentes add column if not exists area text not null default 'arena';

do $$
declare r record;
begin
  -- La única vieja (fecha, cuil), con el nombre que tenga.
  for r in
    select c.conname
      from pg_constraint c
     where c.conrelid = 'public.planilla_presentes'::regclass
       and c.contype = 'u'
       and (select array_agg(a.attname::text order by a.attname)
              from unnest(c.conkey) k
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k) = array['cuil', 'fecha']
  loop
    execute format('alter table public.planilla_presentes drop constraint %I', r.conname);
  end loop;
end $$;

create unique index if not exists planilla_presentes_area_fecha_cuil
  on public.planilla_presentes (area, fecha, cuil);

-- 2) Los contratos de Externos por presente (origen 'planilla_externos'): uno por persona y por fecha, como los
--    del Arena (origen 'planilla'), pero aparte.
create unique index if not exists contratos_presente_externos_unico
  on public.contratos (doc_nucleo, fecha_show)
  where origen = 'planilla_externos' and estado <> 'anulado';

-- Cómo quedó: columna_area 1 · indices 2 · unica_vieja 0.
select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'planilla_presentes' and column_name = 'area') as columna_area,
  (select count(*) from pg_indexes
    where schemaname = 'public' and indexname in ('planilla_presentes_area_fecha_cuil', 'contratos_presente_externos_unico')) as indices,
  (select count(*) from pg_constraint
    where conrelid = 'public.planilla_presentes'::regclass and contype = 'u') as unica_vieja,
  (select count(*) from public.planilla_presentes where area = 'arena') as filas_del_arena;
