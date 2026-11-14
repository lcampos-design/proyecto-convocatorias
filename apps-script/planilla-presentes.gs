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
 *     "disponibilidad" o el mes en el nombre. Para los CUIL incompletos usa la
 *     planilla de altas de ARCA ("Detalle altas…"); si no la encuentra sola:
 *     PLANILLA_ALTAS = su link.
 *  3. Elegir la función "probar" y tocar Ejecutar: muestra qué planillas y
 *     qué respuestas de disponibilidad encontró, sin mandar nada. (La primera
 *     vez Google pide permiso para ver el Drive y las planillas: aceptar.)
 *  4. "revisar": qué pasaría si todos tuvieran "P", sin mandar nada.
 *  5. "instalar": deja programado que corra solo cada 5 minutos. Listo.
 *
 *  EL REPORTE DE INCIDENCIAS (al terminar cada show del Arena, desde esta casilla):
 *  - Propiedad REPORTE_PARA = los mails que lo reciben, separados por coma; REPORTE_CC, los de
 *    la copia, y REPORTE_CCO, los de la copia oculta (opcionales).
 *  - "probar_reporte": el de hoy, sólo a esta casilla (o a REPORTE_PRUEBA), para ver cómo queda (la primera
 *    vez Google pide permiso para mandar mails: aceptar).
 *  - Sale solo a la 1:30 de la noche del show; "enviar_reporte" lo manda ya.
 *  Para apagarlo: ejecutar "desinstalar".
 */

var VERSION = '14-nov, reporte (enviar_reporte cierra lo abierto) y 30 minutos de espera';
var URL_PLATAFORMA = 'https://convocatorias.show-bs.com/api/presentes-planilla';
var HORAS_ATRAS = 36;   // qué planillas mira: las que cambiaron en el último día y medio
// El contrato sale a los 30 minutos de la P (propiedad ESPERA_MINUTOS para cambiarlo; 0 = enseguida):
// así una P puesta por error se corrige antes de que le llegue el mail. La hora de la P es la de la
// columna HORARIO (la planilla la completa sola al poner la P), leída en la zona horaria de la planilla.
var ESPERA_MINUTOS = 30;
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
  var incompletos = p.filas.filter(function (x) { return x.cuil.length !== 11; });
  Logger.log('   Altas de ARCA: ' + (d.altasArchivos.length ? d.altasArchivos.join(' · ') : 'no la encontré') + ' · de ' + incompletos.length + ' con el CUIL incompleto en la planilla, '
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
  // El reporte de incidencias del show de anoche, a la 1:30 (si no salió todavía).
  try { reportes_(clave); } catch (e) { Logger.log('Error con el reporte: ' + e); }
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
  // Sin la propiedad (o vacía), la de siempre: 30 minutos. Number(null) da 0, por eso no se usa directo.
  var ep = PropertiesService.getScriptProperties().getProperty('ESPERA_MINUTOS');
  var espera = ep === null || String(ep).trim() === '' ? ESPERA_MINUTOS : Number(ep);
  if (!(espera >= 0)) espera = ESPERA_MINUTOS;
  var filas = [], sector = '', col = null;
  valores.forEach(function (fila) {
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
  });
  return { archivo: { id: f.getId(), nombre: f.getName() }, fecha: fecha, show: show, disponibilidad: d.total, filas: filas };
}

// ── El reporte de incidencias de cada show, al terminar (13-nov-2026) ──
// Pedido de Thomas: "que finalizado el show se envíe automáticamente el reporte de incidencias vía
// mail desde convocatorias.arena". A la 1:30 (hora del Arena) de la noche del show, la vuelta de cada
// 5 minutos le pide a la plataforma las incidencias de los shows de esa fecha, arma el PDF (como el
// "Informe" de la gerencia) y lo manda desde esta casilla a los mails de la propiedad REPORTE_PARA
// (separados por coma). Uno por show y por fecha: no se repite. Si a la 1:30 no salió (el script
// estaba apagado), sale a la mañana, hasta las 14.
//   probar_reporte: el de hoy (lo cargado hasta ahora), sólo a esta casilla, para ver cómo queda.
//   enviar_reporte: el de hoy, ya, a REPORTE_PARA (por si hace falta antes de la 1:30). Es para cuando el
//                   show terminó: lo que quedó abierto se da por cerrado, como a la 1:30.
var URL_REPORTE = 'https://convocatorias.show-bs.com/api/reporte-incidencias';
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
  var f = diaFuncion_(), r = pedirReporte_(f, clave), yo = String(PropertiesService.getScriptProperties().getProperty('REPORTE_PRUEBA') || '').trim() || Session.getEffectiveUser().getEmail();
  if (!r || !r.ok) { Logger.log('No se pudo: ' + JSON.stringify(r)); return; }
  if (!(r.shows || []).length) { Logger.log('Hoy (' + f + ') no hay shows del Centro de Control del Arena.'); return; }
  r.shows.forEach(function (s) { mandarReporte_(s, yo, true); Logger.log('Prueba mandada a ' + yo + ': ' + s.nombre + ' · ' + s.incidencias.length + ' incidencias'); });
  Logger.log('Destinatarios para el envío de verdad (REPORTE_PARA): ' + (PropertiesService.getScriptProperties().getProperty('REPORTE_PARA') || '(falta la propiedad)'));
}
function enviar_reporte() {
  var props = PropertiesService.getScriptProperties(), clave = props.getProperty('CLAVE'), para = String(props.getProperty('REPORTE_PARA') || '').trim();
  if (!clave || !para) throw new Error('Faltan las propiedades CLAVE o REPORTE_PARA.');
  var f = diaFuncion_(), r = pedirReporte_(f, clave, true);
  if (!r || !r.ok) { Logger.log('No se pudo: ' + JSON.stringify(r)); return; }
  if (!(r.shows || []).length) { Logger.log('Hoy (' + f + ') no hay shows del Centro de Control del Arena.'); return; }
  (r.shows || []).forEach(function (s) { mandarReporte_(s, para, false); props.setProperty('rep_' + f + '_' + s.conv_id, new Date().toISOString()); Logger.log('Enviado: ' + s.nombre); });
  props.setProperty('rep_' + f, new Date().toISOString() + ' · a mano');
}

function mandarReporte_(s, para, prueba) {
  var ddmm = s.fecha.slice(8, 10) + '/' + s.fecha.slice(5, 7);
  var asunto = (prueba ? '[Prueba] ' : '') + 'Reporte de incidencias - ' + s.nombre + ' ' + ddmm;
  var pdf = Utilities.newBlob(htmlReporte_(s, logoReporte_()), MimeType.HTML, 'reporte.html').getAs(MimeType.PDF)
    .setName('Reporte de incidencias - ' + s.nombre + ' ' + ddmm.replace('/', '-') + '.pdf');
  var c = cuerpoReporte_(s), o = { to: para, subject: asunto, body: c.texto, htmlBody: c.html, name: 'Show Business Solutions', attachments: [pdf] };
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
  var partes = r.porNivel.filter(function (p) { return p[1]; }).map(function (p) { return p[1] + ' ' + (p[1] === 1 ? NIVELES_[p[0]].una : NIVELES_[p[0]].plural); });
  var detalle = r.total ? r.total + (r.total === 1 ? ' incidencia' : ' incidencias') + ' (' + (partes.length > 1 ? partes.slice(0, -1).join(', ') + ' y ' + partes[partes.length - 1] : partes[0]) + '), ' + r.resueltas + (r.resueltas === 1 ? ' resuelta' : ' resueltas') + '.' : 'no se registraron incidencias.';
  var t1 = 'Les compartimos el reporte de incidencias del show de ' + s.nombre + ' del ' + cuando + ' en el ' + (s.venue || 'Movistar Arena') + ': ' + detalle;
  var texto = 'Hola:\n\n' + t1 + '\n\nVa adjunto en PDF.\n\nSaludos,\nShow Business Solutions\nconvocatorias.arena@show-bs.com';
  var P = 'margin:0 0 14px;font-size:15px;line-height:1.6;color:#1A1A1A';
  var html = '<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px">'
    + '<p style="' + P + '">Hola:</p><p style="' + P + '">' + esc_(t1) + '</p><p style="' + P + '">Va adjunto en PDF.</p>'
    + '<p style="' + P + '">Saludos,<br>Show Business Solutions<br><span style="color:#5C5C5C">convocatorias.arena@show-bs.com</span></p></div>';
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
  var th = function (t) { return '<th style="background:' + T + ';color:#FFFFFF;padding:5px;text-align:left;font-size:9px">' + t + '</th>'; };
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
  return '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Arial,Helvetica,sans-serif;color:' + T + ';font-size:10px;margin:0">'
    + '<table style="border-collapse:collapse;width:100%;border-bottom:2px solid ' + T + ';margin-bottom:12px"><tr>'
    + (logo ? '<td style="width:52px;padding:0 12px 10px 0"><img src="' + logo + '" width="42" height="42"></td>' : '')
    + '<td style="padding:0 0 10px 0"><div style="font-size:9.5px;font-weight:bold;color:' + G + '">AX · Audience Experience · Informe del show</div>'
    + '<div style="font-size:18px;font-weight:bold;margin:2px 0">Informe de incidencias · ' + esc_(s.nombre) + '</div>'
    + '<div style="font-size:10px;color:' + G + '">' + cuando + ' · ' + esc_(s.venue || 'Movistar Arena') + ' · generado ' + fAr_(new Date(), 'dd/MM/yyyy HH:mm') + '</div></td></tr></table>'
    + '<table style="border-collapse:separate;border-spacing:6px 0;width:100%;margin:0 0 16px -6px"><tr>'
    + num(r.total, 'Incidencias') + num(r.abiertas, 'Abiertas') + num(r.porNivel[0][1], 'Graves') + num(r.asistencias, 'Asistencias') + num(r.derivadas, 'Derivadas') + num(r.tMedio, 'Resolución media') + num(r.pico, 'Momento más cargado')
    + '</tr></table>'
    + '<table style="border-collapse:collapse;width:100%;margin-bottom:16px"><tr>'
    + tabla('Gravedad', r.porNivel.map(function (p) { return [NIVELES_[p[0]].nombre, p[1]]; })) + tabla('Categoría', cuentaPor_(l, function (i) { return i.categoria; })) + tabla('Sector', cuentaPor_(l, function (i) { return i.sector; }))
    + '</tr></table>'
    + '<div style="font-size:10.5px;font-weight:bold;margin:0 0 5px">Línea de tiempo</div>'
    + (l.length ? '<table style="border-collapse:collapse;width:100%"><tr>' + th('Cuándo') + th('Sector') + th('Qué pasó') + th('Gravedad') + th('Qué se hizo') + th('Derivado a') + th('Cómo se resolvió') + '</tr>' + filas + '</table>'
      : '<div style="font-size:10px;color:' + G + '">No se registraron incidencias en este show.</div>')
    + '</body></html>';
}
