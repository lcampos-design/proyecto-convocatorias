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

//
// Turnos de acreditaciones (24-nov): la grilla de turnos del panel llama acá con { accion: 'turno', post, turno } y la
// sesión de admin. Si la persona tiene la P en ese turno, sale el contrato de esa jornada (origen 'turno', uno por
// persona y turno, con el monto del turno y el puesto de la fila); si no la tiene (A, o le sacaron la P, o la sacaron
// del turno), el que no firmó se anula. Ver turnos-acreditaciones.sql.

import { TIPO_GOOGLE, esMicrosoft } from './_lib/correo-google.js';
import { armarMailPeriodo, armarMail, armarTexto, numeroALetras, montoFormateado, montoANumero, fechaLarga } from './presentes-planilla.js';

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

// ── Turnos de acreditaciones ──
export const ORIGEN_TURNO = 'turno';
const SB_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5rbW1pZnl6bGlpaW1tdGx6ZXFvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjM0MTAsImV4cCI6MjA5NjY5OTQxMH0.QU5JBRH_rbTzUu12oeWmCDmJv6B3UUVKPA5HyeuuzSg';
const ROLES_PANEL = ['admin', 'admin_movistar', 'admin_externos'];
// Quien llama tiene que estar logueado y tener ficha de admin (como en send-email).
async function verificarAdmin(req) {
  const token = String(req.headers['authorization'] || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return false;
  try {
    const ru = await fetch(`${SB_URL}/auth/v1/user`, { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } });
    if (!ru.ok) return false;
    const user = await ru.json();
    const rp = await fetch(`${SB_URL}/rest/v1/user_profiles?id=eq.${encodeURIComponent(user.id)}&select=rol`, { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } });
    const perfil = rp.ok ? await rp.json() : [];
    return ROLES_PANEL.includes(Array.isArray(perfil) && perfil[0] ? perfil[0].rol : null);
  } catch (_) { return false; }
}
// Qué hacer con el contrato de un turno. Sin efectos: devuelve el plan.
//  con la P: si ya salió (o lo firmó), nada; si está armado sin salir, se manda; si no hay, se arma y se manda.
//  sin la P: se anulan los que no firmó (el firmado queda, y se avisa).
export function planTurno(presente, contratos) {
  const activos = (contratos || []).filter(c => c.estado !== 'anulado');
  if (!presente) return { anular: activos.filter(c => c.estado !== 'firmado'), firmado: activos.some(c => c.estado === 'firmado') };
  if (activos.some(c => ['enviado', 'visto', 'firmado'].includes(c.estado))) return { ya: true };
  const pendiente = activos.find(c => c.estado === 'pendiente');
  return pendiente ? { mandar: pendiente } : { crear: true };
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hoyLarga = () => new Date().toLocaleDateString('es-AR', { day: 'numeric', month: 'long', timeZone: 'America/Argentina/Buenos_Aires' }).toUpperCase();

async function contratoTurno(req, res, cuerpo, servicio, resend) {
  if (!(await verificarAdmin(req))) return res.status(401).json({ error: 'Hace falta la sesión del panel' });
  const postId = String(cuerpo.post || ''), turnoId = String(cuerpo.turno || '').slice(0, 80);
  if (!UUID.test(postId) || !turnoId) return res.status(400).json({ error: 'Datos inválidos' });
  const rp = await sbJson(servicio, `postulaciones?select=id,conv_id,persona_id,puesto_id,nombre,cuit,presentes,asignaciones&id=eq.${postId}`);
  const post = rp.ok && Array.isArray(rp.data) ? rp.data[0] : null;
  if (!post) return res.status(404).json({ error: 'No está esa postulación' });
  // Lo que manda es lo que dice la base (el panel la guarda antes de llamar): presente y asignada a ese turno.
  const presente = ((post.presentes || {})[turnoId] === 'presente') && Object.prototype.hasOwnProperty.call(post.asignaciones || {}, turnoId);
  const [rconv, rc] = await Promise.all([
    sbJson(servicio, `convocatorias?select=id,nombre,area,venue,turnos&id=eq.${post.conv_id}`),
    sbJson(servicio, `contratos?select=id,estado,token,email,nombre&postulacion_id=eq.${postId}&turno_id=eq.${encodeURIComponent(turnoId)}&origen=eq.${ORIGEN_TURNO}&estado=neq.anulado`)
  ]);
  if (!rc.ok) return res.status(500).json({ error: 'Falta correr turnos-acreditaciones.sql en Supabase', detalle: (rc.data && rc.data.message) || '' });
  const conv = rconv.ok && Array.isArray(rconv.data) ? rconv.data[0] : null;
  const turno = conv && (Array.isArray(conv.turnos) ? conv.turnos : []).find(t => t && String(t.id) === turnoId);
  if (!turno) return res.status(200).json({ ok: false, error: 'sin_turno' });
  const plan = planTurno(presente, rc.data || []), ahora = new Date().toISOString();
  const evento = (id, tipo, meta) => sbFetch(servicio, 'contrato_eventos', { method: 'POST', body: { contrato_id: id, tipo, meta: Object.assign({ origen: ORIGEN_TURNO, turno: turno.nombre || null }, meta || {}) } });

  if (!presente) {
    const motivo = (post.presentes || {})[turnoId] === 'ausente' ? 'Ausente en el turno' : 'Le sacaron el presente del turno';
    for (const c of plan.anular) {
      const ra = await sbFetch(servicio, `contratos?id=eq.${c.id}&estado=neq.firmado`, { method: 'PATCH', body: { estado: 'anulado', vence_el: ahora, anulado_at: ahora, anulado_motivo: motivo } });
      if (ra.ok) await evento(c.id, 'anulado', { motivo });
    }
    return res.status(200).json({ ok: true, anulados: plan.anular.length, firmado: plan.firmado });
  }
  if (plan.ya) return res.status(200).json({ ok: true, ya: true });

  // Si tiene el contrato de todo el período (puesto "contrato al confirmar"), no lleva uno por jornada.
  if (post.persona_id) {
    const rpe = await sbJson(servicio, `contratos?select=id&conv_id=eq.${post.conv_id}&persona_id=eq.${post.persona_id}&origen=eq.${ORIGEN}&estado=neq.anulado&limit=1`);
    if (rpe.ok && Array.isArray(rpe.data) && rpe.data.length) return res.status(200).json({ ok: true, ya: 'periodo' });
  }

  let c = plan.mandar || null;
  const area = areaDe(conv), show = String(conv.nombre || '').split(' — ')[0].trim(), lugar = area === 'externos' ? String(conv.venue || '') : 'Movistar Arena';
  if (!c) {
    const monto = montoANumero(turno.monto);
    if (!(monto > 0)) return res.status(200).json({ ok: false, error: 'sin_monto' });
    const [rper, rpu, rcfg] = await Promise.all([
      post.persona_id ? sbJson(servicio, `personas?select=id,nombre,cuit,email&id=eq.${post.persona_id}`) : Promise.resolve({ ok: true, data: [] }),
      sbJson(servicio, `puestos?select=nombre&id=eq.${UUID.test(String(turno.puestoId || '')) ? turno.puestoId : post.puesto_id}`),
      sbJson(servicio, 'config?select=value&key=eq.contrato_plantilla')
    ]);
    const persona = (rper.ok && Array.isArray(rper.data) && rper.data[0]) || {};
    const plantilla = String(((rcfg.ok && rcfg.data && rcfg.data[0] && rcfg.data[0].value) || {}).ar || '').trim();
    if (!plantilla) return res.status(200).json({ ok: false, error: 'sin_plantilla' });
    const email = String(persona.email || '').trim();
    if (!email.includes('@')) return res.status(200).json({ ok: false, error: 'sin_mail' });
    const cuil = String(persona.cuit || post.cuit || '').replace(/\D/g, ''), dia = fechaLarga(turno.fecha);
    const puesto = String((rpu.ok && Array.isArray(rpu.data) && rpu.data[0] && rpu.data[0].nombre) || turno.nombre || '').trim();
    const datos = {
      nombre: String(persona.nombre || post.nombre || '').trim(), cuil, puesto, venue: lugar,
      fecha_inicio: dia, fecha_fin: dia, anio: String(turno.fecha).slice(0, 4),
      monto_letras: numeroALetras(monto), monto_numero: montoFormateado(monto), fecha_firma_doc: hoyLarga()
    };
    const ri = await sbJson(servicio, 'contratos', {
      method: 'POST', headers: { 'Prefer': 'return=representation' },
      body: Object.assign({}, datos, { conv_id: conv.id, persona_id: post.persona_id || null, postulacion_id: post.id, puesto_id: UUID.test(String(turno.puestoId || '')) ? turno.puestoId : (post.puesto_id || null),
        doc_nucleo: nucleo(cuil) || null, email, texto_contrato: armarTexto(plantilla, datos), estado: 'pendiente', firma_empleador_img: 'firmas/firma-richard.png',
        fecha_show: turno.fecha, origen: ORIGEN_TURNO, turno_id: turnoId })
    });
    if (!ri.ok || !Array.isArray(ri.data) || !ri.data[0]) {
      // Otro pedido lo armó al mismo tiempo (uno por persona y turno).
      if (ri.status === 409) return res.status(200).json({ ok: true, ya: true });
      return res.status(500).json({ error: 'No se pudo crear el contrato', detalle: (ri.data && ri.data.message) || ri.status });
    }
    c = ri.data[0];
    await evento(c.id, 'creado');
  }
  const para = String(c.email || '').trim();
  if (!para.includes('@')) return res.status(200).json({ ok: false, error: 'sin_mail', contrato: c.id });
  // Hotmail, Outlook, Live: por Google (la fila del script), como los demás contratos.
  if (esMicrosoft(para)) {
    const ya = await sbJson(servicio, `contrato_eventos?select=id&contrato_id=eq.${c.id}&tipo=eq.${TIPO_GOOGLE}&limit=1`);
    if (!(ya.ok && Array.isArray(ya.data) && ya.data.length)) await evento(c.id, TIPO_GOOGLE, { motivo: 'contrato', show, lugar });
    return res.status(200).json({ ok: true, porGoogle: true, contrato: c.id });
  }
  const mail = armarMail({ nombre: c.nombre, fecha: turno.fecha, show, link: `${SITIO}/contrato.html?t=${c.token}`, lugar: area === 'externos' ? lugar : undefined });
  const envio = await mandarMail(resend, para, mail, CASILLA[area]);
  if (!envio.ok) return res.status(200).json({ ok: false, error: envio.error, contrato: c.id });
  await sbFetch(servicio, `contratos?id=eq.${c.id}`, { method: 'PATCH', body: { estado: 'enviado', fecha_envio: new Date().toISOString() } });
  await evento(c.id, 'enviado');
  return res.status(200).json({ ok: true, enviado: true, contrato: c.id });
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', resend = process.env.RESEND_API_KEY || '';
  if (!servicio || !resend) return res.status(500).json({ error: 'Falta configurar en Vercel la clave de Supabase o la de Resend' });
  let cuerpo;
  try { cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch (_) { return res.status(400).json({ error: 'El pedido no es JSON' }); }
  if (cuerpo.accion === 'turno') return contratoTurno(req, res, cuerpo, servicio, resend);
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
