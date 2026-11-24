-- ============================================================
--  FEEDBACK DE OPERACIONES (24-nov-2026)
--  Supabase → SQL Editor → pegar todo → Run. Se puede volver a correr.
--
--  Pedido de RR. HH. (planilla "Convocados 2026 con roles, para feedback de operaciones"): Operaciones carga su
--  feedback de cada persona desde la plataforma, con un puntaje del 1 al 5, el feedback y lo que hay que tener en
--  cuenta. Va en la misma tabla de feedbacks, marcado como de Operaciones:
--    · feedbacks.tipo: vacío = el de siempre (supervisores, planillas); 'operaciones' = el de Operaciones;
--    · feedbacks.puntaje_ops: el puntaje de Operaciones, del 1 al 5;
--    · feedbacks.tener_en_cuenta: los comentarios a tener en cuenta.
--  No cuenta para el semáforo (como las observaciones): tiene su propio promedio.
-- ============================================================

alter table public.feedbacks add column if not exists tipo text;
alter table public.feedbacks add column if not exists puntaje_ops smallint;
alter table public.feedbacks add column if not exists tener_en_cuenta text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'feedbacks_puntaje_ops_rango') then
    alter table public.feedbacks add constraint feedbacks_puntaje_ops_rango check (puntaje_ops is null or puntaje_ops between 1 and 5);
  end if;
end $$;
create index if not exists feedbacks_tipo_idx on public.feedbacks (tipo) where tipo is not null;

-- ── CÓMO QUEDÓ ── tiene que dar 3 · true.
select
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'feedbacks' and column_name in ('tipo', 'puntaje_ops', 'tener_en_cuenta')) as columnas_nuevas,
  exists (select 1 from pg_constraint where conname = 'feedbacks_puntaje_ops_rango') as puntaje_del_1_al_5;
