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
// Variables de entorno en Vercel (nunca en el código):
//   SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY (ya estaban) y PRESENTES_CLAVE
//   (la clave que lleva el script de la planilla; la misma en los dos lados).

import crypto from 'crypto';

export const config = { maxDuration: 60 };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';
const REMITENTE = 'convocatorias.arena@show-bs.com';
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
export function armarMail({ nombre, fecha, show, link }) {
  const pila = String(nombre || '').trim().split(/\s+/)[0] || '';
  const hola = pila ? 'Hola, ' + pila.charAt(0).toUpperCase() + pila.slice(1).toLowerCase() : 'Hola';
  const cuando = fechaMail(fecha), que = show ? ' (' + show + ')' : '';
  const subject = `Tu contrato del ${fechaLarga(fecha).toLowerCase()}${show ? ' · ' + show : ''}`;
  const text = `${hola}:\n\nGracias por trabajar con nosotros el ${cuando}${que} en el Movistar Arena.\n\nPara firmar tu contrato de esa fecha, entrá a este link:\n${link}\n\nEl link vence en 7 días. Cualquier duda, respondé este mail.\n\nSaludos,\nShow Business Solutions`;
  const P = 'margin:0 0 16px;font-size:15px;line-height:1.65;color:#374151';
  const html = `<div style="background:#f5f5f7;margin:0;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:8px;padding:40px 44px">
    <img src="${SITIO}/logo-sbs.png" alt="Show Business Solutions" width="56" height="56" style="display:block;width:56px;height:56px;border:0;margin-bottom:22px">
    <p style="${P}">${esc(hola)}:</p>
    <p style="${P}">Gracias por trabajar con nosotros el ${esc(cuando)}${esc(que)} en el Movistar Arena.</p>
    <p style="${P}">Para firmar tu contrato de esa fecha, tocá el botón:</p>
    <p style="margin:22px 0"><a href="${esc(link)}" style="display:inline-block;background:#0f1117;color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;padding:14px 26px;border-radius:10px">Firmar mi contrato</a></p>
    <p style="${P}">O copiá este link: <a href="${esc(link)}" style="color:#534AB7;text-decoration:underline">${esc(link)}</a></p>
    <p style="${P}">El link vence en 7 días. Cualquier duda, respondé este mail.</p>
    <div style="margin-top:28px;padding-top:22px;border-top:1px solid #ececf1">
      <img src="${SITIO}/firmas/firma-arena.jpg" alt="Show Business Solutions" width="300" style="max-width:300px;width:100%;height:auto;display:block;border:0">
    </div>
  </div>
  <div style="max-width:560px;margin:16px auto 0;text-align:center;font-size:11px;color:#9ca3af;line-height:1.7">
    Show Business Solutions · ${REMITENTE}<br>
    Instagram @showbs · @showbspain
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
    const m = String((f && f.marca) || '').trim().toUpperCase().charAt(0);
    const marca = m === 'P' ? 'P' : m === 'A' ? 'A' : '';
    const fila = { cuil, marca, sector: String(f.sector || '').trim().slice(0, 40), rol: String(f.rol || '').trim().slice(0, 40), obs: String(f.obs || '').trim().slice(0, 80), apellido: String(f.apellido || '').trim().slice(0, 80), nombre: String(f.nombre || '').trim().slice(0, 80) };
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
// Qué hacer con una fila: lo decide sin tocar nada (se prueba aparte).
// El DNI de 8 números que lleva adentro un CUIL (o el DNI suelto). Con 10 números no se sabe.
export function nucleoDe(doc) { const d = String(doc || '').replace(/D/g, ''); return d.length === 11 ? d.slice(2, 10) : d.length >= 7 && d.length <= 8 ? d.padStart(8, '0') : ''; }
const sinTildes = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
// De lo que encontró la base para un CUIL de la planilla, a quién se le manda: el de la nómina con
// el mismo CUIL; si no, el de la nómina con el mismo DNI; con un CUIL de 10 números (se prueba de
// las dos maneras), sólo si el apellido de la planilla coincide. Si no está en la nómina, lo mismo
// en las inscripciones. Si quedan dos personas distintas, es dudoso (no se manda).
export function elegirPersona(cands, fila) {
  const palabras = sinTildes(fila.apellido).split(/[^a-zñ]+/).filter(w => w.length >= 3);
  const apellidoOk = c => palabras.length > 0 && palabras.some(w => sinTildes(c.nombre).includes(w));
  for (const fuente of ['nomina', 'inscripcion']) {
    const deFuente = (cands || []).filter(c => c.fuente === fuente);
    const exactos = deFuente.filter(c => c.como === 'exacto');
    const otros = deFuente.filter(c => c.como === 'dni' || (c.como === 'aproximado' && apellidoOk(c)));
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
export function decidir(fila, ctx) {
  const persona = ctx.personas.get(fila.cuil);
  const contrato = ctx.contratos.get((persona && persona.nucleo) || nucleoDe(fila.cuil)) || null;
  if (fila.marca === 'P') {
    if (!persona) return { resultado: fila.cuil.length === 11 || fila.cuil.length <= 8 ? 'sin_persona' : 'cuil_incompleto', detalle: fila.cuil.length === 11 || fila.cuil.length <= 8 ? 'No está en la nómina ni en las inscripciones' : 'El CUIL de la planilla está incompleto (' + fila.cuil.length + ' números) y no se encontró a nadie con ese apellido' };
    if (persona.ambigua) return { resultado: 'cuil_incompleto', detalle: 'Con ese documento hay más de una persona: revisá el CUIL en la planilla' };
    if (persona.distinta) return { resultado: 'sin_persona', detalle: 'Con ese DNI hay alguien en la nómina con otro apellido: revisá el CUIL en la planilla' };
    if (contrato && contrato.estado === 'firmado') return { resultado: 'firmado', contrato };
    if (contrato && contrato.estado !== 'pendiente') return { resultado: 'ya_tenia', contrato };
    // Armado en una vuelta anterior, pero el mail no salió: se vuelve a mandar (el contrato ya está hecho).
    if (contrato) return { resultado: 'mandar', persona, contrato };
    if (!String(persona.email || '').includes('@')) return { resultado: 'sin_mail', detalle: 'No tiene mail en la nómina' };
    if (!ctx.plantilla) return { resultado: 'sin_plantilla', detalle: 'Falta el modelo de contrato en el panel' };
    if (!ctx.conv) return { resultado: 'sin_show', detalle: 'No hay un show del Arena con esa fecha en el panel' };
    const tarifa = tarifaDe(ctx.cfg, ctx.fecha, fila.sector, fila.rol, fila.obs);
    if (!tarifa) { const p = puestoDe(ctx.cfg, fila.sector, fila.rol, fila.obs); return { resultado: 'sin_monto', detalle: p ? 'Falta el monto de ' + p + ' para ' + String(ctx.fecha).slice(5, 7) + '/' + String(ctx.fecha).slice(0, 4) : 'Falta decir qué puesto lleva ' + (fila.sector || 'ese sector') }; }
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
async function mandarMail(resend, para, mail) {
  for (let intento = 0; ; intento++) {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST', headers: { 'Authorization': `Bearer ${resend}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: REMITENTE, to: [para], subject: mail.subject, text: mail.text, html: mail.html })
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

  // Lo que ya hay de esa fecha: los contratos de la planilla (los no anulados) y lo último que dijo.
  const [rc, rp, rcfg, rconv] = await Promise.all([
    sbJson(servicio, `contratos?select=id,persona_id,doc_nucleo,estado,token,email,nombre&fecha_show=eq.${fecha}&origen=eq.planilla&estado=neq.anulado`),
    sbJson(servicio, `planilla_presentes?select=cuil,marca,resultado,persona_id,contrato_id&fecha=eq.${fecha}`),
    sbJson(servicio, `config?select=key,value&key=in.(contratos_presentes,contrato_plantilla)`),
    sbJson(servicio, `convocatorias?select=id,nombre,venue,area,fecha,centro_control&area=eq.movistar_arena&fecha=like.*${fecha}*`)
  ]);
  if (!rc.ok || !rp.ok) return res.status(500).json({ error: 'Falta correr contratos-presentes.sql en Supabase', detalle: (rc.data && rc.data.message) || (rp.data && rp.data.message) || '' });
  const contratos = new Map((rc.data || []).map(c => [c.doc_nucleo, c]));
  const antes = new Map((rp.data || []).map(x => [x.cuil, x]));
  const cfgs = Object.fromEntries((rcfg.data || []).map(x => [x.key, x.value]));
  const cfg = cfgs.contratos_presentes || {};
  const plantilla = String(((cfgs.contrato_plantilla || {}).ar) || '').trim();
  const conv = elegirShow(rconv.ok ? rconv.data : [], show);

  // Las personas: las de las filas que importan (con marca, o que ya tenían algo).
  const buscar = filas.filter(f => cuerpo.simular || f.marca || antes.has(f.cuil)).map(f => f.cuil);
  const personas = new Map();
  if (buscar.length) {
    const rb = await sbJson(servicio, 'rpc/presentes_buscar_personas', { method: 'POST', body: { p_cuils: buscar } });
    if (!rb.ok) return res.status(500).json({ error: 'Falta correr contratos-presentes.sql en Supabase', detalle: (rb.data && rb.data.message) || '' });
    const porCuil = new Map(); (rb.data || []).forEach(p => { if (!porCuil.has(p.buscado)) porCuil.set(p.buscado, []); porCuil.get(p.buscado).push(p); });
    filas.forEach(f => { const p = elegirPersona(porCuil.get(f.cuil) || [], f); if (p) personas.set(f.cuil, p); });
  }

  const ctx = { personas, contratos, cfg, plantilla, conv, fecha };

  // Revisar (desde el script, antes del show): qué pasaría si todos tuvieran "P", sin mandar ni guardar nada.
  if (cuerpo.simular) {
    const porResultado = {}, problemas = [];
    for (const f of filas) {
      const d = decidir(Object.assign({}, f, { marca: 'P' }), ctx), k = d.resultado === 'mandar' ? 'saldria' : d.resultado;
      porResultado[k] = (porResultado[k] || 0) + 1;
      if (k !== 'saldria' && k !== 'ya_tenia' && k !== 'firmado') problemas.push({ sector: f.sector, apellido: f.apellido, nombre: f.nombre, resultado: k, detalle: d.detalle || '' });
      if (d.resultado === 'mandar' && d.tarifa) porResultado['puesto: ' + d.tarifa.puesto] = (porResultado['puesto: ' + d.tarifa.puesto] || 0) + 1;
    }
    return res.status(200).json({ ok: true, simulacion: true, fecha, show: (conv && conv.nombre) || '', filas: filas.length, porResultado, problemas: problemas.slice(0, 80) });
  }
  const registro = [], cuenta = { enviados: 0, anulados: 0, pendientes: 0, problemas: 0 };
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
            puesto: t.puesto || tituloSector(fila.sector), venue: String(cfg.venue || (conv && conv.venue) || 'Movistar Arena'),
            fecha_inicio: dia, fecha_fin: dia, anio: fecha.slice(0, 4),
            monto_letras: numeroALetras(t.monto), monto_numero: montoFormateado(t.monto), fecha_firma_doc: hoyLarga()
          };
          const ri = await sbJson(servicio, 'contratos', {
            method: 'POST', headers: { 'Prefer': 'return=representation' },
            body: Object.assign({}, datos, { conv_id: conv.id, persona_id: p.id || null, doc_nucleo: p.nucleo, email: p.email, texto_contrato: armarTexto(plantilla, datos), estado: 'pendiente', firma_empleador_img: FIRMA_CONTRATO, fecha_show: fecha, origen: 'planilla', sector: fila.sector || null })
          });
          if (!ri.ok || !Array.isArray(ri.data) || !ri.data[0]) {
            // Otra vuelta lo creó al mismo tiempo (uno por persona y por fecha): queda para la próxima.
            resultado = ri.status === 409 ? 'pendiente' : 'error_mail'; detalle = ri.status === 409 ? 'Ya se estaba armando' : 'No se pudo crear el contrato: ' + ((ri.data && ri.data.message) || ri.status);
            registro.push({ fila, resultado, detalle, persona: p, contratoId: null }); if (resultado === 'pendiente') cuenta.pendientes++; else cuenta.problemas++;
            continue;
          }
          c = ri.data[0];
          await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: c.id, tipo: 'creado', meta: { origen: 'planilla', archivo, sector: fila.sector || null } } });
          contratos.set(p.nucleo, c);
        }
        contratoId = c.id;
        if (cuenta.enviados) await espera(600);   // Resend: 2 por segundo para toda la cuenta
        const envio = await mandarMail(resend, c.email || dec.persona.email, armarMail({ nombre: c.nombre || dec.persona.nombre, fecha, show: show || (conv && conv.nombre), link: `${SITIO}/contrato.html?t=${c.token}` }));
        if (envio.ok) {
          await sbFetch(servicio, `contratos?id=eq.${c.id}`, { method: 'PATCH', body: { estado: 'enviado', fecha_envio: ahora() } });
          await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: c.id, tipo: 'enviado', meta: { origen: 'planilla' } } });
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
      if (ra.ok) { await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: dec.contrato.id, tipo: 'anulado', meta: { origen: 'planilla', motivo } } }); contratos.delete(dec.contrato.doc_nucleo || ((personas.get(fila.cuil) || {}).nucleo)); resultado = 'anulado'; detalle = motivo; cuenta.anulados++; }
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
    await sbFetch(servicio, 'planilla_presentes?on_conflict=fecha,cuil', { method: 'POST', headers: { 'Prefer': 'resolution=merge-duplicates' }, body: filasReg });
  }
  return res.status(200).json(Object.assign({ ok: true, fecha, show: show || (conv && conv.nombre) || '', filas: filas.length }, cuenta));
}
