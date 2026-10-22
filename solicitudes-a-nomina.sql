-- ============================================================
--  LAS 5.900 INSCRIPCIONES PENDIENTES, A LA NÓMINA
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no duplica a nadie.
--
--  QUÉ HAY
--  Por el formulario público entran unas 2.500 personas por mes. Para poder
--  convocarlas, alguien tiene que aprobarlas de a una desde Solicitudes, y
--  eso no lo hace nadie porque no se puede: son 5.938 personas distintas
--  esperando desde julio, mientras se convoca siempre de las mismas 1.676.
--
--  LO QUE PIDIÓ MERCEDES (18/10)
--  "Que pueda filtrar masivamente para seleccionar y pasar a nómina; si
--  tiene antecedentes penales o cobra beneficio social, que los pueda
--  seleccionar a todos, aceptar y poner en OUT."
--
--  LO QUE HACE ESTE ARCHIVO, SIGUIENDO ESA REGLA
--   · Cada inscripción pendiente pasa a la nómina con los mismos datos que
--     carga el panel al aprobar: nombre, área, mail, teléfono, documento,
--     el puesto de interés como nota y lo que escribió en el formulario.
--   · Entran como "pendiente" —que ya existe y quiere decir "nunca la
--     contactamos"— y no como "confirmada": así se distinguen de un vistazo
--     de las 1.676 que ya trabajaron.
--   · Quien declaró antecedentes penales o beneficio social entra igual,
--     pero marcada OUT con el motivo escrito. Se puede sacar del OUT de a
--     una desde el panel si alguien lo revisa.
--   · Si la misma persona se anotó dos veces, entra una sola vez.
--   · Si ya estaba en la nómina, no se la crea de nuevo.
--   · No se manda ningún mail a nadie.
--
--  Todo lo que toca queda marcado con 'solicitudes-2026-10-22': las personas
--  que entran y las inscripciones que se cierran. Así se puede volver atrás
--  con exactitud, sin rozar nada que ya estuviera.
-- ============================================================

alter table public.personas    add column if not exists origen       text;
alter table public.solicitudes add column if not exists aprobada_por text;

-- El núcleo del documento (el DNI adentro del CUIL), igual que lo compara el
-- panel. Se crea para este archivo y se borra al final.
create or replace function public._nucleo_doc(v text)
returns text language sql immutable as $$
  select ltrim(case when length(regexp_replace(coalesce(v, ''), '\D', '', 'g')) = 11
                    then substr(regexp_replace(coalesce(v, ''), '\D', '', 'g'), 3, 8)
                    else regexp_replace(coalesce(v, ''), '\D', '', 'g') end, '0');
$$;

-- ── 1) DAR DE ALTA A LAS QUE NO ESTÁN ──
--  De cada documento, la inscripción más reciente. Si ya hay una persona con
--  ese documento, no se crea otra.
insert into public.personas
  (id, nombre, area, estado, email, tel, cuit, notas, cv, out_flag, out_categoria, out_nota, origen)
select gen_random_uuid(),
       e.nombre,
       e.area,
       'pendiente',
       nullif(btrim(coalesce(e.email, '')), ''),
       nullif(btrim(coalesce(e.tel, '')), ''),
       nullif(btrim(coalesce(e.cuit, '')), ''),
       case when nullif(btrim(coalesce(e.puesto_interes, '')), '') is not null
            then 'Interés: ' || btrim(e.puesto_interes) end,
       jsonb_build_object(
         'puestoInteres',  coalesce(e.puesto_interes, ''),
         'experiencia',    coalesce(e.experiencia, ''),
         'formacion',      coalesce(e.formacion, ''),
         'habilidades',    coalesce(e.habilidades, ''),
         'disponibilidad', coalesce(e.disponibilidad, ''),
         'fechaEnvio',     coalesce(to_char(e.created_at, 'YYYY-MM-DD'), ''),
         'archivo',        e.archivo_cv
       ),
       -- La regla de Mercedes: con antecedentes o beneficio, OUT con el motivo.
       coalesce(e.antecedentes, false) or coalesce(e.beneficio_social, false),
       case when coalesce(e.antecedentes, false)     then 'legal'
            when coalesce(e.beneficio_social, false) then 'situacion' end,
       case when coalesce(e.antecedentes, false) and coalesce(e.beneficio_social, false)
              then 'Declaró antecedentes penales y que cobra un beneficio social, al inscribirse'
            when coalesce(e.antecedentes, false)     then 'Declaró antecedentes penales al inscribirse'
            when coalesce(e.beneficio_social, false) then 'Declaró que cobra un beneficio social, al inscribirse' end,
       'solicitudes-2026-10-22'
from (
  select distinct on (coalesce(nullif(public._nucleo_doc(s.cuit), ''), s.id::text)) s.*
  from public.solicitudes s
  where s.estado = 'pendiente'
  order by coalesce(nullif(public._nucleo_doc(s.cuit), ''), s.id::text), s.created_at desc
) e
where not exists (
  select 1 from public.personas p
  where length(public._nucleo_doc(p.cuit)) >= 6
    and public._nucleo_doc(p.cuit) = public._nucleo_doc(e.cuit)
);

-- ── 2) LAS INSCRIPCIONES QUEDAN COMO APROBADAS ──
--  Todas las pendientes, incluidas las repetidas y las de quien ya estaba:
--  ya no hay nada que revisar ahí. Quedan marcadas para poder volver atrás.
update public.solicitudes
   set estado = 'aprobado', aprobada_por = 'solicitudes-2026-10-22'
 where estado = 'pendiente';

drop function if exists public._nucleo_doc(text);

-- ── CÓMO QUEDÓ ──
select count(*)                                            as entraron,
       count(*) filter (where out_flag)                     as de_esas_en_out,
       count(*) filter (where out_categoria = 'legal')      as por_antecedentes,
       count(*) filter (where out_categoria = 'situacion')  as por_beneficio_social,
       count(*) filter (where area = 'movistar_arena')      as movistar_arena,
       count(*) filter (where area = 'externos')            as externos,
       count(*) filter (where area = 'espana')              as espana
from public.personas where origen = 'solicitudes-2026-10-22';

select count(*) as inscripciones_que_siguen_pendientes
from public.solicitudes where estado = 'pendiente';
--  Tiene que dar 0.

-- ── PARA VOLVER ATRÁS, SI ALGO NO CIERRA ──
--  Saca exactamente a las que entraron por acá y reabre exactamente las
--  inscripciones que cerró. Lo que ya estaba antes no se toca.
--   delete from public.personas    where origen = 'solicitudes-2026-10-22';
--   update public.solicitudes set estado = 'pendiente', aprobada_por = null
--    where aprobada_por = 'solicitudes-2026-10-22';
