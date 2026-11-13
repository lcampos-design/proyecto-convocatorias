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
 *     (la clave no se escribe en ningún otro lado). Y, para que busque los mails
 *     sólo en la carpeta de la disponibilidad: CARPETA_DISPONIBILIDAD = el
 *     código de esa carpeta (lo que va después de /folders/ en su link). Sin
 *     esa propiedad los busca en todo el Drive de la cuenta.
 *  3. Elegir la función "probar" y tocar Ejecutar: muestra qué planillas y
 *     qué respuestas de disponibilidad encontró, sin mandar nada. (La primera
 *     vez Google pide permiso para ver el Drive y las planillas: aceptar.)
 *  4. "revisar": qué pasaría si todos tuvieran "P", sin mandar nada.
 *  5. "instalar": deja programado que corra solo cada 5 minutos. Listo.
 *  Para apagarlo: ejecutar "desinstalar".
 */

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
  planillas_().forEach(function (f) {
    var p = leer_(f);
    if (!p) { Logger.log('No entiendo el nombre: ' + f.getName()); return; }
    var cuenta = function (fn) { return p.filas.filter(fn).length; };
    Logger.log(f.getName() + ' → ' + p.fecha + ' · ' + p.show + ' · ' + p.filas.length + ' personas · ' + cuenta(function (x) { return x.marca === 'P'; }) + ' P · ' + cuenta(function (x) { return x.marca === 'A'; }) + ' A · '
      + cuenta(function (x) { return !!x.mail; }) + ' con mail en la disponibilidad');
    var d = disponibilidad_(p.fecha);
    Logger.log('   Disponibilidad de ' + MESES[Number(p.fecha.slice(5, 7)) - 1] + ': ' + (d.archivos.length ? d.archivos.join(' · ') : '(no encontré respuestas de ese mes)') + ' · ' + d.total + ' mails');
  });
}

// Antes del show: le pregunta a la plataforma qué pasaría si todos tuvieran "P" (a cuántos
// les saldría el contrato, con qué puesto, y quiénes no: no están en ningún lado, sin mail, CUIL
// incompleto…). No manda ni guarda nada. Necesita la CLAVE.
function revisar() {
  var clave = PropertiesService.getScriptProperties().getProperty('CLAVE');
  if (!clave) throw new Error('Falta la propiedad CLAVE (Configuración del proyecto → Propiedades del script).');
  planillas_().forEach(function (f) {
    var p = leer_(f);
    if (!p) return;
    p.simular = true;
    var r = mandar_(p, clave);
    if (!r || !r.ok) { Logger.log(f.getName() + ' → ' + JSON.stringify(r)); return; }
    Logger.log(f.getName() + ' → ' + r.fecha + ' · show del panel: ' + (r.show || '(ninguno)') + ' · ' + r.filas + ' personas · ' + JSON.stringify(r.porResultado));
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
// Las planillas de respuestas ("Disponibilidad Noviembre 2026 (Respuestas)") del mes del show: las
// de la carpeta CARPETA_DISPONIBILIDAD y sus subcarpetas o, si no está esa propiedad, las de todo el
// Drive que se llamen "Disponibilidad…". Del mes: el nombre de la planilla o de su carpeta dice el mes
// ("Noviembre" o "Nov"). De cada respuesta: el correo, el CUIL (o DNI), el apellido y el nombre, por
// cómo se llaman las columnas. Sólo las respuestas de los 4 meses antes del show (por la "Marca
// temporal"): así no se mezcla la disponibilidad de noviembre del año pasado. Si una persona
// respondió más de una vez, gana la más nueva. Se lee una vez por mes en cada vuelta.
var cacheDisp_ = {};
function disponibilidad_(fecha) {
  var mes = MESES[Number(String(fecha).slice(5, 7)) - 1] || '';
  var clave = String(fecha).slice(0, 7);
  if (cacheDisp_[clave]) return cacheDisp_[clave];
  var res = { porNucleo: {}, gente: [], archivos: [], total: 0 };
  cacheDisp_[clave] = res;
  if (!mes) return res;
  var delMes = function (nombre) { var p = palabras_(nombre); return p.indexOf(mes) >= 0 || p.indexOf(mes.slice(0, 3)) >= 0; };
  var anio = Number(clave.slice(0, 4)), nMes = Number(clave.slice(5, 7));
  var desde = new Date(anio, nMes - 1, 1).getTime() - 120 * 86400000, hasta = new Date(anio, nMes, 1).getTime() + 31 * 86400000;
  var hojas = [], vistas = {};
  var sumar = function (a) { if (!vistas[a.getId()]) { vistas[a.getId()] = 1; hojas.push(a); } };
  var id = PropertiesService.getScriptProperties().getProperty('CARPETA_DISPONIBILIDAD');
  try {
    if (id) {
      var juntar = function (carpeta, enMes, nivel) {
        var f = carpeta.getFilesByType(MimeType.GOOGLE_SHEETS);
        while (f.hasNext()) { var a = f.next(); if (enMes || delMes(a.getName())) sumar(a); }
        if (nivel >= 3) return;
        var sub = carpeta.getFolders();
        while (sub.hasNext()) { var c = sub.next(); juntar(c, enMes || delMes(c.getName()), nivel + 1); }
      };
      juntar(DriveApp.getFolderById(id), false, 0);
    } else {
      var it = DriveApp.searchFiles('title contains "disponibilidad" and mimeType = "application/vnd.google-apps.spreadsheet" and trashed = false');
      while (it.hasNext()) { var a = it.next(); if (delMes(a.getName())) sumar(a); }
    }
  } catch (e) { Logger.log('No pude buscar la disponibilidad: ' + e); return res; }
  // De la más vieja a la más nueva, para que la última respuesta de cada uno gane.
  hojas.sort(function (a, b) { return a.getLastUpdated() - b.getLastUpdated(); });
  hojas.slice(-30).forEach(function (a) {
    try {
      SpreadsheetApp.openById(a.getId()).getSheets().forEach(function (h) {
        var v = h.getDataRange().getDisplayValues();
        if (v.length < 2) return;
        var enc = v[0].map(function (x) { return String(x).trim().toLowerCase(); });
        var col = function (re) { for (var i = 0; i < enc.length; i++) if (re.test(enc[i])) return i; return -1; };
        var iMail = col(/correo|e-?mail|mail/), iCuil = col(/cuil|cuit/), iDni = col(/(^|[^a-z])dni([^a-z]|$)|documento/), iHora = col(/marca temporal|timestamp/);
        var iNombres = [];
        enc.forEach(function (t, i) { if (/apellido|nombre/.test(t) && !/emergencia|contacto|referi|familiar|usuario/.test(t)) iNombres.push(i); });
        if (iMail < 0 || (iCuil < 0 && iDni < 0 && !iNombres.length)) return;
        var sumo = 0;
        for (var r = 1; r < v.length; r++) {
          var mail = String(v[r][iMail] || '').trim().toLowerCase();
          if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) continue;
          // La respuesta tiene que ser de los meses antes del show (la Marca temporal: 21/4/2026 16:26:51).
          var cuando = iHora >= 0 ? String(v[r][iHora]).match(/(\d{1,2})\/(\d{1,2})\/(\d{4})/) : null;
          var t = cuando ? new Date(Number(cuando[3]), Number(cuando[2]) - 1, Number(cuando[1])).getTime() : a.getDateCreated().getTime();
          if (t < desde || t > hasta) continue;
          var doc = String((iCuil >= 0 ? v[r][iCuil] : '') || (iDni >= 0 ? v[r][iDni] : '') || '').replace(/\D/g, '');
          var item = { mail: mail, doc: doc, palabras: palabras_(iNombres.map(function (i) { return v[r][i]; }).join(' ')) };
          var n = nucleo_(doc);
          if (n) (res.porNucleo[n] = res.porNucleo[n] || []).push(item);
          if (item.palabras.length) res.gente.push(item);
          sumo++;
        }
        if (sumo) res.archivos.push(a.getName() + ' (' + sumo + ')');
        res.total += sumo;
      });
    } catch (e) { Logger.log('No pude leer ' + a.getName() + ': ' + e); }
  });
  return res;
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
