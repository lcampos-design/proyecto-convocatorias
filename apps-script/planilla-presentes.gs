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
 * CÓMO SE INSTALA (una sola vez, con la cuenta de convocatorias del Arena):
 *  1. script.google.com → Proyecto nuevo → pegar este archivo entero.
 *  2. Configuración del proyecto (el engranaje) → Propiedades del script →
 *     Agregar: nombre CLAVE, valor: la misma clave que está en Vercel como
 *     PRESENTES_CLAVE. (La clave no se escribe en ningún otro lado.)
 *  3. Elegir la función "probar" y tocar Ejecutar: pide permiso para ver el
 *     Drive y las planillas (es la cuenta mirando sus propias planillas) y
 *     muestra en el registro qué encontró, sin mandar nada.
 *  4. Elegir la función "instalar" y tocar Ejecutar: deja programado que
 *     corra solo cada 5 minutos. Listo.
 *  Para apagarlo: ejecutar "desinstalar".
 */

var URL_PLATAFORMA = 'https://convocatorias.show-bs.com/api/presentes-planilla';
var HORAS_ATRAS = 36;   // qué planillas mira: las que cambiaron en el último día y medio

// La programación: cada 5 minutos.
function instalar() {
  desinstalar();
  ScriptApp.newTrigger('sincronizar').timeBased().everyMinutes(5).create();
  Logger.log('Listo: corre solo cada 5 minutos.');
}
function desinstalar() {
  ScriptApp.getProjectTriggers().forEach(function (t) { if (t.getHandlerFunction() === 'sincronizar') ScriptApp.deleteTrigger(t); });
}

// Muestra qué planillas y cuántas marcas encuentra, sin mandar nada.
function probar() {
  planillas_().forEach(function (f) {
    var p = leer_(f);
    if (!p) { Logger.log('No entiendo el nombre: ' + f.getName()); return; }
    var P = p.filas.filter(function (x) { return x.marca === 'P'; }).length, A = p.filas.filter(function (x) { return x.marca === 'A'; }).length;
    Logger.log(f.getName() + ' → ' + p.fecha + ' · ' + p.show + ' · ' + p.filas.length + ' personas · ' + P + ' P · ' + A + ' A');
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

// Una planilla → { archivo, fecha, show, filas: [{ sector, cuil, rol, obs, apellido, nombre, marca }] }.
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
  return { archivo: { id: f.getId(), nombre: f.getName() }, fecha: fecha, show: show, filas: filas };
}
