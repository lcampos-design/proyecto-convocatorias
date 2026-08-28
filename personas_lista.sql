-- ============================================================
-- FIX Nómina en 0: la columna cv guarda el archivo en base64.
-- Traer las 217 personas con select('*') baja cientos de MB de una
-- y la consulta corta -> la Nómina queda vacía.
-- Esta función trae TODAS las columnas pero SIN el archivo pesado
-- (cv.archivo.datos). El archivo se baja por persona bajo demanda.
-- Correr en Supabase -> SQL Editor.
-- ============================================================

create or replace function public.personas_lista()
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select
    (to_jsonb(p) - 'cv')
    || jsonb_build_object('cv',
         case when p.cv is null then null
              else p.cv #- '{archivo,datos}'   -- saca SOLO el base64 pesado, deja nombre/tipo
         end)
  from public.personas p
  order by p.created_at;
$$;

grant execute on function public.personas_lista() to authenticated;
