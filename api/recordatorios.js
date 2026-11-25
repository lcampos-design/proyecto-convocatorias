// Recordatorios de los contratos sin firmar (14-nov-2026).
//
// Pedido: "si una persona no firmó un contrato, que automáticamente se le envíen recordatorios de
// contrato pendiente de firma, hasta que lo firme". Acordado: uno por día, al mediodía; a todos los
// contratos (Arena, Externos y España), cada uno desde su casilla; hasta que firme o venza el link
// (7 días: después figura "el link venció" y se renueva a mano desde el panel, como siempre).
//
// Lo llama el script de la planilla (apps-script/planilla-presentes.gs) una vez por día desde las 12,
// con la misma clave que usa para los presentes (PRESENTES_CLAVE). A quién le toca: contrato enviado
// (o abierto) y sin firmar, con el link vigente, mandado un día anterior y sin ningún mail hoy (ni el
// envío, ni un reenvío, ni otro recordatorio). Cada recordatorio queda como evento del contrato.
// Se puede llamar las veces que haga falta: el que ya recibió uno hoy no recibe otro.
// Manda hasta MAX_ENVIOS por llamada (Resend admite 2 por segundo): el resto vuelve como "pendientes".
//
// { simular: true } → cuántos saldrían, sin mandar nada.
// { prueba: "mail" } → uno de ejemplo (datos inventados, sin link de verdad) a ese mail.

import crypto from 'crypto';
import { TIPO_GOOGLE, esMicrosoft } from './_lib/correo-google.js';
import { armarMail as armarMailSBS } from './_lib/mail-sbs.js';

export const config = { maxDuration: 60 };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';
const CASILLA = { arena: 'convocatorias.arena@show-bs.com', externos: 'convocatorias.externos@show-bs.com' };
const FIRMA_MAIL = { arena: 'firmas/firma-rrhh.jpg', externos: 'firmas/firma-rrhh.jpg' };
export const MAX_ENVIOS = 25;
const TZ = 'America/Argentina/Buenos_Aires';

// ── Fechas (Argentina, UTC-3 todo el año) ──
export function diaAR(d) { return new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d); }
export function horaAR(d) { return Number(new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', hourCycle: 'h23' }).format(d)); }
export function inicioDelDiaAR(d) { const [a, m, dd] = diaAR(d).split('-').map(Number); return new Date(Date.UTC(a, m - 1, dd, 3, 0, 0)); }
function fechaLinda(iso) { const [a, m, d] = String(iso).slice(0, 10).split('-').map(Number); return new Date(Date.UTC(a, m - 1, d, 12)).toLocaleDateString('es-AR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).replace(',', ''); }
function fechaCorta(iso) { const [a, m, d] = String(iso).slice(0, 10).split('-').map(Number); return new Date(Date.UTC(a, m - 1, d, 12)).toLocaleDateString('es-AR', { day: 'numeric', month: 'long', timeZone: 'UTC' }); }

// ── A quién le toca hoy ──
// contratos: los enviados o abiertos, sin firmar, con el link vigente (ya filtrados por la base).
// eventosHoy: los contrato_id que hoy ya recibieron un mail (envío, reenvío o recordatorio).
export function aQuienes(contratos, eventosHoy, ahora) {
  const inicio = inicioDelDiaAR(ahora).getTime(), yaHoy = new Set(eventosHoy || []);
  return (contratos || []).filter(c =>
    (c.estado === 'enviado' || c.estado === 'visto')
    && String(c.email || '').includes('@')
    && c.token && c.vence_el && new Date(c.vence_el).getTime() > ahora.getTime()
    && c.fecha_envio && new Date(c.fecha_envio).getTime() < inicio
    && !yaHoy.has(c.id));
}

// ── El mail ──
export function areaDe(conv) { return conv && String(conv.area || '').toLowerCase() === 'externos' ? 'externos' : 'arena'; }
// El show sin "— Movistar Arena" y la fecha: la del contrato o, si el show tiene una sola, esa.
function showYFecha(c) {
  const conv = c.convocatorias || null, show = String((conv && conv.nombre) || '').split(' — ')[0].trim();
  const fs = String((conv && conv.fecha) || '').split(',').map(x => x.trim()).filter(x => /^\d{4}-\d{2}-\d{2}$/.test(x));
  return { show, fecha: c.fecha_show || (fs.length === 1 ? fs[0] : '') };
}
export function armarRecordatorio(c) {
  const area = areaDe(c.convocatorias), casilla = CASILLA[area];
  const { show, fecha } = showYFecha(c), doc = !!c.solo_documentos;
  const pila = String(c.nombre || '').trim().split(/\s+/)[0] || '';
  const hola = pila ? 'Hola, ' + pila.charAt(0).toUpperCase() + pila.slice(1).toLowerCase() : 'Hola';
  const link = `${SITIO}/contrato.html?t=${c.token}`;
  const de = fecha ? ' del ' + fechaLinda(fecha) + (show ? ' (' + show + ')' : '') : show ? ' de ' + show : '';
  const que = doc ? 'el documento' : 'tu contrato';
  // Empieza con "Contrato ·", como el primero, así lo encuentran buscando igual.
  const subject = `Contrato · pendiente de firma${show ? ' · ' + show : ''}${fecha ? ' · ' + fechaCorta(fecha) : ''}`;
  const vence = c.vence_el ? fechaLinda(diaAR(new Date(c.vence_el))) : '';
  const text = `${hola}:\n\nTe recordamos que todavía no firmaste ${que}${de}.\n\nPara firmarlo, entrá a este link:\n${link}\n\n${vence ? 'El link vence el ' + vence + '. ' : ''}Cualquier duda, respondé este mail.\n\nSaludos,\nShow Business Solutions`;
  const html = armarMailSBS({ kicker: 'Contratos', titulo: 'Recordatorio', hola,
    parrafos: [`Te recordamos que todavía no firmaste ${que}${de}.`, 'Para firmarlo, tocá el botón:'], boton: doc ? 'Firmar el documento' : 'Firmar mi contrato', link, copiar: true,
    pie: (vence ? 'El link vence el ' + vence + '. ' : '') + 'Cualquier duda, respondé este mail.', firma: `${SITIO}/${FIRMA_MAIL[area]}`, instagram: true }).html;
  return { from: casilla, subject, text, html };
}

// ── Supabase y Resend ──
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
      body: JSON.stringify({ from: mail.from, to: [para], subject: mail.subject, text: mail.text, html: mail.html })
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

  // Uno de ejemplo, para ver cómo llega (datos inventados; el link no abre ningún contrato).
  if (cuerpo.prueba) {
    const para = String(cuerpo.prueba).trim();
    if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(para)) return res.status(400).json({ error: 'El mail de prueba no es válido' });
    const hoy = diaAR(new Date()), vence = new Date(Date.now() + 5 * 864e5).toISOString();
    const mail = armarRecordatorio({ nombre: 'Ejemplo', token: 'ejemplo', vence_el: vence, fecha_show: hoy, convocatorias: { nombre: 'Show de ejemplo — Movistar Arena', area: 'movistar_arena' } });
    mail.subject = '[Prueba] ' + mail.subject;
    const envio = await mandarMail(resend, para, mail);
    return res.status(envio.ok ? 200 : 502).json(envio.ok ? { ok: true, prueba: para } : { ok: false, error: envio.error });
  }

  const ahora = new Date(), inicio = inicioDelDiaAR(ahora).toISOString();
  // A la noche no: sólo de 9 a 21 (el script llama desde las 12).
  const hora = horaAR(ahora);
  if (!cuerpo.simular && (hora < 9 || hora >= 21)) return res.status(200).json({ ok: true, fuera_de_hora: true, enviados: 0, pendientes: 0, problemas: 0 });

  const [rc, re] = await Promise.all([
    sbJson(servicio, `contratos?select=id,nombre,email,token,estado,fecha_envio,vence_el,fecha_show,solo_documentos,convocatorias(nombre,area,fecha)&estado=in.(enviado,visto)&vence_el=gt.${encodeURIComponent(ahora.toISOString())}&fecha_envio=lt.${encodeURIComponent(inicio)}&order=fecha_envio.asc&limit=2000`),
    // También los que hoy quedaron en la fila para salir por Google (19-nov): ya tienen su mail del día.
    sbJson(servicio, `contrato_eventos?select=contrato_id&tipo=in.(enviado,reenviado,recordatorio,${TIPO_GOOGLE})&fecha=gte.${encodeURIComponent(inicio)}&limit=10000`)
  ]);
  if (!rc.ok || !re.ok) return res.status(500).json({ error: 'No se pudieron leer los contratos', detalle: (rc.data && rc.data.message) || (re.data && re.data.message) || '' });
  let toca = aQuienes(rc.data, (re.data || []).map(e => e.contrato_id), ahora);

  if (cuerpo.simular) {
    return res.status(200).json({ ok: true, saldrian: toca.length, lista: toca.slice(0, 300).map(c => { const { show, fecha } = showYFecha(c); return { nombre: c.nombre, show, fecha, estado: c.estado }; }) });
  }

  const cuenta = { enviados: 0, problemas: 0, porGoogle: 0 }, errores = [];
  // Hotmail, Outlook, Live (19-nov): a la fila, y el script los manda por Google (api/correo-google.js). No cuentan
  // para el tope de Resend.
  if (cuerpo.google === true) {
    const google = toca.filter(c => esMicrosoft(c.email));
    if (google.length) {
      const ri = await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: google.map(c => ({ contrato_id: c.id, tipo: TIPO_GOOGLE, meta: { motivo: 'recordatorio', origen: 'automatico' } })) });
      if (ri.ok) cuenta.porGoogle = google.length;
    }
    if (cuenta.porGoogle) toca = toca.filter(c => !esMicrosoft(c.email));
  }
  const tanda = toca.slice(0, MAX_ENVIOS);
  for (let i = 0; i < tanda.length; i++) {
    const c = tanda[i];
    if (i) await espera(550);
    const envio = await mandarMail(resend, String(c.email).trim(), armarRecordatorio(c));
    if (envio.ok) {
      await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: c.id, tipo: 'recordatorio', meta: { origen: 'automatico' } } });
      cuenta.enviados++;
    } else if (envio.tope) {
      break;   // Resend pidió esperar: lo que falta sale en la llamada siguiente
    } else {
      cuenta.problemas++; errores.push({ nombre: c.nombre, error: envio.error });
    }
  }
  const pendientes = Math.max(0, toca.length - cuenta.enviados - cuenta.problemas);
  return res.status(200).json({ ok: true, enviados: cuenta.enviados, pendientes, problemas: cuenta.problemas, porGoogle: cuenta.porGoogle, errores });
}
