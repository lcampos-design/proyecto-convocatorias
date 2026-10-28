-- ============================================================
--  LOS OTROS ARCHIVOS DE CADA PERSONA, SIN PESO EN LA NÓMINA
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  Desde ahora, además del CV, la gente puede subir otros archivos
--  (carnet de manipulación de alimentos, certificados, títulos): hasta 3,
--  de 1 MB cada uno. Al aprobar la solicitud quedan en la ficha, en
--  cv.adjuntos.
--
--  La nómina se trae entera de una vez con personas_lista(), y por eso ya
--  le sacaba el contenido del CV (el archivo se baja al abrirlo). Esto hace
--  lo mismo con los otros archivos: vienen sólo el nombre y el tipo, y el
--  contenido se baja al abrir cada uno.
--
--  No toca ningún dato: sólo cambia lo que devuelve la función.
-- ============================================================

create or replace function public.personas_lista()
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select
    (to_jsonb(p) - 'cv')
    || jsonb_build_object('cv',
         case when p.cv is null then null
              else (p.cv #- '{archivo,datos}')
                   || case when jsonb_typeof(p.cv -> 'adjuntos') = 'array'
                           then jsonb_build_object('adjuntos',
                                  (select coalesce(jsonb_agg(a - 'datos'), '[]'::jsonb)
                                   from jsonb_array_elements(p.cv -> 'adjuntos') a))
                           else '{}'::jsonb end
         end)
  from public.personas p
  where public.es_admin()
  order by p.created_at;
$$;

grant execute on function public.personas_lista() to authenticated;

-- ── PARA REVISAR ──
--  Tiene que dar 0: ninguna fila de la lista trae el contenido de un archivo.
select count(*) as con_contenido
from public.personas_lista() x
where x -> 'cv' -> 'archivo' ? 'datos'
   or exists (select 1 from jsonb_array_elements(coalesce(x -> 'cv' -> 'adjuntos', '[]'::jsonb)) a where a ? 'datos');
