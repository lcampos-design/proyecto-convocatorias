-- ============================================================
--  CENTRO DE CONTROL: el plano admite las salidas de evacuación (13-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  El plano suma las posiciones de salida de los planos de evacuación que
--  mandó el Arena (46 en los cuatro pisos). Con eso pasa de 80 puestos, que
--  era el tope de la tabla del plano guardado: esto lo sube a 160.
--
--  Sin esto, el plano igual muestra las salidas (el panel, la gerencia y la
--  app las suman solas a lo guardado), pero el panel no puede guardar el
--  plano desde el editor.
--
--  No guarda datos de nadie: sólo nombres de lugares y su posición.
-- ============================================================

-- ── 1) Sale el tope viejo (80), sea cual sea su nombre ──
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.arena_plano'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%jsonb_array_length%'
  loop
    execute format('alter table public.arena_plano drop constraint %I', r.conname);
  end loop;
end $$;

-- ── 2) El tope nuevo: hasta 160 puestos ──
alter table public.arena_plano add constraint arena_plano_lugares_check
  check (jsonb_typeof(lugares) = 'array' and jsonb_array_length(lugares) <= 160);

-- ── CÓMO QUEDÓ ──
--  Tiene que decir "<= 160" y, en guardados, cuántos puestos tiene hoy el
--  plano guardado (las salidas se suman cuando se guarde desde el panel).
select pg_get_constraintdef(c.oid) as tope,
       (select jsonb_array_length(p.lugares) from public.arena_plano p where p.id = 1) as guardados
from pg_constraint c
where c.conrelid = 'public.arena_plano'::regclass and c.conname = 'arena_plano_lugares_check';
