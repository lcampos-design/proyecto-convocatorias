// Los eventos de los Google Calendar del Movistar Arena y de Externos, para el
// panel ("Disponibilidad del mes"): los del mes que todavía no son una
// convocatoria se crean desde ahí, con nombre, fechas, lugar y horario.
//
// No hace falta conectar la cuenta de Google: cada calendario tiene una
// "dirección secreta en formato iCal" (Configuración del calendario →
// Integrar el calendario). Esa dirección da acceso de lectura a todo el
// calendario, así que va como variable de entorno en Vercel, nunca en el
// código: GCAL_ICS_ARENA y GCAL_ICS_EXTERNOS. Sólo la usa el servidor, y
// sólo le contesta a un admin logueado.

import crypto from 'crypto';
import { FICHAS_URL, planFichas } from './_lib/fichas.js';

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SB_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5rbW1pZnl6bGlpaW1tdGx6ZXFvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjM0MTAsImV4cCI6MjA5NjY5OTQxMH0.QU5JBRH_rbTzUu12oeWmCDmJv6B3UUVKPA5HyeuuzSg';
const ROLES_ADMIN = ['admin', 'admin_movistar', 'admin_externos'];
const CALENDARIOS = [['movistar_arena', 'GCAL_ICS_ARENA'], ['externos', 'GCAL_ICS_EXTERNOS']];

async function verificarAdmin(req) {
  const token = String(req.headers['authorization'] || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return { ok: false, status: 401, error: 'Falta sesión de admin' };
  try {
    const userRes = await fetch(`${SB_URL}/auth/v1/user`, { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } });
    if (!userRes.ok) return { ok: false, status: 401, error: 'Sesión inválida o vencida' };
    const user = await userRes.json();
    const perfilRes = await fetch(`${SB_URL}/rest/v1/user_profiles?id=eq.${encodeURIComponent(user.id)}&select=rol`,
      { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } });
    if (!perfilRes.ok) return { ok: false, status: 403, error: 'No se pudo verificar el permiso' };
    const perfil = await perfilRes.json();
    const rol = Array.isArray(perfil) && perfil[0] ? perfil[0].rol : null;
    if (!ROLES_ADMIN.includes(rol)) return { ok: false, status: 403, error: 'Tu usuario no tiene permiso para ver los calendarios' };
    return { ok: true };
  } catch (_) {
    return { ok: false, status: 401, error: 'No se pudo validar la sesión' };
  }
}

// ── El formato iCal (RFC 5545), lo justo para los eventos de Google ──
const desescapar = s => String(s || '').replace(/\\n/gi, '\n').replace(/\\([,;\\])/g, '$1').trim();
const dosDig = n => String(n).padStart(2, '0');
// Argentina está en UTC-3 todo el año (sin horario de verano).
const AR = -3;
// "20261115" / "20261115T230000Z" / "20261115T200000" → { fecha: 'aaaa-mm-dd', hora: 'hh:mm' | '' } en hora de Argentina.
function leerFecha(valor, params) {
  const m = String(valor || '').match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$/);
  if (!m) return null;
  const [, y, mo, d, h, mi, , z] = m;
  if (h === undefined || /VALUE=DATE(?!-)/.test(params || '')) return { fecha: `${y}-${mo}-${d}`, hora: '', diaEntero: h === undefined };
  if (z) {
    const t = new Date(Date.UTC(+y, +mo - 1, +d, +h + AR, +mi));
    return { fecha: `${t.getUTCFullYear()}-${dosDig(t.getUTCMonth() + 1)}-${dosDig(t.getUTCDate())}`, hora: `${dosDig(t.getUTCHours())}:${dosDig(t.getUTCMinutes())}` };
  }
  return { fecha: `${y}-${mo}-${d}`, hora: `${h}:${mi}` };   // con TZID: la hora local de ese calendario
}
const sumarDia = (f, n) => { const t = new Date(f + 'T12:00:00Z'); t.setUTCDate(t.getUTCDate() + n); return t.toISOString().slice(0, 10); };

export function leerIcs(texto) {
  // Las líneas largas vienen partidas: la que sigue empieza con un espacio.
  const lineas = String(texto || '').replace(/\r\n/g, '\n').replace(/\n[ \t]/g, '').split('\n');
  const eventos = [];
  let ev = null;
  for (const linea of lineas) {
    if (linea === 'BEGIN:VEVENT') { ev = {}; continue; }
    if (linea === 'END:VEVENT') { if (ev) eventos.push(ev); ev = null; continue; }
    if (!ev) continue;
    const dos = linea.indexOf(':'); if (dos < 0) continue;
    const izq = linea.slice(0, dos), valor = linea.slice(dos + 1);
    const [nombre, ...params] = izq.split(';');
    ev[nombre.toUpperCase()] = { valor, params: params.join(';') };
  }
  return eventos.map(e => {
    const ini = e.DTSTART && leerFecha(e.DTSTART.valor, e.DTSTART.params);
    if (!ini) return null;
    const fin = e.DTEND && leerFecha(e.DTEND.valor, e.DTEND.params);
    // Los días que ocupa: los de día entero terminan el día antes de DTEND; uno con hora, el día que empieza.
    const fechas = [ini.fecha];
    if (ini.diaEntero && fin && fin.fecha > ini.fecha) { for (let f = sumarDia(ini.fecha, 1); f < fin.fecha && fechas.length < 31; f = sumarDia(f, 1)) fechas.push(f); }
    return {
      uid: e.UID ? e.UID.valor : '',
      titulo: desescapar(e.SUMMARY && e.SUMMARY.valor) || '(sin título)',
      lugar: desescapar(e.LOCATION && e.LOCATION.valor),
      detalle: desescapar(e.DESCRIPTION && e.DESCRIPTION.valor).slice(0, 500),
      fechas,
      horario: ini.hora ? ini.hora + (fin && fin.hora ? ' a ' + fin.hora : '') : '',
      cancelado: /CANCELLED/i.test(e.STATUS ? e.STATUS.valor : ''),
      repite: !!e.RRULE,
    };
  }).filter(Boolean);
}

// Los del mes (los que tienen algún día en él), sin cancelados, de los dos calendarios.
export function delMes(eventos, mes) {
  return eventos.filter(e => !e.cancelado && e.fechas.some(f => f.startsWith(mes)))
    .sort((a, b) => a.fechas[0].localeCompare(b.fechas[0]) || a.titulo.localeCompare(b.titulo));
}

// ── Las fichas técnicas del Arena (24-nov): ?fichas=1 pone al día los shows del Arena con sus fichas (ver
// api/_lib/fichas.js). La llama el cron de Vercel una vez por día y el panel al abrirse; como mucho una vez cada 10
// minutos (con &forzar=1, un admin la corre igual).
const ESPERA_FICHAS_MIN = 10;
async function sbJson(servicio, ruta, op = {}) {
  const r = await fetch(`${SB_URL}/rest/v1/${ruta}`, { method: op.method || 'GET', headers: Object.assign({ 'apikey': servicio, 'Authorization': `Bearer ${servicio}`, 'Content-Type': 'application/json' }, op.headers || {}), body: op.body === undefined ? undefined : JSON.stringify(op.body) });
  const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {}
  return { ok: r.ok, status: r.status, data: j };
}
const esCron = req => {
  const secreto = process.env.CRON_SECRET || '';
  if (secreto) return String(req.headers['authorization'] || '') === 'Bearer ' + secreto;
  return /^vercel-cron/i.test(String(req.headers['user-agent'] || ''));
};
async function fichasDelArena(req, res) {
  const cron = esCron(req);
  if (!cron) { const auth = await verificarAdmin(req); if (!auth.ok) return res.status(auth.status).json({ error: auth.error }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  if (!servicio) return res.status(500).json({ error: 'Falta configurar en Vercel la clave de Supabase' });
  // Hace poco que se corrió: lo de esa vez (salvo que un admin la fuerce).
  const rcfg = await sbJson(servicio, 'config?select=value&key=eq.fichas_sync');
  const ultima = rcfg.ok && rcfg.data && rcfg.data[0] ? rcfg.data[0].value || {} : {};
  const forzar = !cron && String((req.query && req.query.forzar) || '') === '1';
  if (!forzar && ultima.at && Date.now() - new Date(ultima.at).getTime() < ESPERA_FICHAS_MIN * 60000) return res.status(200).json(Object.assign({ ok: true, reciente: true }, ultima));
  let fichas;
  try { const r = await fetch(FICHAS_URL); if (!r.ok) throw new Error('la app de fichas contestó ' + r.status); fichas = await r.json(); if (!Array.isArray(fichas)) throw new Error('respuesta inesperada'); }
  catch (err) { return res.status(502).json({ error: 'No se pudieron leer las fichas del Arena: ' + err.message }); }
  const rc = await sbJson(servicio, 'convocatorias?select=id,nombre,fecha,turnos,horario,armado_campo,centro_control,ficha&area=eq.movistar_arena&limit=3000');
  if (!rc.ok) return res.status(500).json({ error: /ficha/.test(JSON.stringify(rc.data || '')) ? 'Falta correr fichas-arena.sql en Supabase' : 'No se pudieron leer los shows', detalle: (rc.data && rc.data.message) || '' });
  const hoy = new Date(Date.now() + AR * 3600000).toISOString().slice(0, 10);
  const plan = planFichas(fichas, rc.data || [], hoy), hechos = [], creados = [], errores = [];
  for (const x of plan.cambios) {
    const r = await sbJson(servicio, `convocatorias?id=eq.${x.id}`, { method: 'PATCH', body: x.cambios });
    if (r.ok) hechos.push({ id: x.id, motivo: x.motivo }); else errores.push(x.id);
  }
  for (const nuevo of plan.crear) {
    const fila = Object.assign({}, nuevo, { id: crypto.randomUUID(), turnos: nuevo.turnos.map(t => Object.assign({ id: crypto.randomUUID() }, t)) });
    const r = await sbJson(servicio, 'convocatorias', { method: 'POST', body: fila });
    if (r.ok) creados.push({ id: fila.id, nombre: fila.nombre, fecha: fila.fecha }); else errores.push(fila.nombre);
  }
  const salida = { at: new Date().toISOString(), por: cron ? 'cron' : 'panel', resumen: plan.resumen, cambiados: hechos, creados, errores };
  await sbJson(servicio, 'config?on_conflict=key', { method: 'POST', headers: { 'Prefer': 'resolution=merge-duplicates' }, body: { key: 'fichas_sync', value: salida, updated_at: salida.at } });
  return res.status(200).json(Object.assign({ ok: true }, salida));
}

export default async function handler(req, res) {
  if (req.method !== 'GET') { res.setHeader('Allow', 'GET'); return res.status(405).json({ error: 'Método no permitido' }); }
  if (String((req.query && req.query.fichas) || '') === '1' || esCron(req)) return fichasDelArena(req, res);
  const auth = await verificarAdmin(req);
  if (!auth.ok) return res.status(auth.status).json({ error: auth.error });
  const mes = String((req.query && req.query.mes) || '');
  if (!/^\d{4}-\d{2}$/.test(mes)) return res.status(400).json({ error: 'Falta el mes (aaaa-mm)' });
  const configurados = CALENDARIOS.filter(([, v]) => process.env[v]);
  if (!configurados.length) return res.status(200).json({ configurado: false, faltan: CALENDARIOS.map(([, v]) => v), eventos: [] });
  const eventos = [], errores = [];
  for (const [area, variable] of configurados) {
    try {
      const r = await fetch(process.env[variable]);
      if (!r.ok) { errores.push(area); continue; }
      delMes(leerIcs(await r.text()), mes).forEach(e => eventos.push(Object.assign({ area }, e)));
    } catch (_) { errores.push(area); }
  }
  eventos.sort((a, b) => a.fechas[0].localeCompare(b.fechas[0]));
  return res.status(200).json({ configurado: true, faltan: CALENDARIOS.filter(([, v]) => !process.env[v]).map(([, v]) => v), errores, eventos });
}
