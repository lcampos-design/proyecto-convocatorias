// El PDF del reporte de incidencias, idéntico al "Informe" de la gerencia (14-nov-2026).
//
// Thomas, al ver el primer reporte por mail: "quiero que sea idéntico al del sistema". El conversor de
// Google (el que usaba el script) no tiene la tipografía, ni la marca de agua, ni los fondos. Acá se arma
// con el mismo código: se lee centro-control.html del sitio, se toma su función informe() con lo que
// necesita, se corre con las incidencias del show y el HTML que sale se imprime con Chromium, como
// cuando la gerencia toca "Informe" y guarda como PDF.

const SITIO = 'https://convocatorias.show-bs.com';

// Las declaraciones de primer nivel del script de la página: nombre → código.
function declaraciones(html) {
  const bloques = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
  const codigo = bloques.reduce((a, b) => (a.length > b.length ? a : b), '');
  const trozos = Object.create(null); let actual = null;
  for (const linea of codigo.split('\n')) {
    const m = linea.match(/^(?:async\s+)?function\s+(\w+)|^(?:const|let|var)\s+(\w+)/);
    if (m) { actual = m[1] || m[2]; trozos[actual] = (trozos[actual] || '') + linea + '\n'; }
    else if (/^[}\])\s]|^\/\/|^$/.test(linea) || (actual && /^\s/.test(linea))) { if (actual) trozos[actual] += linea + '\n'; }
    else actual = null;   // una sentencia suelta (iniciar(), addEventListener…): no se corre
  }
  // "let a = 1, b = 2": cada nombre apunta al trozo de la línea.
  for (const [n, t] of Object.entries({ ...trozos })) {
    const l = t.split('\n')[0];
    if (/^(?:let|var|const)\s/.test(l)) for (const m of l.matchAll(/[,\s](\w+)\s*=(?!=)/g)) if (!trozos[m[1]]) trozos[m[1]] = '\0' + n;
  }
  return trozos;
}
// El código de esas declaraciones con todo lo que usan, en orden.
function armar(trozos, desde) {
  const puestos = new Set(), orden = [];
  const real = n => (typeof trozos[n] === 'string' && trozos[n][0] === '\0' ? trozos[n].slice(1) : n);
  const agregar = n => {
    n = real(n);
    if (typeof trozos[n] !== 'string' || puestos.has(n)) return;
    puestos.add(n);
    for (const id of new Set(trozos[n].match(/\b[A-Za-z_$][\w$]*\b/g))) if (id !== n) agregar(id);
    orden.push(n);
  };
  desde.forEach(agregar);
  return orden.map(n => trozos[n]).join('');
}

// El HTML del informe, como lo arma la gerencia. conv: { id, nombre, fecha }; fecha: la del show (AAAA-MM-DD).
// notas: las de los supervisores de esa fecha (notas.sql), con el link de cada archivo (url) si se van a ver las fotos.
export async function htmlInforme(conv, fecha, incidencias, pagina, notas) {
  if (!pagina) {
    const r = await fetch(SITIO + '/centro-control.html', { headers: { 'Cache-Control': 'no-cache' } });
    if (!r.ok) throw new Error('No se pudo leer centro-control.html (' + r.status + ')');
    pagina = await r.text();
  }
  const codigo = armar(declaraciones(pagina), ['informe', 'shows', 'showId', 'dia', 'lista']);
  if (!/function informe\(\)/.test(codigo)) throw new Error('No encontré informe() en centro-control.html');
  // La hora de la gerencia es la del Arena.
  process.env.TZ = 'America/Argentina/Buenos_Aires';
  let escrito = '';
  const ventana = { open: () => ({ document: { open() {}, write(h) { escrito += h; }, close() {} } }) };
  const stubs = {
    window: ventana, location: { origin: SITIO }, alert() {}, document: { getElementById: () => null, querySelector: () => null },
    supabase: { createClient: () => ({ auth: {}, from: () => ({}), rpc: async () => ({}) }) },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} }, matchMedia: () => ({ matches: false, addEventListener() {} })
  };
  const datos = 'shows = ' + JSON.stringify([{ id: conv.id, nombre: conv.nombre, fecha: conv.fecha }]) + '; showId = ' + JSON.stringify(conv.id)
    + '; dia = ' + JSON.stringify(fecha) + '; lista = ' + JSON.stringify(incidencias || []) + '; notasShow = ' + JSON.stringify(notas || []) + '; informe();';
  new Function(...Object.keys(stubs), codigo + '\n' + datos)(...Object.values(stubs));
  if (!/Informe de incidencias/.test(escrito)) throw new Error('El informe salió vacío');
  // Sin el "imprimir" automático (acá lo imprime Chromium).
  return escrito.replace(/<script>window\.onload=[\s\S]*?<\/script>/, '');
}

// Las notas de los supervisores de un show y fecha (notas.sql), con el servicio de Supabase. firmar: el link de cada
// archivo (vence en 7 días; la página se arma en cada visita), para ver las fotos en el link del informe. Sin notas.sql
// (la tabla no está), ninguna.
export async function notasDelShow(sbUrl, servicio, convId, fecha, firmar) {
  try {
    const h = { apikey: servicio, Authorization: `Bearer ${servicio}` };
    const r = await fetch(`${sbUrl}/rest/v1/notas_show?select=id,fecha,zona,autor_nombre,texto,archivos,created_at&conv_id=eq.${convId}&fecha=eq.${fecha}&order=created_at.asc&limit=500`, { headers: h });
    if (!r.ok) return [];
    const notas = await r.json();
    const paths = [...new Set(notas.flatMap(n => (n.archivos || []).map(a => a && a.path)).filter(Boolean))];
    if (firmar && paths.length) {
      const rs = await fetch(`${sbUrl}/storage/v1/object/sign/notas`, { method: 'POST', headers: Object.assign({ 'Content-Type': 'application/json' }, h), body: JSON.stringify({ expiresIn: 7 * 24 * 3600, paths }) });
      const firmados = rs.ok ? await rs.json() : [];
      const url = {}; (firmados || []).forEach(x => { if (x && x.path && x.signedURL) url[x.path] = `${sbUrl}/storage/v1${x.signedURL}`; });
      notas.forEach(n => (n.archivos || []).forEach(a => { if (a && url[a.path]) a.url = url[a.path]; }));
    }
    return notas;
  } catch (_) { return []; }
}

// Las fotos de cada incidencia (incidencias-fotos.sql, 18-nov), sumadas a la lista: sin la cuenta que subió cada una.
// firmar: con su link (vence en 7 días), para verlas en el link del informe; sin firmar (el PDF), el informe dice
// cuántas son. Sin el SQL (la columna no está), la lista queda como vino.
export async function fotosDeIncidencias(sbUrl, servicio, incidencias, firmar) {
  const l = incidencias || [];
  try {
    const h = { apikey: servicio, Authorization: `Bearer ${servicio}` };
    const ids = l.map(i => i && i.id).filter(Boolean), arch = {};
    for (let k = 0; k < ids.length; k += 100) {
      const r = await fetch(`${sbUrl}/rest/v1/incidencias?select=id,archivos&id=in.(${ids.slice(k, k + 100).join(',')})`, { headers: h });
      if (!r.ok) return l;
      (await r.json()).forEach(x => {
        if (x && Array.isArray(x.archivos) && x.archivos.length) arch[x.id] = x.archivos.filter(a => a && a.path).map(a => { const b = Object.assign({}, a); delete b.por; return b; });
      });
    }
    const paths = [...new Set(Object.values(arch).flat().map(a => a.path))];
    if (firmar && paths.length) {
      const rs = await fetch(`${sbUrl}/storage/v1/object/sign/incidencias`, { method: 'POST', headers: Object.assign({ 'Content-Type': 'application/json' }, h), body: JSON.stringify({ expiresIn: 7 * 24 * 3600, paths }) });
      const firmados = rs.ok ? await rs.json() : [];
      const url = {}; (firmados || []).forEach(x => { if (x && x.path && x.signedURL) url[x.path] = `${sbUrl}/storage/v1${x.signedURL}`; });
      Object.values(arch).flat().forEach(a => { if (url[a.path]) a.url = url[a.path]; });
    }
    return l.map(i => i && arch[i.id] ? Object.assign({}, i, { archivos: arch[i.id] }) : i);
  } catch (_) { return l; }
}

// El PDF (base64) de ese HTML, con Chromium: A4, con los fondos, como "Guardar como PDF".
// ejecutable: para probarlo en la compu (Edge o Chrome); en Vercel, el de @sparticuz/chromium.
export async function pdfDeHtml(html, ejecutable) {
  const puppeteer = (await import('puppeteer-core')).default;
  let args = [], executablePath = ejecutable, headless = true;
  if (!ejecutable) {
    const chromium = (await import('@sparticuz/chromium')).default;
    chromium.setGraphicsMode = false;
    args = await puppeteer.defaultArgs({ args: chromium.args, headless: 'shell' });
    executablePath = await chromium.executablePath();
    headless = 'shell';
  }
  const navegador = await puppeteer.launch({ args, executablePath, headless, defaultViewport: { width: 1240, height: 1754 } });
  try {
    const pag = await navegador.newPage();
    await pag.setContent(html, { waitUntil: 'networkidle0', timeout: 20000 });
    await pag.evaluate(() => document.fonts && document.fonts.ready);
    const pdf = await pag.pdf({ format: 'A4', printBackground: true, margin: { top: '10mm', right: '10mm', bottom: '10mm', left: '10mm' } });
    return Buffer.from(pdf).toString('base64');
  } finally {
    await navegador.close();
  }
}
