// El informe de incidencias de un show, por link (14-nov-2026).
//
// Thomas: "que tengan directamente acceso al link del informe y que, si quieren descargarlo, puedan".
// El mail del reporte lleva un link /informe?t=… a esta página: el mismo Informe de la gerencia (el del
// PDF), con un botón "Descargar PDF" (…&pdf=1). Sin usuario: el link es único por show y fecha (firmado
// con PRESENTES_CLAVE, que sólo está en Vercel), así que sólo lo abre quien recibió el mail.
//
// El de los socios (15-nov), /socios?t=…: el mismo informe con los contratos y el personal del show arriba. Thomas:
// "que reciban sólo uno ellos con el informe de incidencias, informe de contratos, etc., para poner todo en uno". Con
// su propia firma: el link del Arena no abre el de los socios (ni al revés).

import crypto from 'crypto';
import { htmlInforme, pdfDeHtml } from './_lib/informe-pdf.js';

export const config = { maxDuration: 60 };
const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';

const firma = (secreto, convId, fecha, tipo) => crypto.createHmac('sha256', secreto).update((tipo === 'socios' ? 'socios|' : 'informe|') + convId + '|' + fecha).digest('base64url').slice(0, 32);
// El link de un show y fecha.
export function linkInforme(secreto, convId, fecha) {
  return SITIO + '/informe?t=' + Buffer.from(convId + '|' + fecha).toString('base64url') + '.' + firma(secreto, convId, fecha);
}
// El de los socios.
export function linkSocios(secreto, convId, fecha) {
  return SITIO + '/socios?t=' + Buffer.from(convId + '|' + fecha).toString('base64url') + '.' + firma(secreto, convId, fecha, 'socios');
}
// Al cambiar PRESENTES_CLAVE (15-nov-2026), los links que ya recibió el Arena estaban firmados con la
// anterior: siguen abriendo con INFORME_CLAVE_ANTERIOR (en Vercel), pero sólo los de los informes de hasta
// ANTERIOR_HASTA. Los nuevos se firman con la clave nueva; con la vieja no se puede armar un link de un show
// que venga.
export const ANTERIOR_HASTA = '2026-11-15';
export function leerTokenConAnterior(secreto, anterior, t, tipo) {
  const tok = leerToken(secreto, t, tipo);
  if (tok || !anterior || anterior === secreto) return tok;
  const viejo = leerToken(anterior, t, tipo);
  return viejo && viejo.fecha <= ANTERIOR_HASTA ? viejo : null;
}
// ── La carpeta con todos los informes (15-nov) ──
// Thomas: "que haya una carpeta donde estén todos los informes, los que se abren con un link, para facilitar al
// Arena su vista; ponerlo en el cuerpo del mail automático, tipo 'pueden ver los informes por acá'". Un link fijo
// (no vence ni cambia por show): la lista de los shows del Arena desde el piloto, del más nuevo al más viejo, cada
// uno con su informe. El de los socios (tipo socios) lleva a los suyos (con contratos y personal).
const firmaTodos = (secreto, p) => crypto.createHmac('sha256', secreto).update(p).digest('base64url').slice(0, 32);
export function linkTodos(secreto, tipo) {
  const p = 'todos|' + (tipo === 'socios' ? 'socios' : 'informe');
  return SITIO + '/informes?t=' + Buffer.from(p).toString('base64url') + '.' + firmaTodos(secreto, p);
}
export function leerTodos(secreto, t) {
  const [a, b] = String(t || '').split('.');
  if (!a || !b || !secreto) return null;
  let p = '';
  try { p = Buffer.from(a, 'base64url').toString('utf8'); } catch (_) { return null; }
  if (!/^todos\|(informe|socios)$/.test(p)) return null;
  const e = Buffer.from(firmaTodos(secreto, p)), d = Buffer.from(b);
  return e.length === d.length && crypto.timingSafeEqual(e, d) ? p.split('|')[1] : null;
}
// Los shows que entran (como el reporte de la 1:30: del Centro de Control, del Arena, sin los de prueba), cada fecha
// después de su 1:30 (cuando ya salió el informe) y desde que arrancó el piloto.
export const DESDE_PILOTO = '2026-11-13';
const fechasDe = c => String((c && c.fecha) || '').split(',').map(x => x.trim()).filter(x => /^\d{4}-\d{2}-\d{2}$/.test(x));
const esArena = area => /arena|movistar/i.test(String(area || ''));
const esPrueba = nombre => /prueba/i.test(String(nombre || ''));
const cierreDe = fecha => new Date(new Date(fecha + 'T09:00:00Z').getTime() + 19.5 * 3600 * 1000);
export function informesDe(convs, ahora) {
  const out = [];
  (convs || []).filter(c => c.centro_control && esArena(c.area) && !esPrueba(c.nombre)).forEach(c => fechasDe(c).forEach(fecha => {
    if (fecha >= DESDE_PILOTO && cierreDe(fecha).getTime() <= ahora) out.push({ conv: c, fecha });
  }));
  return out.sort((a, b) => b.fecha.localeCompare(a.fecha) || String(a.conv.nombre).localeCompare(String(b.conv.nombre)));
}
const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const escH = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
// La página: una fila por show y fecha, con lo principal y el botón a su informe.
export function paginaTodos(tipo, filas) {
  const socios = tipo === 'socios';
  const fila = x => {
    const d = new Date(x.fecha + 'T12:00:00Z'), dia = DIAS[d.getUTCDay()] + ' ' + d.getUTCDate() + ' de ' + MESES[d.getUTCMonth()];
    const nombre = String(x.conv.nombre || '').split(' — ')[0].trim();
    const partes = [x.incidencias + (x.incidencias === 1 ? ' incidencia' : ' incidencias') + (x.graves ? ' · ' + x.graves + (x.graves === 1 ? ' grave' : ' graves') : '')];
    if (socios && x.contratos) partes.push(x.firmados + ' de ' + x.contratos + ' contratos firmados');
    return '<a class="fila" href="' + escH(x.link) + '"><div class="dia"><b>' + d.getUTCDate() + '</b><span>' + MESES[d.getUTCMonth()].slice(0, 3) + '</span></div>'
      + '<div class="que"><div class="n">' + escH(nombre) + '</div><div class="s">' + escH(dia.charAt(0).toUpperCase() + dia.slice(1)) + ' · Movistar Arena</div><div class="m">' + escH(partes.join(' · ')) + '</div></div>'
      + '<div class="ir">Ver el informe<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg></div></a>';
  };
  return '<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    + '<title>' + (socios ? 'Informes para socios' : 'Informes de incidencias') + ' · Movistar Arena</title>'
    + '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap"><style>'
    + '*{box-sizing:border-box}html{background:#fff}body{margin:0;font-family:Poppins,sans-serif;color:#1a1a1a}'
    // La marca de SBS de fondo, como en el informe (Thomas, 16-nov: "el wallpaper de SBS de fondo, como el del informe"), entera de
    // borde a borde, como en las apps; con el celular parado, entera de ancho arriba y fundiéndose hacia abajo.
    + 'body::before{content:"";position:fixed;inset:0;z-index:-1;pointer-events:none;opacity:.07;background:url(' + SITIO + '/fondo-sbs.jpg) center/cover no-repeat}'
    + '@media (max-aspect-ratio:3/4){body::before{background:linear-gradient(rgba(255,255,255,0),#fff) 0 34vw/100% 23vw no-repeat,url(' + SITIO + '/fondo-sbs.jpg) center 0/100% auto no-repeat}}'
    + '.hoja{max-width:760px;margin:0 auto;padding:40px 16px 56px}'
    + '.cab{display:flex;align-items:center;gap:14px;padding-bottom:22px;border-bottom:2px solid #1a1a1a;margin-bottom:22px}.cab img{width:52px;height:52px}'
    + '.k{font-size:12px;font-weight:600;color:#5c5c5c}h1{font-size:24px;line-height:1.2;margin:2px 0 0;font-weight:700}'
    + '.intro{font-size:14px;color:#5c5c5c;line-height:1.6;margin:0 0 20px}'
    + '.fila{display:flex;align-items:center;gap:16px;padding:16px;border:1px solid #dadada;border-radius:14px;margin-bottom:10px;text-decoration:none;color:inherit}'
    + '.fila:hover{border-color:#1a1a1a}.fila:focus-visible{outline:3px solid #1a1a1a;outline-offset:2px}'
    + '.dia{flex:0 0 56px;height:56px;border-radius:12px;background:rgba(26,26,26,.06);display:flex;flex-direction:column;align-items:center;justify-content:center;line-height:1}'
    + '.dia b{font-size:22px;font-weight:700}.dia span{font-size:11px;font-weight:600;color:#5c5c5c;margin-top:4px;text-transform:uppercase;letter-spacing:.04em}'
    + '.que{flex:1;min-width:0}.n{font-size:16px;font-weight:600}.s{font-size:13px;color:#5c5c5c;margin-top:2px}.m{font-size:13px;margin-top:6px}'
    + '.ir{flex:0 0 auto;display:inline-flex;align-items:center;gap:6px;font-size:13px;font-weight:600;background:#1a1a1a;color:#fff;padding:10px 14px;border-radius:10px}.ir svg{width:16px;height:16px}'
    + '.vacio{padding:28px;border:1px dashed #dadada;border-radius:14px;text-align:center;color:#5c5c5c;font-size:14px}'
    + '@media (max-width:560px){.fila{flex-wrap:wrap}.ir{width:100%;justify-content:center}}'
    + '</style></head><body><div class="hoja">'
    + '<div class="cab"><img src="' + SITIO + '/logo-sbs.png" alt="Show Business Solutions"><div><div class="k">AX · Audience Experience · Show Business Solutions</div><h1>'
    + (socios ? 'Informes para socios' : 'Informes de incidencias') + '</h1></div></div>'
    + '<p class="intro">' + (socios ? 'Cada show del Movistar Arena, con los contratos, el personal y las incidencias. ' : 'Cada show del Movistar Arena, con su informe de incidencias. ')
    + 'Están siempre actualizados y, si lo necesitan en PDF, se descarga desde cada informe.</p>'
    + (filas.length ? filas.map(fila).join('') : '<div class="vacio">Todavía no hay informes.</div>')
    + '</div></body></html>';
}

// El token → { convId, fecha }, o null si no es válido.
export function leerToken(secreto, t, tipo) {
  const [a, b] = String(t || '').split('.');
  if (!a || !b || !secreto) return null;
  let txt = '';
  try { txt = Buffer.from(a, 'base64url').toString('utf8'); } catch (_) { return null; }
  const [convId, fecha] = txt.split('|');
  if (!/^[0-9a-f-]{36}$/i.test(convId || '') || !/^\d{4}-\d{2}-\d{2}$/.test(fecha || '')) return null;
  const esperada = Buffer.from(firma(secreto, convId, fecha, tipo)), dada = Buffer.from(b);
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

// Para los socios: arriba, los contratos y el personal del show; abajo, el informe de incidencias de siempre. Sin nombres:
// sólo cuántos. Pendiente = enviado sin firmar (lo abrió o no); les llega un recordatorio por día hasta que firmen.
export function conContratos(html, contratos, presentes) {
  const n = e => contratos.filter(c => e.includes(c.estado)).length;
  const firmados = n(['firmado']), abrieron = n(['visto']), noAbrieron = n(['enviado', 'pendiente']), sin = abrieron + noAbrieron, total = firmados + sin;
  const num = (v, t) => '<div class="num"><b>' + v + '</b><span>' + t + '</span></div>';
  const bloque = '<h3>Contratos y personal</h3><div class="nums">'
    + (presentes == null ? '' : num(presentes, 'Con presente'))
    + num(total, 'Contratos') + num(firmados, 'Firmados') + num(sin, 'Sin firmar') + num(total ? Math.round(firmados * 100 / total) + '%' : '—', 'Firmado')
    + '</div>' + (sin ? '<p style="font-size:11px;color:#5c5c5c;margin:-8px 0 18px">De los sin firmar, ' + abrieron + (abrieron === 1 ? ' lo abrió' : ' lo abrieron') + ' y ' + noAbrieron + ' todavía no. Les llega un recordatorio por día hasta que firmen.</p>' : '')
    + '<h3>Incidencias</h3>';
  return html.replace('<title>Informe de incidencias · ', '<title>Informe del show · ').replace('<h1>Informe de incidencias · ', '<h1>Informe del show · ')
    .replace('<div class="nums">', bloque + '<div class="nums">');
}

export default async function handler(req, res) {
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('Cache-Control', 'private, no-store');
  if (req.method !== 'GET') { res.setHeader('Allow', 'GET'); return res.status(405).send('Método no permitido'); }
  const secreto = process.env.PRESENTES_CLAVE || '', servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  const t = String((req.query && req.query.t) || ''), quierePdf = String((req.query && req.query.pdf) || '') === '1';
  if (String((req.query && req.query.vista) || '') === 'todos') {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    const anterior = process.env.INFORME_CLAVE_ANTERIOR || '';
    const tt = String((req.query && req.query.t) || ''), tipoT = leerTodos(secreto, tt) || (anterior && anterior !== secreto ? leerTodos(anterior, tt) : null);
    if (!tipoT) return res.status(404).send(pagina('Link inválido', 'Este link no es válido. Pedile los informes a Show Business Solutions.'));
    if (!servicio) return res.status(500).send(pagina('No disponible', 'Los informes no están disponibles en este momento. Probá de nuevo en un rato.'));
    const rc = await sb(servicio, 'convocatorias?select=id,nombre,fecha,area,centro_control&centro_control=eq.true&limit=1000');
    if (!rc.ok) return res.status(500).send(pagina('No disponible', 'No se pudieron leer los shows. Probá de nuevo en un rato.'));
    const lista = informesDe(rc.data || [], Date.now());
    const ids = [...new Set(lista.map(x => x.conv.id))];
    let incs = [], cts = [];
    if (ids.length) {
      const [ri2, rk2] = await Promise.all([
        sb(servicio, `incidencias?select=conv_id,created_at,nivel&conv_id=in.(${ids.join(',')})&created_at=gte.${DESDE_PILOTO}T09:00:00Z&limit=20000`),
        tipoT === 'socios' ? sb(servicio, `contratos?select=conv_id,fecha_show,estado&conv_id=in.(${ids.join(',')})&estado=neq.anulado&limit=20000`) : Promise.resolve({ ok: true, data: [] })
      ]);
      incs = ri2.ok ? ri2.data || [] : []; cts = rk2.ok ? rk2.data || [] : [];
    }
    const filas = lista.map(x => {
      const desde = new Date(x.fecha + 'T09:00:00Z').getTime(), hasta = desde + 24 * 3600 * 1000;
      const l = incs.filter(i => i.conv_id === x.conv.id && new Date(i.created_at).getTime() >= desde && new Date(i.created_at).getTime() < hasta);
      const k = cts.filter(c => c.conv_id === x.conv.id && c.fecha_show === x.fecha);
      return Object.assign({}, x, { incidencias: l.length, graves: l.filter(i => i.nivel === 3).length, contratos: k.length, firmados: k.filter(c => c.estado === 'firmado').length,
        link: tipoT === 'socios' ? linkSocios(secreto, x.conv.id, x.fecha) : linkInforme(secreto, x.conv.id, x.fecha) });
    });
    return res.status(200).send(paginaTodos(tipoT, filas));
  }
  const tipo = String((req.query && req.query.tipo) || '') === 'socios' ? 'socios' : 'informe';
  const tok = leerTokenConAnterior(secreto, process.env.INFORME_CLAVE_ANTERIOR || '', t, tipo);
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
  if (tipo === 'socios') {
    const [rk, rp] = await Promise.all([
      sb(servicio, `contratos?select=estado&conv_id=eq.${conv.id}&fecha_show=eq.${tok.fecha}&estado=neq.anulado&limit=5000`),
      sb(servicio, `planilla_presentes?select=cuil&fecha=eq.${tok.fecha}&marca=eq.P&limit=5000`)
    ]);
    if (!rk.ok) return res.status(500).send(pagina('No disponible', 'No se pudieron leer los contratos. Probá de nuevo en un rato.'));
    html = conContratos(html, rk.data || [], rp.ok ? (rp.data || []).length : null);
  }
  const nombre = String(conv.nombre || '').split(' — ')[0].trim(), ddmm = tok.fecha.slice(8, 10) + '-' + tok.fecha.slice(5, 7);
  if (quierePdf) {
    try {
      const pdf = Buffer.from(await pdfDeHtml(html, process.env.CHROME_LOCAL), 'base64');
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodeURIComponent((tipo === 'socios' ? 'Informe del show - ' : 'Reporte de incidencias - ') + nombre + ' ' + ddmm + '.pdf')}`);
      return res.status(200).send(pdf);
    } catch (e) { return res.status(500).send(pagina('No se pudo descargar', 'No se pudo armar el PDF. Probá de nuevo en un rato.')); }
  }
  // En la página, arriba a la derecha, "Descargar PDF" (no sale al imprimir).
  const barra = `<style>.dl{position:fixed;top:16px;right:16px;z-index:10;display:inline-flex;align-items:center;gap:8px;background:#1a1a1a;color:#fff;text-decoration:none;font:600 13px Poppins,sans-serif;padding:11px 16px;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,.15)}.dl svg{width:16px;height:16px}@media print{.dl{display:none}}</style>`
    + `<a class="dl" href="/${tipo}?t=${encodeURIComponent(t)}&pdf=1"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>Descargar PDF</a>`;
  // En la compu, el informe centrado (como una hoja) y la marca de agua entera y desvanecida hacia los bordes (sin el corte seco que en el PDF tapa el borde de la hoja); en el celular, como un documento que se agranda con los dedos.
  html = html.replace('</head>', '<style>@media screen{body{max-width:1040px;margin:28px auto!important;padding:0 16px}body::before{width:min(1240px,100vw,177.78vh)!important}}</style></head>').replace('<body>', '<body>' + barra);
  return res.status(200).send(html);
}
