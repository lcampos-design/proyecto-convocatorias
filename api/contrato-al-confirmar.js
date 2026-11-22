// Contrato al confirmar (Externos, 22-nov-2026).
//
// Pedido de RR. HH.: a los coordinadores de acreditación o de servicios, operadores y otros eventuales de varios
// días, el contrato les sale con el "sí" del mail. En el panel, el puesto se marca "Contrato al confirmar": al
// mandarles la confirmación, el panel deja el contrato armado (uno por todo el período, con la remuneración del
// puesto como total; origen 'al_confirmar', estado 'pendiente') sin mandarlo. Cuando la persona toca ✓ CONFIRMO,
// confirmar.html llama acá con { c: CUIL, v: convocatoria, r: 'si' } y el contrato sale al instante (a Hotmail y
// Outlook, por Google: queda en la fila del script, como los demás). Si después toca ✕ NO CONFIRMO, el que no firmó
// se anula; si vuelve a confirmar, se reactiva y sale de nuevo.
//
// No pide clave: sólo hace lo que la base ya registró. La respuesta la guarda registrar_confirmacion_firmada (con la
// firma del link) y acá se mira que la postulación diga eso mismo; si no, no hace nada.
//
// Variables de entorno en Vercel: SUPABASE_SERVICE_ROLE_KEY y RESEND_API_KEY (las de siempre).

import { TIPO_GOOGLE, esMicrosoft } from './_lib/correo-google.js';
import { armarMailPeriodo } from './presentes-planilla.js';

export const config = { maxDuration: 30 };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';
const CASILLA = { arena: 'convocatorias.arena@show-bs.com', externos: 'convocatorias.externos@show-bs.com' };
export const MOTIVO_NO = 'No confirmó la asistencia';
export const ORIGEN = 'al_confirmar';

function sbFetch(servicio, ruta, op = {}) {
  return fetch(`${SB_URL}/rest/v1/${ruta}`, {
    method: op.method || 'GET',
    headers: Object.assign({ 'apikey': servicio, 'Authorization': `Bearer ${servicio}`, 'Content-Type': 'application/json' }, op.headers || {}),
    body: op.body === undefined ? undefined : JSON.stringify(op.body)
  });
}
async function sbJson(servicio, ruta, op) { const r = await sbFetch(servicio, ruta, op); const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {} return { ok: r.ok, status: r.status, data: j }; }
async function mandarMail(resend, para, mail, de) {
  for (let intento = 0; ; intento++) {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST', headers: { 'Authorization': `Bearer ${resend}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: de, to: [para], subject: mail.subject, text: mail.text, html: mail.html })
    });
    if (r.ok) return { ok: true };
    const cuerpo = await r.json().catch(() => null), txt = JSON.stringify(cuerpo || {});
    if (intento === 0 && r.status === 429 && /rate_limit|too many/i.test(txt)) { await new Promise(x => setTimeout(x, 1500)); continue; }
    return { ok: false, error: (cuerpo && (cuerpo.message || cuerpo.error)) || ('Resend contestó ' + r.status) };
  }
}

// El DNI de adentro del CUIL, sin ceros adelante (como doc_nucleo en la base).
export function nucleo(v) {
  const d = String(v || '').replace(/\D/g, '');
  if (d.length === 11) return d.slice(2, 10).replace(/^0+/, '');
  if (d.length === 7 || d.length === 8) return d.replace(/^0+/, '');
  return d;
}
const areaDe = conv => String((conv && conv.area) || '').toLowerCase().startsWith('ext') ? 'externos' : 'arena';
export function fechasDe(conv) { return String((conv && conv.fecha) || '').split(',').map(x => x.trim()).filter(x => /^\d{4}-\d{2}-\d{2}$/.test(x)).sort(); }

// Qué hacer con los contratos de esa persona en esa convocatoria, según lo que respondió. Sin efectos: devuelve el plan.
//  'si': manda el pendiente (o reactiva el que se anuló porque había dicho que no); si ya salió, nada.
//  'no': anula los que no firmó.
export function planDe(respuesta, contratos) {
  const activos = contratos.filter(c => c.estado !== 'anulado');
  if (respuesta === 'no') return { anular: activos.filter(c => ['pendiente', 'enviado', 'visto'].includes(c.estado)) };
  if (activos.some(c => ['enviado', 'visto', 'firmado'].includes(c.estado))) return { ya: true };
  const pendientes = activos.filter(c => c.estado === 'pendiente');
  const mandar = pendientes[0] || contratos.find(c => c.estado === 'anulado' && c.anulado_motivo === MOTIVO_NO) || null;
  // Si por algún motivo quedaron dos armados (se mandó dos veces la confirmación), sale el más nuevo y el otro se anula.
  return { mandar, reactivar: !!mandar && mandar.estado === 'anulado', repetidos: pendientes.filter(c => c !== mandar) };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', resend = process.env.RESEND_API_KEY || '';
  if (!servicio || !resend) return res.status(500).json({ error: 'Falta configurar en Vercel la clave de Supabase o la de Resend' });
  let cuerpo;
  try { cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch (_) { return res.status(400).json({ error: 'El pedido no es JSON' }); }
  const doc = nucleo(cuerpo.c), conv = String(cuerpo.v || ''), resp = String(cuerpo.r || '').toLowerCase();
  if (!doc || doc.length < 6 || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(conv) || !['si', 'no'].includes(resp)) return res.status(400).json({ error: 'Datos inválidos' });

  // La postulación de esa persona en esa convocatoria tiene que decir lo mismo que respondió.
  // (La postulación puede no tener el CUIL: entonces, por la ficha de la nómina con ese documento.)
  const [rp, rpe] = await Promise.all([
    sbJson(servicio, `postulaciones?select=id,persona_id,cuit,confirmacion&conv_id=eq.${conv}&limit=5000`),
    sbJson(servicio, `personas?select=id,cuit&cuit=ilike.*${doc}*&limit=50`)
  ]);
  if (!rp.ok) return res.status(500).json({ error: 'No se pudo leer la convocatoria' });
  const fichas = new Set(((rpe.ok && rpe.data) || []).filter(p => nucleo(p.cuit) === doc).map(p => p.id));
  const suyas = (rp.data || []).filter(p => nucleo(p.cuit) === doc || (p.persona_id && fichas.has(p.persona_id)));
  if (!suyas.some(p => String(p.confirmacion || '').toLowerCase() === resp)) return res.status(200).json({ ok: true, nada: 'sin_confirmacion' });
  const personas = new Set(suyas.map(p => p.persona_id).filter(Boolean));

  // Sus contratos de "contrato al confirmar" en esa convocatoria (el más nuevo primero).
  const rc = await sbJson(servicio, `contratos?select=id,estado,token,email,nombre,puesto,cuil,doc_nucleo,persona_id,anulado_motivo,fecha_creacion,convocatorias(nombre,area,venue,fecha)&conv_id=eq.${conv}&origen=eq.${ORIGEN}&order=fecha_creacion.desc&limit=200`);
  if (!rc.ok) return res.status(500).json({ error: 'No se pudieron leer los contratos' });
  const suyos = (rc.data || []).filter(c => nucleo(c.doc_nucleo || c.cuil) === doc || (c.persona_id && personas.has(c.persona_id)));
  if (!suyos.length) return res.status(200).json({ ok: true, nada: 'sin_contrato' });

  const ahora = new Date().toISOString(), plan = planDe(resp, suyos);
  const evento = (id, tipo, meta) => sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: id, tipo, meta: Object.assign({ origen: ORIGEN }, meta || {}) } });

  if (resp === 'no') {
    for (const c of plan.anular) {
      const ra = await sbFetch(servicio, `contratos?id=eq.${c.id}&estado=neq.firmado`, { method: 'PATCH', body: { estado: 'anulado', vence_el: ahora, anulado_at: ahora, anulado_motivo: MOTIVO_NO } });
      if (ra.ok) await evento(c.id, 'anulado', { motivo: MOTIVO_NO });
    }
    return res.status(200).json({ ok: true, anulados: plan.anular.length });
  }
  if (plan.ya) return res.status(200).json({ ok: true, ya: true });
  if (!plan.mandar) return res.status(200).json({ ok: true, nada: 'sin_contrato' });
  for (const c of plan.repetidos) {
    await sbFetch(servicio, `contratos?id=eq.${c.id}&estado=eq.pendiente`, { method: 'PATCH', body: { estado: 'anulado', vence_el: ahora, anulado_at: ahora, anulado_motivo: 'Repetido (se mandó el más nuevo)' } });
    await evento(c.id, 'anulado', { motivo: 'Repetido' });
  }

  // El link vence a los días de siempre desde ahora (no desde que se armó el contrato).
  const c = plan.mandar;
  const rcfg = await sbJson(servicio, 'config?select=value&key=eq.contrato_link');
  const dias = Math.max(1, Number(rcfg.ok && rcfg.data && rcfg.data[0] && rcfg.data[0].value && rcfg.data[0].value.dias) || 7);
  const vence = new Date(Date.now() + dias * 864e5).toISOString();
  const ru = await sbFetch(servicio, `contratos?id=eq.${c.id}&estado=in.(pendiente,anulado)`, { method: 'PATCH', body: Object.assign({ vence_el: vence }, plan.reactivar ? { estado: 'pendiente', anulado_at: null, anulado_motivo: null } : {}) });
  if (!ru.ok) return res.status(500).json({ error: 'No se pudo preparar el contrato' });
  if (plan.reactivar) await evento(c.id, 'reactivado', { motivo: 'Volvió a confirmar' });

  const para = String(c.email || '').trim();
  if (!para.includes('@')) return res.status(200).json({ ok: false, error: 'sin_mail' });
  const cv = c.convocatorias || {}, area = areaDe(cv), fs = fechasDe(cv);
  const show = String(cv.nombre || '').split(' — ')[0].trim(), lugar = area === 'externos' ? String(cv.venue || '') : 'Movistar Arena';
  // Hotmail, Outlook, Live: Microsoft frena lo que llega por Resend. Va a la fila que manda el script por Google.
  if (esMicrosoft(para)) {
    await evento(c.id, TIPO_GOOGLE, { motivo: 'contrato', show, lugar });
    return res.status(200).json({ ok: true, porGoogle: true });
  }
  const mail = armarMailPeriodo({ nombre: c.nombre, desde: fs[0], hasta: fs[fs.length - 1], show, puesto: c.puesto, link: `${SITIO}/contrato.html?t=${c.token}`, lugar });
  const envio = await mandarMail(resend, para, mail, CASILLA[area]);
  if (!envio.ok) return res.status(200).json({ ok: false, error: envio.error });
  await sbFetch(servicio, `contratos?id=eq.${c.id}`, { method: 'PATCH', body: { estado: 'enviado', fecha_envio: new Date().toISOString() } });
  await evento(c.id, 'enviado');
  return res.status(200).json({ ok: true, enviado: true });
}
