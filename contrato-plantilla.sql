-- ============================================================
--  EL MODELO DE CONTRATO, EDITABLE DESDE EL PANEL
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema: no pisa lo que ya esté cargado.
--
--  EL PROBLEMA
--  El texto del contrato estaba escrito adentro del código. Cambiar una
--  coma —un domicilio, un artículo de la ley, el nombre del socio gerente—
--  obligaba a tocar el archivo y volver a publicar la página. Nadie de
--  Recursos Humanos podía hacerlo.
--
--  Y hay un solo modelo, con ley argentina, CUIL y domicilio en CABA. Para
--  la gente de España no sirve.
--
--  LO QUE HACE
--  Guarda el modelo en la configuración, uno por país, para que se edite
--  desde el panel sin tocar código. El argentino entra tal cual está hoy.
--  El de España queda vacío a propósito: ese texto lo tiene que redactar
--  quien corresponda, no se inventa. Mientras esté vacío, el panel avisa
--  al intentar generar un contrato para España.
-- ============================================================

insert into public.config (key, value)
values ('contrato_plantilla', jsonb_build_object(
  'ar', 'CONTRATO DE TRABAJO A PLAZO FIJO

En Buenos Aires a los días {{fecha_inicio}} al {{fecha_fin}} de {{anio}} entre: {{nombre}} con CUIL N° {{cuil}} cuyo domicilio es: _______________________________________ en adelante "EL TRABAJADOR" y representada por Richard Rickemberg, DNI 32558207, en su carácter de Socio Gerente, con domicilio en Ramallo 4608, de la Ciudad Autónoma de Buenos Aires, en adelante "LA EMPRESA" SHOW BUSINESS SOLUTIONS, celebran el presente CONTRATO DE TRABAJO A PLAZO FIJO (Art.93 de la Ley 20.744), con sujeción a las siguientes normas:

Primera: La empresa contrata al trabajador para desempeñar tareas de {{puesto}}. Las actividades mencionadas revisten naturaleza transitoria, conforme a lo normado por el ART 90 de la LCT, y se desarrollarán en el {{venue}}.

Segunda: El presente contrato se celebra los días {{fecha_inicio}} al {{fecha_fin}} de {{anio}}, fecha en que de hecho y de derecho, quedará extinguida la relación laboral entre las partes, dejando aclarado que en el caso en que las necesidades de la actividad transitoria así lo requieran, deberá notificarse a el trabajador por escrito, pudiendo la empresa optar por una prórroga si la modalidad de la tarea o la actividad así lo justifica.

Tercera: El trabajador percibirá por dicho período una remuneración neta diaria por JORNADA EFECTIVAMENTE TRABAJADA de {{monto_letras}} (\${{monto_numero}}) por todo concepto. - Durante las jornadas extendidas, el valor de la JORNADA EFECTIVAMENTE TRABAJADA será el INDICADO EN LA CONVOCATORIA OFICIAL.

Cuarta: Se deja expresa constancia y de común acuerdo se ratifica el vencimiento del presente contrato el día {{fecha_fin}} de {{anio}} sirviendo la presente de suficiente preaviso legal conforme al Art. 90 y concordantes LCT.

Quinta: a) Mantener el orden del lugar de trabajo al finalizar la jornada. b) Utilizar correctamente el uniforme provisto, manteniéndolo limpio y en buen estado, y devolverlo en las mismas condiciones al finalizar la relación laboral. No se permiten modificaciones ni el uso de calzado/ropa deportiva. c) Cuidar y reportar cualquier daño, pérdida o deterioro de los materiales e implementos de trabajo provistos por la empresa.

Sexta: Para todos los efectos legales, las partes constituyen domicilios en los lugares indicados en el encabezamiento del presente, lugar en que serán válidas todas las notificaciones derivadas del presente. Ante cualquier conflicto judicial y/o extrajudicial que pudiera derivarse del presente contrato de trabajo, las partes acuerdan que será competente la Justicia Nacional del Trabajo de Capital Federal.

Séptima: Show Business Solution S.R.L prohíbe estrictamente cualquier forma de acoso y discriminación, creando un ambiente de trabajo hostil, intimidatorio, ofensivo o abusivo. Esto incluye, sin limitación, acoso sexual, laboral y discriminación por raza, género, religión, orientación sexual, edad, discapacidad, o cualquier otra característica protegida por la ley. La violación de esta política conllevará medidas disciplinarias, incluyendo la rescisión del contrato, sin perjuicio de acciones legales.

Octava: El trabajador autoriza a la empresa a captar, reproducir y difundir su imagen y/o voz obtenidas durante la prestación de tareas, con fines institucionales y promocionales, en cualquier medio y sin contraprestación adicional, conforme al Art. 31 de la Ley 11.723. La empresa no podrá darles un uso discriminatorio ni lesivo de la dignidad del trabajador. NO se pueden sacar fotos ni generar contenido en/con/durante la convocatoria ni lugar de trabajo.

En expresión de conformidad y previa lectura de ratificación de las partes firman el presente ejemplar los días {{fecha_firma_doc}} de {{anio}}.',
  'espana', ''
))
on conflict (key) do nothing;

-- ── CÓMO QUEDÓ ──
select length(value->>'ar')     as largo_del_modelo_argentino,
       length(value->>'espana') as largo_del_de_espana
from public.config where key = 'contrato_plantilla';
--  El argentino tiene que dar unos 3.700 caracteres; el de España, 0, hasta
--  que lo carguen desde el panel.

-- ── PARA VOLVER ATRÁS ──
--  (el panel vuelve a usar el texto que trae el código)
--   delete from public.config where key = 'contrato_plantilla';
