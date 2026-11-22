// La fila de mails que salen por Google (19-nov-2026): ver api/_lib/correo-google.js.
//
// Lo llama el script de la planilla (apps-script/planilla-presentes.gs), en cada vuelta, con la misma clave que
// los presentes (PRESENTES_CLAVE):
//   { accion: 'pendientes' } → los mails por mandar: [{ pedido, para, responder, subject, text, html }]. Un pedido es
//       un evento "por_google" de los últimos 3 días que todavía no tiene su envío (otro evento con meta.pedido). Los
//       de contratos firmados o anulados no se mandan.
//   { accion: 'enviados', pedidos: [id] } → los que salieron: queda el evento (enviado, reenviado o recordatorio, con
//       meta.via 'google'); si era el primer envío del contrato, pasa a "enviado" (y la fila de la planilla también).
//   { accion: 'demorados' } → una sola vez: pone en la fila (como reenvío) los contratos enviados a Microsoft en los
//       últimos 4 días que nadie abrió (los que Resend dejó "Delivery Delayed").

import crypto from 'crypto';
import { TIPO_GOOGLE, esMicrosoft } from './_lib/correo-google.js';
import { armarMail, armarMailPeriodo } from './presentes-planilla.js';
import { armarRecordatorio } from './recordatorios.js';

export const config = { maxDuration: 60 };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';
const CASILLA = { arena: 'convocatorias.arena@show-bs.com', externos: 'convocatorias.externos@show-bs.com' };
const POR_VEZ = 40;
const TIPO_HECHO = { contrato: 'enviado', reenvio: 'reenviado', recordatorio: 'recordatorio' };

function sbFetch(servicio, ruta, op = {}) {
  return fetch(`${SB_URL}/rest/v1/${ruta}`, {
    method: op.method || 'GET',
    headers: Object.assign({ 'apikey': servicio, 'Authorization': `Bearer ${servicio}`, 'Content-Type': 'application/json' }, op.headers || {}),
    body: op.body === undefined ? undefined : JSON.stringify(op.body)
  });
}
async function sbJson(servicio, ruta, op) { const r = await sbFetch(servicio, ruta, op); const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {} return { ok: r.ok, status: r.status, data: j }; }
function claveOk(dada, esperada) {
  const a = Buffer.from(String(dada || '')), b = Buffer.from(String(esperada || ''));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}
const areaDe = c => String((c.convocatorias && c.convocatorias.area) || '').toLowerCase() === 'externos' ? 'externos' : 'arena';
const nombreShow = c => String((c.convocatorias && c.convocatorias.nombre) || '').split(' — ')[0].trim();
function fechaDe(c) {
  if (/^\d{4}-\d{2}-\d{2}/.test(String(c.fecha_show || ''))) return String(c.fecha_show).slice(0, 10);
  const fs = String((c.convocatorias && c.convocatorias.fecha) || '').split(',').map(x => x.trim()).filter(x => /^\d{4}-\d{2}-\d{2}$/.test(x));
  return fs.length === 1 ? fs[0] : '';
}

// El mail de cada pedido: el mismo que hubiera salido por Resend.
export function mailDelPedido(motivo, meta, c) {
  const area = areaDe(c), link = `${SITIO}/contrato.html?t=${c.token}`, fecha = fechaDe(c);
  const show = String((meta && meta.show) || nombreShow(c) || '').trim();
  const lugar = area === 'externos' ? String((meta && meta.lugar) || (c.convocatorias && c.convocatorias.venue) || '') : undefined;
  if (motivo === 'recordatorio') { const m = armarRecordatorio(c); return { subject: m.subject, text: m.text, html: m.html, responder: m.from || CASILLA[area] }; }
  // Contrato al confirmar (Externos, 22-nov): uno por todo el período, del primero al último día.
  if (c.origen === 'al_confirmar') {
    const fs = String((c.convocatorias && c.convocatorias.fecha) || '').split(',').map(x => x.trim()).filter(x => /^\d{4}-\d{2}-\d{2}$/.test(x)).sort();
    const m = armarMailPeriodo({ nombre: c.nombre, desde: fs[0], hasta: fs[fs.length - 1], show, puesto: c.puesto, link, lugar: area === 'externos' ? lugar : 'Movistar Arena' });
    return { subject: (motivo === 'reenvio' ? 'Reenvío — ' : '') + m.subject, text: m.text, html: m.html, responder: CASILLA[area] };
  }
  if (fecha) {
    const m = armarMail({ nombre: c.nombre, fecha, show, link, lugar });
    return { subject: (motivo === 'reenvio' ? 'Reenvío — ' : '') + m.subject, text: m.text, html: m.html, responder: CASILLA[area] };
  }
  // Sin fecha (un contrato del panel que no es por presente): sólo el link para firmar.
  const pila = String(c.nombre || '').trim().split(/\s+/)[0] || '', hola = pila ? 'Hola, ' + pila.charAt(0).toUpperCase() + pila.slice(1).toLowerCase() : 'Hola';
  const text = `${hola}:\n\nTe reenviamos tu contrato de trabajo${show ? ' (' + show + ')' : ''}. Para firmarlo, entrá a este link:\n${link}\n\nCualquier duda, respondé este mail.\n\nSaludos,\nShow Business Solutions`;
  const m = armarMail({ nombre: c.nombre, fecha: '2026-01-01', show, link, lugar: '' });
  const html = m.html.replace(/<p style="[^"]*">Gracias por trabajar con nosotros[^<]*<\/p>/, `<p style="margin:0 0 16px;font-size:15px;line-height:1.65;color:#374151">Te reenviamos tu contrato de trabajo${show ? ' (' + show.replace(/[&<>"]/g, '') + ')' : ''}.</p>`)
    .replace('Para firmar tu contrato de esa fecha', 'Para firmarlo');
  return { subject: 'Reenvío — Contrato de trabajo' + (show ? ' · ' + show : ''), text, html, responder: CASILLA[area] };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', clave = process.env.PRESENTES_CLAVE || '';
  if (!clave) return res.status(500).json({ error: 'Falta configurar PRESENTES_CLAVE en Vercel' });
  if (!claveOk(req.headers['x-clave'], clave)) return res.status(401).json({ error: 'Clave incorrecta' });
  if (!servicio) return res.status(500).json({ error: 'Falta configurar en Vercel la clave de Supabase' });
  let cuerpo;
  try { cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch (_) { return res.status(400).json({ error: 'El pedido no es JSON' }); }
  const hace = dias => encodeURIComponent(new Date(Date.now() - dias * 864e5).toISOString());
  const colsC = 'id,nombre,email,token,estado,fecha_show,fecha_envio,vence_el,solo_documentos,origen,puesto,convocatorias(nombre,area,fecha,venue)';

  if (cuerpo.accion === 'demorados') {
    const or = 'or=(' + ['hotmail', 'outlook', 'live', 'msn'].map(d => `email.ilike.*@${d}.*`).join(',') + ')';
    const [rc, rp] = await Promise.all([
      sbJson(servicio, `contratos?select=id,email&estado=eq.enviado&fecha_envio=gte.${hace(4)}&vence_el=gt.${encodeURIComponent(new Date().toISOString())}&${or}&limit=2000`),
      sbJson(servicio, `contrato_eventos?select=contrato_id&tipo=eq.${TIPO_GOOGLE}&fecha=gte.${hace(5)}&limit=5000`)
    ]);
    if (!rc.ok || !rp.ok) return res.status(500).json({ error: 'No se pudieron leer los contratos', detalle: (rc.data && rc.data.message) || (rp.data && rp.data.message) || '' });
    const ya = new Set((rp.data || []).map(e => e.contrato_id));
    const nuevos = (rc.data || []).filter(c => esMicrosoft(c.email) && !ya.has(c.id)).map(c => ({ contrato_id: c.id, tipo: TIPO_GOOGLE, meta: { motivo: 'reenvio', origen: 'demorados' } }));
    if (nuevos.length) { const ri = await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: nuevos }); if (!ri.ok) return res.status(500).json({ error: 'No se pudieron poner en la fila' }); }
    return res.status(200).json({ ok: true, encolados: nuevos.length });
  }

  if (cuerpo.accion === 'pendientes') {
    const [rp, rh] = await Promise.all([
      sbJson(servicio, `contrato_eventos?select=id,contrato_id,fecha,meta&tipo=eq.${TIPO_GOOGLE}&fecha=gte.${hace(3)}&order=fecha.asc&limit=2000`),
      sbJson(servicio, `contrato_eventos?select=meta&tipo=in.(enviado,reenviado,recordatorio,google_omitido)&fecha=gte.${hace(3)}&meta->>via=eq.google&limit=5000`)
    ]);
    if (!rp.ok || !rh.ok) return res.status(500).json({ error: 'No se pudo leer la fila', detalle: (rp.data && rp.data.message) || (rh.data && rh.data.message) || '' });
    const hechos = new Set((rh.data || []).map(e => String((e.meta || {}).pedido || '')));
    const pend = (rp.data || []).filter(p => !hechos.has(String(p.id)));
    const ids = [...new Set(pend.map(p => p.contrato_id))];
    const rc = ids.length ? await sbJson(servicio, `contratos?select=${colsC}&id=in.(${ids.join(',')})`) : { ok: true, data: [] };
    if (!rc.ok) return res.status(500).json({ error: 'No se pudieron leer los contratos', detalle: (rc.data && rc.data.message) || '' });
    const porId = new Map((rc.data || []).map(c => [c.id, c]));
    // Uno por contrato y motivo (si se pidió dos veces el mismo, va uno); sin los firmados, anulados o sin mail.
    const vistos = new Set(), items = [], sobran = [];
    for (const p of pend) {
      const c = porId.get(p.contrato_id), motivo = (p.meta && p.meta.motivo) || 'contrato', k = p.contrato_id + '|' + motivo;
      if (!c || c.estado === 'firmado' || c.estado === 'anulado' || !String(c.email || '').includes('@') || !c.token || vistos.has(k)) { sobran.push(p.id); continue; }
      vistos.add(k);
      if (items.length < POR_VEZ) { const m = mailDelPedido(motivo, p.meta, c); items.push(Object.assign({ pedido: p.id, para: String(c.email).trim() }, m)); }
    }
    // Los que no van (firmó, se anuló, repetido): se dan por hechos para que no vuelvan a aparecer.
    if (sobran.length) await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: pend.filter(p => sobran.includes(p.id)).map(p => ({ contrato_id: p.contrato_id, tipo: 'google_omitido', meta: { via: 'google', pedido: p.id } })) });
    return res.status(200).json({ ok: true, items, mas: vistos.size > items.length });
  }

  if (cuerpo.accion === 'enviados') {
    const pedidos = (Array.isArray(cuerpo.pedidos) ? cuerpo.pedidos : []).map(x => Number(x)).filter(x => Number.isInteger(x) && x > 0).slice(0, 200);
    if (!pedidos.length) return res.status(200).json({ ok: true, marcados: 0 });
    const rp = await sbJson(servicio, `contrato_eventos?select=id,contrato_id,meta&tipo=eq.${TIPO_GOOGLE}&id=in.(${pedidos.join(',')})`);
    if (!rp.ok) return res.status(500).json({ error: 'No se pudo leer la fila', detalle: (rp.data && rp.data.message) || '' });
    const ahora = new Date().toISOString(), eventos = [], primeros = [];
    (rp.data || []).forEach(p => {
      const motivo = (p.meta && p.meta.motivo) || 'contrato';
      eventos.push({ contrato_id: p.contrato_id, tipo: TIPO_HECHO[motivo] || 'reenviado', meta: { via: 'google', pedido: p.id, origen: (p.meta && p.meta.origen) || null } });
      if (motivo === 'contrato') primeros.push(p.contrato_id);
    });
    if (eventos.length) { const ri = await sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: eventos }); if (!ri.ok) return res.status(500).json({ error: 'No se pudo anotar el envío' }); }
    for (const id of primeros) {
      await sbFetch(servicio, `contratos?id=eq.${id}&estado=eq.pendiente`, { method: 'PATCH', body: { estado: 'enviado', fecha_envio: ahora } });
      await sbFetch(servicio, `planilla_presentes?contrato_id=eq.${id}&resultado=eq.por_google`, { method: 'PATCH', body: { resultado: 'enviado', detalle: 'Salió por Google', actualizado: ahora } });
    }
    return res.status(200).json({ ok: true, marcados: eventos.length });
  }

  return res.status(400).json({ error: 'Falta la acción (pendientes, enviados o demorados)' });
}
