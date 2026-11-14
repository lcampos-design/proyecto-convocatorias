// El informe de incidencias de un show, por link (14-nov-2026).
//
// Thomas: "que tengan directamente acceso al link del informe y que, si quieren descargarlo, puedan".
// El mail del reporte lleva un link /informe?t=… a esta página: el mismo Informe de la gerencia (el del
// PDF), con un botón "Descargar PDF" (…&pdf=1). Sin usuario: el link es único por show y fecha (firmado
// con PRESENTES_CLAVE, que sólo está en Vercel), así que sólo lo abre quien recibió el mail.

import crypto from 'crypto';
import { htmlInforme, pdfDeHtml } from './_lib/informe-pdf.js';

export const config = { maxDuration: 60 };
const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';

const firma = (secreto, convId, fecha) => crypto.createHmac('sha256', secreto).update('informe|' + convId + '|' + fecha).digest('base64url').slice(0, 32);
// El link de un show y fecha.
export function linkInforme(secreto, convId, fecha) {
  return SITIO + '/informe?t=' + Buffer.from(convId + '|' + fecha).toString('base64url') + '.' + firma(secreto, convId, fecha);
}
// El token → { convId, fecha }, o null si no es válido.
export function leerToken(secreto, t) {
  const [a, b] = String(t || '').split('.');
  if (!a || !b || !secreto) return null;
  let txt = '';
  try { txt = Buffer.from(a, 'base64url').toString('utf8'); } catch (_) { return null; }
  const [convId, fecha] = txt.split('|');
  if (!/^[0-9a-f-]{36}$/i.test(convId || '') || !/^\d{4}-\d{2}-\d{2}$/.test(fecha || '')) return null;
  const esperada = Buffer.from(firma(secreto, convId, fecha)), dada = Buffer.from(b);
  return esperada.length === dada.length && crypto.timingSafeEqual(esperada, dada) ? { convId, fecha } : null;
}

async function sb(servicio, ruta) {
  const r = await fetch(`${SB_URL}/rest/v1/${ruta}`, { headers: { apikey: servicio, Authorization: `Bearer ${servicio}` } });
  const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {}
  return { ok: r.ok, data: j };
}
const pagina = (titulo, texto) => `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${titulo}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;600&display=swap"></head>
<body style="margin:0;font-family:Poppins,sans-serif;background:#fff;color:#1a1a1a;display:flex;min-height:100vh;align-items:center;justify-content:center;padding:24px;box-sizing:border-box">
<div style="max-width:420px;text-align:center"><img src="${SITIO}/logo-sbs.png" alt="SBS" width="56" height="56"><h1 style="font-size:20px;margin:16px 0 8px">${titulo}</h1><p style="color:#5c5c5c;line-height:1.6;margin:0">${texto}</p></div></body></html>`;

export default async function handler(req, res) {
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('Cache-Control', 'private, no-store');
  if (req.method !== 'GET') { res.setHeader('Allow', 'GET'); return res.status(405).send('Método no permitido'); }
  const secreto = process.env.PRESENTES_CLAVE || '', servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  const t = String((req.query && req.query.t) || ''), quierePdf = String((req.query && req.query.pdf) || '') === '1';
  const tok = leerToken(secreto, t);
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  if (!tok) return res.status(404).send(pagina('Link inválido', 'Este link no es válido. Pedile el informe a Show Business Solutions.'));
  if (!servicio) return res.status(500).send(pagina('No disponible', 'El informe no está disponible en este momento. Probá de nuevo en un rato.'));
  const rc = await sb(servicio, `convocatorias?select=id,nombre,fecha&id=eq.${tok.convId}`);
  const conv = rc.ok && rc.data && rc.data[0];
  if (!conv) return res.status(404).send(pagina('No encontramos el show', 'Puede que ya no esté en el sistema. Pedile el informe a Show Business Solutions.'));
  // Lo del show: de las 6 de la mañana de la fecha a las 6 del día siguiente (como el reporte y la gerencia).
  const desde = new Date(tok.fecha + 'T09:00:00Z'), hasta = new Date(desde.getTime() + 24 * 3600 * 1000);
  const ri = await sb(servicio, `incidencias?select=id,created_at,sector,ubicacion,categoria,tipo,nivel,acciones,nota,estado,resolucion,resuelta_at`
    + `&conv_id=eq.${conv.id}&created_at=gte.${encodeURIComponent(desde.toISOString())}&created_at=lt.${encodeURIComponent(hasta.toISOString())}&order=created_at.asc&limit=2000`);
  if (!ri.ok) return res.status(500).send(pagina('No disponible', 'No se pudo leer el informe. Probá de nuevo en un rato.'));
  let html;
  try { html = await htmlInforme(conv, tok.fecha, ri.data || []); }
  catch (e) { return res.status(500).send(pagina('No disponible', 'No se pudo armar el informe. Probá de nuevo en un rato.')); }
  const nombre = String(conv.nombre || '').split(' — ')[0].trim(), ddmm = tok.fecha.slice(8, 10) + '-' + tok.fecha.slice(5, 7);
  if (quierePdf) {
    try {
      const pdf = Buffer.from(await pdfDeHtml(html, process.env.CHROME_LOCAL), 'base64');
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent('Reporte de incidencias - ' + nombre + ' ' + ddmm + '.pdf')}`);
      return res.status(200).send(pdf);
    } catch (e) { return res.status(500).send(pagina('No se pudo descargar', 'No se pudo armar el PDF. Probá de nuevo en un rato.')); }
  }
  // En la página, arriba a la derecha, "Descargar PDF" (no sale al imprimir).
  const barra = `<style>.dl{position:fixed;top:16px;right:16px;z-index:10;display:inline-flex;align-items:center;gap:8px;background:#1a1a1a;color:#fff;text-decoration:none;font:600 13px Poppins,sans-serif;padding:11px 16px;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,.15)}.dl svg{width:16px;height:16px}@media print{.dl{display:none}}</style>`
    + `<a class="dl" href="/informe?t=${encodeURIComponent(t)}&pdf=1"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>Descargar PDF</a>`;
  // En la compu, el informe centrado (como una hoja); en el celular, como un documento que se agranda con los dedos.
  html = html.replace('</head>', '<style>@media screen{body{max-width:1040px;margin:28px auto!important;padding:0 16px}}</style></head>').replace('<body>', '<body>' + barra);
  return res.status(200).send(html);
}
