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
--  Primero anota a quiénes y cómo estaban en respaldo.gastronomia_arena (un
--  esquema aparte que el panel no ve), y recién después cambia, y sólo las
--  filas que siguen exactamente como se anotaron. Así no importa si el
--  editor corre todo junto o de a una, o si se corta a la mitad: se vuelve
--  a correr y termina. No se borra nada.
-- ============================================================

-- ── 1) EL RESPALDO: a quiénes se les cambia y cómo estaban ──
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
alter table respaldo.gastronomia_arena add column if not exists puesto_nuevo text;

--  En la nómina, el puesto está en cv.puestoInteres (se copia de la
--  inscripción al aprobarla). "Gastronomía" cuenta sólo si es uno de los
--  puestos de la lista, tal cual se elegía en el formulario.
insert into respaldo.gastronomia_arena (tabla, id, area_antes, puesto_antes, notas_antes, paso_a, puesto_nuevo)
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
),
marcadas as (
  select tabla, id, puesto, notas,
         array_to_string(array(select x from unnest(todas) x where x !~* '^gastronom(i|í)a$'), ', ') as sin_gastro,
         -- Sin ningún puesto del Arena (lo de "Otro: …" no cuenta como tal).
         not exists (select 1 from unnest(todas) x where x !~* '^gastronom(i|í)a$' and x !~* '^otro($|[: ])') as solo_gastro
  from partes
  where exists (select 1 from unnest(todas) x where x ~* '^gastronom(i|í)a$')
)
select m.tabla, m.id, 'movistar_arena', m.puesto, m.notas,
       case when m.solo_gastro then 'externos' else 'movistar_arena (sin Gastronomía)' end,
       case when m.solo_gastro then m.puesto else m.sin_gastro end
from marcadas m
-- Si una corrida anterior ya la anotó y se cortó antes de cambiarla, no se anota dos veces.
where not exists (select 1 from respaldo.gastronomia_arena r
                  where r.tabla = m.tabla and r.id = m.id and r.puesto_antes is not distinct from m.puesto);

-- ── 2) SÓLO GASTRONOMÍA: A EXTERNOS ──
--  (Sólo si sigue en el Arena con el mismo puesto que se anotó.)
update public.solicitudes s set area = 'externos'
from respaldo.gastronomia_arena r
where r.tabla = 'solicitudes' and r.paso_a = 'externos' and s.id::text = r.id
  and s.area = 'movistar_arena' and s.puesto_interes is not distinct from r.puesto_antes;

update public.personas p set area = 'externos'
from respaldo.gastronomia_arena r
where r.tabla = 'personas' and r.paso_a = 'externos' and p.id::text = r.id
  and p.area = 'movistar_arena' and (p.cv->>'puestoInteres') is not distinct from r.puesto_antes;

-- ── 3) ARENA Y OTROS PUESTOS: SE QUEDAN, SIN "GASTRONOMÍA" ──
update public.solicitudes s set puesto_interes = r.puesto_nuevo
from respaldo.gastronomia_arena r
where r.tabla = 'solicitudes' and r.paso_a <> 'externos' and s.id::text = r.id
  and s.area = 'movistar_arena' and s.puesto_interes is not distinct from r.puesto_antes;

--  En la nómina, también la nota "Interés: …" que se armó al aprobar (si nadie la cambió).
update public.personas p
set cv = jsonb_set(p.cv, '{puestoInteres}', to_jsonb(coalesce(r.puesto_nuevo, ''))),
    notas = case when p.notas = 'Interés: ' || r.puesto_antes then 'Interés: ' || r.puesto_nuevo else p.notas end
from respaldo.gastronomia_arena r
where r.tabla = 'personas' and r.paso_a <> 'externos' and p.id::text = r.id
  and p.area = 'movistar_arena' and (p.cv->>'puestoInteres') is not distinct from r.puesto_antes;

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
