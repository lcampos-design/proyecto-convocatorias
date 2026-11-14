// El reporte de incidencias de cada show del Arena, para mandarlo solo al terminar (13-nov-2026).
//
// Pedido de Thomas: "que finalizado el show se envíe automáticamente el reporte de incidencias
// vía mail desde convocatorias.arena". El script de la planilla de presentes
// (apps-script/planilla-presentes.gs), que corre cada 5 minutos con la cuenta del Arena, pide acá
// las incidencias de los shows de una fecha, arma el PDF (como el "Informe" de la gerencia) y lo
// manda desde esa casilla. Acá sólo se leen los datos: nada se cambia.
//
// La fecha es la del show (la función): lo cargado entre las 6 de la mañana de ese día y las 6 del
// día siguiente, como en el Centro de Control. Entran los shows del Centro de Control del Arena,
// menos los de prueba ("Calamaro — Prueba piloto").
//
// Usa la misma clave que el envío de contratos (PRESENTES_CLAVE, en Vercel y en el script).

import crypto from 'crypto';

export const config = { maxDuration: 30 };
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
export function showsDelDia(convs, fecha) {
  return (convs || []).filter(c => c.centro_control && esArena(c.area) && !esPrueba(c.nombre) && fechasDe(c).includes(fecha));
}

async function sb(servicio, ruta) {
  const r = await fetch(`${SB_URL}/rest/v1/${ruta}`, { headers: { apikey: servicio, Authorization: `Bearer ${servicio}` } });
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
  const salida = [];
  for (const c of shows) {
    const ri = await sb(servicio, `incidencias?select=id,created_at,sector,ubicacion,categoria,tipo,nivel,acciones,nota,estado,resolucion,resuelta_at`
      + `&conv_id=eq.${c.id}&created_at=gte.${encodeURIComponent(desde)}&created_at=lt.${encodeURIComponent(hasta)}&order=created_at.asc&limit=2000`);
    if (!ri.ok) return res.status(500).json({ error: 'No se pudieron leer las incidencias' });
    salida.push({ conv_id: c.id, nombre: String(c.nombre || '').split(' — ')[0].trim(), venue: c.venue || 'Movistar Arena', fecha, incidencias: ri.data || [] });
  }
  return res.status(200).json({ ok: true, fecha, shows: salida });
}
