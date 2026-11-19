// Contratos por presente (Arena, 13-nov-2026).
//
// Pedido de los socios: el contrato se manda sólo a quien tiene el presente.
// Los presentes se toman en las planillas "SUPERVISORES dd/mm "SHOW"" de Google
// Sheets. Un script de la cuenta de convocatorias del Arena
// (apps-script/planilla-presentes.gs) las mira cada 5 minutos y manda acá,
// por cada planilla, la fecha, el show y cada fila (sector, CUIL, apellido,
// nombre y la marca de PRESENTES: "P", "A" o vacío).
//
// Con una "P": se busca a la persona en la nómina por CUIL (o DNI) y, si no
// tiene contrato de esa fecha, se le arma uno (la plantilla del panel, con el
// puesto y el monto del sector para ese mes) y se le manda el link para
// firmar. Uno por persona y por fecha.
// Con "A" o sin marca, si tenía contrato de esa fecha sin firmar: se anula (el
// link vence en ese momento). Si ya lo firmó, queda y el panel lo avisa.
// Todo lo que pasó con cada fila queda en planilla_presentes, para el panel.
//
// Se puede llamar las veces que haga falta: lo que ya está hecho no se repite.
// Manda hasta MAX_ENVIOS mails por llamada (Resend admite 2 por segundo y la
// función tiene un tiempo máximo): el resto vuelve como "pendientes" y el
// script vuelve a llamar.
//
// Externos (19-nov): el mismo script manda también la hoja PRESENTES de las planillas "PRESENTISMO" de cada
// evento (las arma RR. HH.: una fila por persona, fecha y turno; P, A o E = extra que asistió, que vale como P),
// con area: 'externos', una llamada por fecha. Lo distinto (Thomas, 19-nov):
//  - el evento tiene que estar en el panel, como en el Arena: una convocatoria de Externos con esa fecha y con
//    alguna palabra del nombre en común (se crea desde el calendario de Externos en "Disponibilidad del mes");
//  - el puesto es el SECTOR / PUESTO de la fila y el monto, el TOTAL POR PERSONA de ese puesto en la "INFO RRHH"
//    del evento (hoja RECURSOS Y VALORES; el script la manda como "tarifas");
//  - el mail sale de convocatorias.externos y dice el lugar del evento;
//  - los contratos llevan origen 'planilla_externos' y las filas, area 'externos': no se cruzan con los del Arena
//    (una persona puede tener los dos el mismo día). Necesita contratos-presentes-externos.sql.
//
// Variables de entorno en Vercel (nunca en el código):
//   SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY (ya estaban) y PRESENTES_CLAVE
//   (la clave que lleva el script de la planilla; la misma en los dos lados).

import crypto from 'crypto';
import { TIPO_GOOGLE, esMicrosoft } from './_lib/correo-google.js';

export const config = { maxDuration: 60 };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';
const REMITENTE = 'convocatorias.arena@show-bs.com';
const REMITENTE_EXT = 'convocatorias.externos@show-bs.com';
const FIRMA_CONTRATO = 'firmas/firma-richard.png';
export const MAX_ENVIOS = 20;
const MAX_FILAS = 600;

// ── El monto en letras (lo mismo que el panel: admin.html, numeroALetras) ──
const U = ['', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez',
  'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte',
  'veintiuno', 'veintidós', 'veintitrés', 'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve'];
const D = ['', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
const C = ['', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos', 'ochocientos', 'novecientos'];
function hastaMil(n, apocope) {
  if (!n) return '';
  if (n === 100) return 'cien';
  const c = Math.floor(n / 100), r = n % 100;
  let t = c ? C[c] : '';
  if (r) {
    if (t) t += ' ';
    if (r < 30) t += (apocope && r === 1) ? 'un' : (apocope && r === 21) ? 'veintiún' : U[r];
    else { const d = Math.floor(r / 10), u = r % 10; t += D[d]; if (u) t += ' y ' + ((apocope && u === 1) ? 'un' : U[u]); }
  }
  return t;
}
function enteroALetras(n) {
  if (!n) return 'cero';
  const millones = Math.floor(n / 1000000), miles = Math.floor((n % 1000000) / 1000), resto = n % 1000, partes = [];
  if (millones) partes.push(millones === 1 ? 'un millón' : hastaMil(millones, true) + ' millones');
  if (miles) partes.push(miles === 1 ? 'mil' : hastaMil(miles, true) + ' mil');
  if (resto) partes.push(hastaMil(resto, false));
  return partes.join(' ');
}
export function numeroALetras(n) {
  const num = Math.abs(Number(n) || 0), entero = Math.floor(num), centavos = Math.round((num - entero) * 100);
  let t = enteroALetras(entero);
  if (centavos) t += ' con ' + hastaMil(centavos, true) + (centavos === 1 ? ' centavo' : ' centavos');
  return t;
}
export function montoFormateado(n) { return Number(n).toLocaleString('es-AR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
// "33560", "33.560", "$33.560,00" → 33560 (como montoANumero del panel).
export function montoANumero(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : 0;
  const m = String(v == null ? '' : v).match(/\d{1,3}(?:[.\s]\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?/);
  if (!m) return 0;
  let t = m[0];
  if (/[.\s]\d{3}(?!\d)/.test(t)) t = t.replace(/[.\s]/g, '');
  const n = Number(t.replace(',', '.'));
  return Number.isFinite(n) ? n : 0;
}

// ── Fechas como las escribe el contrato: "23 DE NOVIEMBRE" ──
export function fechaLarga(iso) {
  const [a, m, d] = String(iso).split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d, 12)).toLocaleDateString('es-AR', { day: 'numeric', month: 'long', timeZone: 'UTC' }).toUpperCase();
}
function hoyLarga() { return new Date().toLocaleDateString('es-AR', { day: 'numeric', month: 'long', timeZone: 'America/Argentina/Buenos_Aires' }).toUpperCase(); }
// "23 de noviembre" (para el mail).
function fechaMail(iso) { const [a, m, d] = String(iso).split('-').map(Number); return new Date(Date.UTC(a, m - 1, d, 12)).toLocaleDateString('es-AR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }); }

// La clave de un sector o un puesto: sin tildes, espacios ni signos ("Corta tickets" = "CORTATICKETS").
export function claveSector(s) { return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z0-9]/g, ''); }
const buscarClave = (obj, k) => { const hit = Object.keys(obj || {}).find(x => claveSector(x) === k); return hit === undefined ? undefined : obj[hit]; };
// Qué puesto lleva una fila (config.contratos_presentes):
//  1) un rol conocido en OBSERVACIÓN ("Firmas": el primero del P.Point) o en la primera columna
//     ("Coordinador", dentro del bloque de supervisores);
//  2) si no, el del bloque (Supervisores, P.Point = Recepciones premium, Firmas, Cargas…);
//  3) si el bloque no figura, el de siempre (Orientador).
export function puestoDe(cfg, sector, rol, obs) {
  const roles = (cfg && cfg.roles) || {};
  const candidatos = [obs, rol].flatMap(t => [t].concat(String(t || '').split(/[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+/)));
  for (const c of candidatos) { const r = c && buscarClave(roles, claveSector(c)); if (r) return String(r); }
  const s = buscarClave(cfg && cfg.sectores, claveSector(sector));
  return String(s || (cfg && cfg.porDefecto) || '').trim();
}
// El monto y el puesto de una fila en un mes: el puesto según el sector y el monto de ese puesto
// en ese mes (config.contratos_presentes.meses["2026-11"].puestos).
export function tarifaDe(cfg, fecha, sector, rol, obs) {
  const mes = cfg && cfg.meses && cfg.meses[String(fecha).slice(0, 7)];
  const puesto = puestoDe(cfg, sector, rol, obs);
  if (!mes || !puesto) return null;
  const monto = montoANumero(buscarClave(mes.puestos, claveSector(puesto)));
  return monto > 0 ? { monto, puesto } : null;
}
function tituloSector(s) { return String(s || '').toLowerCase().replace(/(^|\s)\S/g, c => c.toUpperCase()); }
// El texto del contrato: la plantilla del panel con los datos puestos (como buildTextoContrato).
export function armarTexto(plantilla, d) {
  return String(plantilla).replace(/\r\n?/g, '\n').trim().replace(/\{\{(\w+)\}\}/g, (_, k) => (d[k] != null ? d[k] : ''));
}

// ── El mail ──
const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
// lugar: el de Externos ("Centro de Convenciones…"); sin pasarlo, el Arena. Vacío: no dice dónde.
export function armarMail({ nombre, fecha, show, link, lugar }) {
  const pila = String(nombre || '').trim().split(/\s+/)[0] || '';
  const hola = pila ? 'Hola, ' + pila.charAt(0).toUpperCase() + pila.slice(1).toLowerCase() : 'Hola';
  const cuando = fechaMail(fecha), que = show ? ' (' + show + ')' : '';
  const enLugar = lugar === undefined ? ' en el Movistar Arena' : String(lugar || '').trim() ? ' en ' + String(lugar).trim() : '';
  // Empieza con "Contrato ·", como dice la guía para firmar desde el celular (Mer, 13-nov).
  const subject = `Contrato · ${show ? show + ' · ' : ''}${fechaLarga(fecha).toLowerCase()}`;
  const text = `${hola}:\n\nGracias por trabajar con nosotros el ${cuando}${que}${enLugar}.\n\nPara firmar tu contrato de esa fecha, entrá a este link:\n${link}\n\nEl link vence en 7 días. Cualquier duda, respondé este mail.\n\nSaludos,\nShow Business Solutions`;
  const P = 'margin:0 0 16px;font-size:15px;line-height:1.65;color:#374151';
  const html = `<div style="background:#f5f5f7;margin:0;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:8px;padding:40px 44px">
    <img src="${SITIO}/logo-sbs.png" alt="Show Business Solutions" width="56" height="56" style="display:block;width:56px;height:56px;border:0;margin-bottom:22px">
    <p style="${P}">${esc(hola)}:</p>
    <p style="${P}">Gracias por trabajar con nosotros el ${esc(cuando)}${esc(que)}${esc(enLugar)}.</p>
    <p style="${P}">Para firmar tu contrato de esa fecha, tocá el botón:</p>
    <p style="margin:22px 0"><a href="${esc(link)}" style="display:inline-block;background:#0f1117;color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;padding:14px 26px;border-radius:10px">Firmar mi contrato</a></p>
    <p style="${P}">O copiá este link: <a href="${esc(link)}" style="color:#534AB7;text-decoration:underline">${esc(link)}</a></p>
    <p style="${P}">El link vence en 7 días. Cualquier duda, respondé este mail.</p>
    <div style="margin-top:28px;padding-top:22px;border-top:1px solid #ececf1">
      <img src="${SITIO}/firmas/firma-rrhh.jpg" alt="Show Business Solutions" width="300" style="max-width:300px;width:100%;height:auto;display:block;border:0">
    </div>
  </div>
  <div style="max-width:560px;margin:16px auto 0;text-align:center;font-size:11px;color:#9ca3af;line-height:1.7">
    Show Business Solutions · <a href="https://show-bs.com/" style="color:#9ca3af;text-decoration:underline">show-bs.com</a><br>
    Instagram <a href="https://www.instagram.com/showbs/" style="color:#9ca3af;text-decoration:underline">@showbs</a> · <a href="https://www.instagram.com/showbspain/" style="color:#9ca3af;text-decoration:underline">@showbspain</a>
  </div>
</div>`;
  return { subject, text, html };
}

// ── La fila que manda la planilla ──
// La marca: "P" (presente), "A" (ausente) o vacío. Una misma persona en dos sectores: gana la "P".
export function normalizarFilas(filas) {
  const por = new Map();
  (Array.isArray(filas) ? filas : []).slice(0, MAX_FILAS).forEach(f => {
    const cuil = String((f && f.cuil) || '').replace(/\D/g, '');
    if (cuil.length < 7) return;
    // Sólo "P"/"Presente" y "A"/"Ausente" (lo demás, sin marca: "Pendiente" no es presente).
    const w = String((f && f.marca) || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toUpperCase().trim().split(/[^A-Z]+/)[0] || '';
    const marca = w === 'P' || w === 'PRESENTE' ? 'P' : w === 'A' || w === 'AUSENTE' ? 'A' : '';
    const fila = { cuil, marca, sector: String(f.sector || '').trim().slice(0, 40), rol: String(f.rol || '').trim().slice(0, 40), obs: String(f.obs || '').trim().slice(0, 80), apellido: String(f.apellido || '').trim().slice(0, 80), nombre: String(f.nombre || '').trim().slice(0, 80) };
    // De la disponibilidad del mes (lo agrega el script): el mail y el CUIL o DNI que dejó ahí la persona.
    const mail = String(f.mail || '').trim().toLowerCase().slice(0, 120), doc = String(f.doc || '').replace(/\D/g, '');
    if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) fila.mail = mail;
    // El script la manda con "espera" si la P es de hace menos de 30 minutos: el contrato sale después.
    if (f.espera === true) fila.espera = true;
    if (doc.length >= 7 && doc.length <= 11 && doc !== cuil) fila.doc = doc;
    // El CUIL del alta de ARCA de esa persona (lo busca el script en la planilla de altas, por el nombre y parecido al de la planilla).
    const alta = String(f.alta || '').replace(/\D/g, '');
    if (cuilValido(alta) && alta !== cuil) fila.alta = alta;
    const antes = por.get(cuil);
    if (!antes || (marca === 'P' && antes.marca !== 'P') || (marca && !antes.marca)) por.set(cuil, fila);
  });
  return [...por.values()];
}
// El show del panel de esa fecha (del Arena): el que más se parece por nombre; si no, el del Centro de Control.
export function elegirShow(convs, show) {
  const n = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const buscado = n(show), palabras = buscado.split(' ').filter(w => w.length > 2);
  const puntos = c => { const t = n(c.nombre); return (buscado && t.includes(buscado) ? 10 : 0) + palabras.filter(w => t.includes(w)).length + (c.centro_control ? 0.5 : 0); };
  return (convs || []).slice().sort((a, b) => puntos(b) - puntos(a))[0] || null;
}
// ── Externos (19-nov) ── (sinTildes está más abajo; las funciones se usan después de cargado el módulo)
// Palabras que no sirven para reconocer un evento (están en muchos nombres).
const GENERICAS_EXT = new Set(('fiesta show shows evento eventos festival masivo privado servicio presentismo presentes info rrhh base '
  + 'del de la las los el en al con por para fin ano anio sbs contratos acreditacion acreditaciones capacitacion tentativo borrador '
  + 'enero febrero marzo abril mayo junio julio agosto septiembre setiembre octubre noviembre diciembre disponibilidad').split(' '));
function palabrasEvento(s) { return sinTildes(s).split(/[^a-z0-9]+/).filter(w => w.length > 2 && !/^\d+$/.test(w) && !GENERICAS_EXT.has(w)); }
// La convocatoria de Externos de esa fecha para el evento de la planilla: la que comparte más palabras del nombre
// ("CAD Gelatina" ↔ "CAD Gelatina @CEC"). Sin ninguna en común, ninguna: no se ata a otro evento del mismo día (por
// ejemplo, a la disponibilidad del mes, que tiene todas las fechas).
export function elegirEvento(convs, nombres) {
  const buscadas = [...new Set((nombres || []).flatMap(palabrasEvento))];
  if (!buscadas.length) return null;
  const parecida = (a, b) => a === b || (a.length >= 5 && b.length >= 5 && (a.startsWith(b) || b.startsWith(a)));
  const puntos = c => { const t = palabrasEvento(c.nombre); return buscadas.filter(w => t.some(x => parecida(w, x))).length; };
  const l = (convs || []).map(c => ({ c, p: puntos(c) })).filter(x => x.p > 0).sort((a, b) => b.p - a.p);
  return l.length ? l[0].c : null;
}
// La raíz de un puesto, para aparear el SECTOR / PUESTO de la fila con el PUESTO de la INFO RRHH: la primera palabra,
// sin tildes, sin "/a" ni lo que va entre paréntesis, sin plural ni género ("SUPERVISORES" = "Supervisor/a" = "supervisora").
export function raizPuesto(s) {
  const w = sinTildes(s).replace(/\/\s*[a-z]{1,2}\b/g, ' ').replace(/\(.*?\)/g, ' ').split(/[^a-z]+/).filter(x => x.length > 1)[0] || '';
  return w.replace(/(es|as|os|s)$/, '').replace(/[ao]$/, '');
}
export function tituloPuesto(s) { const t = String(s || '').trim().replace(/\s+/g, ' ').toLowerCase(); return t.charAt(0).toUpperCase() + t.slice(1); }
// El puesto (el de la fila) y el monto (el TOTAL POR PERSONA de ese puesto en la INFO RRHH) de una fila de Externos.
export function tarifaExterna(tarifas, sector) {
  const r = raizPuesto(sector);
  if (!r || /^(backup|reserva|suplente)/.test(r)) return null;
  const t = (tarifas || []).find(x => { const k = raizPuesto(x && x.puesto); return k && (k === r || (k.length >= 5 && r.length >= 5 && (k.startsWith(r) || r.startsWith(k)))); });
  const monto = t ? montoANumero(t.monto) : 0;
  return monto > 0 ? { monto, puesto: tituloPuesto(sector) } : null;
}
function sinMontoExterno(ctx, sector) {
  if (/backup|reserva|suplente/i.test(sector || '')) return 'La fila dice "' + sector + '": poné en SECTOR / PUESTO el puesto que cubrió';
  if (!raizPuesto(sector)) return 'Falta el puesto en SECTOR / PUESTO';
  if (!(ctx.tarifas || []).length) return 'No encontré los montos en la INFO RRHH del evento (hoja RECURSOS Y VALORES, con PUESTO y TOTAL POR PERSONA, en la misma carpeta)';
  return 'Falta el monto de "' + sector + '" en la INFO RRHH (hoja RECURSOS Y VALORES; hay: ' + ctx.tarifas.map(t => t.puesto).join(', ') + ')';
}

// Qué hacer con una fila: lo decide sin tocar nada (se prueba aparte).
// El DNI de 8 números que lleva adentro un CUIL (o el DNI suelto). Con 10 números no se sabe.
export function nucleoDe(doc) { const d = String(doc || '').replace(/\D/g, ''); return d.length === 11 ? d.slice(2, 10) : d.length >= 7 && d.length <= 8 ? d.padStart(8, '0') : ''; }
const sinTildes = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
// De lo que encontró la base para un CUIL de la planilla, a quién se le manda: el de la nómina con
// el mismo CUIL; si no, el de la nómina con el mismo DNI o, con un CUIL de 10 números, de las dos
// maneras posibles, sólo si el apellido de la planilla coincide (un CUIL mal tipeado puede dar el DNI de otro). Si no está en la nómina, lo mismo
// en las inscripciones. Si quedan dos personas distintas, es dudoso (no se manda).
export function elegirPersona(cands, fila) {
  const palabras = sinTildes(fila.apellido).split(/[^a-zñ]+/).filter(w => w.length >= 3);
  const apellidoOk = c => palabras.length > 0 && palabras.some(w => sinTildes(c.nombre).includes(w));
  for (const fuente of ['nomina', 'inscripcion']) {
    const deFuente = (cands || []).filter(c => c.fuente === fuente);
    const exactos = deFuente.filter(c => c.como === 'exacto');
    // Por el DNI solo (o un CUIL de 10 números), también el apellido: un CUIL mal tipeado puede dar el DNI de otro.
    const otros = deFuente.filter(c => (c.como === 'dni' || c.como === 'aproximado') && apellidoOk(c));
    for (const l of [exactos, otros]) {
      if (!l.length) continue;
      const nucleos = new Set(l.map(c => c.nucleo));
      if (nucleos.size > 1) return { ambigua: true, nombre: l[0].nombre };
      return l.slice().sort((a, b) => (b.email ? 1 : 0) - (a.email ? 1 : 0))[0];
    }
    if (deFuente.length && !exactos.length && !otros.length && fuente === 'nomina') { const ins = (cands || []).some(c => c.fuente === 'inscripcion'); if (!ins) return { distinta: true }; }
  }
  return null;
}
// ── Por el nombre, cuando el CUIL de la planilla no lleva a nadie (a veces está mal escrito) ──
// Las palabras de un nombre, sin tildes ni signos ("Díaz Cabrera" → ["diaz", "cabrera"]).
export function palabrasDe(s) { return sinTildes(s).replace(/ñ/g, 'n').split(/[^a-z]+/).filter(w => w.length >= 2); }
// El pedazo de apellido para buscar en la base (la palabra más larga, con las vocales y la ene
// como comodín: así "Diaz" encuentra "Díaz" y "Munoz" encuentra "Muñoz").
export function patronApellido(apellido) {
  const w = palabrasDe(apellido).sort((a, b) => b.length - a.length)[0] || '';
  return w.length >= 3 ? w.replace(/[aeioun]/g, '_') : '';
}
// La persona con ese apellido y ese nombre: todas las palabras del apellido y la primera del
// nombre tienen que estar en su nombre. Primero en la nómina y, si no, en las inscripciones; sólo
// si hay una sola (con dos personas con el mismo nombre no se manda) y con documento.
// Un CUIL con el dígito verificador bien (no está mal tipeado). El de 10 al final (que ARCA corrige con el 23) no
// se puede saber: cuenta como no válido.
export function cuilValido(cuil) {
  const d = String(cuil || '').replace(/\D/g, '');
  if (d.length !== 11) return false;
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  const suma = pesos.reduce((t, p, i) => t + p * Number(d[i]), 0), r = 11 - (suma % 11);
  return (r === 11 ? 0 : r) === Number(d[10]);
}
// Los CUIL de la planilla para corregir (Thomas, 14-nov: "generalmente las planillas de supervisores tienen
// errores en números de DNI/CUIL"): cuando se encontró a la persona con otro CUIL válido (por el nombre, el
// DNI de la disponibilidad o el alta de ARCA), el del sistema, para que el script lo marque en la misma
// planilla y los supervisores lo corrijan. No cambia nada acá: el contrato sale igual con el del sistema.
// Con ctx: si esa fila ya tiene un contrato de esta fecha con otro documento que el de la persona de ahora
// ("doc_distinto": dos documentos en juego, lo decide una persona), no se marca nada: el del sistema podría
// ser el equivocado (13-nov: Amparo, el bueno era el del contrato firmado, con el CUIL del alta de ARCA).
export function cuilesACorregir(filas, personas, ctx) {
  const out = [];
  for (const f of filas) {
    const p = personas.get(f.cuil);
    if (!p || p.ambigua || p.distinta) continue;
    if (ctx) { const c = contratoDe(f, p, ctx); if (c && c.doc_nucleo && p.nucleo && c.doc_nucleo !== p.nucleo) continue; }
    const bueno = String(p.cuit || '').replace(/\D/g, '');
    if (!cuilValido(bueno) || bueno === f.cuil) continue;
    const motivo = f.cuil.length < 11 ? 'le faltan números' : f.cuil.length > 11 ? 'tiene números de más'
      : !cuilValido(f.cuil) ? 'está mal escrito (no da el dígito verificador)' : 'no coincide con el de esta persona en el sistema';
    out.push({ cuil: f.cuil, correcto: bueno.slice(0, 2) + '-' + bueno.slice(2, 10) + '-' + bueno.slice(10), motivo });
  }
  return out;
}
export function elegirPorNombre(cands, fila) {
  const ap = palabrasDe(fila.apellido), nom = palabrasDe(fila.nombre)[0];
  if (!ap.length || !nom) return null;
  // Con un CUIL válido en la planilla, quien tenga otro DNI es otra persona con el mismo nombre (13-nov: un
  // contrato le llegó a una homónima de la nómina): por el nombre sólo se busca si el CUIL está mal escrito.
  const nPlanilla = cuilValido(fila.cuil) ? nucleoDe(fila.cuil) : '';
  const coincide = c => { const t = new Set(palabrasDe(c.nombre)); return ap.every(w => t.has(w)) && t.has(nom); };
  for (const fuente of ['nomina', 'inscripcion']) {
    const l = (cands || []).filter(c => c.fuente === fuente && c.nucleo && coincide(c) && (!nPlanilla || c.nucleo === nPlanilla));
    if (!l.length) continue;
    if (new Set(l.map(c => c.nucleo)).size > 1) return { ambigua: true, nombre: l[0].nombre, porNombre: true };
    return Object.assign({}, l.slice().sort((a, b) => (b.email ? 1 : 0) - (a.email ? 1 : 0))[0], { como: 'nombre' });
  }
  return null;
}
// Lo que trae la base (personas y solicitudes) como candidatos, con el DNI y el mail de la inscripción.
export function candidatosPorNombre(personas, solicitudes) {
  const doc = c => String(c || '').replace(/\D/g, '');
  const ins = (solicitudes || []).map(s => ({ fuente: 'inscripcion', id: null, nombre: s.nombre, email: String(s.email || '').trim() || null, cuit: doc(s.cuit), nucleo: nucleoDe(s.cuit) }));
  const mailIns = n => (ins.find(s => s.nucleo === n && s.email) || {}).email || null;
  const per = (personas || []).map(p => ({ fuente: 'nomina', id: p.id, nombre: p.nombre, cuit: doc(p.cuit), nucleo: nucleoDe(p.cuit), email: String(p.email || '').trim() || null }))
    .map(p => Object.assign(p, { email: p.email || mailIns(p.nucleo) }));
  const enNomina = new Set(per.map(p => p.nucleo));
  return per.concat(ins.filter(s => !enNomina.has(s.nucleo)));
}
// ── El mail de la disponibilidad (lo agrega el script de la planilla: fila.mail y fila.doc) ──
// A quien la base encontró pero sin mail: el de la disponibilidad, si el documento que dejó ahí es
// el mismo. A quien la base no encontró: el contrato con los datos de la planilla y ese mail, si con
// ese documento no hay nadie en la base (si hay alguien y no se lo eligió es porque no coincide
// el apellido: se revisa a mano). `cands`: lo que la base trajo para el CUIL de la planilla y para
// el documento de la disponibilidad.
export function conDisponibilidad(p, fila, cands) {
  if (!fila.mail) return p;
  const nDisp = nucleoDe(fila.doc);
  if (p && !p.ambigua && !p.distinta) {
    if (String(p.email || '').includes('@') || (nDisp && nDisp !== p.nucleo)) return p;
    return Object.assign({}, p, { email: fila.mail, mailDe: 'disponibilidad' });
  }
  if (p && p.ambigua && !(p.porNombre && nDisp)) return p;
  const docs = [fila.doc, fila.cuil].filter(Boolean);
  const doc = docs.find(d => d.length === 11) || docs.find(d => nucleoDe(d)) || '';
  const nucleo = nucleoDe(doc);
  if (!nucleo || (cands || []).some(c => c.nucleo === nucleo)) return p;
  return { fuente: 'disponibilidad', como: 'disponibilidad', id: null, nombre: (fila.nombre + ' ' + fila.apellido).trim(), email: fila.mail, cuit: doc, nucleo, mailDe: 'disponibilidad' };
}
// ── El mail corregido a mano (18-nov) ──
// Si en el panel se le cambió el mail a un contrato de la persona ("Cambiar mail"), los contratos siguientes salen al
// mail nuevo, aunque la nómina, la inscripción o la disponibilidad del mes tengan todavía el viejo, y aunque no esté en
// la nómina (Thomas, 18-nov: "que esté OK para siempre, no para uno en particular"; el contrato del show siguiente
// salía otra vez al mail que no andaba). Sólo si el que trae es uno de los que se corrigieron o no trae ninguno: si la
// persona dejó después otro distinto, se usa ése. Vale el último cambio.
export function correccionesDeMail(eventos) {
  const m = new Map();
  (eventos || []).slice().sort((a, b) => String(b.fecha || '').localeCompare(String(a.fecha || ''))).forEach(e => {
    const meta = e.meta || {}, c = e.contratos || {};
    const antes = String(meta.antes || '').trim().toLowerCase(), nuevo = String(meta.nuevo || '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(nuevo)) return;
    [...new Set([nucleoDe(c.cuil), nucleoDe(c.doc_nucleo)].filter(Boolean))].forEach(n => {
      if (!m.has(n)) m.set(n, { nuevo, antes: new Set() });
      if (antes) m.get(n).antes.add(antes);
    });
  });
  return m;
}
export function conMailCorregido(p, correcciones) {
  if (!p || p.ambigua || p.distinta || !p.nucleo || !correcciones) return p;
  const k = correcciones.get(p.nucleo); if (!k) return p;
  const actual = String(p.email || '').trim().toLowerCase();
  if (actual === k.nuevo || (actual.includes('@') && !k.antes.has(actual))) return p;
  return Object.assign({}, p, { email: k.nuevo, mailDe: 'corregido' });
}
// El contrato que ya tiene esa fila (de esa fecha, sin anular). No sólo por el documento de la persona: si cambia
// el documento con que se la encuentra (la disponibilidad o las altas de ARCA traen otro), también por el de la
// planilla, el de la disponibilidad, el contrato que ya tenía esa fila y la persona. El 13-nov salieron contratos
// duplicados porque a las 18:22 se encontró a algunas personas con otro documento y no se vio el anterior.
export function contratoDe(fila, persona, ctx) {
  const porDoc = k => (k && ctx.contratos.get(k)) || null;
  const previo = ctx.antes && ctx.antes.get(fila.cuil);
  return porDoc(persona && persona.nucleo) || porDoc(nucleoDe(fila.cuil)) || porDoc(nucleoDe(fila.doc))
    || (previo && previo.contrato_id && ctx.porId && ctx.porId.get(previo.contrato_id))
    || (persona && persona.id && ctx.porPersona && ctx.porPersona.get(persona.id)) || null;
}
export function decidir(fila, ctx) {
  const persona = ctx.personas.get(fila.cuil);
  const contrato = contratoDe(fila, persona, ctx);
  // Ya tiene uno de esta fecha, pero con otro documento que el de la persona de ahora: no se manda otro ni se
  // anula solo; se revisa a mano cuál es el correcto (13-nov: dos contratos para la misma fila).
  if (fila.marca === 'P' && contrato && persona && persona.nucleo && contrato.doc_nucleo && contrato.doc_nucleo !== persona.nucleo && contrato.estado !== 'firmado')
    return { resultado: 'doc_distinto', contrato, detalle: 'Ya tiene un contrato de esta fecha con otro documento: revisá cuál es el correcto y anulá el otro' };
  if (fila.marca === 'P' && contrato && persona && persona.nucleo && contrato.doc_nucleo && contrato.doc_nucleo !== persona.nucleo)
    return { resultado: 'doc_distinto', contrato, detalle: 'Firmó un contrato de esta fecha con otro documento: revisá cuál es el correcto' };
  if (fila.marca === 'P') {
    if (!persona) return { resultado: fila.cuil.length === 11 || fila.cuil.length <= 8 ? 'sin_persona' : 'cuil_incompleto', detalle: fila.cuil.length === 11 || fila.cuil.length <= 8 ? (ctx.disponibilidad ? 'No está en la nómina, ni en las inscripciones, ni en la disponibilidad del mes' : 'No está en la nómina ni en las inscripciones') : 'El CUIL de la planilla está incompleto (' + fila.cuil.length + ' números) y no se encontró a nadie con ese apellido' };
    if (persona.ambigua && persona.porNombre) return { resultado: 'sin_persona', detalle: 'El CUIL no coincide y hay más de una persona con ese nombre: revisá el CUIL en la planilla' };
    if (persona.ambigua) return { resultado: 'cuil_incompleto', detalle: 'Con ese documento hay más de una persona: revisá el CUIL en la planilla' };
    if (persona.distinta) return { resultado: 'sin_persona', detalle: 'Con ese DNI hay alguien en la nómina con otro apellido: revisá el CUIL en la planilla' };
    if (contrato && contrato.estado === 'firmado') return { resultado: 'firmado', contrato };
    if (contrato && contrato.estado !== 'pendiente') return { resultado: 'ya_tenia', contrato };
    // Armado en una vuelta anterior, pero el mail no salió: se vuelve a mandar (el contrato ya está hecho).
    if (contrato) return { resultado: 'mandar', persona, contrato };
    if (!String(persona.email || '').includes('@')) return { resultado: 'sin_mail', detalle: ctx.disponibilidad ? 'No tiene mail en la nómina ni en la disponibilidad del mes' : 'No tiene mail en la nómina' };
    if (!ctx.plantilla) return { resultado: 'sin_plantilla', detalle: 'Falta el modelo de contrato en el panel' };
    if (!ctx.conv) return { resultado: 'sin_show', detalle: ctx.ext ? 'No hay un evento de Externos con esa fecha y ese nombre en el panel (se crea desde el calendario de Externos, en "Disponibilidad del mes")' : 'No hay un show del Arena con esa fecha en el panel' };
    const tarifa = ctx.ext ? tarifaExterna(ctx.tarifas, fila.sector) : tarifaDe(ctx.cfg, ctx.fecha, fila.sector, fila.rol, fila.obs);
    if (!tarifa && ctx.ext) return { resultado: 'sin_monto', detalle: sinMontoExterno(ctx, fila.sector) };
    if (!tarifa) { const p = puestoDe(ctx.cfg, fila.sector, fila.rol, fila.obs); return { resultado: 'sin_monto', detalle: p ? 'Falta el monto de ' + p + ' para ' + String(ctx.fecha).slice(5, 7) + '/' + String(ctx.fecha).slice(0, 4) : 'Falta decir qué puesto lleva ' + (fila.sector || 'ese sector') }; }
    // La P es de hace un rato: todavía no (por si fue un error). Sale en una vuelta siguiente.
    if (fila.espera) return { resultado: 'en_espera', detalle: 'Todavía no pasó la espera después de la P (propiedad ESPERA_MINUTOS del script)' };
    return { resultado: 'mandar', persona, contrato, tarifa };
  }
  if (contrato && contrato.estado === 'firmado') return { resultado: 'firmado_ausente', contrato, detalle: 'Firmó, pero la planilla ya no le da el presente' };
  if (contrato) return { resultado: 'anular', contrato };
  return fila.marca === 'A' ? { resultado: 'ausente' } : null;
}

// ── Supabase, con la clave de servidor ──
function sbFetch(servicio, ruta, op = {}) {
  return fetch(`${SB_URL}/rest/v1/${ruta}`, {
    method: op.method || 'GET',
    headers: Object.assign({ 'apikey': servicio, 'Authorization': `Bearer ${servicio}`, 'Content-Type': 'application/json' }, op.headers || {}),
    body: op.body === undefined ? undefined : JSON.stringify(op.body)
  });
}
async function sbJson(servicio, ruta, op) { const r = await sbFetch(servicio, ruta, op); const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {} return { ok: r.ok, status: r.status, data: j }; }
const espera = ms => new Promise(r => setTimeout(r, ms));
async function mandarMail(resend, para, mail, de) {
  for (let intento = 0; ; intento++) {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST', headers: { 'Authorization': `Bearer ${resend}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: de || REMITENTE, to: [para], subject: mail.subject, text: mail.text, html: mail.html })
    });
    if (r.ok) return { ok: true };
    const cuerpo = await r.json().catch(() => null), txt = JSON.stringify(cuerpo || {});
    if (intento === 0 && r.status === 429 && /rate_limit|too many/i.test(txt)) { await espera(1500); continue; }
    return { ok: false, tope: r.status === 429, error: (cuerpo && (cuerpo.message || cuerpo.error)) || ('Resend contestó ' + r.status) };
  }
}
function claveOk(dada, esperada) {
  const a = Buffer.from(String(dada || '')), b = Buffer.from(String(esperada || ''));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', resend = process.env.RESEND_API_KEY || '', clave = process.env.PRESENTES_CLAVE || '';
  if (!clave) return res.status(500).json({ error: 'Falta configurar PRESENTES_CLAVE en Vercel' });
  if (!claveOk(req.headers['x-clave'], clave)) return res.status(401).json({ error: 'Clave incorrecta' });
  if (!servicio || !resend) return res.status(500).json({ error: 'Falta configurar en Vercel la clave de Supabase o la de Resend' });
  let cuerpo;
  try { cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch (_) { return res.status(400).json({ error: 'El pedido no es JSON' }); }
  const fecha = String(cuerpo.fecha || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fecha)) return res.status(400).json({ error: 'Falta la fecha (AAAA-MM-DD)' });
  const show = String(cuerpo.show || '').trim().slice(0, 80);
  const archivo = String((cuerpo.archivo && cuerpo.archivo.id) || '').slice(0, 120);
  const filas = normalizarFilas(cuerpo.filas);
  // Externos (19-nov): otra área y otro origen (no se cruzan con el Arena), el evento por el nombre y los montos de la INFO RRHH.
  const ext = cuerpo.area === 'externos', area = ext ? 'externos' : 'arena', origen = ext ? 'planilla_externos' : 'planilla';
  const lugar = String(cuerpo.lugar || '').trim().slice(0, 120);
  const tarifas = ext ? (Array.isArray(cuerpo.tarifas) ? cuerpo.tarifas : []).slice(0, 40)
    .map(t => ({ puesto: String((t && t.puesto) || '').trim().slice(0, 60), monto: t && t.monto })).filter(t => t.puesto && montoANumero(t.monto) > 0) : [];

  // Lo que ya hay de esa fecha: los contratos de la planilla (los no anulados) y lo último que dijo.
  const colsPres = 'cuil,marca,resultado,persona_id,contrato_id';
  const [rc, rp0, rcfg, rconv] = await Promise.all([
    sbJson(servicio, `contratos?select=id,persona_id,doc_nucleo,estado,token,email,nombre&fecha_show=eq.${fecha}&origen=eq.${origen}&estado=neq.anulado`),
    sbJson(servicio, `planilla_presentes?select=${colsPres}&fecha=eq.${fecha}&area=eq.${area}`),
    sbJson(servicio, `config?select=key,value&key=in.(contratos_presentes,contrato_plantilla)`),
    sbJson(servicio, `convocatorias?select=id,nombre,venue,area,fecha,centro_control&area=eq.${ext ? 'externos' : 'movistar_arena'}&fecha=like.*${fecha}*`)
  ]);
  // Sin la columna "area" (antes de correr contratos-presentes-externos.sql), el Arena sigue como siempre.
  let rp = rp0;
  const conArea = rp0.ok;
  if (!rp.ok && !ext) rp = await sbJson(servicio, `planilla_presentes?select=${colsPres}&fecha=eq.${fecha}`);
  if (!rc.ok || !rp.ok) return res.status(500).json({ error: ext ? 'Falta correr contratos-presentes-externos.sql en Supabase' : 'Falta correr contratos-presentes.sql en Supabase', detalle: (rc.data && rc.data.message) || (rp.data && rp.data.message) || '' });
  const contratos = new Map((rc.data || []).map(c => [c.doc_nucleo, c]));
  const antes = new Map((rp.data || []).map(x => [x.cuil, x]));
  const cfgs = Object.fromEntries((rcfg.data || []).map(x => [x.key, x.value]));
  const cfg = cfgs.contratos_presentes || {};
  const plantilla = String(((cfgs.contrato_plantilla || {}).ar) || '').trim();
  const conv = ext ? elegirEvento(rconv.ok ? rconv.data : [], [show].concat(Array.isArray(cuerpo.nombres) ? cuerpo.nombres.slice(0, 3).map(String) : []))
    : elegirShow(rconv.ok ? rconv.data : [], show);

  // Las personas: las de las filas que importan (con marca, o que ya tenían algo).
  const buscar = filas.filter(f => cuerpo.simular || f.marca || antes.has(f.cuil)).map(f => f.cuil);
  const personas = new Map();
  if (buscar.length) {
    // También el documento que la persona dejó en la disponibilidad, por si el de la planilla está mal.
    // El CUIL del alta de ARCA manda sobre el de la planilla (Thomas, 15-nov: "no puedo estar corrigiendo en cada planilla, tenemos
    // que ver no sólo para ella sino para los demás"): la planilla la escriben los supervisores a mano; el alta la validó ARCA.
    // Sólo en las filas que todavía no tienen contrato: lo que ya salió no se toca (si se rearmara, saldría otro contrato).
    const conAlta = f => !!f.alta && !((antes.get(f.cuil) || {}).contrato_id);
    const deBusqueda = f => conAlta(f) ? Object.assign({}, f, { cuil: f.alta }) : f;   // la fila, como si la planilla dijera el del alta
    const docs = filas.filter(f => buscar.includes(f.cuil)).flatMap(f => [f.doc, f.alta].filter(Boolean));
    const rb = await sbJson(servicio, 'rpc/presentes_buscar_personas', { method: 'POST', body: { p_cuils: [...new Set(buscar.concat(docs))] } });
    if (!rb.ok) return res.status(500).json({ error: 'Falta correr contratos-presentes.sql en Supabase', detalle: (rb.data && rb.data.message) || '' });
    const porCuil = new Map(); (rb.data || []).forEach(p => { if (!porCuil.has(p.buscado)) porCuil.set(p.buscado, []); porCuil.get(p.buscado).push(p); });
    const candsDe = f => (porCuil.get(f.cuil) || []).concat(f.doc ? porCuil.get(f.doc) || [] : []).concat(f.alta ? porCuil.get(f.alta) || [] : []);
    const elegir = f => {
      let p = elegirPersona(porCuil.get(f.cuil) || [], f);
      if ((!p || p.distinta || p.ambigua) && f.doc) { const q = elegirPersona(porCuil.get(f.doc) || [], f); if (q && !q.distinta && !q.ambigua) p = q; else if (!p) p = q; }
      return p;
    };
    // Con el alta: a quien encuentre el de la planilla sólo si tiene el mismo apellido (su ficha tiene otro número); si no,
    // el de la planilla puede ser de otra persona (la que el supervisor anotó por error), y a ésa no se le manda nada.
    const mismoApellido = (p, f) => { const ws = palabrasDe(f.apellido).filter(w => w.length >= 3), t = palabrasDe(p.nombre || ''); return ws.length > 0 && ws.some(w => t.includes(w)); };
    filas.forEach(f0 => {
      let p = elegir(deBusqueda(f0));
      if (conAlta(f0) && (!p || p.distinta || p.ambigua)) { const q = elegir(f0); if (q && !q.distinta && !q.ambigua && mismoApellido(q, f0)) p = q; }
      if (p) personas.set(f0.cuil, p);
    });
    // A los que el CUIL no llevó a nadie: por el apellido y el nombre (una sola consulta para todos).
    const faltan = filas.filter(f => buscar.includes(f.cuil) && (!personas.has(f.cuil) || personas.get(f.cuil).distinta) && patronApellido(f.apellido));
    if (faltan.length) {
      const patrones = [...new Set(faltan.map(f => patronApellido(f.apellido)))].slice(0, 150);
      const or = 'or=(' + patrones.map(p => 'nombre.ilike.*' + p + '*').join(',') + ')';
      const [rpn, rsn] = await Promise.all([
        sbJson(servicio, `personas?select=id,nombre,email,cuit&${or}&limit=5000`),
        sbJson(servicio, `solicitudes?select=nombre,email,cuit,created_at&${or}&order=created_at.desc&limit=5000`)
      ]);
      const cands = candidatosPorNombre(rpn.ok ? rpn.data : [], rsn.ok ? rsn.data : []);
      faltan.forEach(f => { const p = elegirPorNombre(cands, deBusqueda(f)) || (conAlta(f) ? elegirPorNombre(cands, f) : null); if (p) personas.set(f.cuil, p); });
    }
    // Lo que todavía falta (la persona o su mail), con el mail de la disponibilidad del mes.
    filas.forEach(f => { if (!f.mail || !buscar.includes(f.cuil)) return; const fb = conAlta(f) ? Object.assign({}, f, { cuil: f.alta, doc: f.alta }) : f; const p = conDisponibilidad(personas.get(f.cuil) || null, fb, candsDe(f)); if (p) personas.set(f.cuil, p); });
    // El contrato, con el CUIL del alta (aunque la ficha o la inscripción tengan otro): es la misma persona (mismo nombre).
    filas.forEach(f => { const p = personas.get(f.cuil); if (!conAlta(f) || !p || p.ambigua || p.distinta) return; personas.set(f.cuil, Object.assign({}, p, { cuit: f.alta, nucleo: nucleoDe(f.alta), deAlta: true })); });
    // El mail que se corrigió a mano en un contrato anterior (ver conMailCorregido).
    const rm = await sbJson(servicio, 'contrato_eventos?select=fecha,meta,contratos(cuil,doc_nucleo)&tipo=eq.mail_cambiado&order=fecha.desc&limit=5000');
    if (rm.ok) { const corr = correccionesDeMail(rm.data); if (corr.size) personas.forEach((p, k) => personas.set(k, conMailCorregido(p, corr))); }
  }

  const porId = new Map((rc.data || []).map(c => [c.id, c])), porPersona = new Map((rc.data || []).filter(c => c.persona_id).map(c => [c.persona_id, c]));
  const ctx = { personas, contratos, porId, porPersona, antes, cfg, plantilla, conv, fecha, disponibilidad: Number(cuerpo.disponibilidad) > 0, ext, tarifas };

  // Revisar (desde el script, antes del show): qué pasaría si todos tuvieran "P", sin mandar ni guardar nada.
  if (cuerpo.simular) {
    const porResultado = {}, problemas = [];
    for (const f of filas) {
      const d = decidir(Object.assign({}, f, { marca: 'P' }), ctx), k = d.resultado === 'mandar' ? 'saldria' : d.resultado;
      porResultado[k] = (porResultado[k] || 0) + 1;
      if (k !== 'saldria' && k !== 'ya_tenia' && k !== 'firmado') problemas.push({ sector: f.sector, apellido: f.apellido, nombre: f.nombre, resultado: k, detalle: d.detalle || '' });
      if (d.resultado === 'mandar' && d.tarifa) porResultado['puesto: ' + d.tarifa.puesto] = (porResultado['puesto: ' + d.tarifa.puesto] || 0) + 1;
      if (d.resultado === 'mandar' && d.persona && d.persona.mailDe === 'disponibilidad') porResultado['con el mail de la disponibilidad'] = (porResultado['con el mail de la disponibilidad'] || 0) + 1;
      if (d.resultado === 'mandar' && d.persona && d.persona.mailDe === 'corregido') porResultado['con el mail corregido a mano'] = (porResultado['con el mail corregido a mano'] || 0) + 1;
    }
    return res.status(200).json({ ok: true, simulacion: true, fecha, show: (conv && conv.nombre) || '', filas: filas.length, porResultado, problemas: problemas.slice(0, 80), cuiles: cuilesACorregir(filas, personas, ctx) });
  }
  const registro = [], cuenta = { enviados: 0, anulados: 0, pendientes: 0, problemas: 0, porGoogle: 0 };
  const ahora = () => new Date().toISOString();
  for (const fila of filas) {
    const dec = decidir(fila, ctx);
    if (!dec) { if (antes.has(fila.cuil)) registro.push({ fila, resultado: 'ausente', detalle: 'Sin marca', persona: personas.get(fila.cuil) }); continue; }
    let resultado = dec.resultado, detalle = dec.detalle || null, contratoId = dec.contrato ? dec.contrato.id : null;
    if (resultado === 'mandar') {
      if (cuenta.enviados >= MAX_ENVIOS) { resultado = 'pendiente'; detalle = 'Sale en la próxima vuelta'; cuenta.pendientes++; }
      else {
        let c = dec.contrato;
        if (!c) {
          const p = dec.persona, t = dec.tarifa, dia = fechaLarga(fecha);
          const datos = {
            nombre: String(p.nombre || (fila.nombre + ' ' + fila.apellido)).trim(), cuil: String(p.cuit || '').length === 11 ? p.cuit : fila.cuil.length === 11 ? fila.cuil : (p.cuit || fila.cuil),
            puesto: t.puesto || tituloSector(fila.sector),
            venue: ext ? String((conv && conv.venue) || lugar || '') : String(cfg.venue || (conv && conv.venue) || 'Movistar Arena'),
            fecha_inicio: dia, fecha_fin: dia, anio: fecha.slice(0, 4),
            monto_letras: numeroALetras(t.monto), monto_numero: montoFormateado(t.monto), fecha_firma_doc: hoyLarga()
          };
          const ri = await sbJson(servicio, 'contratos', {
            method: 'POST', headers: { 'Prefer': 'return=representation' },
            body: Object.assign({}, datos, { conv_id: conv.id, persona_id: p.id || null, doc_nucleo: p.nucleo, email: p.email, texto_contrato: armarTexto(plantilla, datos), estado: 'pendiente', firma_empleador_img: FIRMA_CONTRATO, fecha_show: fecha, origen, sector: fila.sector || null })
          });
          if (!ri.ok || !Array.isArray(ri.data) || !ri.data[0]) {
            // Otra vuelta lo creó al mismo tiempo (uno por persona y por fecha): queda para la próxima.
            resultado = ri.status === 409 ? 'pendiente' : 'error_mail'; detalle = ri.status === 409 ? 'Ya se estaba armando' : 'No se pudo crear el contrato: ' + ((ri.data && ri.data.message) || ri.status);
            registro.push({ fila, resultado, detalle, persona: p, contratoId: null }); if (resultado === 'pendiente') cuenta.pendientes++; else cuenta.problemas++;
            continue;
          }
          c = ri.data[0];
          await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: c.id, tipo: 'creado', meta: { origen, archivo, sector: fila.sector || null } } });
          contratos.set(p.nucleo, c);
        }
        contratoId = c.id;
        // Hotmail, Outlook, Live (19-nov): Microsoft frena lo que llega por Resend ("Delivery Delayed"). Queda en la fila
        // y el script lo manda por Google en esta misma vuelta (api/correo-google.js). Sólo si el script lo sabe hacer.
        const para = c.email || dec.persona.email;
        if (cuerpo.google === true && esMicrosoft(para)) {
          const ya = await sbJson(servicio, `contrato_eventos?select=id&contrato_id=eq.${c.id}&tipo=eq.${TIPO_GOOGLE}&limit=1`);
          if (!(ya.ok && Array.isArray(ya.data) && ya.data.length))
            await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: c.id, tipo: TIPO_GOOGLE, meta: { motivo: 'contrato', origen, show: show || (conv && conv.nombre) || '', lugar: ext ? ((conv && conv.venue) || lugar || '') : null } } });
          resultado = 'por_google'; detalle = 'Sale por Google (Hotmail y Outlook frenan los mails del sistema)'; cuenta.porGoogle++;
          registro.push({ fila, resultado, detalle, persona: dec.persona, contratoId });
          continue;
        }
        if (cuenta.enviados) await espera(600);   // Resend: 2 por segundo para toda la cuenta
        const mail = armarMail({ nombre: c.nombre || dec.persona.nombre, fecha, show: show || (conv && conv.nombre), link: `${SITIO}/contrato.html?t=${c.token}`, lugar: ext ? ((conv && conv.venue) || lugar) : undefined });
        const envio = await mandarMail(resend, c.email || dec.persona.email, mail, ext ? REMITENTE_EXT : REMITENTE);
        if (envio.ok) {
          await sbFetch(servicio, `contratos?id=eq.${c.id}`, { method: 'PATCH', body: { estado: 'enviado', fecha_envio: ahora() } });
          await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: c.id, tipo: 'enviado', meta: { origen } } });
          resultado = 'enviado'; detalle = null; cuenta.enviados++;
        } else {
          resultado = envio.tope ? 'pendiente' : 'error_mail'; detalle = envio.tope ? 'Resend pidió esperar: sale en la próxima vuelta' : 'No salió el mail: ' + envio.error;
          if (envio.tope) cuenta.pendientes++; else cuenta.problemas++;
          if (envio.tope) { registro.push({ fila, resultado, detalle, persona: dec.persona, contratoId }); break; }
        }
      }
    } else if (resultado === 'anular') {
      const motivo = fila.marca === 'A' ? 'Ausente en la planilla' : 'Le sacaron el presente en la planilla';
      const ra = await sbFetch(servicio, `contratos?id=eq.${dec.contrato.id}&estado=neq.firmado`, { method: 'PATCH', body: { estado: 'anulado', vence_el: ahora(), anulado_at: ahora(), anulado_motivo: motivo } });
      if (ra.ok) { await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: dec.contrato.id, tipo: 'anulado', meta: { origen, motivo } } }); contratos.delete(dec.contrato.doc_nucleo || ((personas.get(fila.cuil) || {}).nucleo)); resultado = 'anulado'; detalle = motivo; cuenta.anulados++; }
      else { resultado = 'error_mail'; detalle = 'No se pudo anular'; cuenta.problemas++; }
    } else if (['sin_persona', 'cuil_incompleto', 'sin_mail', 'sin_monto', 'sin_show', 'sin_plantilla', 'firmado_ausente'].includes(resultado)) cuenta.problemas++;
    registro.push({ fila, resultado, detalle, persona: personas.get(fila.cuil), contratoId });
  }

  // Lo que pasó con cada fila, para el panel.
  if (registro.length) {
    const filasReg = registro.map(({ fila, resultado, detalle, persona, contratoId }) => ({
      fecha, show: show || null, archivo_id: archivo || null, sector: fila.sector || null, cuil: fila.cuil, apellido: fila.apellido || null, nombre: fila.nombre || null,
      marca: fila.marca || null, persona_id: (persona && !persona.ambigua && persona.id) || null, contrato_id: contratoId || null, resultado, detalle, actualizado: ahora()
    }));
    // Con la columna "area", una fila por área, fecha y CUIL; sin ella (el SQL de Externos sin correr), como antes.
    if (conArea) await sbFetch(servicio, 'planilla_presentes?on_conflict=area,fecha,cuil', { method: 'POST', headers: { 'Prefer': 'resolution=merge-duplicates' }, body: filasReg.map(x => Object.assign({ area }, x)) });
    else await sbFetch(servicio, 'planilla_presentes?on_conflict=fecha,cuil', { method: 'POST', headers: { 'Prefer': 'resolution=merge-duplicates' }, body: filasReg });
  }
  return res.status(200).json(Object.assign({ ok: true, fecha, show: show || (conv && conv.nombre) || '', filas: filas.length }, cuenta, { cuiles: cuilesACorregir(filas, personas, ctx) }));
}
