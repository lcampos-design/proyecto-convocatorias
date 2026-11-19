/**
 * Contratos por presente — el script de las planillas "SUPERVISORES" (13-nov-2026).
 *
 * Cada 5 minutos mira las planillas de Google Sheets que se llaman
 * SUPERVISORES dd/mm "SHOW" y que cambiaron en el último día y medio, y le
 * pasa a la plataforma, por cada una, quién tiene "P" (presente) y quién "A"
 * (ausente) en la columna PRESENTES. Con eso la plataforma manda el contrato
 * de esa fecha a los presentes y anula el de los que pasan a ausentes.
 * Si una planilla no cambió desde la última vez, no la vuelve a mandar.
 *
 * Los CUIL mal escritos: si la plataforma encontró a la persona con otro CUIL,
 * la celda queda en amarillo con una nota con el del sistema, para que los
 * supervisores lo corrijan (la nota se va sola cuando se corrige). Para eso la
 * cuenta del script tiene que poder editar la planilla; si no, sólo lo avisa.
 *
 * El mail: la plataforma lo toma de la nómina o de las inscripciones. Para
 * los que no están ahí (o no tienen mail), este script lo busca en las
 * respuestas de disponibilidad del mes del show ("Disponibilidad Noviembre
 * 2026 (Respuestas)"): por el CUIL, si coincide el apellido, y si no, por
 * apellido y nombre.
 *
 * CÓMO SE INSTALA (una sola vez, con la cuenta de convocatorias del Arena):
 *  1. script.google.com → Proyecto nuevo → pegar este archivo entero.
 *  2. Configuración del proyecto (el engranaje) → Propiedades del script →
 *     Agregar: CLAVE = la misma clave que está en Vercel como PRESENTES_CLAVE
 *     (la clave no se escribe en ningún otro lado). Y, para los mails:
 *     PLANILLA_DISPONIBILIDAD = el link (o el código) de la planilla de
 *     respuestas de disponibilidad del mes; se pueden poner varias, separadas
 *     por coma. Opcional: CARPETA_DISPONIBILIDAD = el código de la carpeta de
 *     la disponibilidad (lo que va después de /folders/ en su link); sin esa
 *     propiedad busca en todo el Drive de la cuenta lo que diga
 *     "disponibilidad" o el mes en el nombre. Para los CUIL incompletos usa la
 *     planilla de altas de ARCA ("Detalle altas…"); si no la encuentra sola:
 *     PLANILLA_ALTAS = su link.
 *  3. Elegir la función "probar" y tocar Ejecutar: muestra qué planillas y
 *     qué respuestas de disponibilidad encontró, sin mandar nada. (La primera
 *     vez Google pide permiso para ver el Drive y las planillas: aceptar.)
 *  4. "revisar": qué pasaría si todos tuvieran "P", sin mandar nada.
 *  5. "instalar": deja programado que corra solo cada 5 minutos. Listo.
 *
 *  EXTERNOS (19-nov): también mira las planillas "PRESENTISMO" de cada evento (las de RR. HH., en la carpeta
 *  del evento), hoja PRESENTES: una P (o E, extra que asistió) en una fecha manda el contrato de ese día desde
 *  convocatorias.externos; una A lo anula. El evento tiene que estar en el panel (convocatoria de Externos con
 *  esa fecha y el mismo nombre). El monto es el TOTAL POR PERSONA del puesto en la "INFO RRHH" de la misma
 *  carpeta (hoja RECURSOS Y VALORES); los mails, también de ahí (hoja CONVOCATORIA). La planilla no se toca.
 *  Propiedad CARPETA_EXTERNOS = el link de la carpeta "1 - EVENTOS 2026 [Por mes]" (la de las carpetas por mes y
 *  por evento; para otro año, otra separada por coma): sin ella no ve la unidad compartida de RR. HH.
 *  Sólo fechas desde el 20-nov-2026 (o la propiedad EXTERNOS_DESDE = AAAA-MM-DD). "probar" y "revisar"
 *  muestran también lo de Externos. Necesita correr contratos-presentes-externos.sql en Supabase.
 *
 *  HOTMAIL Y OUTLOOK (19-nov): Microsoft frena los mails que salen por Resend ("Delivery Delayed"). Los contratos,
 *  recordatorios y reenvíos a casillas de Hotmail, Outlook, Live o MSN salen desde esta cuenta de Google, en cada
 *  vuelta (con "Responder" a convocatorias.arena o .externos). La primera vez reenvía así los de los últimos días
 *  que nadie abrió. "probar_google": cuántos hay en la fila, sin mandar nada.
 *
 *  EL REPORTE DE INCIDENCIAS (al terminar cada show del Arena, desde esta casilla):
 *  - Propiedad REPORTE_PARA = los mails que lo reciben, separados por coma; REPORTE_CC, los de
 *    la copia, y REPORTE_CCO, los de la copia oculta (opcionales).
 *  - "probar_reporte": el de hoy, sólo a esta casilla (o a REPORTE_PRUEBA), para ver cómo queda (la primera
 *    vez Google pide permiso para mandar mails: aceptar).
 *  - Sale solo a la 1:30 de la noche del show; "enviar_reporte" lo manda ya.
 *
 *  EL INFORME PARA SOCIOS (15-nov): uno solo, con incidencias, contratos y personal, por link a una página siempre
 *  actualizada. Sale el día siguiente del show, desde las 12, a la propiedad SOCIOS_PARA (mails separados por coma).
 *  Los socios ya no van en REPORTE_PARA / REPORTE_CC / REPORTE_CCO (ése es el del Arena).
 *  - "probar_socios": el del show de ayer, sólo a esta casilla (o a REPORTE_PRUEBA), para ver cómo queda.
 *
 *  LOS CONTRATOS FIRMADOS, AL DRIVE (18-nov): cada 15 minutos guarda los PDF firmados en la carpeta compartida
 *  de RR. HH., uno por persona, como ya se guardaban a mano: Arena "01- MARÍA BECERRA 13 /11", Externos
 *  "01- Cancillería 08,09 /11 - Contratos", y adentro "Nombre - Contrato 13-11.pdf". Si la carpeta del show ya
 *  está (con cualquier número adelante), usa ésa; si no, la crea con el número que sigue. No repite a quien ya
 *  está guardado (aunque el nombre esté en otro orden o sin tildes). La primera vez guarda todos los firmados.
 *  - Propiedades: CARPETA_FIRMADOS_ARENA (Arena y "ambas áreas"), CARPETA_FIRMADOS_EXTERNOS y, si algún día hace
 *    falta, CARPETA_FIRMADOS_ESPANA = el link o el código de la carpeta, con una subcarpeta opcional detrás
 *    ("código/03 - CONTRATOS DIGITALES": la crea si no está). Para otro año, otra carpeta: "2026:código, 2027:código".
 *    Un área sin su propiedad no se guarda (y queda para cuando se ponga).
 *  - La cuenta del script tiene que poder agregar archivos en esas carpetas (colaborador de la unidad compartida).
 *  - "probar_firmados": cuántos faltan guardar y en qué carpetas, sin guardar nada.
 *  - "guardar_firmados": los guarda ya (sin esperar los 15 minutos).
 *  - Si el registro dice que falta el permiso del Drive: ejecutar "autorizar" y, en la ventana de Google, tocar
 *    "Seleccionar todo" y "Continuar" (al autorizar se pueden destildar permisos, y el de guardar queda afuera).
 *  Para apagarlo: ejecutar "desinstalar".
 */

var VERSION = '19-nov 13:00, Externos: sin puesto en la fila, el del bloque';
var URL_PLATAFORMA = 'https://convocatorias.show-bs.com/api/presentes-planilla';
var HORAS_ATRAS = 36;   // qué planillas mira: las que cambiaron en el último día y medio
// El contrato sale al instante: en la vuelta siguiente a la P (el script corre cada 5 minutos). Thomas,
// 14-nov: "lo de la media hora no va, tiene que ser al instante". Si algún día se quiere un margen para
// corregir una P puesta por error: la propiedad ESPERA_MINUTOS (los minutos desde la hora de la P, la
// columna HORARIO, leída en la zona horaria de la planilla).
var ESPERA_MINUTOS = 0;
var MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

// La programación: cada 5 minutos.
function instalar() {
  desinstalar();
  ScriptApp.newTrigger('sincronizar').timeBased().everyMinutes(5).create();
  Logger.log('Listo: corre solo cada 5 minutos.');
}
function desinstalar() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'sincronizar') ScriptApp.deleteTrigger(t); });
}

// Muestra qué planillas y cuántas marcas encuentra, y cuántos mails trae de la disponibilidad, sin mandar nada.
function probar() {
  FRESCO_ = true;
  planillas_().forEach(function (f) {
    var p = leer_(f);
    if (!p) { Logger.log('No entiendo el nombre: ' + f.getName()); return; }
    var cuenta = function (fn) { return p.filas.filter(fn).length; };
    Logger.log(f.getName() + ' → ' + p.fecha + ' · ' + p.show + ' · ' + p.filas.length + ' personas · ' + cuenta(function (x) { return x.marca === 'P'; }) + ' P · ' + cuenta(function (x) { return x.marca === 'A'; }) + ' A · '
      + cuenta(function (x) { return !!x.mail; }) + ' con mail en la disponibilidad');
    lineaDisponibilidad_(p);
  });
  probarExternos_();
}
// Qué respuestas de disponibilidad usó y a cuántos de la planilla les encontró el mail.
function lineaDisponibilidad_(p) {
  var d = disponibilidad_(p.fecha), props = PropertiesService.getScriptProperties();
  var donde = [props.getProperty('PLANILLA_DISPONIBILIDAD') ? 'la planilla de PLANILLA_DISPONIBILIDAD' : '', props.getProperty('CARPETA_DISPONIBILIDAD') ? 'la carpeta "' + d.carpeta + '"' : 'todo el Drive'].filter(String).join(' y ');
  Logger.log('   [script ' + VERSION + '] Disponibilidad de ' + MESES[Number(p.fecha.slice(5, 7)) - 1] + ' (en ' + donde + '): '
    + (d.archivos.length ? d.archivos.join(' · ') : 'no encontré respuestas de ese mes') + ' · ' + d.total + ' mails leídos · '
    + p.filas.filter(function (x) { return !!x.mail; }).length + ' de ' + p.filas.length + ' de la planilla con mail ahí');
  var incompletos = p.filas.filter(function (x) { return x.cuil.length !== 11; });
  Logger.log('   Altas de ARCA: ' + (d.altasArchivos.length ? d.altasArchivos.join(' · ') : 'no la encontré') + ' · ' + p.filas.filter(function (x) { return x.alta; }).length + ' con otro CUIL en el alta (va el del alta) · de ' + incompletos.length + ' con el CUIL incompleto en la planilla, '
    + incompletos.filter(function (x) { return String(x.doc || '').length === 11; }).length + ' tienen el completo (' + p.filas.filter(function (x) { return x.deAltas; }).length + ' de la planilla de altas)');
  d.notas.slice(0, 10).forEach(function (n) { Logger.log('      ' + n); });
  if (!d.archivos.length) Logger.log('      Vi ' + d.vistos.length + ' planillas o formularios' + (d.vistos.length ? ': ' + d.vistos.slice(0, 12).join(' · ') : ''));
}

// Antes del show: le pregunta a la plataforma qué pasaría si todos tuvieran "P" (a cuántos
// les saldría el contrato, con qué puesto, y quiénes no: no están en ningún lado, sin mail, CUIL
// incompleto…). No manda ni guarda nada. Necesita la CLAVE.
function revisar() {
  var clave = PropertiesService.getScriptProperties().getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE (Configuración del proyecto → Propiedades del script).');
  FRESCO_ = true;
  planillas_().forEach(function (f) {
    var p = leer_(f);
    if (!p) return;
    p.simular = true;
    var r = mandar_(p, clave);
    if (!r || !r.ok) { Logger.log(f.getName() + ' → ' + JSON.stringify(r)); return; }
    Logger.log(f.getName() + ' → ' + r.fecha + ' · show del panel: ' + (r.show || '(ninguno)') + ' · ' + r.filas + ' personas · ' + JSON.stringify(r.porResultado) + marcarYContar_(f, p, r, true));
    lineaDisponibilidad_(p);
    (r.problemas || []).forEach(function (x) { Logger.log('   ' + x.sector + ' · ' + x.apellido + ', ' + x.nombre + ' → ' + x.resultado + (x.detalle ? ' (' + x.detalle + ')' : '')); });
  });
  revisarExternos_(clave);
}

// Lo que corre cada 5 minutos.
function sincronizar() {
  var clave = PropertiesService.getScriptProperties().getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE (Configuración del proyecto → Propiedades del script).');
  var guardado = PropertiesService.getScriptProperties(), inicio = Date.now();
  planillas_().forEach(function (f) {
    try {
      var p = leer_(f);
      if (!p) return;
      // Si no cambió nada desde la última vez que salió bien, no se manda de nuevo.
      var huella = Utilities.base64Encode(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, JSON.stringify(p)));
      if (guardado.getProperty('h_' + f.getId()) === huella) return;
      var vueltas = 0, r;
      do {
        r = mandar_(p, clave);
        vueltas++;
      } while (r && r.ok && r.pendientes > 0 && vueltas < 8);
      // Se recuerda sólo si salió todo: si quedó algo para corregir (un monto que faltaba, un
      // mail), en la próxima vuelta se manda de nuevo y sale apenas se corrige en el panel.
      if (r && r.ok && !r.pendientes && !r.problemas) guardado.setProperty('h_' + f.getId(), huella);
      Logger.log(f.getName() + ' → ' + JSON.stringify(sinCuiles_(r)) + marcarYContar_(f, p, r, false));
    } catch (e) {
      Logger.log('Error con ' + f.getName() + ': ' + e);
    }
  });
  // Externos (19-nov): las planillas "PRESENTISMO" de cada evento.
  try { sincronizarExternos_(clave, inicio); } catch (e) { Logger.log('Error con Externos: ' + e); }
  // Los mails a Hotmail/Outlook/Live, por Google (19-nov): los contratos de recién, los reenvíos del panel.
  try { correoGoogle_(clave); } catch (e) { Logger.log('Error con los mails por Google: ' + e); }
  // El reporte de incidencias del show de anoche, a la 1:30 (si no salió todavía).
  try { reportes_(clave); } catch (e) { Logger.log('Error con el reporte: ' + e); }
  // Los recordatorios de los contratos sin firmar: una vez por día, desde las 12.
  try { recordatorios_(clave); } catch (e) { Logger.log('Error con los recordatorios: ' + e); }
  // El informe para socios del show de ayer: una vez, desde las 12.
  try { socios_(clave); } catch (e) { Logger.log('Error con el informe para socios: ' + e); }
  // Los contratos firmados, al Drive de RR. HH.: cada 15 minutos.
  try { firmados_(clave, false); } catch (e) { Logger.log('Error con los contratos firmados: ' + e); }
}

function mandar_(p, clave) {
  var resp = UrlFetchApp.fetch(URL_PLATAFORMA, {
    method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: { 'x-clave': clave }, payload: JSON.stringify(p)
  });
  var txt = resp.getContentText();
  try { return JSON.parse(txt); } catch (_) { return { ok: false, status: resp.getResponseCode(), error: txt.slice(0, 200) }; }
}

// Las planillas "SUPERVISORES …" que cambiaron hace poco.
function planillas_() {
  var desde = Utilities.formatDate(new Date(Date.now() - HORAS_ATRAS * 3600 * 1000), 'UTC', "yyyy-MM-dd'T'HH:mm:ss");
  var it = DriveApp.searchFiles('title contains "SUPERVISORES" and mimeType = "application/vnd.google-apps.spreadsheet" and modifiedDate > "' + desde + '" and trashed = false');
  var lista = [];
  while (it.hasNext()) lista.push(it.next());
  return lista;
}

// ── Las palabras de un nombre, sin tildes ni signos, y el DNI de 8 números de un CUIL ──
var TILDES_ = new RegExp('[' + String.fromCharCode(0x300) + '-' + String.fromCharCode(0x36f) + ']', 'g');
function palabras_(s) {
  return String(s || '').normalize('NFD').replace(TILDES_, '').toLowerCase().split(/[^a-z]+/).filter(function (w) { return w.length >= 2; });
}
function nucleo_(doc) {
  var d = String(doc || '').replace(/\D/g, '');
  return d.length === 11 ? d.slice(2, 10) : (d.length >= 7 && d.length <= 8 ? ('00000000' + d).slice(-8) : '');
}

// ── El mail, de las respuestas de disponibilidad ──
// Las respuestas ("Disponibilidad Noviembre 2026 (Respuestas)") del mes del show: en la carpeta
// CARPETA_DISPONIBILIDAD y sus subcarpetas o, si no está esa propiedad, en todo el Drive, lo que se
// llame "Disponibilidad…". Del mes: el nombre del archivo o de su carpeta dice el mes ("Noviembre" o
// "Nov"). Sirven las planillas de respuestas y también los formularios: de un formulario se lee su
// planilla de respuestas o, si no tiene, las respuestas del formulario mismo. De cada respuesta: el
// correo, el CUIL (o DNI), el apellido y el nombre, por cómo se llaman las columnas (o preguntas).
// Sólo las respuestas de los 4 meses antes del show (por la "Marca temporal"): así no se mezcla la
// disponibilidad de noviembre del año pasado. Si alguien respondió más de una vez, gana la más nueva.
// Se lee una vez por mes y se guarda 25 minutos (las vueltas de cada 5 minutos no la releen; "probar"
// y "revisar" sí, siempre). Lo que vio queda en `vistos` y `notas`, para "probar".
var cacheDisp_ = {};
var MIME_HOJA_ = 'application/vnd.google-apps.spreadsheet', MIME_FORM_ = 'application/vnd.google-apps.form';
var FRESCO_ = false;   // "probar" y "revisar": siempre leen todo de nuevo
function disponibilidad_(fecha) {
  var clave = String(fecha).slice(0, 7);
  if (!cacheDisp_[clave]) {
    var res = FRESCO_ ? null : desdeCache_(clave);
    if (!res) { res = leerDisponibilidad_(clave); guardarCache_(clave, res); }
    cacheDisp_[clave] = res;
  }
  return cacheDisp_[clave];
}
function leerDisponibilidad_(clave) {
  var mes = MESES[Number(clave.slice(5, 7)) - 1] || '';
  var res = { porNucleo: {}, gente: [], items: [], archivos: [], total: 0, vistos: [], notas: [], carpeta: '', altas: [], altasArchivos: [] };
  if (!mes) return res;
  leerAltas_(res);
  var delMes = function (nombre) { var p = palabras_(nombre); return p.indexOf(mes) >= 0 || p.indexOf(mes.slice(0, 3)) >= 0; };
  var anio = Number(clave.slice(0, 4)), nMes = Number(clave.slice(5, 7));
  var desde = new Date(anio, nMes - 1, 1).getTime() - 120 * 86400000, hasta = new Date(anio, nMes, 1).getTime() + 31 * 86400000;
  var lista = [], vistas = {};
  var mirar = function (a, enMes) {
    var tipo = a.getMimeType(), nombre = a.getName();
    if (tipo !== MIME_HOJA_ && tipo !== MIME_FORM_) {
      if (/spreadsheet|excel|csv/.test(tipo) && (enMes || delMes(nombre))) res.notas.push(nombre + ': es un Excel o CSV, no lo puedo leer (abrilo y guardalo como Hoja de cálculo de Google)');
      return;
    }
    res.vistos.push(nombre);
    if ((enMes || delMes(nombre)) && !vistas[a.getId()]) { vistas[a.getId()] = 1; lista.push(a); }
  };
  var props = PropertiesService.getScriptProperties(), id = props.getProperty('CARPETA_DISPONIBILIDAD');
  // Las planillas que se le pasan directo (PLANILLA_DISPONIBILIDAD: el link o el código, una o varias
  // separadas por coma): se leen siempre, digan o no el mes en el nombre.
  var directas = {};
  (String(props.getProperty('PLANILLA_DISPONIBILIDAD') || '').match(/[-\w]{25,}/g) || []).forEach(function (d) {
    try { var a = DriveApp.getFileById(d); directas[a.getId()] = 1; mirar(a, true); }
    catch (e) { res.notas.push('No puedo abrir la planilla de PLANILLA_DISPONIBILIDAD (' + d.slice(0, 6) + '…): ¿la cuenta del script la ve?'); }
  });
  try {
    if (id) {
      var juntar = function (carpeta, enMes, nivel) {
        var f = carpeta.getFiles();
        while (f.hasNext()) mirar(f.next(), enMes);
        if (nivel >= 3) return;
        var sub = carpeta.getFolders();
        while (sub.hasNext()) { var c = sub.next(); juntar(c, enMes || delMes(c.getName()), nivel + 1); }
      };
      var raiz = DriveApp.getFolderById(id);
      res.carpeta = raiz.getName();
      juntar(raiz, delMes(raiz.getName()), 0);
    } else {
      // En todo el Drive: lo que diga "disponibilidad" o el mes ("NOVIEMBRE TODOS (Respuestas)").
      var it = DriveApp.searchFiles('(title contains "disponibilidad" or title contains "' + mes + '") and trashed = false and (mimeType = "' + MIME_HOJA_ + '" or mimeType = "' + MIME_FORM_ + '")');
      while (it.hasNext()) mirar(it.next(), false);
    }
  } catch (e) { res.notas.push('No pude abrir la carpeta o buscar en el Drive: ' + e); return res; }

  // Qué se lee: las planillas; de cada formulario, su planilla de respuestas (una sola vez) o él mismo.
  var fuentes = [], porId = {};
  var sumarFuente = function (x) { if (!porId[x.id]) { porId[x.id] = 1; fuentes.push(x); } };
  lista.forEach(function (a) {
    // Sin marca temporal, una planilla pasada directo vale igual (creada: null); las otras, por su fecha.
    var directa = !!directas[a.getId()];
    if (a.getMimeType() === MIME_HOJA_) { sumarFuente({ id: a.getId(), nombre: a.getName(), act: a.getLastUpdated(), creada: directa ? null : a.getDateCreated(), form: null }); return; }
    try {
      var form = FormApp.openById(a.getId()), dest = '';
      try { if (form.getDestinationType() === FormApp.DestinationType.SPREADSHEET) dest = form.getDestinationId(); } catch (_) {}
      if (dest) {
        try { var h = DriveApp.getFileById(dest); sumarFuente({ id: dest, nombre: h.getName(), act: h.getLastUpdated(), creada: directa ? null : h.getDateCreated(), form: null }); return; }
        catch (e) { res.notas.push(a.getName() + ': no puedo abrir su planilla de respuestas, leo el formulario'); }
      }
      sumarFuente({ id: a.getId(), nombre: a.getName() + ' (formulario)', act: a.getLastUpdated(), creada: directa ? null : a.getDateCreated(), form: form });
    } catch (e) { res.notas.push('No pude abrir el formulario ' + a.getName() + ': ' + e); }
  });
  // De la más vieja a la más nueva, para que la última respuesta de cada uno gane.
  fuentes.sort(function (a, b) { return a.act - b.act; });
  fuentes.slice(-30).forEach(function (x) {
    try {
      var tablas = x.form ? [respuestasForm_(x.form)] : SpreadsheetApp.openById(x.id).getSheets().map(function (h) { return h.getDataRange().getDisplayValues(); });
      var sumo = 0, fuera = 0, sinMail = true;
      tablas.forEach(function (v) {
        if (v.length < 2) return;
        var enc = v[0].map(function (t) { return String(t).trim().toLowerCase(); });
        var cols = function (re) { var l = []; enc.forEach(function (t, i) { if (re.test(t)) l.push(i); }); return l; };
        var iMails = cols(/correo|e-?mail|mail/), iCuil = cols(/cuil|cuit/)[0], iDni = cols(/(^|[^a-z])dni([^a-z]|$)|documento/)[0], iHora = cols(/marca temporal|timestamp/)[0];
        var iNombres = cols(/apellido|nombre/).filter(function (i) { return !/emergencia|contacto|referi|familiar|usuario/.test(enc[i]); });
        if (!iMails.length || (iCuil === undefined && iDni === undefined && !iNombres.length)) return;
        sinMail = false;
        for (var r = 1; r < v.length; r++) {
          var mail = '';
          iMails.forEach(function (i) { var m = String(v[r][i] || '').trim().toLowerCase(); if (!mail && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(m)) mail = m; });
          if (!mail) continue;
          // La respuesta tiene que ser de los meses antes del show (la Marca temporal: 21/4/2026 16:26:51).
          if (!enVentana_(iHora === undefined ? '' : v[r][iHora], x.creada, desde, hasta)) { fuera++; continue; }
          var doc = String((iCuil !== undefined ? v[r][iCuil] : '') || (iDni !== undefined ? v[r][iDni] : '') || '').replace(/\D/g, '');
          var item = { mail: mail, doc: doc, palabras: palabras_(iNombres.map(function (i) { return v[r][i]; }).join(' ')) };
          indexar_(res, item);
          sumo++;
        }
      });
      if (sumo) res.archivos.push(x.nombre + ' (' + sumo + ')');
      else res.notas.push(x.nombre + ': ' + (sinMail ? 'no encontré una columna de correo con CUIL o nombre' : 'ninguna respuesta con mail de estos meses' + (fuera ? ' (' + fuera + ' de otras fechas)' : '')));
      res.total += sumo;
    } catch (e) { res.notas.push('No pude leer ' + x.nombre + ': ' + e); }
  });
  return res;
}
function indexar_(res, item) {
  res.items.push(item);
  var n = nucleo_(item.doc);
  if (n) (res.porNucleo[n] = res.porNucleo[n] || []).push(item);
  if (item.palabras.length) res.gente.push(item);
}
// Lo leído, guardado 25 minutos en la caché del script (en pedazos: cada valor admite hasta 100 KB).
function guardarCache_(clave, res) {
  try {
    var txt = JSON.stringify({ i: res.items.map(function (x) { return [x.mail, x.doc, x.palabras.join(' ')]; }), a: res.archivos, n: res.notas, v: res.vistos.slice(0, 30), t: res.total, c: res.carpeta,
      al: res.altas.map(function (x) { return [x.doc, x.palabras.join(' ')]; }), aa: res.altasArchivos });
    var n = Math.ceil(txt.length / 40000), partes = {};
    if (!n || n > 60) return;
    for (var k = 0; k < n; k++) partes['disp_' + clave + '_' + k] = txt.slice(k * 40000, (k + 1) * 40000);
    partes['disp_' + clave] = String(n);
    CacheService.getScriptCache().putAll(partes, 1500);
  } catch (e) { Logger.log('No pude guardar la disponibilidad en la caché: ' + e); }
}
function desdeCache_(clave) {
  try {
    var c = CacheService.getScriptCache(), n = Number(c.get('disp_' + clave) || 0);
    if (!n) return null;
    var claves = [];
    for (var k = 0; k < n; k++) claves.push('disp_' + clave + '_' + k);
    var hay = c.getAll(claves), txt = '';
    for (var j = 0; j < n; j++) { if (hay[claves[j]] == null) return null; txt += hay[claves[j]]; }
    var o = JSON.parse(txt);
    var res = { porNucleo: {}, gente: [], items: [], archivos: o.a, notas: o.n, vistos: o.v, total: o.t, carpeta: o.c, deCache: true, altasArchivos: o.aa || [],
      altas: (o.al || []).map(function (x) { return { doc: x[0], palabras: x[1] ? x[1].split(' ') : [] }; }) };
    o.i.forEach(function (x) { indexar_(res, { mail: x[0], doc: x[1], palabras: x[2] ? x[2].split(' ') : [] }); });
    return res;
  } catch (e) { return null; }
}
// ── El CUIL completo, de la planilla de altas de ARCA ("DETALLE ALTAS ORIENTADORES 2026") ──
// La de la propiedad PLANILLA_ALTAS (link o código) o, sin ella, la que se llame "Detalle altas…". Una
// pestaña por mes, un bloque por show; de cada fila con encabezado APELLIDO · NOMBRE · … · CUIL, el
// CUIL de 11 números (el que validó ARCA) y el nombre. No tiene mail: sólo sirve para el CUIL.
function leerAltas_(res) {
  var ids = String(PropertiesService.getScriptProperties().getProperty('PLANILLA_ALTAS') || '').match(/[-\w]{25,}/g) || [];
  try {
    if (!ids.length) {
      var it = DriveApp.searchFiles('title contains "detalle" and title contains "altas" and trashed = false and mimeType = "' + MIME_HOJA_ + '"');
      while (it.hasNext() && ids.length < 3) ids.push(it.next().getId());
    }
  } catch (e) { res.notas.push('No pude buscar la planilla de altas: ' + e); }
  if (!ids.length) res.notas.push('No encontré la planilla de altas de ARCA (se puede poner su link en PLANILLA_ALTAS)');
  var vistos = {};
  ids.forEach(function (id) {
    try {
      var libro = SpreadsheetApp.openById(id), sumo = 0;
      libro.getSheets().forEach(function (h) {
        var col = null;
        h.getDataRange().getDisplayValues().forEach(function (fila) {
          var arriba = fila.map(function (t) { return String(t).trim().toUpperCase(); });
          var iC = arriba.indexOf('CUIL'), iA = arriba.indexOf('APELLIDO');
          if (iC >= 0 && iA >= 0) { col = { cuil: iC, ape: iA, nom: arriba.indexOf('NOMBRE') }; return; }
          if (!col) return;
          var cuil = String(fila[col.cuil] || '').replace(/\D/g, '');
          if (cuil.length !== 11) return;
          var palabras = palabras_(fila[col.ape] + ' ' + (col.nom >= 0 ? fila[col.nom] : ''));
          var k = cuil + '|' + palabras.join(' ');
          if (!palabras.length || vistos[k]) return;
          vistos[k] = 1; res.altas.push({ doc: cuil, palabras: palabras }); sumo++;
        });
      });
      res.altasArchivos.push(libro.getName() + ' (' + sumo + ' personas)');
    } catch (e) { res.notas.push('No puedo abrir la planilla de altas (' + id.slice(0, 6) + '…): ¿la cuenta del script la ve?'); }
  });
}
// El CUIL de la planilla de altas para alguien de la planilla de presentes sin CUIL completo: por el
// nombre (todas las palabras del apellido y la primera del nombre) y sólo si encaja con el que está
// incompleto (con 10 números, le falta uno; con 7 u 8, es el DNI). Si quedan dos, ninguno.
function cuilDeAltas_(d, fila) {
  var ap = palabras_(fila.apellido), nom = palabras_(fila.nombre)[0];
  if (!ap.length || !nom || !d.altas) return '';
  var docs = {};
  d.altas.forEach(function (g) { if (ap.every(function (w) { return g.palabras.indexOf(w) >= 0; }) && g.palabras.indexOf(nom) >= 0) docs[g.doc] = 1; });
  var k = Object.keys(docs).filter(function (c) { return encaja_(c, [fila.cuil, fila.doc]); });
  return k.length === 1 ? k[0] : '';
}
// ── El CUIL del alta de ARCA para cada fila (15-nov) ──
// Thomas: "no puedo estar corrigiendo en cada planilla, tenemos que ver no sólo para ella sino para los demás". El de la
// planilla lo escriben los supervisores a mano; el de la planilla de altas lo validó ARCA. Se busca por el nombre (todas las
// palabras del apellido y la primera del nombre: una sola persona) y sólo si se parece al de la planilla (le falta un número,
// es el DNI solo, otro prefijo o dígito verificador, uno o dos números distintos, dos números al revés): así no se le pone el
// de un homónimo. La plataforma usa ése para el contrato (en las filas que todavía no tienen contrato) y marca la celda.
function cerca_(cuil, parcial) {
  var p = String(parcial || '').replace(/\D/g, '');
  if (!p) return false;
  if (encaja_(cuil, [p])) return true;
  if (p.length !== 11) return false;
  var a = cuil.slice(2, 10), b = p.slice(2, 10), dif = 0, i;
  for (i = 0; i < 8; i++) if (a[i] !== b[i]) dif++;
  if (dif <= 2) return true;
  for (i = 0; i < 7; i++) if (a.slice(0, i) + a[i + 1] + a[i] + a.slice(i + 2) === b) return true;
  return false;
}
function altaDe_(d, fila) {
  var ap = palabras_(fila.apellido), nom = palabras_(fila.nombre)[0];
  if (!ap.length || !nom || !d.altas || !d.altas.length) return '';
  var docs = {};
  d.altas.forEach(function (g) { if (ap.every(function (w) { return g.palabras.indexOf(w) >= 0; }) && g.palabras.indexOf(nom) >= 0) docs[g.doc] = 1; });
  var k = Object.keys(docs);
  if (k.length !== 1 || !cuilValido_(k[0])) return '';
  return cerca_(k[0], fila.cuil) || cerca_(k[0], fila.doc) ? k[0] : '';
}
function encaja_(cuil, parciales) {
  return parciales.some(function (p) {
    p = String(p || '').replace(/\D/g, '');
    if (p.length === 10) { for (var i = 0; i < 11; i++) if (cuil.slice(0, i) + cuil.slice(i + 1) === p) return true; return false; }
    return p.length >= 7 && p.length <= 8 && nucleo_(cuil) === nucleo_(p);
  });
}
// ¿La marca temporal cae entre desde y hasta? Con 21/4/2026 (o 4/21/2026 si la planilla está en
// formato de EE. UU.: vale cualquiera de las dos) o 2026-04-21. Sin marca, la fecha del archivo.
function enVentana_(txt, creada, desde, hasta) {
  // Un día y un mes posibles (un "mes 20" no es fecha: Date lo correría al año siguiente).
  var dentro = function (anio, mes, dia) { if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return false; var t = new Date(anio, mes - 1, dia).getTime(); return t >= desde && t <= hasta; };
  var s = String(txt || ''), m = s.match(/(\d{1,2})\/(\d{1,2})\/(\d{4})/), iso = s.match(/(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return dentro(+m[3], +m[2], +m[1]) || dentro(+m[3], +m[1], +m[2]);
  if (iso) return dentro(+iso[1], +iso[2], +iso[3]);
  if (creada) { var c = new Date(creada.getTime()); return dentro(c.getFullYear(), c.getMonth() + 1, c.getDate()); }
  return creada === null;
}
// Las respuestas de un formulario como una tabla: Marca temporal, cada pregunta y el correo con que respondió.
function respuestasForm_(form) {
  var items = form.getItems(), filas = [['Marca temporal'].concat(items.map(function (i) { return i.getTitle(); }), ['Correo con que respondió'])];
  form.getResponses().forEach(function (r) {
    var por = {};
    r.getItemResponses().forEach(function (ir) { por[ir.getItem().getId()] = ir.getResponse(); });
    filas.push([Utilities.formatDate(r.getTimestamp(), 'America/Argentina/Buenos_Aires', 'd/M/yyyy HH:mm:ss')]
      .concat(items.map(function (i) { var v = por[i.getId()]; return Array.isArray(v) ? v.join(', ') : (v == null ? '' : String(v)); }), [r.getRespondentEmail() || '']));
  });
  return filas;
}
// El mail (y el documento) de una persona de la planilla en la disponibilidad.
//  1. Por el DNI que lleva el CUIL, si el apellido coincide (un CUIL mal escrito puede ser el DNI de otro).
//  2. Si no, por el nombre: todas las palabras del apellido y la primera del nombre; sólo si es una
//     persona (con dos documentos distintos, no se manda).
// Si respondió más de una vez, la respuesta más nueva.
function mailDe_(d, fila) {
  var ap = palabras_(fila.apellido), nom = palabras_(fila.nombre)[0];
  var apOk = function (g) { return !g.palabras.length || ap.some(function (w) { return w.length >= 3 && g.palabras.indexOf(w) >= 0; }); };
  var n = nucleo_(fila.cuil);
  if (n && d.porNucleo[n]) { var l = d.porNucleo[n].filter(apOk); if (l.length) return l[l.length - 1]; }
  if (!ap.length || !nom) return null;
  var hits = d.gente.filter(function (g) { return ap.every(function (w) { return g.palabras.indexOf(w) >= 0; }) && g.palabras.indexOf(nom) >= 0; });
  if (!hits.length) return null;
  var docs = {}; hits.forEach(function (h) { var k = nucleo_(h.doc); if (k) docs[k] = 1; });
  return Object.keys(docs).length > 1 ? null : hits[hits.length - 1];
}

// La marca de PRESENTES: sólo "P" o "Presente" (presente) y "A" o "Ausente" (ausente); lo demás, sin marca
// (antes, cualquier cosa que empezara con P contaba como presente: "Pendiente", "Pidió cambio").
function marca_(v) {
  var w = String(v || '').normalize('NFD').replace(TILDES_, '').toUpperCase().trim().split(/[^A-Z]+/)[0] || '';
  return w === 'P' || w === 'PRESENTE' ? 'P' : w === 'A' || w === 'AUSENTE' ? 'A' : '';
}
// "13/11/2026 17:56:18" (como la escribe la planilla) → el momento, en la zona horaria de la planilla.
function horaDe_(v, tz) {
  var s = String(v || '').trim(), m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return null;
  try { return Utilities.parseDate(m[1] + '/' + m[2] + '/' + m[3] + ' ' + m[4] + ':' + m[5] + ':' + (m[6] || '00'), tz || TZ_AR, 'd/M/yyyy H:mm:ss').getTime(); }
  catch (_) { return null; }
}
// Una planilla → { archivo, fecha, show, filas: [{ sector, cuil, rol, obs, apellido, nombre, marca, mail, doc }] }.
// El nombre trae la fecha y el show: SUPERVISORES 08/11 "FIESTA FA". El año, el de
// cuando se creó la planilla (si la fecha quedó muy atrás, es del año siguiente).
function leer_(f) {
  var m = f.getName().match(/SUPERVISORES\s+(\d{1,2})\s*[\/\-.]\s*(\d{1,2})(?:\s*[\/\-.]\s*(\d{2,4}))?\s*["“”']?([^"“”']*)/i);
  if (!m) return null;
  var dia = Number(m[1]), mes = Number(m[2]);
  var creada = f.getDateCreated(), anio = m[3] ? Number(m[3].length === 2 ? '20' + m[3] : m[3]) : creada.getFullYear();
  if (!m[3] && mes < creada.getMonth() + 1 - 6) anio++;
  var fecha = anio + '-' + ('0' + mes).slice(-2) + '-' + ('0' + dia).slice(-2);
  var show = String(m[4] || '').trim();
  // Cada sector es un bloque con su encabezado (SECTOR · APELLIDO · NOMBRE · CUIL · … · PRESENTES).
  var libro = SpreadsheetApp.openById(f.getId()), tz = libro.getSpreadsheetTimeZone ? libro.getSpreadsheetTimeZone() : TZ_AR;
  var valores = libro.getSheets()[0].getDataRange().getDisplayValues();
  // Sin la propiedad (o vacía), la de siempre: al instante (ESPERA_MINUTOS). Number(null) da 0, por eso no se usa directo.
  var ep = PropertiesService.getScriptProperties().getProperty('ESPERA_MINUTOS');
  var espera = ep === null || String(ep).trim() === '' ? ESPERA_MINUTOS : Number(ep);
  if (!(espera >= 0)) espera = ESPERA_MINUTOS;
  var filas = [], sector = '', col = null, celdas = [];
  valores.forEach(function (fila, nFila) {
    var arriba = fila.map(function (v) { return String(v).trim().toUpperCase(); });
    var iCuil = arriba.indexOf('CUIL'), iPres = arriba.indexOf('PRESENTES');
    if (iCuil >= 0 && iPres >= 0) {
      sector = String(fila[0]).trim();
      var iObs = -1;
      arriba.forEach(function (v, i) { if (iObs < 0 && /^OBSERVACI[OÓ]N/.test(v)) iObs = i; });
      col = { cuil: iCuil, pres: iPres, ape: arriba.indexOf('APELLIDO'), nom: arriba.indexOf('NOMBRE'), obs: iObs, hora: arriba.indexOf('HORARIO') };
      return;
    }
    if (!col) return;
    var cuil = String(fila[col.cuil] || '').replace(/\D/g, '');
    if (cuil.length < 7) return;
    // La primera columna (el número, o la zona en el bloque de supervisores: "Coordinador") y
    // OBSERVACIÓN ("Firmas", en el primero del P.Point): de ahí sale el puesto si no es el del bloque.
    filas.push({
      sector: sector, cuil: cuil, rol: String(fila[0] || '').trim(),
      obs: col.obs >= 0 ? String(fila[col.obs] || '').trim() : '',
      apellido: col.ape >= 0 ? String(fila[col.ape]).trim() : '',
      nombre: col.nom >= 0 ? String(fila[col.nom]).trim() : '',
      marca: marca_(fila[col.pres])
    });
    // Dónde está su CUIL en la planilla (para marcarlo si está mal escrito).
    celdas.push({ r: nFila, c: col.cuil, cuil: cuil, marca: filas[filas.length - 1].marca });
    // Todavía no pasó la espera desde la P: va, pero el contrato sale en una vuelta siguiente.
    var x = filas[filas.length - 1], t = x.marca === 'P' && espera > 0 && col.hora >= 0 ? horaDe_(fila[col.hora], tz) : null;
    if (t && Date.now() - t < espera * 60000) x.espera = true;
  });
  // El mail de la disponibilidad del mes (y el documento que dejó ahí), para quien la plataforma no tenga.
  var d = disponibilidad_(fecha);
  filas.forEach(function (x) {
    var h = mailDe_(d, x);
    if (h) { x.mail = h.mail; if (h.doc) x.doc = h.doc; }
    // Sin un CUIL completo (ni en la planilla ni en la disponibilidad): el de la planilla de altas de ARCA.
    if (x.cuil.length !== 11 && String(x.doc || '').length !== 11) { var c = cuilDeAltas_(d, x); if (c) { x.doc = c; x.deAltas = true; } }
    // El del alta de ARCA, si es otro que el de la planilla: es el que va en el contrato.
    var a = altaDe_(d, x); if (a && a !== x.cuil) x.alta = a;
  });
  // google: los de Hotmail/Outlook los manda este script por Google (19-nov, correoGoogle_).
  var p = { archivo: { id: f.getId(), nombre: f.getName() }, fecha: fecha, show: show, disponibilidad: d.total, google: true, filas: filas };
  // Las celdas no viajan a la plataforma ni cuentan para la huella (no enumerable: JSON.stringify las saltea).
  Object.defineProperty(p, 'celdas', { value: celdas, enumerable: false });
  return p;
}

// ── EXTERNOS (19-nov): la hoja PRESENTES de las planillas "PRESENTISMO" de cada evento ──
// Las arma RR. HH., una por evento, en la carpeta del evento del Drive de RR. HH. ("02 - PRESENTISMO - CAD Gelatina
// @CEC - 21-11-2026"): una fila por persona, fecha y turno, con SECTOR / PUESTO · APELLIDO · NOMBRE · CUIL · … · FECHA
// · … · PRESENTISMO. P = presente, A = ausente, E = extra que asistió (vale como P). También entiende la hoja con una
// columna por fecha ("21/11/2026 P / A"). Las hojas "Respaldo …" y "CONTROL …" no se leen. La planilla no se toca
// (Thomas, 19-nov: la columna CONTRATO es de RR. HH.).
// En la misma carpeta, la "INFO RRHH" del evento: de RECURSOS Y VALORES salen los montos (PUESTO · TOTAL POR PERSONA)
// y de CONVOCATORIA, los mails (por CUIL o DNI, o por apellido y nombre), para quien la plataforma no los tenga.
// A la plataforma va una llamada por fecha, con area 'externos'. Sólo las fechas desde EXTERNOS_DESDE (propiedad
// con una fecha AAAA-MM-DD; sin ella, el 20-nov-2026): lo de antes ya se hizo a mano y no se repite.
var EXTERNOS_DESDE = '2026-11-20';
var EXTERNOS_TOPE_MS = 150000;   // en cada vuelta, Externos no sigue después de 2 minutos y medio (lo que falta va en la próxima)
function desdeExternos_() {
  var p = String(PropertiesService.getScriptProperties().getProperty('EXTERNOS_DESDE') || '').trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(p) ? p : EXTERNOS_DESDE;
}
// Dónde están: la carpeta de la propiedad CARPETA_EXTERNOS (el link o el código de "1 - EVENTOS 2026 [Por mes]"; para
// otro año, otra separada por coma), con sus carpetas por mes ("11-NOVIEMBRE 26") y por evento ("21-11 - CAD Gelatina
// @CEC"). Sólo el mes anterior, éste y el siguiente. La búsqueda de todo el Drive no ve la unidad compartida de RR. HH.
// (19-nov: "probar" no encontraba ninguna), así que se recorren las carpetas; además, por si hay alguna fuera de ahí.
var ULTIMO_RECORRIDO_EXT_ = { carpetas: 0, raices: [], errores: [] };
function planillasExternos_() {
  var desde = Utilities.formatDate(new Date(Date.now() - HORAS_ATRAS * 3600 * 1000), 'UTC', "yyyy-MM-dd'T'HH:mm:ss");
  var q = 'title contains "PRESENTISMO" and mimeType = "application/vnd.google-apps.spreadsheet" and modifiedDate > "' + desde + '" and trashed = false';
  var lista = [], vistos = {}, sirve = function (f) {
    var n = f.getName();
    if (vistos[f.getId()] || /^\s*00\s*-/.test(n) || /\bBASE\b|[ÍI]NDICE|DUPLICAR/i.test(n)) return;   // las bases para duplicar y el índice
    vistos[f.getId()] = 1; lista.push(f);
  };
  var mesActual = Number(Utilities.formatDate(new Date(), TZ_AR, 'M')), meses = {};
  [mesActual - 1, mesActual, mesActual + 1].forEach(function (m) { meses[((m + 11) % 12) + 1] = 1; });
  ULTIMO_RECORRIDO_EXT_ = { carpetas: 0, raices: [], errores: [], deCache: false };
  // Recorrer todas las carpetas lleva unos 20 segundos: se hace cada media hora (y siempre en "probar" y "revisar") y se
  // guardan las planillas "PRESENTISMO" que hay; en las vueltas del medio sólo se mira si cambió alguna de ésas.
  var cache = CacheService.getScriptCache(), guardadas = FRESCO_ ? null : cache.get('ext_planillas');
  if (guardadas) {
    ULTIMO_RECORRIDO_EXT_.deCache = true;
    var limite = new Date(Date.now() - HORAS_ATRAS * 3600 * 1000).getTime();
    JSON.parse(guardadas).forEach(function (id) {
      try { var f = DriveApp.getFileById(id); if (!f.isTrashed() && f.getLastUpdated().getTime() > limite) sirve(f); } catch (_) {}
    });
  } else {
    var todas = [], qTodas = 'title contains "PRESENTISMO" and mimeType = "application/vnd.google-apps.spreadsheet" and trashed = false';
    var visitar = function (carpeta, nivel) {
      var n = carpeta.getName(), mes = mesDeCarpeta_(n);
      if (mes && !meses[mes]) return;                               // otro mes
      if (nivel > 0 && /CONTRATO|RECIBO|FIRMAD/i.test(n)) return;   // los contratos guardados, no
      ULTIMO_RECORRIDO_EXT_.carpetas++;
      var it = carpeta.searchFiles(qTodas), limite2 = new Date(Date.now() - HORAS_ATRAS * 3600 * 1000).getTime();
      while (it.hasNext()) { var f = it.next(); todas.push(f.getId()); if (f.getLastUpdated().getTime() > limite2) sirve(f); }
      if (nivel < 3) { var sub = carpeta.getFolders(); while (sub.hasNext()) visitar(sub.next(), nivel + 1); }
    };
    String(PropertiesService.getScriptProperties().getProperty('CARPETA_EXTERNOS') || '').split(',').forEach(function (t) {
      var m = String(t).match(/[-\w]{25,}/);
      if (!m) return;
      try { var c = DriveApp.getFolderById(m[0]); ULTIMO_RECORRIDO_EXT_.raices.push(c.getName()); visitar(c, 0); }
      catch (e) { ULTIMO_RECORRIDO_EXT_.errores.push(m[0] + ': ' + e); }
    });
    if (ULTIMO_RECORRIDO_EXT_.raices.length && !ULTIMO_RECORRIDO_EXT_.errores.length) { try { cache.put('ext_planillas', JSON.stringify(todas), 1800); } catch (_) {} }
  }
  var it2 = DriveApp.searchFiles(q);
  while (it2.hasNext()) sirve(it2.next());
  return lista;
}
// "11-NOVIEMBRE 26" → 11 (una carpeta de un mes); "21-11 - CAD Gelatina" → 0 (no es de un mes).
function mesDeCarpeta_(n) {
  var m = etiqueta_(n).match(/^\d{1,2}\s*[-.]?\s*([A-Z]+)/);
  if (!m) return 0;
  var i = MESES.map(function (x) { return x.toUpperCase(); }).indexOf(m[1] === 'SETIEMBRE' ? 'SEPTIEMBRE' : m[1]);
  return i >= 0 ? i + 1 : 0;
}
// Una celda de encabezado, para comparar: sin tildes, en mayúsculas, con un espacio entre palabras.
function etiqueta_(v) { return String(v == null ? '' : v).normalize('NFD').replace(TILDES_, '').toUpperCase().replace(/\s+/g, ' ').trim(); }
function siguiente_(fila, c) { for (var i = c + 1; i < fila.length; i++) { var t = String(fila[i] == null ? '' : fila[i]).trim(); if (t) return t; } return ''; }
// "21/11/2026", "21/11" o "2026-11-21" → "2026-11-21". Sin año, el de cuando se creó la planilla (o el siguiente).
function isoExt_(txt, creada) {
  var s = String(txt || ''), m = s.match(/(\d{4})-(\d{1,2})-(\d{1,2})/), d, mes, anio;
  if (m) { anio = Number(m[1]); mes = Number(m[2]); d = Number(m[3]); }
  else {
    m = s.match(/(\d{1,2})\s*\/\s*(\d{1,2})(?:\s*\/\s*(\d{2,4}))?/);
    if (!m) return '';
    d = Number(m[1]); mes = Number(m[2]);
    anio = m[3] ? Number(m[3].length === 2 ? '20' + m[3] : m[3]) : creada.getFullYear();
    if (!m[3] && mes < creada.getMonth() + 1 - 6) anio++;
  }
  if (!(d >= 1 && d <= 31 && mes >= 1 && mes <= 12)) return '';
  return anio + '-' + ('0' + mes).slice(-2) + '-' + ('0' + d).slice(-2);
}
// P / Presente / E / Extra (extra que asistió) → P; A / Ausente → A; lo demás, sin marca.
function marcaExt_(v) {
  var w = etiqueta_(v).split(/[^A-Z]+/)[0] || '';
  return w === 'P' || w === 'PRESENTE' || w === 'E' || w === 'EXTRA' ? 'P' : w === 'A' || w === 'AUSENTE' ? 'A' : '';
}
// Las filas de una hoja: busca el encabezado (APELLIDO y CUIL en la misma fila; a veces la fila de abajo completa los
// que van en celdas combinadas) y lee hasta el próximo encabezado. Una fila por fecha.
function filasExterno_(v, creada) {
  var out = [], col = null;
  for (var r = 0; r < v.length; r++) {
    var lab = v[r].map(etiqueta_), iApe = lab.indexOf('APELLIDO'), iCuil = lab.indexOf('CUIL');
    if (iApe >= 0 && iCuil >= 0) {
      var sub = r + 1 < v.length ? v[r + 1].map(etiqueta_) : [];
      var L = lab.map(function (x, i) { return x || sub[i] || ''; });
      // El título del bloque ("SUPERVISORES", "ORIENTADORES"), en la primera columna del encabezado: el puesto de las
      // filas que no lo dicen (19-nov: en CAD Gelatina los orientadores no tenían SECTOR).
      var b0 = String(v[r][0] || '').trim(), bloque = /[A-Za-z]{3,}/.test(b0) && !/^(SECTOR|PUESTO|CARGO|APELLIDO|NOMBRE|N[°º]?|NRO|NUMERO)\b/.test(lab[0])
        ? b0.replace(/(OR|ER)ES$/i, '$1').replace(/([^S])S$/i, '$1') : '';   // en singular: "ORIENTADORES" → "ORIENTADOR"
      var c = { ape: iApe, cuil: iCuil, nom: L.indexOf('NOMBRE'), sector: -1, fecha: L.indexOf('FECHA'), pres: -1, obs: -1, turno: L.indexOf('TURNO'), fechas: [], bloque: bloque };
      L.forEach(function (x, i) {
        if (c.sector < 0 && /^(SECTOR|PUESTO|CARGO)/.test(x)) c.sector = i;
        if (c.pres < 0 && /^(PRESENTISMO|ASISTENCIA|PRESENTES?)$/.test(x)) c.pres = i;
        if (c.obs < 0 && /^OBSERVACI/.test(x)) c.obs = i;
        var m = x.match(/\d{1,2}\s*\/\s*\d{1,2}(?:\s*\/\s*\d{2,4})?/);
        if (m && /\bP\b/.test(x.replace(m[0], ' '))) { var fe = isoExt_(m[0], creada); if (fe) c.fechas.push({ i: i, fecha: fe }); }
      });
      col = (c.fecha >= 0 && c.pres >= 0) || c.fechas.length ? c : null;
      continue;
    }
    if (!col) continue;
    var fila = v[r], cuil = String(fila[col.cuil] || '').replace(/\D/g, '');
    if (cuil.length < 7) continue;
    var obs = [col.turno >= 0 ? fila[col.turno] : '', col.obs >= 0 ? fila[col.obs] : ''].map(function (t) { return String(t || '').trim(); }).filter(String).join(' · ');
    var enFila = col.sector >= 0 ? String(fila[col.sector] || '').trim() : '';
    var base = { sector: enFila || col.bloque, deBloque: !enFila && !!col.bloque, cuil: cuil, obs: obs.slice(0, 80),
      apellido: String(fila[col.ape] || '').trim(), nombre: col.nom >= 0 ? String(fila[col.nom] || '').trim() : '' };
    var una = function (fecha, celda) { var x = {}; Object.keys(base).forEach(function (k) { x[k] = base[k]; }); x.fecha = fecha; x.marca = marcaExt_(celda); out.push(x); };
    if (col.fecha >= 0 && col.pres >= 0) { var f1 = isoExt_(fila[col.fecha], creada); if (f1) una(f1, fila[col.pres]); }
    else col.fechas.forEach(function (d) { una(d.fecha, fila[d.i]); });
  }
  return out;
}
// "02 - PRESENTISMO - CAD Gelatina @CEC - 21-11-2026" → { evento: "CAD Gelatina", lugar: "CEC", nombre: "CAD Gelatina @CEC" }.
function nombreExterno_(n) {
  var s = String(n || '').replace(/^\s*\d+\s*-\s*/, '').replace(/^\s*PRESENTISMO(\s+RRHH)?\s*-\s*/i, '').replace(/^\s*PRESENTES\s+/i, '');
  s = s.split(/\s+-\s+/)[0].trim();
  var a = s.split('@');
  return { nombre: s, evento: a[0].trim(), lugar: a.length > 1 ? a.slice(1).join('@').trim() : '' };
}
// Una planilla de Externos → { evento, lugar, nombre, hojas, filas: [{ fecha, sector, cuil, obs, apellido, nombre, marca }] }.
function leerExterno_(f) {
  var creada = f.getDateCreated(), desdeNombre = nombreExterno_(f.getName());
  var evento = '', lugar = '', filas = [], hojas = [];
  SpreadsheetApp.openById(f.getId()).getSheets().forEach(function (h) {
    if (/^(RESPALDO|CONTROL|INSTRUCCION|LEEME|COMO USAR)/.test(etiqueta_(h.getName()))) return;
    var v = h.getDataRange().getDisplayValues();
    for (var r = 0; r < Math.min(v.length, 12); r++) for (var c = 0; c < v[r].length; c++) {
      var e = etiqueta_(v[r][c]);
      if (!evento && (e === 'EVENTO' || e === 'EVENTO / SERVICIO')) evento = siguiente_(v[r], c);
      if (!lugar && (e === 'LUGAR' || e === 'LUGAR / DIRECCION')) lugar = siguiente_(v[r], c);
    }
    var l = filasExterno_(v, creada);
    if (l.length) { hojas.push(h.getName()); filas = filas.concat(l); }
  });
  // La misma persona y fecha en dos hojas (PRESENTES y la de una columna por fecha): una sola fila, con la marca que
  // haya (P antes que A) y el puesto de la que lo diga.
  var una = {}, orden = [];
  filas.forEach(function (x) {
    var k = x.fecha + '|' + x.cuil, y = una[k];
    if (!y) { una[k] = x; orden.push(k); return; }
    var gana = (x.marca === 'P' && y.marca !== 'P') || (x.marca && !y.marca) ? x : y, otra = gana === x ? y : x;
    if ((!gana.sector || gana.deBloque) && otra.sector && !otra.deBloque) { gana.sector = otra.sector; gana.deBloque = false; }
    else if (!gana.sector && otra.sector) { gana.sector = otra.sector; gana.deBloque = otra.deBloque; }
    una[k] = gana;
  });
  filas = orden.map(function (k) { return una[k]; });
  return { evento: (evento || desdeNombre.evento).slice(0, 80), lugar: (lugar || desdeNombre.lugar).slice(0, 120), nombre: desdeNombre.nombre, hojas: hojas, filas: filas };
}
// La INFO RRHH del evento (en la misma carpeta que la planilla): los montos y los mails.
function infoRrhh_(f) {
  var res = { archivo: '', tarifas: [], d: { porNucleo: {}, gente: [], items: [] } }, padres = f.getParents();
  while (padres.hasNext()) {
    var it = padres.next().getFilesByType(MimeType.GOOGLE_SHEETS), mejor = null;
    while (it.hasNext()) { var x = it.next(); if (/INFO\s*RRHH|RRHH\s*INFO/i.test(x.getName()) && (!mejor || x.getLastUpdated() > mejor.getLastUpdated())) mejor = x; }
    if (mejor) { leerInfo_(mejor, res); res.archivo = mejor.getName(); break; }
  }
  return res;
}
function leerInfo_(x, res) {
  var ya = {};
  SpreadsheetApp.openById(x.getId()).getSheets().forEach(function (h) {
    if (/^RESPALDO/.test(etiqueta_(h.getName()))) return;
    var v = h.getDataRange().getDisplayValues();
    for (var r = 0; r < v.length; r++) {
      var lab = v[r].map(etiqueta_), iP = lab.indexOf('PUESTO'), iM = -1, iMa = -1;
      lab.forEach(function (t, i) { if (iM < 0 && /^(TOTAL POR PERSONA|MONTO|VALOR|REMUNERACION)/.test(t)) iM = i; if (iMa < 0 && /^(MAIL|E-?MAIL|CORREO)/.test(t)) iMa = i; });
      // Montos: PUESTO · … · TOTAL POR PERSONA, hasta la primera fila sin puesto (sin las de TOTAL).
      if (iP >= 0 && iM >= 0) for (var k = r + 1; k < v.length; k++) {
        var puesto = String(v[k][iP] || '').trim();
        if (!puesto) break;
        if (/^TOTAL/i.test(puesto) || ya[etiqueta_(puesto)] || !/\d/.test(String(v[k][iM] || ''))) continue;
        ya[etiqueta_(puesto)] = 1;
        res.tarifas.push({ puesto: puesto, monto: String(v[k][iM]).trim() });
      }
      // Mails: APELLIDO · NOMBRE · CUIL · DNI · … · MAIL, hasta el próximo encabezado.
      var iA = lab.indexOf('APELLIDO'), iN = lab.indexOf('NOMBRE'), iC = lab.indexOf('CUIL'), iD = lab.indexOf('DNI');
      if (iA >= 0 && iMa >= 0) for (var k2 = r + 1; k2 < v.length; k2++) {
        var fila = v[k2];
        if (etiqueta_(fila[iA]) === 'APELLIDO') break;
        var mail = String(fila[iMa] || '').trim().toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) continue;
        var doc = String(iC >= 0 ? fila[iC] : '').replace(/\D/g, '') || String(iD >= 0 ? fila[iD] : '').replace(/\D/g, '');
        indexar_(res.d, { mail: mail, doc: doc, palabras: palabras_(String(fila[iA] || '') + ' ' + (iN >= 0 ? String(fila[iN] || '') : '')) });
      }
    }
  });
}
// Lo que va a la plataforma: una llamada por fecha (desde EXTERNOS_DESDE), con los montos y los mails de la INFO RRHH.
function externosPorFecha_(f, p) {
  p = p || leerExterno_(f);
  var desde = desdeExternos_(), info = infoRrhh_(f), porFecha = {};
  p.filas.forEach(function (x) { if (x.fecha >= desde) (porFecha[x.fecha] = porFecha[x.fecha] || []).push(x); });
  return Object.keys(porFecha).sort().map(function (fecha) {
    var d = disponibilidad_(fecha);
    var filas = porFecha[fecha].map(function (x) {
      var y = { sector: x.sector, cuil: x.cuil, rol: '', obs: x.obs, apellido: x.apellido, nombre: x.nombre, marca: x.marca };
      var h = mailDe_(info.d, y) || mailDe_(d, y);
      if (h) { y.mail = h.mail; var doc = String(h.doc || '').replace(/\D/g, ''); if (doc && doc !== y.cuil) y.doc = doc; }
      var a = altaDe_(d, y); if (a && a !== y.cuil) y.alta = a;
      return y;
    });
    var q = { area: 'externos', archivo: { id: f.getId(), nombre: f.getName() }, fecha: fecha, show: p.evento, nombres: [p.nombre], lugar: p.lugar, tarifas: info.tarifas, disponibilidad: d.total, google: true, filas: filas };
    Object.defineProperty(q, 'info', { value: info.archivo, enumerable: false });
    return q;
  });
}
// En cada vuelta (desde sincronizar): cada fecha que cambió desde la última vez que salió bien.
function sincronizarExternos_(clave, inicio) {
  var guardado = PropertiesService.getScriptProperties(), hoy = Utilities.formatDate(new Date(), TZ_AR, 'yyyy-MM-dd');
  planillasExternos_().forEach(function (f) {
    if (Date.now() - inicio > EXTERNOS_TOPE_MS) return;
    try {
      var lista = externosPorFecha_(f);
      if (!lista.length) return;
      var k = 'he_' + f.getId(), hechas = {};
      try { hechas = JSON.parse(guardado.getProperty(k) || '{}') || {}; } catch (_) { hechas = {}; }
      lista.forEach(function (p) {
        if (Date.now() - inicio > EXTERNOS_TOPE_MS) return;
        var huella = Utilities.base64Encode(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, JSON.stringify(p)));
        if (hechas[p.fecha] === huella) return;
        var vueltas = 0, r;
        do { r = mandar_(p, clave); vueltas++; } while (r && r.ok && r.pendientes > 0 && vueltas < 8);
        if (r && r.ok && !r.pendientes && !r.problemas) hechas[p.fecha] = huella; else delete hechas[p.fecha];
        Logger.log('Externos · ' + f.getName() + ' · ' + p.fecha + ' → ' + JSON.stringify(sinCuiles_(r)));
      });
      // Sólo se recuerdan las fechas de los últimos 60 días.
      var limite = Utilities.formatDate(new Date(Date.now() - 60 * 86400000), TZ_AR, 'yyyy-MM-dd');
      Object.keys(hechas).forEach(function (fe) { if (fe < limite) delete hechas[fe]; });
      guardado.setProperty(k, JSON.stringify(hechas));
    } catch (e) { Logger.log('Error con ' + f.getName() + ' (Externos): ' + e); }
  });
}
// Para "probar": qué lee de cada planilla de Externos, sin mandar nada.
function probarExternos_() {
  FRESCO_ = true;
  var desde = desdeExternos_(), lista = planillasExternos_();
  var rr = ULTIMO_RECORRIDO_EXT_;
  Logger.log('EXTERNOS [script ' + VERSION + '] — planillas "PRESENTISMO" que cambiaron en las últimas ' + HORAS_ATRAS + ' horas: ' + lista.length + ' · fechas desde ' + desde
    + ' · ' + (rr.raices.length ? 'carpeta "' + rr.raices.join('", "') + '" (' + rr.carpetas + ' carpetas mirando el mes anterior, éste y el siguiente)' : 'falta la propiedad CARPETA_EXTERNOS = el link de la carpeta "1 - EVENTOS 2026 [Por mes]" (sin ella no ve la unidad compartida de RR. HH.)')
    + (rr.errores.length ? ' · no pude abrir: ' + rr.errores.join(' · ') : ''));
  lista.forEach(function (f) {
    var p = leerExterno_(f);
    if (!p.filas.length) { Logger.log('   ' + f.getName() + ' → no encontré la tabla (APELLIDO, CUIL y FECHA + PRESENTISMO, o una columna por fecha "dd/mm P / A")'); return; }
    var info = infoRrhh_(f), fechas = {};
    p.filas.forEach(function (x) { var o = fechas[x.fecha] = fechas[x.fecha] || { n: 0, P: 0, A: 0 }; o.n++; if (x.marca) o[x.marca]++; });
    Logger.log('   ' + f.getName() + ' → evento "' + p.evento + '"' + (p.lugar ? ' en "' + p.lugar + '"' : '') + ' · hojas: ' + p.hojas.join(', ')
      + ' · INFO RRHH: ' + (info.archivo ? '"' + info.archivo + '" (montos: ' + (info.tarifas.length ? info.tarifas.map(function (t) { return t.puesto + ' ' + t.monto; }).join(', ') : 'no encontré RECURSOS Y VALORES con PUESTO y TOTAL POR PERSONA') + ' · ' + info.d.items.length + ' mails)' : 'no está en la carpeta'));
    Object.keys(fechas).sort().forEach(function (fe) { var o = fechas[fe]; Logger.log('      ' + fe + (fe < desde ? ' (antes de ' + desde + ': no se manda)' : '') + ' · ' + o.n + ' filas · ' + o.P + ' P/E · ' + o.A + ' A'); });
  });
}
// Para "revisar": qué pasaría si todos tuvieran P, fecha por fecha, sin mandar nada.
function revisarExternos_(clave) {
  planillasExternos_().forEach(function (f) {
    externosPorFecha_(f).forEach(function (p) {
      p.simular = true;
      var r = mandar_(p, clave);
      if (!r || !r.ok) { Logger.log('Externos · ' + f.getName() + ' · ' + p.fecha + ' → ' + JSON.stringify(r)); return; }
      Logger.log('Externos · ' + f.getName() + ' · ' + p.fecha + ' → evento del panel: ' + (r.show || '(ninguno: crealo desde el calendario de Externos)') + ' · ' + r.filas + ' personas · ' + JSON.stringify(r.porResultado));
      (r.problemas || []).slice(0, 40).forEach(function (x) { Logger.log('   ' + x.sector + ' · ' + x.apellido + ', ' + x.nombre + ' → ' + x.resultado + (x.detalle ? ' (' + x.detalle + ')' : '')); });
    });
  });
}

// ── Los mails a Hotmail, Outlook y Live, por Google (19-nov) ──
// En Resend, los contratos del 18-nov a Hotmail quedaron "Delivery Delayed": Microsoft frena lo que llega desde
// Resend. Thomas: "que salgan por Google". La plataforma deja esos mails en una fila (contratos por presente,
// recordatorios y reenvíos del panel) y acá salen con MailApp, desde esta cuenta (con "Responder" a la casilla del
// área), y se le avisa a la plataforma cuáles salieron. La primera vez, además, pone en la fila los contratos a esas
// casillas de los últimos días que nadie abrió (los demorados). MailApp ya tiene permiso (lo usan los reportes).
var URL_CORREO = 'https://convocatorias.show-bs.com/api/correo-google';
function pedirCorreo_(clave, cuerpo) {
  var resp = UrlFetchApp.fetch(URL_CORREO, { method: 'post', contentType: 'application/json', muteHttpExceptions: true, headers: { 'x-clave': clave }, payload: JSON.stringify(cuerpo) });
  try { return JSON.parse(resp.getContentText()); } catch (_) { return { ok: false, status: resp.getResponseCode() }; }
}
function correoGoogle_(clave) {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('google_demorados') !== 'hecho') {
    var d = pedirCorreo_(clave, { accion: 'demorados' });
    if (d && d.ok) { props.setProperty('google_demorados', 'hecho'); Logger.log('Por Google: ' + d.encolados + ' contratos a Hotmail/Outlook que nadie abrió, para reenviar'); }
    else Logger.log('Por Google: no pude pedir los demorados: ' + JSON.stringify(d));
  }
  var total = 0;
  for (var vuelta = 0; vuelta < 6; vuelta++) {
    var r = pedirCorreo_(clave, { accion: 'pendientes' });
    if (!r || !r.ok) { Logger.log('Por Google: no pude leer la fila: ' + JSON.stringify(r)); return total; }
    if (!r.items || !r.items.length) break;
    var hechos = [], cupo = MailApp.getRemainingDailyQuota();
    r.items.forEach(function (it) {
      if (hechos.length >= cupo) return;
      try {
        MailApp.sendEmail({ to: it.para, subject: it.subject, body: it.text, htmlBody: it.html, name: 'Show Business Solutions', replyTo: it.responder });
        hechos.push(it.pedido);
      } catch (e) { Logger.log('Por Google: no salió un mail (' + e + ')'); }
    });
    if (!hechos.length) break;
    var c = pedirCorreo_(clave, { accion: 'enviados', pedidos: hechos });
    total += hechos.length;
    // Si la plataforma no lo anotó, no se sigue (si no, en la vuelta siguiente saldrían de nuevo).
    if (!c || !c.ok) { Logger.log('Por Google: salieron ' + hechos.length + ' pero no pude avisarle a la plataforma: ' + JSON.stringify(c)); break; }
    if (hechos.length < r.items.length || !r.mas) break;
  }
  if (total) Logger.log('Por Google: ' + total + ' mails a Hotmail/Outlook/Live');
  return total;
}
// Para mirar: cuántos hay en la fila, sin mandar nada.
function probar_google() {
  var clave = PropertiesService.getScriptProperties().getProperty('CLAVE');
  var r = pedirCorreo_(clave, { accion: 'pendientes' });
  Logger.log('[script ' + VERSION + '] Por Google: ' + (r && r.ok ? r.items.length + ' mails en la fila' + (r.mas ? ' (y más)' : '') + ' · quedan ' + MailApp.getRemainingDailyQuota() + ' envíos de Google hoy' : 'no pude leer la fila: ' + JSON.stringify(r))
    + ' · demorados: ' + (PropertiesService.getScriptProperties().getProperty('google_demorados') === 'hecho' ? 'ya se pusieron en la fila' : 'se ponen en la fila en la próxima vuelta'));
}

// ── Los CUIL mal escritos, marcados en la misma planilla (Thomas, 14-nov) ──
// "Generalmente las planillas de supervisores tienen errores en números de DNI/CUIL." Cuando la plataforma
// encontró a la persona con otro CUIL (por el nombre, el DNI de la disponibilidad o el alta de ARCA), la celda
// del CUIL queda con una nota con el del sistema y, si no tenía color, pintada de amarillo, para que los
// supervisores lo corrijan. El número no se toca: lo corrige una persona. Cuando se corrige (la celda pasa a
// tener el CUIL de la nota, o uno válido que la plataforma ya no marca), la nota y el color se van solos.
// Una nota escrita por alguien no se pisa. Si la cuenta del script no puede editar la planilla, sólo lo avisa.
var NOTA_FIRMA_ = 'Nota automática del sistema de contratos: se borra sola cuando se corrige el CUIL.';
var COLOR_CUIL_ = '#fff2cc';
function cuilValido_(c) {
  c = String(c || '').replace(/\D/g, '');
  if (c.length !== 11) return false;
  var pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2], s = 0;
  for (var i = 0; i < 10; i++) s += pesos[i] * Number(c[i]);
  var r = 11 - (s % 11);
  return (r === 11 ? 0 : r) === Number(c[10]);
}
// todas: la plataforma miró todas las filas ("revisar"); si no, sólo las que tienen marca.
function marcarCuiles_(f, p, cuiles, todas) {
  var celdas = p.celdas || [], cuenta = { marcadas: 0, borradas: 0 };
  if (!celdas.length) return cuenta;
  var porCuil = {};
  (cuiles || []).forEach(function (x) { porCuil[x.cuil] = x; });
  var hoja = SpreadsheetApp.openById(f.getId()).getSheets()[0], porCol = {};
  celdas.forEach(function (c) { (porCol[c.c] = porCol[c.c] || []).push(c); });
  Object.keys(porCol).forEach(function (k) {
    var l = porCol[k], col = Number(k) + 1;
    var r0 = Math.min.apply(null, l.map(function (c) { return c.r; })), r1 = Math.max.apply(null, l.map(function (c) { return c.r; }));
    var rango = hoja.getRange(r0 + 1, col, r1 - r0 + 1, 1), notas = rango.getNotes(), fondos = rango.getBackgrounds();
    l.forEach(function (c) {
      var i = c.r - r0, nota = String(notas[i][0] || ''), fondo = String(fondos[i][0] || '').toLowerCase();
      var nuestra = nota.indexOf(NOTA_FIRMA_) >= 0, x = porCuil[c.cuil], celda = hoja.getRange(c.r + 1, col);
      if (x) {
        var texto = 'Revisar el CUIL: ' + x.motivo + '.\nEn el sistema figura ' + x.correcto + '.\n\n' + NOTA_FIRMA_;
        if (nota === texto || (nota && !nuestra)) return;
        celda.setNote(texto);
        if (fondo === '#ffffff' || fondo === '') celda.setBackground(COLOR_CUIL_);
        cuenta.marcadas++;
      } else if (nuestra) {
        var m = nota.match(/\d{2}-\d{8}-\d/), bueno = m ? m[0].replace(/\D/g, '') : '';
        var revisada = todas || !!c.marca;
        if (!(c.cuil === bueno || (revisada && cuilValido_(c.cuil)))) return;   // todavía no se corrigió
        celda.clearNote();
        if (fondo === COLOR_CUIL_) celda.setBackground(null);
        cuenta.borradas++;
      }
    });
  });
  return cuenta;
}
// Lo que devolvió la plataforma, para el registro: sin la lista de CUIL (no van al registro de ejecuciones).
function sinCuiles_(r) {
  if (!r || typeof r !== 'object') return r;
  var o = {}; Object.keys(r).forEach(function (k) { if (k !== 'cuiles') o[k] = r[k]; });
  if (r.cuiles && r.cuiles.length) o.cuilesParaCorregir = r.cuiles.length;
  return o;
}
function marcarYContar_(f, p, r, todas) {
  if (!r || !r.ok || !r.cuiles) return '';
  try {
    var c = marcarCuiles_(f, p, r.cuiles, todas);
    return c.marcadas || c.borradas ? ' · CUIL en la planilla: ' + c.marcadas + ' marcados, ' + c.borradas + ' corregidos' : '';
  } catch (e) {
    return ' · No pude marcar los CUIL mal escritos en la planilla (¿la cuenta del script puede editarla?): ' + e;
  }
}

// ── El reporte de incidencias de cada show, al terminar (13-nov-2026) ──
// Pedido de Thomas: "que finalizado el show se envíe automáticamente el reporte de incidencias vía
// mail desde convocatorias.arena". A la 1:30 (hora del Arena) de la noche del show, la vuelta de cada
// 5 minutos le pide a la plataforma las incidencias de los shows de esa fecha y manda el reporte, con el link al
// "Informe" de la gerencia (siempre actualizado, con Descargar PDF; desde el 15-nov sin PDF adjunto), desde esta casilla a los mails de la propiedad REPORTE_PARA
// (separados por coma). Uno por show y por fecha: no se repite. Si a la 1:30 no salió (el script
// estaba apagado), sale a la mañana, hasta las 14.
//   probar_reporte: el de hoy (lo cargado hasta ahora), sólo a esta casilla, para ver cómo queda.
//   enviar_reporte: el de hoy, ya, a REPORTE_PARA (por si hace falta antes de la 1:30). Es para cuando el
//                   show terminó: lo que quedó abierto se da por cerrado, como a la 1:30.
var URL_REPORTE = 'https://convocatorias.show-bs.com/api/reporte-incidencias';
var URL_RECORDATORIOS = 'https://convocatorias.show-bs.com/api/recordatorios';
var REPORTE_DESDE = 90;   // minutos desde la medianoche: 1:30
var TZ_AR = 'America/Argentina/Buenos_Aires';
var NIVELES_ = { 1: { nombre: 'Leve', una: 'leve', plural: 'leves', color: '#667080', letra: 'L' }, 2: { nombre: 'Medio', una: 'media', plural: 'medias', color: '#8A6900', letra: 'M' }, 3: { nombre: 'Grave', una: 'grave', plural: 'graves', color: '#D62839', letra: 'G' } };
var DERIVA_ = [[/seguridad/i, 'Seguridad'], [/socorrismo|enfermer[ií]a|SAME|ambulancia/i, 'Servicio médico'], [/polic[ií]a/i, 'Policía'], [/mantenimiento/i, 'Mantenimiento'], [/boleter[ií]a/i, 'Boletería'], [/coordinaci[oó]n/i, 'Coordinación'], [/Atenci[oó]n al Cliente/i, 'Atención al Cliente']];
var DIAS_ = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];

function fAr_(d, fmt) { return Utilities.formatDate(d, TZ_AR, fmt); }
function diaFuncion_(ahora) { return fAr_(new Date((ahora || new Date()).getTime() - 6 * 3600000), 'yyyy-MM-dd'); }
// Qué fecha toca mandar ahora: de 1:30 a 6, el show de esta noche; de 6 a 14, el de anoche (si no salió).
function reporteFechaDebida_(ahora) {
  ahora = ahora || new Date();
  var hm = fAr_(ahora, 'HH:mm').split(':'), min = Number(hm[0]) * 60 + Number(hm[1]);
  if (min >= REPORTE_DESDE && min < 360) return diaFuncion_(ahora);
  if (min >= 360 && min < 840) return fAr_(new Date(ahora.getTime() - 30 * 3600000), 'yyyy-MM-dd');
  return '';
}
// cerrar: el show ya terminó (el envío a mano): lo que quedó abierto se da por cerrado, como a la 1:30.
function pedirReporte_(fecha, clave, cerrar) {
  var resp = UrlFetchApp.fetch(URL_REPORTE, { method: 'post', contentType: 'application/json', muteHttpExceptions: true, headers: { 'x-clave': clave }, payload: JSON.stringify(cerrar ? { fecha: fecha, cerrar: true } : { fecha: fecha }) });
  try { return JSON.parse(resp.getContentText()); } catch (_) { return { ok: false, status: resp.getResponseCode() }; }
}
// ── Recordatorios de los contratos sin firmar (14-nov) ──
// Uno por día, al mediodía, a cada contrato enviado y sin firmar (de cualquier show: Arena, Externos y
// España), hasta que lo firme o venza el link (7 días). Lo decide la plataforma (api/recordatorios.js);
// acá sólo se pide una vez por día, desde las 12 (y hasta las 20, por si a esa hora el script no corrió).
// La propiedad "recordatorios_<fecha>" queda cuando salieron todos los de ese día.
function pedirRecordatorios_(clave, extra) {
  var resp = UrlFetchApp.fetch(URL_RECORDATORIOS, { method: 'post', contentType: 'application/json', muteHttpExceptions: true, headers: { 'x-clave': clave }, payload: JSON.stringify(extra || {}) });
  try { return JSON.parse(resp.getContentText()); } catch (_) { return { ok: false, status: resp.getResponseCode() }; }
}
// Arrancan el 15-nov al mediodía (así, pegando el script hoy, se puede mirar antes con probar_recordatorio).
var RECORDATORIOS_DESDE = '2026-11-15';
function recordatorios_(clave) {
  var ahora = new Date(), hoy = Utilities.formatDate(ahora, TZ_AR, 'yyyy-MM-dd'), hora = Number(Utilities.formatDate(ahora, TZ_AR, 'H'));
  if (hoy < RECORDATORIOS_DESDE || hora < 12 || hora >= 20) return;
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('recordatorios_' + hoy)) return;
  var vueltas = 0, r, total = 0, problemas = 0, google = 0;
  do {
    r = pedirRecordatorios_(clave, { google: true });   // los de Hotmail/Outlook, a la fila de Google (19-nov)
    vueltas++;
    if (r && r.ok) { total += r.enviados || 0; problemas += r.problemas || 0; google += r.porGoogle || 0; }
  } while (r && r.ok && r.pendientes > 0 && vueltas < 8);
  if (google) correoGoogle_(clave);
  Logger.log('Recordatorios de contratos sin firmar → ' + total + ' enviados' + (google ? ' + ' + google + ' por Google (Hotmail/Outlook)' : '') + (problemas ? ', ' + problemas + ' con problema: ' + JSON.stringify(r.errores || []) : '') + (r && r.ok ? '' : ' · ' + JSON.stringify(r)));
  if (r && r.ok && !r.pendientes) props.setProperty('recordatorios_' + hoy, new Date().toISOString() + ' · ' + total + ' enviados');
}
// Para mirar antes (no manda nada a nadie): un recordatorio de ejemplo a REPORTE_PRUEBA (o a esta
// casilla) y, en el registro, cuántos saldrían hoy y a quiénes.
function probar_recordatorio() {
  var props = PropertiesService.getScriptProperties(), clave = props.getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE.');
  var yo = String(props.getProperty('REPORTE_PRUEBA') || '').trim() || Session.getEffectiveUser().getEmail();
  var p = pedirRecordatorios_(clave, { prueba: yo });
  Logger.log(p && p.ok ? 'Recordatorio de ejemplo mandado a ' + yo : 'No salió el de ejemplo: ' + JSON.stringify(p));
  var s = pedirRecordatorios_(clave, { simular: true });
  if (!s || !s.ok) { Logger.log('No se pudo ver cuántos saldrían: ' + JSON.stringify(s)); return; }
  Logger.log('Si los recordatorios salieran ahora, le llegaría uno a ' + s.saldrian + ' persona(s):');
  (s.lista || []).forEach(function (x) { Logger.log('   · ' + x.nombre + ' — ' + (x.show || 'sin show') + (x.fecha ? ' ' + x.fecha : '') + (x.estado === 'visto' ? ' (lo abrió)' : ' (no lo abrió)')); });
}

// Lo que corre en cada vuelta (desde sincronizar).
function reportes_(clave) {
  var props = PropertiesService.getScriptProperties(), para = String(props.getProperty('REPORTE_PARA') || '').trim();
  if (!para) return;
  var f = reporteFechaDebida_();
  if (!f || props.getProperty('rep_' + f)) return;
  var r = pedirReporte_(f, clave);
  if (!r || !r.ok) { Logger.log('Reporte ' + f + ': ' + JSON.stringify(r)); return; }
  var todos = true;
  (r.shows || []).forEach(function (s) {
    var k = 'rep_' + f + '_' + s.conv_id;
    if (props.getProperty(k)) return;
    try { mandarReporte_(s, para, false); props.setProperty(k, new Date().toISOString()); Logger.log('Reporte enviado: ' + s.nombre + ' ' + f); }
    catch (e) { todos = false; Logger.log('No salió el reporte de ' + s.nombre + ': ' + e); }
  });
  if (todos) props.setProperty('rep_' + f, new Date().toISOString() + ' · ' + (r.shows || []).length + ' show(s)');
}
function probar_reporte() {
  var clave = PropertiesService.getScriptProperties().getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE.');
  // La prueba va a REPORTE_PRUEBA (un mail que se pueda mirar) o, si no está, a esta casilla.
  var f = reporteFechaDebida_() || diaFuncion_(), r = pedirReporte_(f, clave), yo = String(PropertiesService.getScriptProperties().getProperty('REPORTE_PRUEBA') || '').trim() || Session.getEffectiveUser().getEmail();
  if (!r || !r.ok) { Logger.log('No se pudo: ' + JSON.stringify(r)); return; }
  if (!(r.shows || []).length) { Logger.log('Hoy (' + f + ') no hay shows del Centro de Control del Arena.'); return; }
  r.shows.forEach(function (s) { mandarReporte_(s, yo, true); Logger.log('Prueba mandada a ' + yo + ': ' + s.nombre + ' · ' + s.incidencias.length + ' incidencias · ' + (s.link ? 'con el link al informe (sin PDF adjunto)' : 'sin link: con el PDF de respaldo adjunto')); });
  Logger.log('Destinatarios para el envío de verdad (REPORTE_PARA): ' + (PropertiesService.getScriptProperties().getProperty('REPORTE_PARA') || '(falta la propiedad)'));
}
function enviar_reporte() {
  var props = PropertiesService.getScriptProperties(), clave = props.getProperty('CLAVE'), para = String(props.getProperty('REPORTE_PARA') || '').trim();
  if (!clave || !para) throw new Error('Faltan las propiedades CLAVE o REPORTE_PARA.');
  var f = reporteFechaDebida_() || diaFuncion_(), r = pedirReporte_(f, clave, true);
  if (!r || !r.ok) { Logger.log('No se pudo: ' + JSON.stringify(r)); return; }
  if (!(r.shows || []).length) { Logger.log('Hoy (' + f + ') no hay shows del Centro de Control del Arena.'); return; }
  (r.shows || []).forEach(function (s) { mandarReporte_(s, para, false); props.setProperty('rep_' + f + '_' + s.conv_id, new Date().toISOString()); Logger.log('Enviado: ' + s.nombre); });
  props.setProperty('rep_' + f, new Date().toISOString() + ' · a mano');
}

// ── El informe para socios (15-nov) ──
// Thomas: "que no reciban más el informe sólo con los del Arena, sino que reciban sólo uno ellos con el informe de
// incidencias, informe de contratos, etc., para poner todo en uno"; "como con los del Arena, que reciben un link a un
// portal"; al día siguiente, a las 12 (ya firmó la mayoría). El link lo arma la plataforma (/socios?t=…).
var SOCIOS_DESDE = '2026-11-16';
function socios_(clave) {
  var props = PropertiesService.getScriptProperties(), para = String(props.getProperty('SOCIOS_PARA') || '').trim();
  if (!para) return;
  var ahora = new Date(), hoy = fAr_(ahora, 'yyyy-MM-dd'), hora = Number(fAr_(ahora, 'H'));
  if (hoy < SOCIOS_DESDE || hora < 12 || hora >= 20) return;
  var f = fAr_(new Date(ahora.getTime() - 24 * 3600000), 'yyyy-MM-dd');   // el show de ayer
  if (props.getProperty('soc_' + f)) return;
  var r = pedirReporte_(f, clave);
  if (!r || !r.ok) { Logger.log('Informe para socios ' + f + ': ' + JSON.stringify(r)); return; }
  var todos = true;
  (r.shows || []).forEach(function (s) {
    var k = 'soc_' + f + '_' + s.conv_id;
    if (props.getProperty(k)) return;
    if (!s.link_socios) { todos = false; Logger.log('Informe para socios de ' + s.nombre + ': no llegó el link'); return; }
    try { mandarSocios_(s, para, false); props.setProperty(k, new Date().toISOString()); Logger.log('Informe para socios enviado: ' + s.nombre + ' ' + f); }
    catch (e) { todos = false; Logger.log('No salió el informe para socios de ' + s.nombre + ': ' + e); }
  });
  if (todos) props.setProperty('soc_' + f, new Date().toISOString() + ' · ' + (r.shows || []).length + ' show(s)');
}
// Para mirarlo antes: el del show de ayer, sólo a REPORTE_PRUEBA (o a esta casilla).
function probar_socios() {
  var props = PropertiesService.getScriptProperties(), clave = props.getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE.');
  var yo = String(props.getProperty('REPORTE_PRUEBA') || '').trim() || Session.getEffectiveUser().getEmail();
  var f = fAr_(new Date(Date.now() - 24 * 3600000), 'yyyy-MM-dd'), r = pedirReporte_(f, clave);
  if (!r || !r.ok) { Logger.log('No se pudo: ' + JSON.stringify(r)); return; }
  if (!(r.shows || []).length) { Logger.log('Ayer (' + f + ') no hubo shows del Centro de Control del Arena.'); return; }
  r.shows.forEach(function (s) { mandarSocios_(s, yo, true); Logger.log('Prueba mandada a ' + yo + ': ' + s.nombre + ' ' + f); });
  Logger.log('Destinatarios para el envío de verdad (SOCIOS_PARA): ' + (props.getProperty('SOCIOS_PARA') || '(falta la propiedad)'));
}
function mandarSocios_(s, para, prueba) {
  var ddmm = s.fecha.slice(8, 10) + '/' + s.fecha.slice(5, 7), d = new Date(s.fecha + 'T12:00:00-03:00');
  var cuando = DIAS_[Number(fAr_(d, 'u')) % 7] + ' ' + Number(s.fecha.slice(8, 10)) + ' de ' + MESES[Number(s.fecha.slice(5, 7)) - 1];
  var t1 = 'Les compartimos el informe del show de ' + s.nombre + ' del ' + cuando + ' en el ' + (s.venue || 'Movistar Arena') + ': los contratos, el personal y las incidencias, en un solo lugar.';
  var t2 = 'Está siempre actualizado (por ejemplo, con los contratos que se firmen después). Si lo necesitan en PDF, se descarga desde ahí.';
  var texto = 'Hola:\n\n' + t1 + '\n\n' + t2 + '\n\nVer el informe: ' + s.link_socios + (s.link_todos_socios ? '\n\nTodos los informes, en un solo lugar: ' + s.link_todos_socios : '') + '\n\nSaludos,\nGerencia de RR. HH. · Show Business Solutions';
  var SITIO = 'https://convocatorias.show-bs.com', P = 'margin:0 0 16px;font-size:15px;line-height:1.65;color:#374151';
  var html = '<div style="background:#f5f5f7;margin:0;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,Helvetica,Arial,sans-serif">'
    + '<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:8px;padding:40px 44px">'
    + '<img src="' + SITIO + '/logo-sbs.png" alt="Show Business Solutions" width="56" height="56" style="display:block;width:56px;height:56px;border:0;margin-bottom:22px">'
    + '<p style="' + P + '">Hola:</p><p style="' + P + '">' + esc_(t1) + '</p><p style="' + P + '">' + esc_(t2) + '</p>'
    + '<p style="margin:22px 0"><a href="' + esc_(s.link_socios) + '" style="display:inline-block;background:#0f1117;color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;padding:14px 26px;border-radius:10px">Ver el informe</a></p>'
    + (s.link_todos_socios ? '<p style="' + P + '">Todos los informes de los shows, en un solo lugar: <a href="' + esc_(s.link_todos_socios) + '" style="color:#0f1117;font-weight:bold">ver todos los informes</a>.</p>' : '')
    + '<div style="margin-top:28px;padding-top:22px;border-top:1px solid #ececf1">'
    + '<img src="' + SITIO + '/firmas/firma-rrhh.jpg" alt="Show Business Solutions · Gerencia de RR. HH." width="300" style="max-width:300px;width:100%;height:auto;display:block;border:0"></div>'
    + '</div></div>';
  MailApp.sendEmail({ to: para, subject: (prueba ? '[Prueba] ' : '') + 'Informe del show - ' + s.nombre + ' ' + ddmm, body: texto, htmlBody: html, name: 'Show Business Solutions' });
}

function mandarReporte_(s, para, prueba) {
  var ddmm = s.fecha.slice(8, 10) + '/' + s.fecha.slice(5, 7);
  var asunto = (prueba ? '[Prueba] ' : '') + 'Reporte de incidencias - ' + s.nombre + ' ' + ddmm;
  var c = cuerpoReporte_(s), o = { to: para, subject: asunto, body: c.texto, htmlBody: c.html, name: 'Show Business Solutions' };
  // Sin PDF adjunto (Thomas, 15-nov: 'si editamos la gravedad, el pdf está con la data vieja; si lo quieren en pdf,
  // que lo descarguen del link'): el link muestra siempre lo actualizado y tiene 'Descargar PDF'. Sólo si no
  // llegó el link (no debería pasar) va el PDF de respaldo, para que el mail no salga vacío.
  if (!s.link) {
    var nombrePdf = 'Reporte de incidencias - ' + s.nombre + ' ' + ddmm.replace('/', '-') + '.pdf';
    o.attachments = [s.pdf ? Utilities.newBlob(Utilities.base64Decode(s.pdf), MimeType.PDF, nombrePdf)
      : Utilities.newBlob(htmlReporte_(s, logoReporte_()), MimeType.HTML, 'reporte.html').getAs(MimeType.PDF).setName(nombrePdf)];
  }
  // En copia (REPORTE_CC) y en copia oculta (REPORTE_CCO), separados por coma; la prueba, sin copias.
  if (!prueba) {
    var props = PropertiesService.getScriptProperties(), cc = String(props.getProperty('REPORTE_CC') || '').trim(), cco = String(props.getProperty('REPORTE_CCO') || '').trim();
    if (cc) o.cc = cc;
    if (cco) o.bcc = cco;
  }
  MailApp.sendEmail(o);
}
var logoCache_ = null;
function logoReporte_() {
  if (logoCache_ !== null) return logoCache_;
  try { logoCache_ = 'data:image/png;base64,' + Utilities.base64Encode(UrlFetchApp.fetch('https://convocatorias.show-bs.com/logo-sbs.png').getBlob().getBytes()); }
  catch (_) { logoCache_ = ''; }
  return logoCache_;
}

// ── Los números del show (los mismos que el "Informe" de la gerencia) ──
function derivadoA_(i) { var a = []; (i.acciones || []).forEach(function (x) { DERIVA_.forEach(function (d) { if (d[0].test(x) && a.indexOf(d[1]) < 0) a.push(d[1]); }); }); return a; }
function nivel_(i) { return NIVELES_[i.nivel] ? i.nivel : 1; }
function minutosTexto_(ms) { var m = Math.round(ms / 60000); return m < 60 ? m + ' min' : m < 1440 ? Math.floor(m / 60) + ' h ' + ('0' + (m % 60)).slice(-2) + ' min' : Math.floor(m / 1440) + ' d ' + Math.floor((m % 1440) / 60) + ' h'; }
// "G1", "M2": por gravedad, en el orden en que se cargaron.
function codigos_(l) {
  var cod = {}, n = {};
  l.slice().sort(function (a, b) { return String(a.created_at).localeCompare(String(b.created_at)) || String(a.id).localeCompare(String(b.id)); })
    .forEach(function (i) { var nv = nivel_(i); n[nv] = (n[nv] || 0) + 1; cod[i.id] = NIVELES_[nv].letra + n[nv]; });
  return cod;
}
// El momento más cargado: franjas de 15, 30, 60 o 120 minutos (la más fina que deje 16 o menos), como la gerencia.
function pico_(l) {
  var ts = l.map(function (i) { return new Date(i.created_at).getTime(); }).filter(function (t) { return !isNaN(t); }).sort(function (a, b) { return a - b; });
  if (!ts.length) return '';
  var paso = [15, 30, 60, 120].filter(function (p) { return (ts[ts.length - 1] - ts[0]) / (p * 60000) < 16; })[0] || 240, pms = paso * 60000, off = 3 * 3600000;
  var ini = Math.floor((ts[0] - off) / pms) * pms + off, mejor = null;
  for (var a = ini; a <= ts[ts.length - 1]; a += pms) {
    var n = ts.filter(function (t) { return t >= a && t < a + pms; }).length;
    if (n > (mejor ? mejor.n : 0)) mejor = { a: a, n: n };
  }
  return mejor ? fAr_(new Date(mejor.a), 'HH:mm') : '';
}
function cuentaPor_(l, fn) {
  var m = {}; l.forEach(function (i) { var k = fn(i) || '—'; m[k] = (m[k] || 0) + 1; });
  return Object.keys(m).map(function (k) { return [k, m[k]]; }).sort(function (a, b) { return b[1] - a[1] || a[0].localeCompare(b[0]); });
}
function resumenReporte_(s) {
  var l = s.incidencias || [], res = l.filter(function (i) { return i.estado === 'resuelta'; });
  var tiempos = res.filter(function (i) { return i.resuelta_at && i.created_at; }).map(function (i) { return new Date(i.resuelta_at) - new Date(i.created_at); }).filter(function (x) { return x >= 0; });
  return {
    total: l.length, abiertas: l.length - res.length, resueltas: res.length,
    porNivel: [3, 2, 1].map(function (nv) { return [nv, l.filter(function (i) { return nivel_(i) === nv; }).length]; }),
    asistencias: l.filter(function (i) { return i.categoria === 'Asistencia'; }).length,
    derivadas: l.filter(function (i) { return derivadoA_(i).length; }).length,
    tMedio: tiempos.length ? minutosTexto_(tiempos.reduce(function (a, b) { return a + b; }, 0) / tiempos.length) : '—',
    pico: pico_(l) || '—'
  };
}

// ── El mail ──
function cuerpoReporte_(s) {
  var r = resumenReporte_(s), d = new Date(s.fecha + 'T12:00:00-03:00');
  var cuando = DIAS_[Number(fAr_(d, 'u')) % 7] + ' ' + Number(s.fecha.slice(8, 10)) + ' de ' + MESES[Number(s.fecha.slice(5, 7)) - 1];
  // Sin el detalle por criticidad (Thomas, 15-nov): si después se corrige una, el número del mail queda viejo; el
  // detalle está en el link, siempre actualizado. Queda el total y si están resueltas (a la 1:30 se cierra lo abierto).
  var res = r.total && r.resueltas === r.total ? (r.total === 1 ? 'resuelta' : 'todas resueltas') : r.resueltas + (r.resueltas === 1 ? ' resuelta' : ' resueltas');
  var detalle = r.total ? r.total + (r.total === 1 ? ' incidencia' : ' incidencias') + ', ' + res + '.' : 'no se registraron incidencias.';
  var t1 = 'Les compartimos el reporte de incidencias del show de ' + s.nombre + ' del ' + cuando + ' en el ' + (s.venue || 'Movistar Arena') + ': ' + detalle;
  var t2 = s.link ? 'Pueden verlo en el sistema, siempre actualizado, con el resumen y la línea de tiempo de cada incidencia. Si lo necesitan en PDF, se descarga desde ahí.' : 'Va adjunto en PDF, con el resumen y la línea de tiempo de cada incidencia.';
  var texto = 'Hola a todos:\n\n' + t1 + '\n\n' + t2 + (s.link ? '\n\nVer el informe: ' + s.link : '') + (s.link_todos ? '\n\nTodos los informes, en un solo lugar: ' + s.link_todos : '') + '\n\nSaludos,\nShow Business Solutions\nconvocatorias.arena@show-bs.com';
  var SITIO = 'https://convocatorias.show-bs.com', P = 'margin:0 0 16px;font-size:15px;line-height:1.65;color:#374151';
  var html = '<div style="background:#f5f5f7;margin:0;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,Helvetica,Arial,sans-serif">'
    + '<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:8px;padding:40px 44px">'
    + '<img src="' + SITIO + '/logo-sbs.png" alt="Show Business Solutions" width="56" height="56" style="display:block;width:56px;height:56px;border:0;margin-bottom:22px">'
    + '<p style="' + P + '">Hola a todos:</p><p style="' + P + '">' + esc_(t1) + '</p><p style="' + P + '">' + esc_(t2) + '</p>'
    + (s.link ? '<p style="margin:22px 0"><a href="' + esc_(s.link) + '" style="display:inline-block;background:#0f1117;color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;padding:14px 26px;border-radius:10px">Ver el informe</a></p>' : '')
    + (s.link_todos ? '<p style="' + P + '">Todos los informes de los shows, en un solo lugar: <a href="' + esc_(s.link_todos) + '" style="color:#0f1117;font-weight:bold">ver todos los informes</a>.</p>' : '')
    + '<div style="margin-top:28px;padding-top:22px;border-top:1px solid #ececf1">'
    + '<img src="' + SITIO + '/firmas/firma-rrhh.jpg" alt="Show Business Solutions · Gerencia de RR. HH." width="300" style="max-width:300px;width:100%;height:auto;display:block;border:0"></div>'
    + '</div>'
    + '<div style="max-width:560px;margin:16px auto 0;text-align:center;font-size:11px;color:#9ca3af;line-height:1.7">Show Business Solutions · <a href="https://show-bs.com/" style="color:#9ca3af;text-decoration:underline">show-bs.com</a><br>Instagram <a href="https://www.instagram.com/showbs/" style="color:#9ca3af;text-decoration:underline">@showbs</a> · <a href="https://www.instagram.com/showbspain/" style="color:#9ca3af;text-decoration:underline">@showbspain</a></div>'
    + '</div>';
  return { texto: texto, html: html };
}
function esc_(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }

// ── El PDF: el "Informe" de la gerencia, en tablas (lo que entiende el conversor de Google) ──
function htmlReporte_(s, logo) {
  var l = (s.incidencias || []).slice().sort(function (a, b) { return String(a.created_at).localeCompare(String(b.created_at)); });
  var r = resumenReporte_(s), cods = codigos_(l), T = '#1A1A1A', G = '#5C5C5C', L = '#DADADA';
  var fh = function (iso) { return iso ? fAr_(new Date(iso), 'dd/MM HH:mm') : ''; };
  var cuando = s.fecha.slice(8, 10) + '/' + s.fecha.slice(5, 7) + '/' + s.fecha.slice(0, 4);
  var num = function (v, t) { return '<td style="border:1.5px solid ' + T + ';padding:7px 9px;width:14%"><div style="font-size:16px;font-weight:bold">' + esc_(v) + '</div><div style="font-size:8.5px;color:' + G + '">' + t + '</div></td>'; };
  var tabla = function (titulo, pares) {
    return '<td style="vertical-align:top;width:33%;padding-right:14px"><div style="font-size:10.5px;font-weight:bold;margin:0 0 5px">' + titulo + '</div><table style="border-collapse:collapse;width:100%">'
      + (pares.length ? pares : [['—', 0]]).map(function (p) { return '<tr><td style="border-bottom:1px solid ' + L + ';padding:4px 5px;font-size:10px">' + esc_(p[0]) + '</td><td style="border-bottom:1px solid ' + L + ';padding:4px 5px;text-align:right;font-weight:bold;font-size:10px">' + p[1] + '</td></tr>'; }).join('') + '</table></td>';
  };
  var th = function (t) { return '<th bgcolor="' + T + '" style="background-color:' + T + ';color:#FFFFFF;padding:5px;text-align:left;font-size:9px;font-weight:bold"><font color="#FFFFFF">' + t + '</font></th>'; };
  var td = 'border-bottom:1px solid ' + L + ';padding:5px;vertical-align:top;font-size:9px';
  var filas = l.map(function (i) {
    var nv = nivel_(i);
    return '<tr><td style="' + td + '">' + fh(i.created_at) + '</td>'
      + '<td style="' + td + '">' + esc_(i.sector) + (i.ubicacion ? '<br><span style="color:' + G + '">' + esc_(i.ubicacion) + '</span>' : '') + '</td>'
      + '<td style="' + td + '">' + esc_(i.tipo) + '<br><span style="color:' + G + '">' + esc_(i.categoria) + '</span>' + (i.nota ? '<br>' + esc_(i.nota) : '') + '</td>'
      + '<td style="' + td + ';font-weight:bold;color:' + NIVELES_[nv].color + '">' + NIVELES_[nv].nombre + ' · ' + cods[i.id] + '</td>'
      + '<td style="' + td + '">' + (i.acciones || []).map(esc_).join('<br>') + '</td>'
      + '<td style="' + td + '">' + (derivadoA_(i).map(esc_).join(', ') || '—') + '</td>'
      + '<td style="' + td + '">' + (i.estado === 'resuelta' ? (i.resuelta_at ? fh(i.resuelta_at) + ' · ' : '') + esc_(i.resolucion || '') : '<b>Abierta</b>') + '</td></tr>';
  }).join('');
  return '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Poppins,Arial,Helvetica,sans-serif;color:' + T + ';font-size:10px;margin:0">'
    + '<table style="border-collapse:collapse;width:100%;border-bottom:2px solid ' + T + ';margin-bottom:12px"><tr>'
    + (logo ? '<td style="width:52px;padding:0 12px 10px 0"><img src="' + logo + '" width="42" height="42"></td>' : '')
    + '<td style="padding:0 0 10px 0"><div style="font-size:9.5px;font-weight:bold;color:' + G + '">AX · Audience Experience · Informe del show</div>'
    + '<div style="font-size:18px;font-weight:bold;margin:2px 0">Informe de incidencias · ' + esc_(s.nombre) + '</div>'
    + '<div style="font-size:10px;color:' + G + '">' + cuando + ' · ' + esc_(s.venue || 'Movistar Arena') + ' · generado ' + fAr_(new Date(), 'dd/MM/yyyy HH:mm') + '</div></td></tr></table>'
    + '<table style="border-collapse:separate;border-spacing:6px 0;width:100%;margin:0 0 16px -6px"><tr>'
    + num(r.total, 'Incidencias') + num(r.abiertas, 'Abiertas') + num(r.porNivel[0][1], 'Graves') + num(r.asistencias, 'Asistencias') + num(r.derivadas, 'Derivadas') + num(r.tMedio, 'Resolución media') + num(r.pico, 'Momento más cargado')
    + '</tr></table>'
    + '<table style="border-collapse:collapse;width:100%;margin-bottom:16px"><tr>'
    + tabla('Criticidad', r.porNivel.map(function (p) { return [NIVELES_[p[0]].nombre, p[1]]; })) + tabla('Categoría', cuentaPor_(l, function (i) { return i.categoria; })) + tabla('Sector', cuentaPor_(l, function (i) { return i.sector; }))
    + '</tr></table>'
    + '<div style="font-size:10.5px;font-weight:bold;margin:0 0 5px">Línea de tiempo</div>'
    + (l.length ? '<table style="border-collapse:collapse;width:100%"><tr>' + th('Cuándo') + th('Sector') + th('Qué pasó') + th('Criticidad') + th('Qué se hizo') + th('Derivado a') + th('Cómo se resolvió') + '</tr>' + filas + '</table>'
      : '<div style="font-size:10px;color:' + G + '">No se registraron incidencias en este show.</div>')
    + '</body></html>';
}

// ── Los contratos firmados, al Drive compartido de RR. HH. (18-nov) ──
// Pedido de Mercedes: "que se descarguen y guarden en el drive en la carpeta del Arena", "tanto del Arena como
// Externos". La plataforma (api/contratos-firmados.js) da los firmados de a pocos, en orden de firma, con el PDF,
// la carpeta del show y el nombre del archivo; acá se guardan y se recuerda hasta cuál (firmados_desde_<área>).
var URL_FIRMADOS = 'https://convocatorias.show-bs.com/api/contratos-firmados';
var FIRMADOS_CADA_MIN = 15;
var FIRMADOS_AREAS = { arena: 'CARPETA_FIRMADOS_ARENA', externos: 'CARPETA_FIRMADOS_EXTERNOS', espana: 'CARPETA_FIRMADOS_ESPANA' };
function pedirFirmados_(clave, cuerpo) {
  var resp = UrlFetchApp.fetch(URL_FIRMADOS, { method: 'post', contentType: 'application/json', muteHttpExceptions: true, headers: { 'x-clave': clave }, payload: JSON.stringify(cuerpo) });
  try { return JSON.parse(resp.getContentText()); } catch (_) { return { ok: false, status: resp.getResponseCode() }; }
}
// La propiedad: "código", "link", "código/Subcarpeta" o, por año, "2026:código, 2027:código/Subcarpeta".
function destinos_(valor) {
  return String(valor || '').split(/[,;\n]+/).map(function (t) { return t.trim(); }).filter(String).map(function (t) {
    var m = t.match(/^(\d{4})\s*:\s*(.+)$/), anio = m ? m[1] : '', resto = m ? m[2] : t;
    var cod = (resto.match(/[-\w]{25,}/) || [''])[0], tras = cod ? resto.slice(resto.indexOf(cod) + cod.length) : '';
    var sub = tras.replace(/^[?#][^/]*/, '').split('/').map(function (x) { return x.trim(); }).filter(String);
    return { anio: anio, codigo: cod, sub: sub };
  }).filter(function (d) { return d.codigo; });
}
function destinoDe_(lista, anio) { var a = lista.filter(function (d) { return d.anio === anio; })[0]; return a || lista.filter(function (d) { return !d.anio; })[0] || null; }
function subcarpeta_(padre, nombre) { var it = padre.getFoldersByName(nombre); return it.hasNext() ? it.next() : padre.createFolder(nombre); }
// Para comparar nombres de carpetas y archivos: sin mayúsculas, tildes ni espacios de más.
function normal_(t) { return String(t || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s*\/\s*/g, '/').replace(/\s+/g, ' ').trim(); }
// La carpeta del show dentro de la del área: la que ya está con ese nombre (con o sin "01- " adelante) o una
// nueva con el número que sigue. Se recuerdan las de cada carpeta durante la vuelta.
var CARPETAS_SHOW_ = {};
function carpetaShow_(raiz, nombre) {
  var k = raiz.getId(), c = CARPETAS_SHOW_[k];
  if (!c) {
    c = CARPETAS_SHOW_[k] = { por: {}, max: 0 };
    var it = raiz.getFolders();
    while (it.hasNext()) { var f = it.next(), n = f.getName(), m = n.match(/^\s*(\d+)\s*-\s*(.*)$/); if (m) c.max = Math.max(c.max, Number(m[1])); c.por[normal_(m ? m[2] : n)] = f; }
  }
  var ya = c.por[normal_(nombre)]; if (ya) return ya;
  c.max++; var nueva = raiz.createFolder((c.max < 10 ? '0' : '') + c.max + '- ' + nombre); c.por[normal_(nombre)] = nueva;
  return nueva;
}
// Un archivo ya guardado: el mismo nombre (las palabras, en cualquier orden) y lo mismo después del " - ".
function claveArchivo_(n) { var p = String(n || '').replace(/\.pdf$/i, '').split(' - '), quien = normal_(p.shift()).split(' ').filter(String).sort().join(' '); return quien + '|' + normal_(p.join(' - ')); }
var ARCHIVOS_ = {};
function yaEsta_(carpeta, nombre) {
  var k = carpeta.getId(), c = ARCHIVOS_[k];
  if (!c) { c = ARCHIVOS_[k] = {}; var it = carpeta.getFiles(); while (it.hasNext()) c[claveArchivo_(it.next().getName())] = true; }
  return !!c[claveArchivo_(nombre)];
}
// forzar: sin esperar los 15 minutos (guardar_firmados). Corta a los 2 minutos y medio; sigue en la vuelta siguiente.
function firmados_(clave, forzar) {
  var props = PropertiesService.getScriptProperties(), ahora = Date.now();
  var areas = Object.keys(FIRMADOS_AREAS).filter(function (a) { return destinos_(props.getProperty(FIRMADOS_AREAS[a])).length; });
  if (!areas.length) return;
  // Mientras quedan por guardar (la primera vez, todos los de antes), no espera los 15 minutos.
  if (!forzar && props.getProperty('firmados_quedan') !== 'si' && ahora - Number(props.getProperty('firmados_ultima') || 0) < FIRMADOS_CADA_MIN * 60000) return;
  props.setProperty('firmados_ultima', String(ahora));
  var quedan = false, resumen = [];
  areas.forEach(function (area) {
    var lista = destinos_(props.getProperty(FIRMADOS_AREAS[area])), raices = {};
    var raizDe = function (anio) {
      var d = destinoDe_(lista, anio); if (!d) return null;
      var k = d.anio + '|' + d.codigo + '|' + d.sub.join('/');
      if (!raices[k]) { var f = DriveApp.getFolderById(d.codigo); d.sub.forEach(function (n) { f = subcarpeta_(f, n); }); raices[k] = f; }
      return raices[k];
    };
    var desde = props.getProperty('firmados_desde_' + area) || '2026-01-01T00:00:00Z', guardados = 0, ya = 0, sinCarpeta = 0;
    while (Date.now() - ahora < 150000) {
      var r = pedirFirmados_(clave, { area: area, desde: desde });
      if (!r || !r.ok) { resumen.push(area + ': no se pudieron pedir · ' + JSON.stringify(r)); return; }
      for (var i = 0; i < r.contratos.length; i++) {
        var c = r.contratos[i];
        try {
          var raiz = raizDe(c.anio);
          if (!raiz) sinCarpeta++;
          else {
            var dest = carpetaShow_(raiz, c.carpeta_show);
            if (yaEsta_(dest, c.archivo)) ya++;
            else { dest.createFile(Utilities.newBlob(Utilities.base64Decode(c.pdf), 'application/pdf', c.archivo)); ARCHIVOS_[dest.getId()][claveArchivo_(c.archivo)] = true; guardados++; }
          }
          desde = c.firmado_at; props.setProperty('firmados_desde_' + area, desde);
        } catch (e) { resumen.push(area + ': no se pudo guardar ' + c.archivo + ' · ' + e + (/auth\/drive|permiso para llamar|permission to call/i.test(String(e)) ? ' → falta el permiso de Google para guardar en el Drive: ejecutar "autorizar" y aceptar todo' : ' (¿la cuenta del script es colaboradora de la unidad compartida?)')); quedan = true; return; }
      }
      if (r.cursor && r.cursor > desde) { desde = r.cursor; props.setProperty('firmados_desde_' + area, desde); }
      if (!r.mas) break;
    }
    if (Date.now() - ahora >= 150000) quedan = true;
    if (guardados || ya || sinCarpeta) resumen.push(area + ': ' + guardados + ' guardado(s)' + (ya ? ', ' + ya + ' ya estaba(n)' : '') + (sinCarpeta ? ', ' + sinCarpeta + ' de un año sin carpeta' : ''));
  });
  props.setProperty('firmados_quedan', quedan ? 'si' : 'no');
  if (resumen.length) Logger.log('Contratos firmados al Drive → ' + resumen.join(' · ') + (quedan ? ' (siguen en la vuelta siguiente)' : ''));
}
// Para mirar antes: cuántos faltan guardar y en qué carpetas (no guarda nada).
function probar_firmados() {
  var props = PropertiesService.getScriptProperties(), clave = props.getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE.');
  Logger.log('Versión del script: ' + VERSION);
  Object.keys(FIRMADOS_AREAS).forEach(function (area) {
    var lista = destinos_(props.getProperty(FIRMADOS_AREAS[area]));
    if (!lista.length) { Logger.log(area + ': sin la propiedad ' + FIRMADOS_AREAS[area] + ' (no se guarda).'); return; }
    lista.forEach(function (d) {
      try { Logger.log(area + (d.anio ? ' ' + d.anio : '') + ': carpeta «' + DriveApp.getFolderById(d.codigo).getName() + '»' + (d.sub.length ? ' › ' + d.sub.join(' › ') : '') + ' (la abro bien).'); }
      catch (e) { Logger.log(area + ': NO puedo abrir la carpeta ' + d.codigo + ' — ¿la cuenta del script es colaboradora de la unidad compartida? · ' + e); }
    });
    var r = pedirFirmados_(clave, { area: area, desde: props.getProperty('firmados_desde_' + area) || '2026-01-01T00:00:00Z', contar: true });
    if (!r || !r.ok) { Logger.log(area + ': no se pudo preguntar · ' + JSON.stringify(r)); return; }
    Logger.log(area + ': faltan revisar ' + r.pendientes + ' contrato(s) firmado(s) (los que ya están en la carpeta no se repiten).');
    Object.keys(r.carpetas || {}).forEach(function (k) { Logger.log('   · ' + k + ': ' + r.carpetas[k]); });
  });
}
// Vuelve a pedir los permisos que falten (por ejemplo, el de guardar en el Drive). Desde el editor: elegir
// "autorizar", Ejecutar y, en la ventana de Google, "Seleccionar todo" y "Continuar".
function autorizar() {
  if (typeof ScriptApp.requireAllScopes === 'function') {
    ScriptApp.requireAllScopes(ScriptApp.AuthMode.FULL);
    Logger.log('Listo: el script tiene todos los permisos que necesita. Ahora se puede ejecutar "guardar_firmados".');
  } else {
    Logger.log('Esta versión de Apps Script no deja pedirlos de nuevo desde acá: en myaccount.google.com/connections (con esta cuenta) quitarle el acceso a este proyecto y volver a ejecutar "guardar_firmados"; en la ventana de Google, "Seleccionar todo".');
  }
}
// Los guarda ya (sin esperar los 15 minutos).
function guardar_firmados() {
  var clave = PropertiesService.getScriptProperties().getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE.');
  firmados_(clave, true);
}
