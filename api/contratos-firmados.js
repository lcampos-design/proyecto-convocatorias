// Los contratos firmados, para guardarlos en el Drive compartido de RR. HH. (18-nov-2026).
//
// Pedido de Mercedes: "contratos: armar una carpeta de descarga y guardado automático cuando estén todos
// firmados, o a la 1:30, en el Drive de las compartidas, tanto del Arena como de Externos". Thomas: dentro de
// la carpeta compartida de Mercedes (las carpetas "CONTRATOS DIGITALES" que armó para el Arena y Externos).
//
// Lo llama el script de la planilla (apps-script/planilla-presentes.gs) con la clave de los presentes
// (PRESENTES_CLAVE). Devuelve los firmados después de "desde" (la hora de la firma), en orden y de a pocos,
// con el PDF; el script los guarda en <carpeta del área>/<show y fecha>/ y sigue desde el último.
// Sólo lee: no cambia nada en la base. Uno firmado hace menos de 10 minutos espera a la vuelta siguiente
// (el PDF se guarda unos segundos después de la firma).
//
// { area: 'arena' | 'externos' | 'espana', desde: ISO } → { ok, contratos: [{ id, carpeta_mes, carpeta_show,
//   archivo, firmado_at, pdf }], cursor, mas } (cursor: hasta dónde miró; el script sigue desde ahí)
// { area, desde, contar: true } → { ok, pendientes, carpetas: { "mes/show": n } } (sin los PDF).
// Arena son los de los shows del Arena y de "ambas áreas" (como el mail del contrato); Externos y España, los suyos.

import crypto from 'crypto';

export const config = { maxDuration: 60 };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const TZ = 'America/Argentina/Buenos_Aires';
const POR_PEDIDO = 8, TOPE_BYTES = 3000000;   // Vercel no deja contestar más de 4,5 MB

const diaAR = d => new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
const limpio = s => String(s == null ? '' : s).replace(/[\\/:*?"<>|\u0000-\u001f]+/g, ' ').replace(/\s+/g, ' ').trim();

// El área del contrato, por su show: Externos y España, las suyas; lo demás (Arena y "ambas"), Arena.
export function areaDe(c) {
  const a = String((c && c.convocatorias && c.convocatorias.area) || '').toLowerCase();
  return a === 'externos' ? 'externos' : a === 'espana' ? 'espana' : 'arena';
}
// La fecha del contrato: la del show (por presente) o, si no, la primera del show; si no tiene, la de la firma.
export function fechaDe(c) {
  if (/^\d{4}-\d{2}-\d{2}/.test(String(c.fecha_show || ''))) return String(c.fecha_show).slice(0, 10);
  const fs = String((c.convocatorias && c.convocatorias.fecha) || '').split(',').map(x => x.trim()).filter(x => /^\d{4}-\d{2}-\d{2}$/.test(x)).sort();
  return fs[0] || (c.fecha_firma ? diaAR(new Date(c.fecha_firma)) : diaAR(new Date()));
}
// Dónde va y cómo se llama, como lo que RR. HH. ya guardaba a mano (18-nov):
//   Arena: "MARÍA BECERRA 13 /11" (una carpeta por fecha) · Externos y España: "Cancillería 08,09 /11 - Contratos"
//   (una por evento, con sus días del mes) · el archivo: "Nombre - Contrato 13-11.pdf" ("Documento" si es sólo eso).
// El script le pone adelante el número que sigue ("01- …") si la carpeta todavía no está.
export function ubicacion(c, area) {
  const f = fechaDe(c), [a, m, d] = f.split('-');
  const nombreShow = limpio(String((c.convocatorias && c.convocatorias.nombre) || 'Sin show').split(' — ')[0]) || 'Sin show';
  const nombre = limpio(c.nombre) || 'Sin nombre';
  let carpeta;
  if ((area || areaDe(c)) === 'arena') carpeta = nombreShow.toUpperCase() + ' ' + d + ' /' + m;
  else {
    // El nombre sin los pedazos que son sólo fechas ("Cancillería · Palacio Libertad y UCA · 8 y 9 11"): los días ya van al final.
    const sinFechas = nombreShow.split(/\s+·\s+/).filter(p => !/^\d{1,2}(\s*(y|,|-|al|a)\s*\d{1,2})*(\s*[\/.-]?\s*\d{1,2})?(\s*[\/.-]\s*\d{2,4})?$/i.test(p.trim())).join(' · ') || nombreShow;
    const dias = String((c.convocatorias && c.convocatorias.fecha) || '').split(',').map(x => x.trim()).filter(x => /^\d{4}-\d{2}-\d{2}$/.test(x) && x.slice(0, 7) === f.slice(0, 7)).sort().map(x => x.slice(8));
    carpeta = sinFechas + ' ' + (dias.length ? [...new Set(dias)].join(',') : d) + ' /' + m + ' - Contratos';
  }
  return { anio: a, carpeta_show: carpeta, archivo: nombre + ' - ' + (c.solo_documentos ? 'Documento' : 'Contrato') + ' ' + d + '-' + m + '.pdf' };
}
export function sinPrefijo(pdf) { return String(pdf || '').replace(/^data:[^,]*,/, '').replace(/\s+/g, ''); }

function claveOk(dada, esperada) {
  const a = Buffer.from(String(dada || '')), b = Buffer.from(String(esperada || ''));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}
async function sb(servicio, ruta) {
  const r = await fetch(`${SB_URL}/rest/v1/${ruta}`, { headers: { apikey: servicio, Authorization: `Bearer ${servicio}` } });
  const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {}
  return { ok: r.ok, data: j };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', clave = process.env.PRESENTES_CLAVE || '';
  if (!clave) return res.status(500).json({ error: 'Falta configurar PRESENTES_CLAVE en Vercel' });
  if (!claveOk(req.headers['x-clave'], clave)) return res.status(401).json({ error: 'Clave incorrecta' });
  if (!servicio) return res.status(500).json({ error: 'Falta configurar en Vercel la clave de Supabase' });
  let cuerpo;
  try { cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch (_) { return res.status(400).json({ error: 'El pedido no es JSON' }); }
  const area = ['arena', 'externos', 'espana'].includes(cuerpo.area) ? cuerpo.area : 'arena';
  const desde = new Date(cuerpo.desde || '2026-01-01T00:00:00Z');
  if (isNaN(desde.getTime())) return res.status(400).json({ error: 'La fecha "desde" no es válida' });
  const hasta = new Date(Date.now() - 10 * 60000).toISOString();
  const base = `estado=eq.firmado&pdf_firmado=not.is.null&fecha_firma=gt.${encodeURIComponent(cuerpo.desde || desde.toISOString())}&fecha_firma=lt.${encodeURIComponent(hasta)}`;
  const LISTA = 'id,nombre,cuil,fecha_show,fecha_firma,solo_documentos,convocatorias(nombre,area,fecha)';

  if (cuerpo.contar) {
    const r = await sb(servicio, `contratos?select=${LISTA}&${base}&order=fecha_firma.asc&limit=5000`);
    if (!r.ok) return res.status(500).json({ error: 'No se pudieron leer los contratos', detalle: (r.data && r.data.message) || '' });
    const carpetas = {}, del = (r.data || []).filter(c => areaDe(c) === area);
    del.forEach(c => { const u = ubicacion(c, area), k = u.anio + ' · ' + u.carpeta_show; carpetas[k] = (carpetas[k] || 0) + 1; });
    return res.status(200).json({ ok: true, area, pendientes: del.length, carpetas });
  }

  // Primero, los que siguen (sin los PDF), y de ésos los del área; después, los PDF de esos pocos.
  const VENTANA = 200;
  const rl = await sb(servicio, `contratos?select=${LISTA}&${base}&order=fecha_firma.asc,id.asc&limit=${VENTANA}`);
  if (!rl.ok) return res.status(500).json({ error: 'No se pudieron leer los contratos', detalle: (rl.data && rl.data.message) || '' });
  const lista = rl.data || [], toca = [];
  let cursor = null, i = 0;
  for (; i < lista.length && toca.length < POR_PEDIDO; i++) { if (areaDe(lista[i]) === area) toca.push(lista[i]); else cursor = lista[i].fecha_firma; }
  if (!toca.length) return res.status(200).json({ ok: true, area, contratos: [], cursor, mas: lista.length === VENTANA });
  const rp = await sb(servicio, `contratos?select=id,pdf_firmado&id=in.(${toca.map(c => c.id).join(',')})`);
  if (!rp.ok) return res.status(500).json({ error: 'No se pudieron leer los PDF', detalle: (rp.data && rp.data.message) || '' });
  const pdfDe = {}; (rp.data || []).forEach(x => { pdfDe[x.id] = sinPrefijo(x.pdf_firmado); });
  const contratos = [];
  let bytes = 0;
  for (const c of toca) {
    const pdf = pdfDe[c.id] || '';
    if (contratos.length && bytes + pdf.length > TOPE_BYTES) break;
    bytes += pdf.length;
    contratos.push(Object.assign({ id: c.id, firmado_at: c.fecha_firma, pdf }, ubicacion(c, area)));
  }
  // Se sigue desde el último que va (los de otra área anteriores ya quedaron mirados).
  cursor = contratos[contratos.length - 1].firmado_at;
  return res.status(200).json({ ok: true, area, contratos, cursor, mas: contratos.length < toca.length || i < lista.length || lista.length === VENTANA });
}
