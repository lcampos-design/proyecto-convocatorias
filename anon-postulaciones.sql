-- ============================================================
--  CERRAR LA LECTURA ABIERTA DE POSTULACIONES
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  ⚠ CORRER DESPUÉS DE QUE EL CAMBIO DE postulate.html ESTÉ ARRIBA.
--    Este archivo le saca a la página el permiso de leer la tabla, y se lo
--    cambia por dos funciones. Si se corre antes del deploy, entre una cosa
--    y la otra la página de inscripción no va a mostrar los cupos.
--    Si eso pasa igual: abajo está cómo volver atrás en una línea.
--
--  EL PROBLEMA
--  La página donde la gente se anota no pide usuario. Para funcionar
--  necesita saber tres cosas de la tabla de postulaciones:
--     · cuántos lugares quedan en cada puesto,
--     · si quien está escribiendo su CUIL ya se anotó,
--     · cuáles son sus inscripciones, para poder darse de baja.
--  La regla que lo permitía decía "dejá leer", sin más. Y como la clave
--  pública está a la vista en el código de la página, cualquiera podía
--  pedir la tabla entera: el nombre y el CUIL de toda la gente anotada.
--
--  LA SOLUCIÓN
--  Dos funciones que devuelven sólo esas tres cosas, y que corren con
--  permisos propios. Después la regla abierta se saca.
--     · cupos_ocupados()  → cuántos hay anotados en cada puesto, nada más:
--                            números, ningún dato de nadie.
--     · mis_postulaciones(cuil) → las inscripciones de ESE documento.
--                            Exige el CUIL completo, así una consulta vacía
--                            no devuelve todo.
--  Es el mismo camino que ya usan crear_postulacion, esta_registrado y
--  dar_de_baja en esa misma página.
-- ============================================================

-- ── 1) CUÁNTOS LUGARES ESTÁN TOMADOS ──
--  Sólo de convocatorias publicadas, que son las únicas que se muestran.
--  Devuelve { "<id del puesto>": cantidad }.
create or replace function public.cupos_ocupados()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(t.puesto_id::text, t.n), '{}'::jsonb)
  from (
    select p.puesto_id, count(*) as n
    from public.postulaciones p
    join public.convocatorias c on c.id = p.conv_id
    where c.publicada
      and p.puesto_id is not null
      and coalesce(p.estado, '') <> 'rechazado'
    group by p.puesto_id
  ) t;
$$;

-- ── 2) LAS INSCRIPCIONES DE UN DOCUMENTO ──
--  Trae también el nombre de la convocatoria y del puesto, así la página no
--  tiene que ir a buscarlos aparte. De paso arregla algo que hoy falla: si
--  la convocatoria ya no está publicada, el nombre salía en blanco.
--  El documento se compara por los números, sin guiones: cómo esté escrito
--  en la base deja de importar.
create or replace function public.mis_postulaciones(p_cuit text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'conv_id', p.conv_id,
           'puesto_id', p.puesto_id,
           'estado', p.estado,
           'conv_nombre', c.nombre,
           'conv_fecha', c.fecha,
           'puesto_nombre', q.nombre
         )), '[]'::jsonb)
  from public.postulaciones p
  left join public.convocatorias c on c.id = p.conv_id
  left join public.puestos q on q.id = p.puesto_id
  -- Sin el CUIL entero no devuelve nada: si no, pedir "" sería pedir todo.
  where length(regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g')) = 11
    and regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')
      = regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g');
$$;

grant execute on function public.cupos_ocupados()            to anon, authenticated;
grant execute on function public.mis_postulaciones(text)     to anon, authenticated;

-- ── 3) CERRAR LA PUERTA ──
drop policy if exists anon_select on public.postulaciones;
revoke select on public.postulaciones from anon;

-- ── CÓMO QUEDÓ ──
--  De postulaciones no tendría que quedar ninguna regla para anon.
select tablename, policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public' and roles && array['anon', 'public']::name[]
order by tablename, policyname;

--  Y esto tiene que seguir devolviendo los números de siempre:
--    select public.cupos_ocupados();

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--   grant select on public.postulaciones to anon;
--   create policy anon_select on public.postulaciones for select to anon using (true);
