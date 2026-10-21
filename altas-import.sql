-- ============================================================
--  ALTAS DE LA PLANILLA → NÓMINA (ÁREA EXTERNOS)
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no duplica.
--
--  Da de alta a las personas que están en la planilla del semáforo con
--  feedback, pero que todavía no tenían ficha en la nómina.
--
--  QUÉ CARGA
--   · Nombre, CUIL, celular, mail y la posición como nota.
--   · Área: Externos, y estado Confirmado.
--   · El semáforo y el feedback de la planilla, igual que en feedbacks-import.
--
--  QUÉ NO CARGA
--   · CV, datos bancarios ni declaración jurada: eso no está en la planilla.
--     Lo van a completar cuando la persona se inscriba por el formulario.
--
--  Da de alta 90 personas.
--  Quedan afuera 31 con el CUIL mal cargado en la planilla
--  (ver abajo): hay que corregirles el documento antes de poder darlas de alta.
-- ============================================================

with nuevas(doc, nombre, tel, mail, nota, sem, coment) as (values
  ('27482410095', 'Eugenia Abregu Cullen', '1135079997', null, 'Interés: ACOMODADOR', 1, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Acomodador: 13/9: 5 – Muy resolutiva, actitud destacable; 19/9: 4.75 [prom 4.88]'),
  ('20483904941', 'Juan Pablo Aceval', '1128579637', null, 'Interés: ACOMODADOR', 1, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Supervisión (feedback Marcos Monti, 20/9): Muy buena predisposición, entendió rápido las tareas a realizar, trabajó bien • PÁDEL SENIOR PQ. ROCA (sep-26) – Acomodador: 13/9: 5 – Muy resolutivo, actitud destacable [prom 5.00]'),
  ('27411288205', 'Nayla Amen', '1127117797', 'nayamen98@gmail.com', 'Interés: OP (ACRED)', 1, '• ACRED TAN BIONICA: Nayla asistió gran parte del armado y del desarme, es alguien que está hace mucho tiempo y conoce mucho Vélez, es proactiva y muy predispuesta en todo momento, algo muy valorable.'),
  ('23284527569', 'Juan Manuel Arana', '1160275025', null, 'Interés: ORIENTADOR / ACOMODADOR', 1, 'Promedio 4 / 5. • ROAD SHOW COLAPINTO: Se desenvuelve muy bien, muy proactivo y atento con el público • AC/DC 1: Muy bien, super atento con el público • ALE SANZ 1: Bien predispuesto y atento • AIRBAG (jun-26): Cumplió con su trabajo, poca iniciativa [puntaje 4.0]'),
  ('20465826216', 'Alejandro Aveldaño', '1126887024', null, 'Interés: ACOMODADOR', 1, '• ALE SANZ 1: Muy buena predisposición.'),
  ('20469937284', 'Matías Nicolas Banegas', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • AIRBAG (jun-26): Muy buena predisposición e iniciativa [puntaje 5.0]'),
  ('20430870883', 'Santiago Juan Bardi', '1136636863', null, 'Interés: ORIENTADOR', 3, 'Promedio 1.75 / 5. • AC/DC 3: Probo un nuevo sector dentro del equipo y le fue muy bien, supo resolver cada problema que se presentaba. • AC/DC 1: Muy buen desempeño durante la jornada. predispuesto y atento con el público • ALE SANZ 2: Bien predispuesto y atento • ECOPARQUE: Se dispersaba mucho, y no sabía medir su forma de hablar frente a encargados/responsables. Además afectaba de manera negativa en el grupo con algunos comentarios (ej: cantar canciones de fútbol eufóricamente mientras laboraba). Concluyeron que ya no sea tenido en cuenta como un buen recurso [puntaje 1.75 - Rojo]'),
  ('20297293274', 'Hugo Alejandro Barzola', '1165270428', null, 'Interés: ACOMODADOR', 1, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Acomodador: 17/9: 5 – Me salvaron, muy buena predisposición para ayudar a los compañeros [prom 5.00]'),
  ('27408479687', 'Barbara Benítez', '1139262264', null, 'Interés: ACOMODADOR', 1, 'Promedio 5 / 5. • AC/DC 3: Muy bien • AIRBAG (jun-26): Muy buena predisposición [puntaje 5.0]'),
  ('27441856402', 'Luana Berman', null, null, 'Interés: -', 1, 'Sin detalle en la planilla'),
  ('27454128147', 'Camila Bianchi', '3413823910', null, 'Interés: ACOMODADOR', 1, '• ALE SANZ 2: Muy bien'),
  ('27425386080', 'Sofía Billinger', '2345458001', 'Sofiamacchiaroli@hotmail.com', 'Interés: OP (ACRED)', 3, '• RRHH (22/9/2026): OUT confirmado por Mercedes (figuraba OUT en CERCANIAS ACRED) – no convocar • ACRED ALE SANZ: Tiene cintura para responder. Falta iniciativa, como operador va muy bien • ACRED LOLLAPALOOZA: Operadora nueva, con buena predisposición y trato adecuado. Se recomienda trabajar en el control de su entusiasmo frente a situaciones particulares, como la presencia de personalidades o artistas en ventanilla, para mantener la profesionalidad del rol.'),
  ('27465007694', 'Chiara Bisaccia', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 4 / 5. • AIRBAG (jun-26): Cumplió con su trabajo, se cuelga hablando [puntaje 4.0]'),
  ('27456234998', 'Zoe Verenice Britos', '1122870738', 'zoe.v.britossss@gmail.com', 'Interés: EQUIPO OPERACIONES / OP (ACRED)', 1, '• ACRED BAD BUNNY: Destaco por ser: proactivos, dispuestos a ayudar, y atentos. • ACRED LOLLAPALOOZA: Cuenta con un trato amable y una personalidad muy agradable, lo cual favorece el vínculo con el entorno laboral. No obstante, en situaciones de presión puede reaccionar con cierta facilidad al enojo, tanto con proveedores como con encargados. Se recomienda trabajar en la gestión de estas situaciones para potenciar su desempeño general. • RRHH OPERACIONES: Quiere probar: Supervisor: gestión de liderazgo, trabajo en equipos, comunicación efectiva — Sabe leer documentación, es proactiva y está ab…'),
  ('27362158430', 'Amparo Buceta', '1122548230', null, 'Interés: ACOMODADOR', 1, '• AC/DC 1: Muy bien'),
  ('27929783455', 'Alexandra Caballero', '1161893991', null, 'Interés: ORIENTADOR', 1, '• AC/DC 2: Muy bien • BAD BUNNY 1: Muy buena predispocision,super atenta y en cualquier punto que se encuentre trabaja muy bien • BAD BUNNY 2: Muy buena predispocision,super atenta y en cualquier punto que se encuentre trabaja muy bien'),
  ('27369158797', 'Pamela Soledad Cacciabue', null, null, 'Interés: -', 1, 'Sin detalle en la planilla'),
  ('27472574510', 'Chandra Francisca Calistro Barzola', '1134388846', null, 'Interés: ORIENTADOR', 1, '• ALE SANZ 1: muy buen desempeño'),
  ('20417771728', 'Gabriel Ariel Candia Mejías', '1127031562', null, 'Interés: ACOMODADOR', 3, '• AC/DC 1 ⚠: No cumple con las normas que se le dice, complicó el trabajo en equipo. • AC/DC 2 ⚠: Sentado en la escalera, poca actitud.(mer)'),
  ('27380668586', 'Dalma Marina Cardinale', '1158430486', null, 'Interés: ACOMODADOR', 2, 'Promedio 2.5 / 5. • BAD BUNNY 2: Buena atencion al publico, proactivo, con ganas y atento a las indicaciones. • BAD BUNNY 3: Buena atencion al publico, proactivo, con ganas y atento a las indicaciones. • AIRBAG (jun-26): Poca iniciativa en general, le pasa la gente por el costado y no se mueve ni para ayudarlos [puntaje 2.5]'),
  ('27479290658', 'Delfina Carnevali Amado', '2995820951', null, 'Interés: ACOMODADOR', 1, '• AC/DC 1: Muy bien'),
  ('20957962328', 'Rubén José Castillo Paez', '1160163980', null, 'Interés: ORIENTADOR', 1, '• ALE SANZ 1: muy proactivo ordenando al público'),
  ('20448369820', 'Lautaro Corvalan', '2364583167', null, 'Interés: ACOMODADOR', 1, '• BAD BUNNY 3: Probar en acred'),
  ('20448580661', 'Tomas Dallochio', null, null, 'Interés: -', 1, 'Sin detalle en la planilla'),
  ('27455003070', 'Sol Dordoni', '2474511068', null, 'Interés: ACOMODADOR', 1, '• ALE SANZ 2: derivadora, simpática, activa, muy linda energía, predispuesta,buena compañera..'),
  ('27424699328', 'Candela Etcheverry', '1134598237', null, 'Interés: ACOMODADOR', 3, '• BAD BUNNY 3 ⚠: Se fue a la platea contraria (con chaleco y pulsera) con la excusa de ir al baño.'),
  ('27455846566', 'Aixa Feijoo', '1140481138', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Trabajó super bien y me buscaba si había algún tema para ver hasta para prevenir • AC/DC 1: Gran trabajo y muy atenta a situaciones que surgían • AC/DC 1: Gran trabajo y muy atenta a situaciones que surgían'),
  ('23384420109', 'Damián Fernández', null, null, 'Interés: ORIENTADOR', 2, 'Promedio 3 / 5. • ECOPARQUE: Buen recurso, entendía la dinámica (similar a la del Arena). Cumplió correctamente, mucha predisposición para aprender. [puntaje 3.0 - Amarillo]'),
  ('27446405050', 'Mora Flores', '1162591066', 'moraflores601@gmail.com', 'Interés: OP (ACRED)', 3, '• ACRED ULTRA: Muy perdida, también se ponía nerviosa al hablar con las personas, no estaba atenta.'),
  ('20452034833', 'Mateo Francini', '1126803860', 'mateofranciniag@gmail.com', 'Interés: OP (ACRED)', 1, '• ACRED BAD BUNNY: Supo manejarse hiper bien, reteniendo todas las indicaciones y resolviendo muy bien. Me parece tambien super destacable el desempeño! • ACRED ALE SANZ: Educado, buena predispocision. estuvo como comodin haciendo seguridad y funciono muy bien. • ACRED AC/DC: Responde bien ante lo que se le solicita y es comunicativo con sus compañeros y superiores. Deberia mejorar la fluidez a la hora de acreditar y liberar la ventanilla.'),
  ('27457863549', 'Lola Galliano', '1123822798', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Trabajó muy bien. Se nota la experiencia para resolver asuntos • AC/DC 1: Bastanta experiencia en acomodadores y muy predispuesta con sus compañeras de sector para ayudar y enseñarles'),
  ('23366891404', 'Rocío Belén Gaona', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 4 / 5. • AIRBAG (jun-26): Trabajó bien. No tuvo problemas en el sector, no sobresale [puntaje 4.0]'),
  ('27462141284', 'Florencia Garcia', '1169184836', null, 'Interés: ACOMODADOR', 3, '• ALE SANZ 1 ⚠: VINO EN VESTIDO • ALE SANZ 2 ⚠: VINO EN VESTIDO'),
  ('23446906674', 'Victoria García Burgos', '1169304419', null, 'Interés: ACOMODADOR', 3, '• AC/DC 3 ⚠: Llegó tarde, se cambió a otro lugar que no la asigné para estar con sus amigas, poco sociable con la gente y se descompensó así que se fue antes'),
  ('27420892271', 'Emiliana Gasparini', '2235814691', null, 'Interés: ORIENTADOR / ACOMODADOR', 2, 'Promedio 2.5 / 5. • ROAD SHOW COLAPINTO: Se desenvuelve muy bien, muy proactiva y atenta con el público • AC/DC 2: Muy bien, buena predisposicion y super atenta. Supo resolver cada problema que se le presento • AC/DC 1: Muy bien • ALE SANZ 1: buen desempeño • ALE SANZ 2: buen desempeño • AIRBAG (jun-26): Le tuve que llamar la atencion varias veces porque se sentaba/apoyaba en las sillas vacias. [puntaje 2.5]'),
  ('27450746180', 'Catalina Genta Silvini', null, null, 'Interés: ORIENTADOR', 2, 'Promedio 3 / 5. • ECOPARQUE: Buen recurso que destaca individualmente; cuando está acompañada se dispersa. [puntaje 3.0 - Amarillo]'),
  ('27445999690', 'Agustina Gil', null, null, 'Interés: -', 1, 'Sin detalle en la planilla'),
  ('20454603169', 'Bautista Girolami', '2494249263', null, 'Interés: ORIENTADOR / ACOMODADOR', 1, 'Promedio 3.5 / 5. • ALE SANZ 2: Buena predisposición. Amable. Proactivo. Acude para resolver problemas cuando fue necesario. • AIRBAG (jun-26): Trabajó bien. No tuvo problemas en el sector. [puntaje 4.0] • ECOPARQUE: Buen potencial, proactivo y educado. Vino solo un día, debemos examinarlo más. [puntaje 3.0 - Amarillo]'),
  ('27964668200', 'Luciano Ramallo Glasinovic', '1177554140', null, 'Interés: ACOMODADOR', 2, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Supervisión (feedback Marcos Monti, 20/9): Trabajando estuvo bien pero llegó muy tarde en reiteradas ocasiones'),
  ('27447492097', 'Julieta Gómez', '1157985004', 'Julietamagaligomez@hotmail.com', 'Interés: OP (ACRED)', 2, '• ACRED LOLLAPALOOZA: Cumplió bien con lo asignado. Se adaptó al ritmo sin problemas y mantuvo buena predisposición.'),
  ('27457873757', 'Zoe Gomez', '1151641800', null, 'Interés: ACOMODADOR', 1, '• ALE SANZ 2: Buena predisposición. Proactiva. Acude para resolver problemas cuendo fue necesario.'),
  ('27470309275', 'Manuela Gonzales Biscia', null, null, 'Interés: ORIENTADOR', 1, 'Promedio 3.5 / 5. • ECOPARQUE: Perfil muy extrovertido, se integró rápido, muy buena predisposición. Gran recurso [puntaje 3.5 - Verde]'),
  ('27475692565', 'Victoria Gonzalez Villalba', '1167997429', null, 'Interés: ACOMODADOR', 1, 'Promedio 3.5 / 5. • AC/DC 3: Súper atenta y amable con la gente • AC/DC 1: Muy bien • AC/DC 1: Muy bien • AIRBAG (jun-26): Cumple su trabajo pero se cuelga. [puntaje 3.5]'),
  ('27958711544', 'Lina Herrera', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 3.5 / 5. • AIRBAG (jun-26): Trabajó bien. No tuvo problemas en el sector. [puntaje 3.5]'),
  ('20411695833', 'Gustavo Ibañez', '1150287865', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Atento y trabaja muy bien en equipo'),
  ('27945076262', 'Zarita Inca', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 3.75 / 5. • AIRBAG (jun-26): Trabajo bien y cumplio su puesto sin problemas. [puntaje 3.75]'),
  ('23358302114', 'Milena Lucía Kohan', '1154192344', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Acomodadora de último momento.. Me dijo que era su primera vez, súper atenta a todo!'),
  ('27426143637', 'Nadia Selene Konaszuk', '3754400301', null, 'Interés: ACOMODADOR', 1, '• ALE SANZ 2: Gran predisposición y energía a la hora de trabajar, recomendable para otros eventos'),
  ('27402404839', 'Soraya Ailén Lencinas', '1137620996', null, 'Interés: ACOMODADOR / HIDRATACIÓN', 2, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Hidratación: 16/9: 4.5 – Vino un solo día, no comprendió las reglas del pádel pero muy buena predisposición para aprender; 19/9: 4.25 – Se va de su puesto de trabajo pese a las indicaciones del supervisor [prom 4.38] • ROAD SHOW COLAPINTO: Muy mal, se iba constantemente de su puesto sin avisar, se fue en un lapso largo con la excusa de que iba al baño. En otros shows hizo lo mismo, muestra disposición y ayuda pero aveces desaparece sin avisar a nadie. No le daría otra oportunidad, pero en el caso de que le dé una chance más, avisar al supervisor al cargo de e…'),
  ('20353994728', 'Diego Macias', null, null, 'Interés: -', 1, 'Sin detalle en la planilla'),
  ('27306552339', 'María Celeste Manzoli', '1553864402', null, 'Interés: ORIENTADOR', 1, '• AC/DC 2: Perfil acreditaciones. Buena predisposición y orden. Experiencia previa en supervisión. • AC/DC 1: Muy buena predispoción, ayudó a los chicos nuevos, perfil acreditaciones.'),
  ('27356749567', 'Yanina Paola Mariani', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 3.87 / 5. • AIRBAG (jun-26): Trabajo bien y cumplio su puesto sin problemas. [puntaje 3.87]'),
  ('27316623560', 'Lucía Marmoria', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 3.75 / 5. • AIRBAG (jun-26): Trabajo bien, le falto mas iniciativa con la gente. [puntaje 3.75]'),
  ('20451329953', 'Lautaro Martínez', '1138160293', null, 'Interés: ACOMODADOR', 1, '• ROAD SHOW COLAPINTO: Hubo momentos tensos que necesitabamos ponernos firmes y no tubo problemas. Respondio excelente. Estaba sobrecargada la platea, pero se pudo acomodar a todos. • AC/DC 3: Muy bien, siempre predispuesto • AC/DC 2: Muy buena predisposición, siempre atento y ante cualquier duda siempre me consultaba para resolver de manera correcta • AC/DC 1: Muy bien.'),
  ('27413169084', 'Karen Miller', '1134933250', 'karumiller@gmail.com', 'Interés: EQUIPO OPERACIONES / OP (ACRED)', 1, '• ACRED LOLLAPALOOZA: Demostró una buena actitud y desenvolvimiento en la interacción con proveedores, desempeñándose de manera adecuada en el rol. Se adapta especialmente bien a los turnos de la tarde, donde su rendimiento resulta óptimo. Como aspecto a mejorar, es importante reforzar el compromiso en turnos nocturnos, ya que se registró el abandono de su puesto durante el período asignado. Se recomienda trabajar en la responsabilidad y cumplimiento de las condiciones del turno para asegurar la continuidad operativa • RRHH OPERACIONES: Quiere probar: Supervisor: gestión de liderazgo, trabajo …'),
  ('27351276822', 'Sabrina Moffa', '1123986188', null, 'Interés: ACOMODADOR / ORIENTADOR', 1, 'Promedio 4.44 / 5. • PÁDEL SENIOR PQ. ROCA (sep-26) – Orientador: 13/9: 5; 14/9: 4.75 [prom 4.88] • AC/DC 3: muy buena acomodadora, la tendría en cuenta más seguido, ágil. • AC/DC 1: Estuvo muy atenta a su sector y muy buena compañera • AIRBAG (jun-26): Trabajó muy bien, no tuvo problemas en el sector, no sobresale [puntaje 4.0]'),
  ('20481161135', 'Tiziano Moffa Aguiar', '1171453537', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: el 2 y 3 día estuvo en la entrada por pedido de el, muy buen acomodador, amable. • AC/DC 2: Buena predisposición, buen acomodador, simpático • ALE SANZ 1: Llegó impuntual (avisó). Trabajo: Excelente. C/experiencia. Predispuesto. Educado. Atento. Proactivo. Resolutivo. Aplica rol "derivador" cuando es necesario.'),
  ('27478713415', 'Zoe Muleiro', '1173852280', null, 'Interés: ACOMODADOR', 2, '• AC/DC 1: Muy bien • AC/DC 3 ⚠: no tiene la predisposición de acomodar, ni de indicarle a la gente, no la tendría en cuenta.'),
  ('23321537979', 'Marcos Omar Navarro', '1144493118', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: muy buen acomodador, rápido en dar indicaciones'),
  ('27384341034', 'Ariana Agustina Nicolete', '1131435391', null, 'Interés: ACOMODADOR', 3, '• AC/DC 3 ⚠: la vio usar el celular para filmar, se la llamó la atención.'),
  ('27460239201', 'Florencia Aylén Occhiato', '1134802004', 'Occhiatoflorencia@gmail.com', 'Interés: OP (ACRED)', 1, '• ACRED LOLLAPALOOZA: Cuenta con experiencia previa y una buena predisposición para colaborar. Se destaca especialmente por su disponibilidad y desempeño en turnos nocturnos, donde su experiencia resulta valiosa.'),
  ('27434084062', 'Mayra Perales', '1126620680', 'Mayra.perales23@gmail.com', 'Interés: OP (ACRED)', 2, '• ACRED ULTRA: Muy buena disposición, estuvo en molinetes y nos avisaba todo, supo responder bien a las personas. • ACRED ALE SANZ: Es promotora, buena presentacion. Educada, predispuesta, buen procedimiento. Perfil nuevo, se adaptó bien y aprendió rápido • ACRED TAN BIONICA: Es alguien que no nos generó confianza desde el minuto 1, participo dos días de armado: el primero hizo un turno tarde relevando a esteban ya que era su franco, se le explicó el manejo y lo que debía hacer al cerrar la lata, se le dejaron unas llaves y se las dio a la primera persona que entró a la lata, y se extraviaron,…'),
  ('27465588530', 'Pilar Pereyra', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 4 / 5. • AIRBAG (jun-26): Trabajó muy bien, no tuvo problemas en el sector, no sobresale [puntaje 4.0]'),
  ('27453239492', 'Camila Petrucci', '1151232150', 'camilapetrucci5@gmail.com', 'Interés: OP (ACRED)', 3, '• ACRED ULTRA: es lenta, no entiende y no habla bien con los proveedores en ventanilla en ningún evento.'),
  ('27474339365', 'Catalina Belén Picco', '1124884321', null, 'Interés: ACOMODADOR', 1, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Acomodador: 13/9: Ausente'),
  ('27449974455', 'Agostina Pozzi', null, null, 'Interés: -', 1, 'Sin detalle en la planilla'),
  ('27447560270', 'Paloma Ramirez', '1165697365', 'palomamoraramirez03@gmail.com', 'Interés: OP (ACRED)', 2, '• ACRED ULTRA: buen perfil para operadora de cargas, ya que tiene una personalidad bastante fuerte • ACRED LOLLAPALOOZA: Responsable y comprometida. Trabajó de forma ordenada y sin generar inconvenientes.'),
  ('27394668619', 'Carolina Evelyn Rick', '1161814498', 'carolinaevelynrick@gmail.com', 'Interés: OP (ACRED)', 1, '• ACRED ULTRA: Dispuesta a todas las tareas, muy buen trato con las personas.'),
  ('20467553098', 'Cristian Gastón Romero', '1128461389', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Muy bien, activo constantemente, posible perfil acreditaciones en un futuro, hay cosas que pulir pero viene bien • ALE SANZ 1: Buena predisposición'),
  ('23404586564', 'Mariana Ross', '2352527258', null, 'Interés: ACOMODADOR', 1, '• ALE SANZ 2: amable, simpática , se sumo a último momento y súper predispuesta. derivo y su desempeño fue impecable.'),
  ('20415510870', 'Mariano Ruiz Díaz', '1162794455', 'mariano.ruizdiaz99@gmail.com', 'Interés: OP (ACRED)', 3, '• ACRED ULTRA: No estuvo en para nada predispuesto, llegó tarde y no entendió la dinámica de acreditaciones. Además tuvo malas contestaciones.'),
  ('27418843166', 'Micaela Soledad Salas', '1156595511', null, 'Interés: ACOMODADOR', 1, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Acomodador: 18/9: 4 [prom 4.00]'),
  ('20413519641', 'Guido San Giorgio', '1167523209', null, 'Interés: ACOMODADOR', 1, '• BAD BUNNY 2: Perfil Acreditaciones'),
  ('27307752455', 'Nancy Sanabria', '1126831549', null, 'Interés: ORIENTADOR', 3, '• AC/DC 1 ⚠: No contestó wpp. • AC/DC 2 ⚠: No contestó wpp.'),
  ('27423974481', 'Milagros Saucedo', '1161026442', null, 'Interés: ORIENTADOR', 3, '• BAD BUNNY 1 ⚠: NO VOLVER A CONVOCAR'),
  ('27427761571', 'Camila Savoy', '1130315871', 'Savoycami@gmail.com', 'Interés: OP (ACRED)', 1, '• ACRED TAN BIONICA: Ella estuvo como turno Comodin, destacó que es seria al momento de trabajar y eso también es importante, era su primera vez como Comodin y supo adaptarse muy rápidamente, me encargue de explicarle el funcionamiento y entendió muy bien el manejo.'),
  ('27470832040', 'Julieta Scaniglia', '1155668595', 'juliscaniglia14@gmail.com', 'Interés: OP (ACRED)', 1, '• ACRED LOLLAPALOOZA: Cumplió su rol de manera correcta, atenta en ventanilla y ante cualquier duda que tenía no dudaba en preguntarnos, siempre buscando resolver de manera correcta sus dudas sobre cada situación. También cumplió de manera correcta los días de show que le toco venir. • ACRED AC/DC: Es amable y responde a las tareas asignadas. Todavia necesita mejorar la atención a ventanilla, para que no se le pasen personas en pendientes y accesos erroneos.'),
  ('27477017636', 'Camila Seco Mussi', '1160056069', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Trabajo muy bien, siempre atenta y con predisposición, perfil op • AC/DC 2: Muy bien, el primer día de show estaba dispuesta a ayudar en cualquier sector, fue enviada a platea alta y segundo día de show resolvió de manera correcta. Es perfil de acreditaciones, está dispuesta a aprender y ayudar. Hay que acompañarla para que vaya aprendiendo durante los eventos y sea un recurso fuerte • ALE SANZ 1: Impecable en su rol y buena compañera'),
  ('27455186515', 'Leonella Alejandra Sessa', null, null, 'Interés: ORIENTADOR', 2, 'Promedio 2.75 / 5. • ECOPARQUE: Buen recurso, vamos a evaluar su compromiso con el equipo; falta de iniciativa en algunas ocasiones [puntaje 2.75 - Amarillo]'),
  ('27433520403', 'Guillermina Toffoli', '3885808681', null, 'Interés: ACOMODADOR', 3, '• AC/DC 2 ⚠: Llego muy tarde, y se iba de su puesto sin avisar, no trabaja mal, pero suele irse mucho de su lugar. Hay que ir viendo cómo se sigue desenvolviendo, pero su desempeño fue bajo durante este show • AC/DC 3 ⚠: se la vio deambulando por varios lugares, usó el celular repetidas veces (aunque se le haya llamado la atención por ambas cosas), no hizo caso, actuó de manera soberbia, no la tendría en cuenta denuevo.'),
  ('27449470317', 'Candela Tatiana Torres', null, 'torrescandee12@gmail.com', 'Interés: EQUIPO OPERACIONES', 1, '• RRHH OPERACIONES: Quiere probar: Supervisor: gestión de liderazgo, trabajo en equipos, comunicación efectiva — Operadora fuerte. Muy predispuesta. Perfil para potenciar'),
  ('27478717763', 'Leonela Marisol Torres Tellez', '1164466179', null, 'Interés: ACOMODADOR', 1, '• ALE SANZ 2: Muy buena actitud'),
  ('27400099516', 'Florencia Urundez', '1149608670', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Muy bien'),
  ('27415419479', 'Victoria Valdez', '1152203705', null, 'Interés: ORIENTADOR', 3, '• AC/DC 1 ⚠: No contestó wpp. • AC/DC 2 ⚠: No contestó wpp.'),
  ('20472551826', 'Carlos Alejo Vazquez', '1141806567', null, 'Interés: ACOMODADOR', 1, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Supervisión (feedback Marcos Monti, 20/9): Trabajó bien, comprendió correctamente la dinámica de trabajo'),
  ('20476938229', 'Gustavo Daniel Velazquez', '1136288297', null, 'Interés: ACOMODADOR', 2, '• PÁDEL SENIOR PQ. ROCA (sep-26) – Supervisión (feedback Marcos Monti, 20/9): No se lo notó muy proactivo, había que repetirle las consignas varias veces'),
  ('27397702818', 'Aldana Vertone', null, null, 'Interés: ACOMODADOR', 1, 'Promedio 4 / 5. • AIRBAG (jun-26): Trabajo bien y cumplio su puesto sin problemas. [puntaje 4.0]'),
  ('27457496341', 'Delfina Vila Sánchez', '1144001890', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Muy bien, perfil operador acreditaciones • AC/DC 2: Actitud y mucha predisposición, tiene perfil para acreditaciones como operadora, estuvo siempre dispuesta a aprender y aportar • AC/DC 1: Muy bien'),
  ('27433165638', 'Ailen Waitzel', '1128501730', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Muy Bien. • AC/DC 1: Muy Bien. • ALE SANZ 1: Proactiva y servicial • BAD BUNNY 2: Buena atencion al publico, proactivo, con ganas y atento a las indicaciones.'),
  ('23416404739', 'Matías Zygier', '1153233965', null, 'Interés: ACOMODADOR', 1, '• AC/DC 3: Trabajo muy bien')
), insertadas as (
  insert into public.personas (id, nombre, area, estado, email, tel, cuit, notas, semaforo)
  select gen_random_uuid(), n.nombre, 'externos', 'confirmado', n.mail, n.tel, n.doc, n.nota, n.sem
  from nuevas n
  -- Si ya existe alguien con ese documento, no se crea de nuevo.
  where not exists (
    select 1 from public.personas p
    where regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') = n.doc
  )
  returning id, cuit
)
insert into public.feedbacks (id, persona_id, conv_id, supervisor_id, supervisor_nombre, puntaje, comentario)
select gen_random_uuid(), i.id, null, null, 'Planilla de feedbacks', n.sem, n.coment
from insertadas i
join nuevas n on n.doc = regexp_replace(coalesce(i.cuit, ''), '\D', '', 'g');

-- Para ver cómo quedó:
--   select count(*) from public.personas where area = 'externos';

-- ── CON EL CUIL MAL CARGADO EN LA PLANILLA, NO SE DIERON DE ALTA ──
--   Maria Victoria Ambuhl Titon       48134856      1154219047
--   Mora Aragón                       48462253      1122560800
--   Sol Araujo                        47202524      1121718905
--   Victoria Bellas Alvarez           47346329      1140456950
--   Serena Biondini Cianni            45522308      1168535252
--   Agustina Blanco                   42933185      1153198567
--   Malena Carreras                   46986238      2966631678
--   Victoria Cornaro                  27440721536   1163350956
--   Florencia De Pascual              47083244      1168390813
--   Sofia Dusman                      44413715      1126072023
--   Luana Ferreyra                    27463654023   1156161538
--   Martina Giovenco                  46278179      1150256112
--   Anna Chiara Giuliano              48430964      2215711186
--   Ariadna Agostina Godoy            47835556      1134826934
--   Angeles Gomez                     48297413      1176619266
--   Zoe Belen Kistner                 46990788      1153181848
--   Clara Belen Lukra                 47493113      1169371698
--   Mateo Luna                        45431333      sin teléfono
--   Francisco Javier Mandara          48165173      2914191255
--   Rocío Mazzonelli                  44131416      1122503210
--   Agustina Morán                    27439920397   1151014524
--   Lucia Navarro                     48054225      2474409272
--   Sofia Pantanali                   48109330      1169550921
--   Yolinel Planchart                 29959899847   sin teléfono
--   Lucila Royán                      47872036      1138569784
--   Agustina Ruiz                     46960121      1133804188
--   Rosario Sofía Sanchez Cabrera     48214959      1127121601
--   Emma Scheffer                     48368923      1176299663
--   Xiomara Valles                    48765998      1166218612
--   Sofia Morena Volpi Porte          46111141      1158133551
--   Angelica Zucchiatti               95422082      1131879254
