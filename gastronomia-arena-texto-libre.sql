-- ============================================================
--  GASTRONOMÍA FUERA DE MOVISTAR ARENA (2): LOS TEXTOS LIBRES
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema (la segunda vez no encuentra nada).
--
--  El primer script (gastronomia-arena-a-externos.sql) arregló a los que
--  eligieron "Gastronomía" de la lista. Quedaron los que lo escribieron a
--  mano, de antes de que el formulario tuviera la lista: "Bartender",
--  "Acomodadores y bartenders", "Acomodadores, runner, barra"… Misma regla,
--  con las mismas palabras que usa el filtro de puestos del panel
--  (gastronomía, gastronómico, barra, bartender, mozo, camarero/a):
--
--   · Si no nombra ningún puesto del Arena (acomodador, orientador,
--     stagehand / cargas, supervisor / coordinador / encargado), pasa a
--     Externos, con el texto como estaba.
--   · Si nombra alguno, se queda en el Arena y se le saca del texto sólo la
--     parte de gastronomía: "Acomodadores, runner, barra" queda
--     "Acomodadores, runner".
--
--  Vale para Postulantes y para la Nómina. Antes de cambiar, anota cómo
--  estaba cada fila en respaldo.gastronomia_arena_texto, y cambia sólo las
--  que siguen exactamente así. Al final muestra la lista de lo que cambió.
-- ============================================================

-- ── 1) EL RESPALDO: a quiénes se les cambia y cómo estaban ──
create schema if not exists respaldo;
revoke all on schema respaldo from public, anon, authenticated;
create table if not exists respaldo.gastronomia_arena_texto (
  tabla        text not null,
  id           text not null,
  area_antes   text not null,
  puesto_antes text,
  notas_antes  text,
  paso_a       text not null,   -- 'externos' o 'movistar_arena (sin gastronomía)'
  puesto_nuevo text,
  cuando       timestamptz not null default now()
);

insert into respaldo.gastronomia_arena_texto (tabla, id, area_antes, puesto_antes, notas_antes, paso_a, puesto_nuevo)
with base as (
  select 'solicitudes'::text as tabla, id::text as id, puesto_interes as puesto, null::text as notas
  from public.solicitudes
  where area = 'movistar_arena'
  union all
  select 'personas', id::text, cv->>'puestoInteres', notas
  from public.personas
  where area = 'movistar_arena' and cv is not null
),
-- Sin mayúsculas ni tildes, para buscar las palabras.
pelado as (
  select b.*, translate(lower(coalesce(b.puesto, '')), 'áéíóúüñàèìòù', 'aeiouunaeiou') as p
  from base b
),
marcadas as (
  select tabla, id, puesto, notas,
         p ~ '(acomod|orient|stage|montaj|supervis|coordin|encargad)|(^|[^a-z])carga' as del_arena
  from pelado
  where p ~ '(gastro|barra|bartend|mozo|camarer)'
)
select m.tabla, m.id, 'movistar_arena', m.puesto, m.notas,
       case when m.del_arena then 'movistar_arena (sin gastronomía)' else 'externos' end,
       case when not m.del_arena then m.puesto
            -- Se parte el texto en sus pedazos (comas, barras, puntos, "y", "o")
            -- y se sacan los de gastronomía que no nombran un puesto del Arena.
            else (select string_agg(btrim(t.seg), ', ' order by t.n)
                  from regexp_split_to_table(m.puesto, '\s*([,;/.]|\s+y\s+|\s+o\s+)\s*') with ordinality as t(seg, n)
                  where btrim(t.seg) <> ''
                    and not (translate(lower(t.seg), 'áéíóúüñàèìòù', 'aeiouunaeiou') ~ '(gastro|barra|bartend|mozo|camarer)'
                             and translate(lower(t.seg), 'áéíóúüñàèìòù', 'aeiouunaeiou') !~ '(acomod|orient|stage|montaj|supervis|coordin|encargad)|(^|[^a-z])carga'))
       end
from marcadas m
-- Si una corrida anterior ya la anotó y se cortó antes de cambiarla, no se anota dos veces.
where not exists (select 1 from respaldo.gastronomia_arena_texto r
                  where r.tabla = m.tabla and r.id = m.id and r.puesto_antes is not distinct from m.puesto);

-- ── 2) SIN PUESTO DEL ARENA: A EXTERNOS ──
--  (Sólo si sigue en el Arena con el mismo texto que se anotó.)
update public.solicitudes s set area = 'externos'
from respaldo.gastronomia_arena_texto r
where r.tabla = 'solicitudes' and r.paso_a = 'externos' and s.id::text = r.id
  and s.area = 'movistar_arena' and s.puesto_interes is not distinct from r.puesto_antes;

update public.personas p set area = 'externos'
from respaldo.gastronomia_arena_texto r
where r.tabla = 'personas' and r.paso_a = 'externos' and p.id::text = r.id
  and p.area = 'movistar_arena' and (p.cv->>'puestoInteres') is not distinct from r.puesto_antes;

-- ── 3) CON PUESTO DEL ARENA: SE QUEDAN, SIN LA PARTE DE GASTRONOMÍA ──
update public.solicitudes s set puesto_interes = r.puesto_nuevo
from respaldo.gastronomia_arena_texto r
where r.tabla = 'solicitudes' and r.paso_a <> 'externos' and s.id::text = r.id
  and s.area = 'movistar_arena' and s.puesto_interes is not distinct from r.puesto_antes;

--  En la nómina, también la nota "Interés: …" que se armó al aprobar (si nadie la cambió).
update public.personas p
set cv = jsonb_set(p.cv, '{puestoInteres}', to_jsonb(coalesce(r.puesto_nuevo, ''))),
    notas = case when p.notas = 'Interés: ' || r.puesto_antes then 'Interés: ' || r.puesto_nuevo else p.notas end
from respaldo.gastronomia_arena_texto r
where r.tabla = 'personas' and r.paso_a <> 'externos' and p.id::text = r.id
  and p.area = 'movistar_arena' and (p.cv->>'puestoInteres') is not distinct from r.puesto_antes;

-- ── CÓMO QUEDÓ: uno por uno ──
--  Lo que cambió (para revisarlo de una mirada) y, al final, si queda alguno
--  en el Arena que todavía nombre la gastronomía.
select * from (
  select r.tabla, coalesce(s.nombre, pe.nombre) as nombre, r.paso_a as que_paso,
         r.puesto_antes as antes, r.puesto_nuevo as ahora
  from respaldo.gastronomia_arena_texto r
  left join public.solicitudes s on r.tabla = 'solicitudes' and s.id::text = r.id
  left join public.personas pe on r.tabla = 'personas' and pe.id::text = r.id
  union all
  select 'quedan', null, 'en el Arena con gastronomía (revisar)', count(*)::text, null
  from public.solicitudes
  where area = 'movistar_arena' and translate(lower(coalesce(puesto_interes, '')), 'áéíóúüñàèìòù', 'aeiouunaeiou') ~ '(gastro|barra|bartend|mozo|camarer)'
) x
order by (tabla = 'quedan'), tabla, que_paso, nombre;

-- ── SI HAY QUE VOLVER ATRÁS ──
--  (No correr salvo que haga falta.)
--   update public.solicitudes s set area = r.area_antes, puesto_interes = r.puesto_antes
--   from respaldo.gastronomia_arena_texto r where r.tabla = 'solicitudes' and s.id::text = r.id;
--   update public.personas p set area = r.area_antes,
--          cv = jsonb_set(p.cv, '{puestoInteres}', to_jsonb(coalesce(r.puesto_antes, ''))), notas = r.notas_antes
--   from respaldo.gastronomia_arena_texto r where r.tabla = 'personas' and p.id::text = r.id;
