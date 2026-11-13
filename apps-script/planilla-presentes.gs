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
 *     "disponibilidad" o el mes en el nombre.
 *  3. Elegir la función "probar" y tocar Ejecutar: muestra qué planillas y
 *     qué respuestas de disponibilidad encontró, sin mandar nada. (La primera
 *     vez Google pide permiso para ver el Drive y las planillas: aceptar.)
 *  4. "revisar": qué pasaría si todos tuvieran "P", sin mandar nada.
 *  5. "instalar": deja programado que corra solo cada 5 minutos. Listo.
 *  Para apagarlo: ejecutar "desinstalar".
 */

var VERSION = '13-nov, con la disponibilidad';
var URL_PLATAFORMA = 'https://convocatorias.show-bs.com/api/presentes-planilla';
var HORAS_ATRAS = 36;   // qué planillas mira: las que cambiaron en el último día y medio
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
}
// Qué respuestas de disponibilidad usó y a cuántos de la planilla les encontró el mail.
function lineaDisponibilidad_(p) {
  var d = disponibilidad_(p.fecha), props = PropertiesService.getScriptProperties();
  var donde = [props.getProperty('PLANILLA_DISPONIBILIDAD') ? 'la planilla de PLANILLA_DISPONIBILIDAD' : '', props.getProperty('CARPETA_DISPONIBILIDAD') ? 'la carpeta "' + d.carpeta + '"' : 'todo el Drive'].filter(String).join(' y ');
  Logger.log('   [script ' + VERSION + '] Disponibilidad de ' + MESES[Number(p.fecha.slice(5, 7)) - 1] + ' (en ' + donde + '): '
    + (d.archivos.length ? d.archivos.join(' · ') : 'no encontré respuestas de ese mes') + ' · ' + d.total + ' mails leídos · '
    + p.filas.filter(function (x) { return !!x.mail; }).length + ' de ' + p.filas.length + ' de la planilla con mail ahí');
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
    Logger.log(f.getName() + ' → ' + r.fecha + ' · show del panel: ' + (r.show || '(ninguno)') + ' · ' + r.filas + ' personas · ' + JSON.stringify(r.porResultado));
    lineaDisponibilidad_(p);
    (r.problemas || []).forEach(function (x) { Logger.log('   ' + x.sector + ' · ' + x.apellido + ', ' + x.nombre + ' → ' + x.resultado + (x.detalle ? ' (' + x.detalle + ')' : '')); });
  });
}

// Lo que corre cada 5 minutos.
function sincronizar() {
  var clave = PropertiesService.getScriptProperties().getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE (Configuración del proyecto → Propiedades del script).');
  var guardado = PropertiesService.getScriptProperties();
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
      Logger.log(f.getName() + ' → ' + JSON.stringify(r));
    } catch (e) {
      Logger.log('Error con ' + f.getName() + ': ' + e);
    }
  });
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
  var res = { porNucleo: {}, gente: [], items: [], archivos: [], total: 0, vistos: [], notas: [], carpeta: '' };
  if (!mes) return res;
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
    var txt = JSON.stringify({ i: res.items.map(function (x) { return [x.mail, x.doc, x.palabras.join(' ')]; }), a: res.archivos, n: res.notas, v: res.vistos.slice(0, 30), t: res.total, c: res.carpeta });
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
    var res = { porNucleo: {}, gente: [], items: [], archivos: o.a, notas: o.n, vistos: o.v, total: o.t, carpeta: o.c, deCache: true };
    o.i.forEach(function (x) { indexar_(res, { mail: x[0], doc: x[1], palabras: x[2] ? x[2].split(' ') : [] }); });
    return res;
  } catch (e) { return null; }
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
  var valores = SpreadsheetApp.openById(f.getId()).getSheets()[0].getDataRange().getDisplayValues();
  var filas = [], sector = '', col = null;
  valores.forEach(function (fila) {
    var arriba = fila.map(function (v) { return String(v).trim().toUpperCase(); });
    var iCuil = arriba.indexOf('CUIL'), iPres = arriba.indexOf('PRESENTES');
    if (iCuil >= 0 && iPres >= 0) {
      sector = String(fila[0]).trim();
      var iObs = -1;
      arriba.forEach(function (v, i) { if (iObs < 0 && /^OBSERVACI[OÓ]N/.test(v)) iObs = i; });
      col = { cuil: iCuil, pres: iPres, ape: arriba.indexOf('APELLIDO'), nom: arriba.indexOf('NOMBRE'), obs: iObs };
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
      marca: String(fila[col.pres] || '').trim().toUpperCase().charAt(0)
    });
  });
  // El mail de la disponibilidad del mes (y el documento que dejó ahí), para quien la plataforma no tenga.
  var d = disponibilidad_(fecha);
  filas.forEach(function (x) { var h = mailDe_(d, x); if (h) { x.mail = h.mail; if (h.doc) x.doc = h.doc; } });
  return { archivo: { id: f.getId(), nombre: f.getName() }, fecha: fecha, show: show, disponibilidad: d.total, filas: filas };
}
