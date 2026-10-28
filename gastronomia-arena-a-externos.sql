-- ============================================================
--  GASTRONOMÍA FUERA DE MOVISTAR ARENA
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema (la segunda vez no encuentra nada).
--
--  En el Arena no hay gastronomía, pero el formulario la ofrecía antes de
--  sacarla, y quedaron inscripciones de Movistar Arena con "Gastronomía".
--  Vale para Postulantes (solicitudes) y para la Nómina (personas):
--
--   · Los que pusieron SÓLO Gastronomía (o Gastronomía y "Otro: …") pasan
--     a Externos, con lo que habían elegido.
--   · Los que además pusieron un puesto del Arena (Acomodador, Orientador,
--     Stagehand, Supervisor…) se quedan en el Arena y se les saca
--     "Gastronomía" de la lista.
--
--  Antes de cambiar nada, guarda cómo estaba cada fila (el área y el puesto)
--  en respaldo.gastronomia_arena, un esquema aparte que el panel no ve, por
--  si hay que volver atrás. No se borra nada.
-- ============================================================

begin;

-- ── 1) QUIÉNES SON ──
--  En la nómina, el puesto está en cv.puestoInteres (se copia de la
--  inscripción al aprobarla). "Gastronomía" cuenta sólo si es uno de los
--  puestos de la lista, tal cual se elegía en el formulario.
create temp table _gastro on commit drop as
with base as (
  select 'solicitudes'::text as tabla, id::text as id, puesto_interes as puesto, null::text as notas
  from public.solicitudes
  where area = 'movistar_arena'
  union all
  select 'personas', id::text, cv->>'puestoInteres', notas
  from public.personas
  where area = 'movistar_arena' and cv is not null
),
partes as (
  select b.*,
         array(select btrim(t) from unnest(string_to_array(coalesce(b.puesto, ''), ',')) t where btrim(t) <> '') as todas
  from base b
)
select tabla, id, puesto, notas,
       array_to_string(array(select x from unnest(todas) x where x !~* '^gastronom(i|í)a$'), ', ') as sin_gastro,
       -- Sin ningún puesto del Arena (lo de "Otro: …" no cuenta como tal).
       not exists (select 1 from unnest(todas) x where x !~* '^gastronom(i|í)a$' and x !~* '^otro($|[: ])') as solo_gastro
from partes
where exists (select 1 from unnest(todas) x where x ~* '^gastronom(i|í)a$');

-- ── 2) EL RESPALDO ──
create schema if not exists respaldo;
revoke all on schema respaldo from public, anon, authenticated;
create table if not exists respaldo.gastronomia_arena (
  tabla        text not null,
  id           text not null,
  area_antes   text not null,
  puesto_antes text,
  notas_antes  text,
  paso_a       text not null,   -- 'externos' o 'movistar_arena (sin Gastronomía)'
  cuando       timestamptz not null default now()
);
insert into respaldo.gastronomia_arena (tabla, id, area_antes, puesto_antes, notas_antes, paso_a)
select tabla, id, 'movistar_arena', puesto, notas,
       case when solo_gastro then 'externos' else 'movistar_arena (sin Gastronomía)' end
from _gastro;

-- ── 3) SÓLO GASTRONOMÍA: A EXTERNOS ──
update public.solicitudes s set area = 'externos'
from _gastro g where g.tabla = 'solicitudes' and g.solo_gastro and s.id::text = g.id;

update public.personas p set area = 'externos'
from _gastro g where g.tabla = 'personas' and g.solo_gastro and p.id::text = g.id;

-- ── 4) ARENA Y OTROS PUESTOS: SE QUEDAN, SIN "GASTRONOMÍA" ──
update public.solicitudes s set puesto_interes = g.sin_gastro
from _gastro g where g.tabla = 'solicitudes' and not g.solo_gastro and s.id::text = g.id;

--  En la nómina, también la nota "Interés: …" que se armó al aprobar (si nadie la cambió).
update public.personas p
set cv = jsonb_set(p.cv, '{puestoInteres}', to_jsonb(coalesce(g.sin_gastro, ''))),
    notas = case when p.notas = 'Interés: ' || g.puesto then 'Interés: ' || g.sin_gastro else p.notas end
from _gastro g where g.tabla = 'personas' and not g.solo_gastro and p.id::text = g.id;

commit;

-- ── CÓMO QUEDÓ ──
--  Cuántos pasaron a Externos y cuántos se quedaron en el Arena sin
--  Gastronomía, en Postulantes y en la Nómina. Y, para revisar a mano, los
--  del Arena que todavía nombran la gastronomía en un texto libre (de antes
--  de que el formulario tuviera la lista): esos no se tocaron.
select tabla, paso_a as que_paso, count(*) as cuantos
from respaldo.gastronomia_arena
group by tabla, paso_a
union all
select 'solicitudes', 'quedan en el Arena con "gastronom…" en texto libre (revisar)', count(*)
from public.solicitudes where area = 'movistar_arena' and puesto_interes ~* 'gastronom'
union all
select 'personas', 'quedan en el Arena con "gastronom…" en texto libre (revisar)', count(*)
from public.personas where area = 'movistar_arena' and cv->>'puestoInteres' ~* 'gastronom'
order by 1, 2;

-- ── SI HAY QUE VOLVER ATRÁS ──
--  (No correr salvo que haga falta.)
--   update public.solicitudes s set area = r.area_antes, puesto_interes = r.puesto_antes
--   from respaldo.gastronomia_arena r where r.tabla = 'solicitudes' and s.id::text = r.id;
--   update public.personas p set area = r.area_antes,
--          cv = jsonb_set(p.cv, '{puestoInteres}', to_jsonb(coalesce(r.puesto_antes, ''))), notas = r.notas_antes
--   from respaldo.gastronomia_arena r where r.tabla = 'personas' and p.id::text = r.id;
