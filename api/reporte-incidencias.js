// El reporte de incidencias de cada show del Arena, para mandarlo solo al terminar (13-nov-2026).
//
// Pedido de Thomas: "que finalizado el show se envíe automáticamente el reporte de incidencias
// vía mail desde convocatorias.arena". El script de la planilla de presentes
// (apps-script/planilla-presentes.gs), que corre cada 5 minutos con la cuenta del Arena, pide acá
// las incidencias de los shows de una fecha, arma el PDF (como el "Informe" de la gerencia) y lo
// manda desde esa casilla. Lo único que cambia: terminado el show (a la 1:30 del día siguiente), lo que
// quedó abierto se da por cerrado ("Cerrada al terminar el show (sin resolución cargada)"); si se manda
// a mano antes (cerrar: true, "enviar_reporte" del script), también.
//
// La fecha es la del show (la función): lo cargado entre las 6 de la mañana de ese día y las 6 del
// día siguiente, como en el Centro de Control. Entran los shows del Centro de Control del Arena,
// menos los de prueba ("Calamaro — Prueba piloto").
//
// Usa la misma clave que el envío de contratos (PRESENTES_CLAVE, en Vercel y en el script).

import crypto from 'crypto';
import { htmlInforme, pdfDeHtml } from './_lib/informe-pdf.js';
import { linkInforme } from './informe.js';

// Con pdf: true, el PDF de cada show lo imprime Chromium (el Informe de la gerencia, idéntico): hasta un minuto.
export const config = { maxDuration: 60 };
const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';

function claveOk(dada, esperada) {
  const a = Buffer.from(String(dada || '')), b = Buffer.from(String(esperada || ''));
  return a.length > 0 && a.length === b.length && crypto.timingSafeEqual(a, b);
}
// Las fechas de una convocatoria ("2026-11-13,2026-11-14").
export function fechasDe(c) { return String((c && c.fecha) || '').split(',').map(f => f.trim()).filter(Boolean); }
export const esArena = area => /arena|movistar/i.test(String(area || ''));
export const esPrueba = nombre => /prueba/i.test(String(nombre || ''));
// De las 6 de la mañana de la fecha (Buenos Aires, UTC-3) a las 6 del día siguiente.
export function ventana(fecha) {
  const desde = new Date(fecha + 'T09:00:00Z');
  return { desde: desde.toISOString(), hasta: new Date(desde.getTime() + 24 * 3600 * 1000).toISOString() };
}
// El show terminó: a la 1:30 del día siguiente (Buenos Aires), cuando sale el reporte.
export function cierreDe(fecha) { return new Date(new Date(fecha + 'T09:00:00Z').getTime() + 19.5 * 3600 * 1000); }
// Lo que se cerró solo al terminar (sin resolución cargada): no cuenta para la resolución media.
export const RESOLUCION_CIERRE = 'Cerrada al terminar el show (sin resolución cargada)';
export function showsDelDia(convs, fecha) {
  return (convs || []).filter(c => c.centro_control && esArena(c.area) && !esPrueba(c.nombre) && fechasDe(c).includes(fecha));
}

async function sb(servicio, ruta, op) {
  op = op || {};
  const r = await fetch(`${SB_URL}/rest/v1/${ruta}`, { method: op.method || 'GET', headers: Object.assign({ apikey: servicio, Authorization: `Bearer ${servicio}`, 'Content-Type': 'application/json' }, op.headers || {}), body: op.body === undefined ? undefined : JSON.stringify(op.body) });
  const t = await r.text(); let j = null; try { j = t ? JSON.parse(t) : null; } catch (_) {}
  return { ok: r.ok, status: r.status, data: j };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', clave = process.env.PRESENTES_CLAVE || '';
  if (!clave) return res.status(500).json({ error: 'Falta configurar PRESENTES_CLAVE en Vercel' });
  if (!claveOk(req.headers['x-clave'], clave)) return res.status(401).json({ error: 'Clave incorrecta' });
  if (!servicio) return res.status(500).json({ error: 'Falta configurar en Vercel la clave de Supabase' });
  let cuerpo;
  try { cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {}); } catch (_) { return res.status(400).json({ error: 'El pedido no es JSON' }); }
  const fecha = String(cuerpo.fecha || '');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fecha)) return res.status(400).json({ error: 'Falta la fecha (AAAA-MM-DD)' });

  const rc = await sb(servicio, `convocatorias?select=id,nombre,area,fecha,venue,centro_control&centro_control=eq.true&fecha=like.*${fecha}*`);
  if (!rc.ok) return res.status(500).json({ error: 'No se pudieron leer los shows' });
  const shows = showsDelDia(rc.data, fecha);
  const { desde, hasta } = ventana(fecha);
  // Terminado: a la 1:30, o antes si se manda a mano ("enviar_reporte" del script, con cerrar: el show ya terminó).
  let pagina = null;   // centro-control.html, una vez por pedido
  const salida = [], terminado = cuerpo.cerrar === true || Date.now() >= cierreDe(fecha).getTime();
  for (const c of shows) {
    // Terminado el show, lo que quedó abierto se da por cerrado (si no, en el reporte no tiene sentido).
    if (terminado) {
      const ahora = new Date().toISOString();
      await sb(servicio, `incidencias?conv_id=eq.${c.id}&estado=eq.abierta&created_at=gte.${encodeURIComponent(desde)}&created_at=lt.${encodeURIComponent(hasta)}`,
        { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: { estado: 'resuelta', resolucion: RESOLUCION_CIERRE, resuelta_at: ahora, resuelta_por_nombre: 'Al terminar el show', updated_at: ahora } });
    }
    const ri = await sb(servicio, `incidencias?select=id,created_at,sector,ubicacion,categoria,tipo,nivel,acciones,nota,estado,resolucion,resuelta_at`
      + `&conv_id=eq.${c.id}&created_at=gte.${encodeURIComponent(desde)}&created_at=lt.${encodeURIComponent(hasta)}&order=created_at.asc&limit=2000`);
    if (!ri.ok) return res.status(500).json({ error: 'No se pudieron leer las incidencias' });
    // Las que se cerraron solas van sin la hora de cierre: así el reporte no las cuenta en la resolución media.
    const lista = (ri.data || []).map(i => i.resolucion === RESOLUCION_CIERRE ? Object.assign({}, i, { resuelta_at: null }) : i);
    const show = { conv_id: c.id, nombre: String(c.nombre || '').split(' — ')[0].trim(), venue: c.venue || 'Movistar Arena', fecha, cerradas_al_final: lista.filter(i => i.resolucion === RESOLUCION_CIERRE).length, incidencias: lista };
    // El link al informe en el sistema (con "Descargar PDF"), para el mail.
    show.link = linkInforme(clave, c.id, fecha);
    // El PDF: el Informe de la gerencia, con las incidencias tal cual están en la base. Si falla, el script usa el suyo.
    if (cuerpo.pdf === true) {
      try {
        if (!pagina) { const rp = await fetch('https://convocatorias.show-bs.com/centro-control.html', { headers: { 'Cache-Control': 'no-cache' } }); if (!rp.ok) throw new Error('centro-control.html: ' + rp.status); pagina = await rp.text(); }
        show.pdf = await pdfDeHtml(await htmlInforme({ id: c.id, nombre: c.nombre, fecha: c.fecha }, fecha, ri.data || [], pagina));
      } catch (e) { show.pdf_error = String((e && e.message) || e).slice(0, 300); }
    }
    salida.push(show);
  }
  return res.status(200).json({ ok: true, fecha, shows: salida });
}
