-- ============================================================
--  ALTAS CON DNI SUELTO → NÓMINA (ÁREA EXTERNOS)
--  Correr DESPUÉS de altas-import.sql.
--  Se puede volver a correr sin problema: no duplica.
--
--  Estas 27 personas están en la planilla con feedback, pero la planilla
--  trae sólo el DNI (8 dígitos) y no el CUIL completo. Entran igual, con el
--  DNI como documento.
--
--  POR QUÉ AHORA SÍ SE PUEDE
--  El panel comparaba documentos como texto, así que el día que una de ellas
--  se inscribiera con su CUIL completo habría quedado duplicada. Desde el
--  cambio del 21/10 compara por el núcleo del documento —el CUIL lleva el DNI
--  adentro— así que las reconoce como la misma persona.
--
--  Les falta el CUIL completo: lo van a completar al inscribirse por el
--  formulario, o se les puede pedir.
-- ============================================================

with nuevas(doc, nombre, tel, mail, nota, sem, coment) as (values
  ('48134856', 'Maria Victoria Ambuhl Titon', '1154219047', null, 'Interés: ACOMODADOR', 2, 'Promedio 3 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 3 – Estuvo orientando en las escaleras recibiendo al publico, cada tanto se ponia al costado para hablar con su compañera dejando sus tareas de lado. [prom 3.00]'),
  ('48462253', 'Mora Aragón', '1122560800', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 5 – Excelente predisposición y súper atenta a los detalles. [prom 5.00]'),
  ('47202524', 'Sol Araujo', '1121718905', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 4.5 [prom 4.50]'),
  ('47346329', 'Victoria Bellas Alvarez', '1140456950', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.25 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4.25 [prom 4.25]'),
  ('45522308', 'Serena Biondini Cianni', '1168535252', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 5 – Super predispuesta, atenta y con ganas de trabajar [prom 5.00]'),
  ('42933185', 'Agustina Blanco', '1153198567', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 5 – Muy atenta a todo, predispuesta y proactiva. Estaria bueno tenerla en cuenta para proximos eventos como staff [prom 5.00]'),
  ('46986238', 'Malena Carreras', '2966631678', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4.5 [prom 4.50]'),
  ('47083244', 'Florencia De Pascual', '1168390813', null, 'Interés: ACOMODADOR', 1, '• LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): super bien y predispuesta'),
  ('44413715', 'Sofia Dusman', '1126072023', null, 'Interés: ACOMODADOR', 1, 'Promedio 3.75 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 3.75 [prom 3.75]'),
  ('46278179', 'Martina Giovenco', '1150256112', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 5 – Me sorprendió su actitud, buena onda y predisposicion para escuchar y preguntar. Muy buena presencia con la gente. [prom 5.00]'),
  ('48430964', 'Anna Chiara Giuliano', '2215711186', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 5 [prom 5.00]'),
  ('47835556', 'Ariadna Agostina Godoy', '1134826934', null, 'Interés: ACOMODADOR', 1, 'Promedio 4 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4 [prom 4.00]'),
  ('48297413', 'Angeles Gomez', '1176619266', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.25 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 4.25 [prom 4.25]'),
  ('46990788', 'Zoe Belen Kistner', '1153181848', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.75 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4.75 – Muchas ganas, excelente manejo con el público. [prom 4.75]'),
  ('47493113', 'Clara Belen Lukra', '1169371698', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.75 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4.75 [prom 4.75]'),
  ('45431333', 'Mateo Luna', null, null, 'Interés: -', 1, 'Sin detalle en la planilla'),
  ('48165173', 'Francisco Javier Mandara', '2914191255', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 5 – El mejor de los PPS sin lugar a duda, ordeno filas de merchandising y baños ademas de filtrar el ingreso a la 314. Y siempre preguntaba cosas, medio sinverguenza pero carismatico. Y ademas, me mando mensaje para seguir sumando desde donde le toque. [prom 5.00]'),
  ('44131416', 'Rocío Mazzonelli', '1122503210', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 5 – Resolutiva y buena compañera. Es OTT pero quiere trabajar también. Gran candidata! [prom 5.00]'),
  ('48054225', 'Lucia Navarro', '2474409272', null, 'Interés: ACOMODADOR', 2, 'Promedio 3 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 3 – Estuvo orientando en las escaleras recibiendo al publico, cada tanto se ponia al costado para hablar con su compañera dejando sus tareas de lado. [prom 3.00]'),
  ('48109330', 'Sofia Pantanali', '1169550921', null, 'Interés: ACOMODADOR', 1, 'Promedio 3.5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 3.5 [prom 3.50]'),
  ('47872036', 'Lucila Royán', '1138569784', null, 'Interés: ACOMODADOR', 1, 'Promedio 4 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4 [prom 4.00]'),
  ('46960121', 'Agustina Ruiz', '1133804188', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.5 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4.5 [prom 4.50]'),
  ('48214959', 'Rosario Sofía Sanchez Cabrera', '1127121601', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.75 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 4.75 [prom 4.75]'),
  ('48368923', 'Emma Scheffer', '1176299663', null, 'Interés: ACOMODADOR', 1, 'Promedio 4.75 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 4.75 [prom 4.75]'),
  ('48765998', 'Xiomara Valles', '1166218612', null, 'Interés: ACOMODADOR', 1, 'Promedio 3.75 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): 3.75 [prom 3.75]'),
  ('46111141', 'Sofia Morena Volpi Porte', '1158133551', null, 'Interés: ACOMODADOR', 1, 'Promedio 4 / 5. • LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS UADE): 4 [prom 4.00]'),
  ('95422082', 'Angelica Zucchiatti', '1131879254', null, 'Interés: ACOMODADOR', 1, '• LALI @ RIVER (sep-26) – Acomodador: 26/9 (PPS OTT): re bien, atenta y con ganas')
), insertadas as (
  insert into public.personas (id, nombre, area, estado, email, tel, cuit, notas, semaforo)
  select gen_random_uuid(), n.nombre, 'externos', 'confirmado', n.mail, n.tel, n.doc, n.nota, n.sem
  from nuevas n
  -- No se crea si ya hay alguien con ese DNI, esté cargado suelto o dentro de un CUIL.
  where not exists (
    select 1 from public.personas p
    where ltrim(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), '0') = ltrim(n.doc, '0')
       or (length(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')) = 11
           and ltrim(substr(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), 3, 8), '0') = ltrim(n.doc, '0'))
  )
  returning id, cuit
)
insert into public.feedbacks (id, persona_id, conv_id, supervisor_id, supervisor_nombre, puntaje, comentario)
select gen_random_uuid(), i.id, null, null, 'Planilla de feedbacks', n.sem, n.coment
from insertadas i
join nuevas n on n.doc = regexp_replace(coalesce(i.cuit, ''), '\D', '', 'g');

-- Para ver cómo quedó:
--   select count(*) from public.personas where area = 'externos';
