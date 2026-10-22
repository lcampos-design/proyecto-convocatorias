-- ============================================================
--  RECOMENDADOS / A LLAMAR
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no duplica ni borra nada.
--
--  Pasa a la plataforma la planilla "Recomendados - Feedbacks - Staffs
--  eventuales", que hoy se usa a mano para decidir a quién llamar:
--     · 51 recomendados agrupados por zona  (hoja 1)
--     · 24 de acreditaciones por cercanía   (hoja 2)
--     · 52 supervisores                      (hoja 3)
--  Son 69 personas distintas: muchas están en más de una hoja.
--
--  QUÉ HACE
--   1. Agrega la columna "recomendado" y la columna "localidad" en la ficha.
--   2. Marca como recomendadas a las que ya están en la nómina.
--   3. Les suma la posición que dice la planilla (Supervisor / Operador
--      acreditaciones) sin sacarles las que ya tenían.
--   4. Les completa la localidad sólo si la tenían vacía, para que entren en
--      el filtro por zona.
--   5. Da de alta en Externos a las que no estaban.
--
--  QUÉ NO HACE
--   · No recomienda a nadie que esté en OUT en la plataforma: si está en OUT,
--     está en OUT. Tampoco a las 2 marcadas OUT en la planilla
--     (Sofía Billinger, Fabián Vicent).
--   · No le saca la marca a nadie que hayan recomendado desde el panel.
--   · No toca notas, semáforo ni feedback de quien ya estaba cargado.
-- ============================================================

alter table public.personas add column if not exists recomendado boolean not null default false;
alter table public.personas add column if not exists localidad text;

-- Para que abrir el apartado no recorra las 2.300 fichas.
create index if not exists personas_recomendado_idx on public.personas (recomendado) where recomendado;

-- ── 1) LAS QUE YA ESTÁN EN LA NÓMINA ──
update public.personas p
set recomendado = coalesce(p.recomendado, false) or (v.rec and not coalesce(p.out_flag, false)),
    posiciones  = (select array_agg(distinct x order by x) from unnest(coalesce(p.posiciones, '{}'::text[]) || v.pos) x),
    localidad   = coalesce(nullif(trim(coalesce(p.localidad, '')), ''), v.localidad)
from (values
  ('23366356754', 'Mayra Soledad Acosta', '1165973151', 'acosta.mayra28@gmail.com', 'Liniers. comuna 9', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20379690182', 'Facundo Acuña', '1132645464', 'Facu.experia@gmail.com', 'Lomas de Zamora', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27431044426', 'Leila Aguiar', '1139053660', 'Aguiarleila72@gmail.com', 'Partido General San Martín', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27457863638', 'Abril Alecci', '1123953848', 'abrualecci@gmail.com', 'Martinez', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27442611269', 'Maia Altamira', '1133966754', 'Maialogares@gmail.com', 'Villa crespo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27433235393', 'Zoe Altamira', '1124556754', 'zoe.a.contact@gmail.com', 'CABA', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27441856402', 'Luana Berman', '1162061560', 'bermanluly@gmail.com', 'Parque Patricios, comuna 4', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27425386080', 'Sofía Billinger', '2345458001', 'Sofiamacchiaroli@hotmail.com', 'Belgrano COMUNA 13', array['Supervisor'], false, 'Alta desde la planilla de recomendados'),
  ('27456234998', 'Zoe Britos', '1122870738', 'zoe.v.britoss@gmail.com', 'Grand Bourg', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27456840197', 'Martina Buffoni', '1141984035', 'martubuffoni@gmail.com', 'Núñez, comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27369158797', 'Pamela Soledad Cacciabue', '1124072148', 'pamelacacciabue@gmail.com', 'Tigre', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20453053033', 'Pablo Caradori', '1150604606', 'pablocaradori@gmail.com', 'Villa Adelina -San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27442569792', 'Guillermina Caro', '1167558004', 'guillecaro2002@gmail.com', 'Quilmes', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23345851704', 'Natalia Castez', '1156609400', 'naticastez@hotmail.com', 'Tigre, GBA norte', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23942150024', 'Lola Contrera', '1160531006', 'contreralola34@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27461923807', 'Pilar Corti', '1123952828', 'p.corti05@gmail.com', 'villa Ballester', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20448580661', 'Tomas Dallochio', '1124605410', 'Tomasdallochio8@gmail.com', 'Villa crespo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27454197130', 'Sofía De Marco', '1161809711', 'sofidm03@hotmail.com', 'San Fernando', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27465809626', 'Fiamma De Mingo', '1153768232', 'fiamma.demingo@gmail.com', 'Villa Lugano - comuna 8', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27456845229', 'Jennifer De Souza', '1150354061', 'jennyjadedesouza@gmail.com', 'Belgrano comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23384420109', 'Damián Fernández', '1126582233', 'damianfernandezdamian@gmail.com', 'Morón', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27392084091', 'Isabella Filip', '1131603312', 'Filip.isabella@gmail.com', 'Vicente lopez', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27412104663', 'Luna Florido', '11316839009', 'lunaflorido@hotmail.com', 'Alem 1254, Banfield.', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20452034833', 'Mateo Francini', '1126803860', 'mateofranciniag@gmail.com', 'Grand Bourg', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473077383', 'Nahiara Azul Garay', '1154664965', 'Nahiaragaray77@gmail.com', 'Lomas de zamora', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27471269943', 'Renata García Mantovani', '1151565967', 'renag.mantovani@gmail.com', 'Villa del parque, comuna 11', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27450746180', 'Catalina Genta Silvini', '1131302282', 'catalinagentasilvini@gmail.com', 'Palermo, Comuna 14', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27445999690', 'Agustina Gil', '1150178925', 'gilagustina65@gmail.com', 'Martínez', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27447492097', 'Julieta Gomez', '1157985004', 'Julietamagaligomez@hotmail.com', 'Tortuguitas', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20421191582', 'Ivan Horvath', '1131241811', 'horvathivan5030@gmail.com', 'Villa Martelli', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27444149049', 'Candela Kinter', '2923659715', 'kintercandela02@gmail.com', 'Palermo, comuna 14', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27440835444', 'Agustín Lavigna', '1132108270', 'agustinlavigna3@gmail.com', 'Belgrano', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27432016310', 'Moira Llano', '1130692001', 'llanomoira26@outlook.com', 'Tigre', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20462877804', 'Juan Francisco Lorenzo', '1151479015', 'franlorenzo04@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('45431333', 'Mateo Luna', '1168116256', 'matualuna.12@gmail.com', 'Boulogne, San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20397598811', 'Lautaro Thomas Lunatti Sanchiz', '1141945810', 'Lautarolunatti@gmail.com', null, array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20476440530', 'Federico Luciano Lupo', '125790022', 'fedelupo012@gmail.com', null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20942026189', 'Jair Luyo', '1136671738', 'Luyo.jairj@gmail.com', 'Ramos Mejia', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20353994728', 'Diego Macias', '1166385027', 'Diegomacias10101010@gmail.com', '3 de Febrero', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27442567757', 'Catalina Michel', '1156218451', 'catamichel1989@gmail.com', null, array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27441660443', 'Candela Milisa', '2392540671', 'candelamilisa54@gmail.com', 'Caballito', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27413169084', 'Karen Miller', '1134933250', 'karumiller@gmail.com', 'Parque Chacabuco - Comuna 7', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20342111255', 'Pablo Moccio', '1134208203', 'moccio.p@gmail.com', 'Liniers, capital federal, comuna 9', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20445534812', 'Esteban Morales', '1139197867', 'estebanmoralesezequiel@gmail.com', 'Floresta', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27460239201', 'Florencia Aylen Occhiato', '1134802004', 'Occhiatoflorencia@gmail.com', 'Vélez Sarsfield, comuna 10.', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20453070418', 'Ignacio Onorati', '1139331201', 'onoratiignacio@gmail.com', null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27445891539', 'Florencia Padilla', '1168310610', 'flor.padilla0102@gmail.com', 'Palermo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27446270082', 'Ana Laura Palavecino', '1153316288', 'Analaurapalavecino93@gmail.com', 'Moreno', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27415444015', 'Sofía Pastorini', '1135799630', 'sofipastorini@gmail.com', 'Moron', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27448672455', 'Julieta Abigail Perez', '5493364007635', 'julietaperez.lt@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20462116560', 'Alejo Pianella', '1167479330', 'pianella.alejo1@gmail.com', 'Villa Lugano, Comuna 8', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27449974455', 'Agostina Pozzi', '1158212166', 'agospozzii@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27450136994', 'Camila Quiroz Sala', '1164530203', 'camilaquiroz033@gmail.com', 'CABA, Colegiales', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27472011060', 'Josefina Ramirez', '1138460850', 'josefinaramirez05@gmail.com', 'Palermo', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27447560270', 'Paloma Ramirez', '1165697365', 'palomamoraramirez03@gmail.com', 'Hurlingham', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23453148734', 'Malena Re Giame', '2477607144', 'miregiame@gmail.com', 'Ciudad Autónoma de Buenos Aires', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27437334280', 'Violeta Recalde', '3388671361', 'vrecalde628@gmail.com', 'Comuna 14', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27455846590', 'Cecilia Recondo', '1156106642', 'recondocecilia@gmail.com', 'Belgrano, CABA.', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27460240803', 'Martina Revilla', null, null, null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20452813433', 'Ignacio Robles', '1138678017', 'Ignaciorobles.cervantes@gmail.com', 'Villa adelina', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27470832040', 'Julieta Scaniglia', '1155668595', 'juliscaniglia14@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473430709', 'Billie Simonini', '1136280090', 'Billiesimonini@outlook.com', 'CABA, comuna 15', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27459289130', 'Marisol Soreira', '1136283448', 'marisolsoreira@gmail.com', 'Monserrat', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('23425045539', 'Ignacio Gabriel Sosa', '542613365716', 'ignaciososaart@gmail.com', 'Comuna 6', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27449470317', 'Candela Tatiana Torres', '1138081934', 'torrescandee12@gmail.com', 'altos de podesta', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27453543485', 'Luna Valea', '1157432434', 'lunavalea6@gmail.com', 'CABA, Comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473160868', 'Tatiana Vargas', '1136485251', 'Tatianajvargasp@gmail.com', 'Núñez - Comuna 13', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20962308636', 'Fabián Vicent', '1123960248', 'fabianjvicent317@gmail.com', 'Avellaneda, José Ignacio Rucci 250', array['Operador acreditaciones'], false, 'Alta desde la planilla de recomendados'),
  ('27458237145', 'Valentina Zárate', '1157433585', 'valentinaluciazarate18@gmail.com', 'Comuna 8', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados')
) as v(doc, nombre, tel, mail, localidad, pos, rec, nota)
where length(ltrim(case when length(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')) = 11
             then substr(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), 3, 8)
             else regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') end, '0')) >= 6 and ltrim(case when length(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')) = 11
             then substr(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), 3, 8)
             else regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') end, '0') = ltrim(case when length(v.doc) = 11 then substr(v.doc, 3, 8) else v.doc end, '0');

-- ── 2) LAS QUE TODAVÍA NO TENÍAN FICHA ──
insert into public.personas (id, nombre, area, estado, email, tel, cuit, localidad, posiciones, recomendado, notas)
select gen_random_uuid(), v.nombre, 'externos', 'confirmado', v.mail, v.tel, v.doc, v.localidad,
       nullif(v.pos, '{}'::text[]), v.rec, v.nota
from (values
  ('23366356754', 'Mayra Soledad Acosta', '1165973151', 'acosta.mayra28@gmail.com', 'Liniers. comuna 9', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20379690182', 'Facundo Acuña', '1132645464', 'Facu.experia@gmail.com', 'Lomas de Zamora', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27431044426', 'Leila Aguiar', '1139053660', 'Aguiarleila72@gmail.com', 'Partido General San Martín', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27457863638', 'Abril Alecci', '1123953848', 'abrualecci@gmail.com', 'Martinez', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27442611269', 'Maia Altamira', '1133966754', 'Maialogares@gmail.com', 'Villa crespo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27433235393', 'Zoe Altamira', '1124556754', 'zoe.a.contact@gmail.com', 'CABA', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27441856402', 'Luana Berman', '1162061560', 'bermanluly@gmail.com', 'Parque Patricios, comuna 4', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27425386080', 'Sofía Billinger', '2345458001', 'Sofiamacchiaroli@hotmail.com', 'Belgrano COMUNA 13', array['Supervisor'], false, 'Alta desde la planilla de recomendados'),
  ('27456234998', 'Zoe Britos', '1122870738', 'zoe.v.britoss@gmail.com', 'Grand Bourg', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27456840197', 'Martina Buffoni', '1141984035', 'martubuffoni@gmail.com', 'Núñez, comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27369158797', 'Pamela Soledad Cacciabue', '1124072148', 'pamelacacciabue@gmail.com', 'Tigre', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20453053033', 'Pablo Caradori', '1150604606', 'pablocaradori@gmail.com', 'Villa Adelina -San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27442569792', 'Guillermina Caro', '1167558004', 'guillecaro2002@gmail.com', 'Quilmes', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23345851704', 'Natalia Castez', '1156609400', 'naticastez@hotmail.com', 'Tigre, GBA norte', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23942150024', 'Lola Contrera', '1160531006', 'contreralola34@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27461923807', 'Pilar Corti', '1123952828', 'p.corti05@gmail.com', 'villa Ballester', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20448580661', 'Tomas Dallochio', '1124605410', 'Tomasdallochio8@gmail.com', 'Villa crespo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27454197130', 'Sofía De Marco', '1161809711', 'sofidm03@hotmail.com', 'San Fernando', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27465809626', 'Fiamma De Mingo', '1153768232', 'fiamma.demingo@gmail.com', 'Villa Lugano - comuna 8', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27456845229', 'Jennifer De Souza', '1150354061', 'jennyjadedesouza@gmail.com', 'Belgrano comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23384420109', 'Damián Fernández', '1126582233', 'damianfernandezdamian@gmail.com', 'Morón', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27392084091', 'Isabella Filip', '1131603312', 'Filip.isabella@gmail.com', 'Vicente lopez', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27412104663', 'Luna Florido', '11316839009', 'lunaflorido@hotmail.com', 'Alem 1254, Banfield.', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20452034833', 'Mateo Francini', '1126803860', 'mateofranciniag@gmail.com', 'Grand Bourg', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473077383', 'Nahiara Azul Garay', '1154664965', 'Nahiaragaray77@gmail.com', 'Lomas de zamora', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27471269943', 'Renata García Mantovani', '1151565967', 'renag.mantovani@gmail.com', 'Villa del parque, comuna 11', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27450746180', 'Catalina Genta Silvini', '1131302282', 'catalinagentasilvini@gmail.com', 'Palermo, Comuna 14', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27445999690', 'Agustina Gil', '1150178925', 'gilagustina65@gmail.com', 'Martínez', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27447492097', 'Julieta Gomez', '1157985004', 'Julietamagaligomez@hotmail.com', 'Tortuguitas', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20421191582', 'Ivan Horvath', '1131241811', 'horvathivan5030@gmail.com', 'Villa Martelli', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27444149049', 'Candela Kinter', '2923659715', 'kintercandela02@gmail.com', 'Palermo, comuna 14', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27440835444', 'Agustín Lavigna', '1132108270', 'agustinlavigna3@gmail.com', 'Belgrano', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27432016310', 'Moira Llano', '1130692001', 'llanomoira26@outlook.com', 'Tigre', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20462877804', 'Juan Francisco Lorenzo', '1151479015', 'franlorenzo04@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('45431333', 'Mateo Luna', '1168116256', 'matualuna.12@gmail.com', 'Boulogne, San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20397598811', 'Lautaro Thomas Lunatti Sanchiz', '1141945810', 'Lautarolunatti@gmail.com', null, array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20476440530', 'Federico Luciano Lupo', '125790022', 'fedelupo012@gmail.com', null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20942026189', 'Jair Luyo', '1136671738', 'Luyo.jairj@gmail.com', 'Ramos Mejia', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20353994728', 'Diego Macias', '1166385027', 'Diegomacias10101010@gmail.com', '3 de Febrero', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27442567757', 'Catalina Michel', '1156218451', 'catamichel1989@gmail.com', null, array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27441660443', 'Candela Milisa', '2392540671', 'candelamilisa54@gmail.com', 'Caballito', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27413169084', 'Karen Miller', '1134933250', 'karumiller@gmail.com', 'Parque Chacabuco - Comuna 7', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20342111255', 'Pablo Moccio', '1134208203', 'moccio.p@gmail.com', 'Liniers, capital federal, comuna 9', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20445534812', 'Esteban Morales', '1139197867', 'estebanmoralesezequiel@gmail.com', 'Floresta', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27460239201', 'Florencia Aylen Occhiato', '1134802004', 'Occhiatoflorencia@gmail.com', 'Vélez Sarsfield, comuna 10.', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20453070418', 'Ignacio Onorati', '1139331201', 'onoratiignacio@gmail.com', null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27445891539', 'Florencia Padilla', '1168310610', 'flor.padilla0102@gmail.com', 'Palermo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27446270082', 'Ana Laura Palavecino', '1153316288', 'Analaurapalavecino93@gmail.com', 'Moreno', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27415444015', 'Sofía Pastorini', '1135799630', 'sofipastorini@gmail.com', 'Moron', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27448672455', 'Julieta Abigail Perez', '5493364007635', 'julietaperez.lt@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20462116560', 'Alejo Pianella', '1167479330', 'pianella.alejo1@gmail.com', 'Villa Lugano, Comuna 8', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27449974455', 'Agostina Pozzi', '1158212166', 'agospozzii@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27450136994', 'Camila Quiroz Sala', '1164530203', 'camilaquiroz033@gmail.com', 'CABA, Colegiales', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27472011060', 'Josefina Ramirez', '1138460850', 'josefinaramirez05@gmail.com', 'Palermo', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27447560270', 'Paloma Ramirez', '1165697365', 'palomamoraramirez03@gmail.com', 'Hurlingham', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23453148734', 'Malena Re Giame', '2477607144', 'miregiame@gmail.com', 'Ciudad Autónoma de Buenos Aires', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27437334280', 'Violeta Recalde', '3388671361', 'vrecalde628@gmail.com', 'Comuna 14', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27455846590', 'Cecilia Recondo', '1156106642', 'recondocecilia@gmail.com', 'Belgrano, CABA.', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27460240803', 'Martina Revilla', null, null, null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20452813433', 'Ignacio Robles', '1138678017', 'Ignaciorobles.cervantes@gmail.com', 'Villa adelina', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27470832040', 'Julieta Scaniglia', '1155668595', 'juliscaniglia14@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473430709', 'Billie Simonini', '1136280090', 'Billiesimonini@outlook.com', 'CABA, comuna 15', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27459289130', 'Marisol Soreira', '1136283448', 'marisolsoreira@gmail.com', 'Monserrat', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('23425045539', 'Ignacio Gabriel Sosa', '542613365716', 'ignaciososaart@gmail.com', 'Comuna 6', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27449470317', 'Candela Tatiana Torres', '1138081934', 'torrescandee12@gmail.com', 'altos de podesta', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27453543485', 'Luna Valea', '1157432434', 'lunavalea6@gmail.com', 'CABA, Comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473160868', 'Tatiana Vargas', '1136485251', 'Tatianajvargasp@gmail.com', 'Núñez - Comuna 13', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20962308636', 'Fabián Vicent', '1123960248', 'fabianjvicent317@gmail.com', 'Avellaneda, José Ignacio Rucci 250', array['Operador acreditaciones'], false, 'Alta desde la planilla de recomendados'),
  ('27458237145', 'Valentina Zárate', '1157433585', 'valentinaluciazarate18@gmail.com', 'Comuna 8', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados')
) as v(doc, nombre, tel, mail, localidad, pos, rec, nota)
where not exists (select 1 from public.personas p where length(ltrim(case when length(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')) = 11
             then substr(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), 3, 8)
             else regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') end, '0')) >= 6 and ltrim(case when length(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')) = 11
             then substr(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), 3, 8)
             else regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') end, '0') = ltrim(case when length(v.doc) = 11 then substr(v.doc, 3, 8) else v.doc end, '0'));

-- ── 3) CÓMO QUEDÓ ──
select count(*) filter (where recomendado) as recomendados,
       count(*) filter (where recomendado and 'Supervisor' = any(posiciones)) as supervisores,
       count(*) filter (where recomendado and 'Operador acreditaciones' = any(posiciones)) as acreditaciones,
       count(*) filter (where recomendado and coalesce(localidad, '') = '') as sin_localidad
from public.personas;

-- ── 4) LAS DE LA PLANILLA QUE FIGURAN EN OUT EN LA PLATAFORMA ──
--  Quedaron sin recomendar a propósito. Si alguna ya no debería estar en OUT,
--  se la saca desde la pestaña OUT y después se la marca con la estrella.
select p.nombre, p.cuit, p.out_categoria, p.out_nota
from public.personas p
where p.out_flag and exists (
  select 1 from (values
  ('23366356754', 'Mayra Soledad Acosta', '1165973151', 'acosta.mayra28@gmail.com', 'Liniers. comuna 9', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20379690182', 'Facundo Acuña', '1132645464', 'Facu.experia@gmail.com', 'Lomas de Zamora', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27431044426', 'Leila Aguiar', '1139053660', 'Aguiarleila72@gmail.com', 'Partido General San Martín', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27457863638', 'Abril Alecci', '1123953848', 'abrualecci@gmail.com', 'Martinez', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27442611269', 'Maia Altamira', '1133966754', 'Maialogares@gmail.com', 'Villa crespo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27433235393', 'Zoe Altamira', '1124556754', 'zoe.a.contact@gmail.com', 'CABA', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27441856402', 'Luana Berman', '1162061560', 'bermanluly@gmail.com', 'Parque Patricios, comuna 4', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27425386080', 'Sofía Billinger', '2345458001', 'Sofiamacchiaroli@hotmail.com', 'Belgrano COMUNA 13', array['Supervisor'], false, 'Alta desde la planilla de recomendados'),
  ('27456234998', 'Zoe Britos', '1122870738', 'zoe.v.britoss@gmail.com', 'Grand Bourg', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27456840197', 'Martina Buffoni', '1141984035', 'martubuffoni@gmail.com', 'Núñez, comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27369158797', 'Pamela Soledad Cacciabue', '1124072148', 'pamelacacciabue@gmail.com', 'Tigre', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20453053033', 'Pablo Caradori', '1150604606', 'pablocaradori@gmail.com', 'Villa Adelina -San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27442569792', 'Guillermina Caro', '1167558004', 'guillecaro2002@gmail.com', 'Quilmes', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23345851704', 'Natalia Castez', '1156609400', 'naticastez@hotmail.com', 'Tigre, GBA norte', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23942150024', 'Lola Contrera', '1160531006', 'contreralola34@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27461923807', 'Pilar Corti', '1123952828', 'p.corti05@gmail.com', 'villa Ballester', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20448580661', 'Tomas Dallochio', '1124605410', 'Tomasdallochio8@gmail.com', 'Villa crespo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27454197130', 'Sofía De Marco', '1161809711', 'sofidm03@hotmail.com', 'San Fernando', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27465809626', 'Fiamma De Mingo', '1153768232', 'fiamma.demingo@gmail.com', 'Villa Lugano - comuna 8', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27456845229', 'Jennifer De Souza', '1150354061', 'jennyjadedesouza@gmail.com', 'Belgrano comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23384420109', 'Damián Fernández', '1126582233', 'damianfernandezdamian@gmail.com', 'Morón', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27392084091', 'Isabella Filip', '1131603312', 'Filip.isabella@gmail.com', 'Vicente lopez', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27412104663', 'Luna Florido', '11316839009', 'lunaflorido@hotmail.com', 'Alem 1254, Banfield.', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20452034833', 'Mateo Francini', '1126803860', 'mateofranciniag@gmail.com', 'Grand Bourg', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473077383', 'Nahiara Azul Garay', '1154664965', 'Nahiaragaray77@gmail.com', 'Lomas de zamora', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27471269943', 'Renata García Mantovani', '1151565967', 'renag.mantovani@gmail.com', 'Villa del parque, comuna 11', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27450746180', 'Catalina Genta Silvini', '1131302282', 'catalinagentasilvini@gmail.com', 'Palermo, Comuna 14', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27445999690', 'Agustina Gil', '1150178925', 'gilagustina65@gmail.com', 'Martínez', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27447492097', 'Julieta Gomez', '1157985004', 'Julietamagaligomez@hotmail.com', 'Tortuguitas', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20421191582', 'Ivan Horvath', '1131241811', 'horvathivan5030@gmail.com', 'Villa Martelli', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27444149049', 'Candela Kinter', '2923659715', 'kintercandela02@gmail.com', 'Palermo, comuna 14', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27440835444', 'Agustín Lavigna', '1132108270', 'agustinlavigna3@gmail.com', 'Belgrano', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27432016310', 'Moira Llano', '1130692001', 'llanomoira26@outlook.com', 'Tigre', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20462877804', 'Juan Francisco Lorenzo', '1151479015', 'franlorenzo04@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('45431333', 'Mateo Luna', '1168116256', 'matualuna.12@gmail.com', 'Boulogne, San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20397598811', 'Lautaro Thomas Lunatti Sanchiz', '1141945810', 'Lautarolunatti@gmail.com', null, array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20476440530', 'Federico Luciano Lupo', '125790022', 'fedelupo012@gmail.com', null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20942026189', 'Jair Luyo', '1136671738', 'Luyo.jairj@gmail.com', 'Ramos Mejia', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20353994728', 'Diego Macias', '1166385027', 'Diegomacias10101010@gmail.com', '3 de Febrero', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27442567757', 'Catalina Michel', '1156218451', 'catamichel1989@gmail.com', null, array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27441660443', 'Candela Milisa', '2392540671', 'candelamilisa54@gmail.com', 'Caballito', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27413169084', 'Karen Miller', '1134933250', 'karumiller@gmail.com', 'Parque Chacabuco - Comuna 7', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20342111255', 'Pablo Moccio', '1134208203', 'moccio.p@gmail.com', 'Liniers, capital federal, comuna 9', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20445534812', 'Esteban Morales', '1139197867', 'estebanmoralesezequiel@gmail.com', 'Floresta', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27460239201', 'Florencia Aylen Occhiato', '1134802004', 'Occhiatoflorencia@gmail.com', 'Vélez Sarsfield, comuna 10.', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20453070418', 'Ignacio Onorati', '1139331201', 'onoratiignacio@gmail.com', null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27445891539', 'Florencia Padilla', '1168310610', 'flor.padilla0102@gmail.com', 'Palermo', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27446270082', 'Ana Laura Palavecino', '1153316288', 'Analaurapalavecino93@gmail.com', 'Moreno', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27415444015', 'Sofía Pastorini', '1135799630', 'sofipastorini@gmail.com', 'Moron', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27448672455', 'Julieta Abigail Perez', '5493364007635', 'julietaperez.lt@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20462116560', 'Alejo Pianella', '1167479330', 'pianella.alejo1@gmail.com', 'Villa Lugano, Comuna 8', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27449974455', 'Agostina Pozzi', '1158212166', 'agospozzii@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27450136994', 'Camila Quiroz Sala', '1164530203', 'camilaquiroz033@gmail.com', 'CABA, Colegiales', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27472011060', 'Josefina Ramirez', '1138460850', 'josefinaramirez05@gmail.com', 'Palermo', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27447560270', 'Paloma Ramirez', '1165697365', 'palomamoraramirez03@gmail.com', 'Hurlingham', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('23453148734', 'Malena Re Giame', '2477607144', 'miregiame@gmail.com', 'Ciudad Autónoma de Buenos Aires', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27437334280', 'Violeta Recalde', '3388671361', 'vrecalde628@gmail.com', 'Comuna 14', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27455846590', 'Cecilia Recondo', '1156106642', 'recondocecilia@gmail.com', 'Belgrano, CABA.', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27460240803', 'Martina Revilla', null, null, null, array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('20452813433', 'Ignacio Robles', '1138678017', 'Ignaciorobles.cervantes@gmail.com', 'Villa adelina', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27470832040', 'Julieta Scaniglia', '1155668595', 'juliscaniglia14@gmail.com', 'San Isidro', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473430709', 'Billie Simonini', '1136280090', 'Billiesimonini@outlook.com', 'CABA, comuna 15', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27459289130', 'Marisol Soreira', '1136283448', 'marisolsoreira@gmail.com', 'Monserrat', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('23425045539', 'Ignacio Gabriel Sosa', '542613365716', 'ignaciososaart@gmail.com', 'Comuna 6', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27449470317', 'Candela Tatiana Torres', '1138081934', 'torrescandee12@gmail.com', 'altos de podesta', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('27453543485', 'Luna Valea', '1157432434', 'lunavalea6@gmail.com', 'CABA, Comuna 13', array['Supervisor'], true, 'Alta desde la planilla de recomendados'),
  ('27473160868', 'Tatiana Vargas', '1136485251', 'Tatianajvargasp@gmail.com', 'Núñez - Comuna 13', array['Operador acreditaciones'], true, 'Alta desde la planilla de recomendados'),
  ('20962308636', 'Fabián Vicent', '1123960248', 'fabianjvicent317@gmail.com', 'Avellaneda, José Ignacio Rucci 250', array['Operador acreditaciones'], false, 'Alta desde la planilla de recomendados'),
  ('27458237145', 'Valentina Zárate', '1157433585', 'valentinaluciazarate18@gmail.com', 'Comuna 8', array['Supervisor', 'Operador acreditaciones'], true, 'Alta desde la planilla de recomendados')
  ) as v(doc, nombre, tel, mail, localidad, pos, rec, nota)
  where length(ltrim(case when length(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')) = 11
             then substr(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), 3, 8)
             else regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') end, '0')) >= 6 and ltrim(case when length(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g')) = 11
             then substr(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), 3, 8)
             else regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g') end, '0') = ltrim(case when length(v.doc) = 11 then substr(v.doc, 3, 8) else v.doc end, '0')
);

-- ── DOCUMENTOS MAL CARGADOS EN LA PLANILLA ──
--  Van igual a la nómina, pero el panel los muestra con el aviso de documento
--  mal cargado hasta que se los corrija:
--   Maia Altamira                 27442611269
--   Mateo Luna                    45431333
