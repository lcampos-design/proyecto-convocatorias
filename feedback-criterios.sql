-- ============================================================
--  FEEDBACK CON LOS CUATRO CRITERIOS
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no borra nada ni duplica.
--
--  Hasta ahora un feedback era un solo puntaje del 1 al 3 (el color del
--  semáforo). El modelo que usa RRHH son cuatro criterios del 1 al 5, y el
--  promedio de esos cuatro define el color:
--
--      3,5 o más          → Verde
--      más de 2, menos de 3,5 → Amarillo
--      2 o menos          → Rojo
--
--  Se agregan las cuatro columnas. La columna puntaje se mantiene: sigue
--  guardando el color, calculado a partir del promedio, para que lo ya
--  cargado siga funcionando igual.
-- ============================================================

alter table public.feedbacks add column if not exists actitud    smallint;
alter table public.feedbacks add column if not exists consignas  smallint;
alter table public.feedbacks add column if not exists presencia  smallint;
alter table public.feedbacks add column if not exists iniciativa smallint;

-- Ninguno puede quedar fuera de la escala de 1 a 5.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'feedbacks_criterios_1a5') then
    alter table public.feedbacks add constraint feedbacks_criterios_1a5 check (
      (actitud    is null or actitud    between 1 and 5) and
      (consignas  is null or consignas  between 1 and 5) and
      (presencia  is null or presencia  between 1 and 5) and
      (iniciativa is null or iniciativa between 1 and 5)
    );
  end if;
end $$;

-- El promedio de los cuatro, calculado por la base: no hay que recordarlo
-- en ningún lado y nunca puede quedar desfasado de los criterios.
create or replace view public.feedbacks_con_promedio as
select f.*,
       case when f.actitud is not null
            then round((f.actitud + f.consignas + f.presencia + f.iniciativa) / 4.0, 2)
       end as promedio
from public.feedbacks f;

-- Para ver cómo quedó:
--   select count(*) filter (where actitud is not null) as con_criterios,
--          count(*) filter (where actitud is null)     as solo_color
--   from public.feedbacks;
