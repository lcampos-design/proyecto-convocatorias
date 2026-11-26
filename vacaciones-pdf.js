// El PDF de la solicitud de vacaciones (24-nov), con el template de SBS (el Word de la marca) y el informe de auditoría.
// Lo usan la página (/vacaciones: al firmar, el PDF final) y el panel (26-nov: bajar el PDF hasta el momento, con las
// firmas que tenga). Necesita pdf-lib y fontkit. Las condiciones viven acá: son las mismas en la página y en el PDF.
(function () {
const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const dos = n => String(n).padStart(2, '0');
const fechaDMA = f => { const [a, m, d] = String(f).slice(0, 10).split('-'); return d && m && a ? d + '/' + m + '/' + a : ''; };
const fechaLarga = f => { const d = new Date(String(f).slice(0, 10) + 'T12:00:00'); return isNaN(d) ? '' : DIAS[d.getDay()] + ' ' + fechaDMA(f); };
const fechaHora = iso => { const d = new Date(iso); return isNaN(d) ? '' : dos(d.getDate()) + '/' + dos(d.getMonth() + 1) + '/' + d.getFullYear() + ' ' + dos(d.getHours()) + ':' + dos(d.getMinutes()); };
const ESTADOS = { nueva: 'Esperando que RR. HH. la derive', jefe: 'Esperando al jefe directo', rrhh: 'Esperando a RR. HH.', aprobada: 'Aprobada', rechazada: 'No aprobada', cancelada: 'Cancelada' };
const estadoTxt = (estado, socios) => estado === 'rrhh' && socios ? 'Esperando a los socios' : ESTADOS[estado];
const DIAS_VAC = 14, sinGoce = total => Math.max(0, (Number(total) || 0) - DIAS_VAC);
const nDias = n => n + (Number(n) === 1 ? ' día' : ' días');
const CONDICIONES = ['Te corresponden 14 días corridos. Todo queda sujeto a la confirmación de RR. HH. según tu saldo: si entraste este año o ya te tomaste días a cuenta, los días se pueden acortar.',
  'Si pedís más de 14 días, los que pasan son sin goce de sueldo y quedan sujetos a la aprobación de tu jefe directo y RR. HH.',
  'Cada tramo dura 7 días corridos o más y empieza un lunes o el primer día hábil de la semana. Si necesitás uno más corto (por un acuerdo con tu jefe, por ejemplo), lo podés pedir igual y queda sujeto a aprobación.',
  'Pedilas con al menos 30 días de anticipación. Si falta menos, la podés mandar igual y queda sujeta a aprobación.',
  'Las aprueba tu jefe directo y/o RR. HH. No se aprueban fechas con eventos de tu área.',
  // 24-nov, Mercedes: "con respecto a la cobertura en la ofi, hay prioridad por antigüedad y se tiene que cubrir el cupo mínimo por área".
  'Cada área tiene que mantener su cobertura mínima: si varios piden las mismas fechas, tiene prioridad el de mayor antigüedad.',
  'Plus vacacional + adelanto de vacaciones: las vacaciones se cobran antes de salir.'];
const PASOS_TIPO = { creada: 'Firmó la solicitud', aviso: 'Mail enviado', derivada: 'Derivada', abierta: 'Abrió para firmar', firmada: 'Firmó', pdf: 'PDF guardado', reenviada: 'Link reenviado', cancelada: 'Cancelada', reemplazada: 'Modificada' };
const uaCorto = ua => { const s = String(ua || ''); if (!s) return ''; if (/^Sistema/.test(s)) return s;
  const nav = /Edg\//.test(s) ? 'Edge' : /OPR\//.test(s) ? 'Opera' : /Chrome\//.test(s) ? 'Chrome' : /Firefox\//.test(s) ? 'Firefox' : /Safari\//.test(s) ? 'Safari' : 'Navegador';
  const so = /iPhone|iPad/.test(s) ? 'iPhone/iPad' : /Android/.test(s) ? 'Android' : /Windows/.test(s) ? 'Windows' : /Mac OS X/.test(s) ? 'Mac' : /Linux/.test(s) ? 'Linux' : '';
  return nav + (so ? ' · ' + so : ''); };

async function bytesDe(url) { const r = await fetch(url); if (!r.ok) throw new Error(url); return new Uint8Array(await r.arrayBuffer()); }
async function armarPdf(d) {
  const { PDFDocument, rgb } = PDFLib;
  const pdf = await PDFDocument.create(); pdf.registerFontkit(fontkit);
  const [reg, neg, logo] = await Promise.all([bytesDe('/fuentes/Poppins-Regular.ttf'), bytesDe('/fuentes/Poppins-SemiBold.ttf'), bytesDe('/logo-sbs-horizontal.png')]);
  const R = await pdf.embedFont(reg, { subset: true }), N = await pdf.embedFont(neg, { subset: true }), L = await pdf.embedPng(logo);
  const M = 50, W = 595.28 - 2 * M, negro = rgb(.1, .1, .1), gris = rgb(.36, .36, .36), linea = rgb(.6, .6, .6), suave = rgb(.83, .83, .83);
  const ancho = (s, f, t) => f.widthOfTextAtSize(String(s), t);
  const partir = (s, f, t, w) => { const out = []; let l = ''; String(s).split(/\s+/).forEach(p => { const n = l ? l + ' ' + p : p; if (ancho(n, f, t) > w && l) { out.push(l); l = p; } else l = n; }); if (l) out.push(l); return out; };
  // Cada página: el logo, show-bs.com y la línea gris arriba (el template); abajo, la línea de la marca.
  const hoja = (titulo1, titulo2, sub) => {
    const pag = pdf.addPage([595.28, 841.89]); let y = 841.89 - 42;
    const txt = (s, x, yy, f, t, c) => pag.drawText(String(s), { x, y: yy, font: f, size: t, color: c || negro });
    const lh = 26, lw = lh * L.width / L.height; pag.drawImage(L, { x: M, y: y - lh, width: lw, height: lh });
    txt('show-bs.com', M + W - ancho('show-bs.com', N, 10), y - lh + 6, N, 10, rgb(.17, .17, .17));
    y -= lh + 14; pag.drawLine({ start: { x: M, y }, end: { x: M + W, y }, thickness: .8, color: linea });
    y -= 44; txt(titulo1, M, y, N, 22); if (titulo2) { y -= 26; txt(titulo2, M, y, N, 22); }
    y -= 18; txt(sub, M, y, R, 11, rgb(.17, .17, .17));
    pag.drawLine({ start: { x: M, y: 44 }, end: { x: M + W, y: 44 }, thickness: .5, color: linea });
    const marca = 'SHOW BUSINESS SOLUTIONS  ·  show-bs.com  ·  HANDS ON EVERYTHING';
    txt(marca, M + (W - ancho(marca, N, 7.5)) / 2, 32, N, 7.5, gris);
    return { pag, txt, get y() { return y; }, set y(v) { y = v; } };
  };
  const h1 = hoja('SOLICITUD', 'DE VACACIONES', 'Temporada 2026/2027 · Recursos Humanos'); let pag = h1.pag, txt = h1.txt;
  let y = h1.y;
  const titulo = s => { y -= 26; txt(s, M, y, N, 10.5); y -= 7; pag.drawLine({ start: { x: M, y }, end: { x: M + W, y }, thickness: .5, color: suave }); y -= 4; };
  const fila = (k, v) => { y -= 16; txt(k, M, y, R, 9.5, gris); txt(v, M + 150, y, R, 10); };
  titulo('1. DATOS');
  fila('Nombre y apellido', d.nombre); fila('Área', d.area); fila('Mail', d.email); fila('Fecha de solicitud', fechaDMA(d.datos.fecha || d.creada));
  titulo('2. FECHAS QUE PIDE');
  y -= 16; [['Desde', 150], ['Hasta', 300], ['Días corridos', 415]].forEach(([s, x]) => txt(s, M + x, y, N, 9.5, gris));
  (d.datos.tramos || []).forEach((t, i) => { y -= 16; txt('Tramo ' + (i + 1), M, y, N, 10); txt(fechaLarga(t.desde), M + 150, y, R, 10); txt(fechaLarga(t.hasta), M + 300, y, R, 10); txt(String(t.dias), M + 415, y, N, 10); });
  y -= 16; txt('Total', M, y, N, 10); txt(String(d.datos.total), M + 415, y, N, 10);
  if (sinGoce(d.datos.total)) { y -= 14; txt(`De esos, ${nDias(sinGoce(d.datos.total))} sin goce de sueldo (por encima de los ${DIAS_VAC}), como lo pide y firma la persona.`, M, y, R, 8.8); }
  y -= 14; txt('Sujeto a la confirmación de RR. HH. según el saldo de la persona (si ya se tomó días a cuenta, se pueden acortar).', M, y, R, 8.8, gris);
  (d.datos.avisos || []).forEach(a => { y -= 14; txt('Aviso: ' + a, M, y, R, 8.5, rgb(.54, .38, 0)); });
  if (d.datos.nota) partir('Nota de la persona: ' + String(d.datos.nota).replace(/\s+/g, ' '), R, 8.8, W).forEach(l => { y -= 13; txt(l, M, y, R, 8.8); });
  titulo('3. CONDICIONES');
  CONDICIONES.forEach(c => partir('· ' + c, R, 8.5, W).forEach(l => { y -= 11; txt(l, M, y, R, 8.5, gris); }));   // 8.5/11: entra un comentario largo sin pisar el pie
  // Si las firmas (con los comentarios) no entran sin pisar el pie, van en una hoja propia: pasa con una nota larga y avisos.
  const alto = 150 + ([(d.firmas || {}).jefe, (d.firmas || {}).rrhh].some(x => x && x.nota) ? 42 : 0);   // el bloque de las firmas, con o sin comentarios
  if (y - alto < 84) { const h = hoja('SOLICITUD', 'DE VACACIONES', 'Las firmas · ' + d.nombre); pag = h.pag; txt = h.txt; y = h.y; }
  titulo('4. FIRMAS');
  const f = d.firmas || {}, sinJefe = !d.con_jefe, col = (W - 24) / 3, top = y - 8;
  const caja = async (i, tit, fi, dec, vacia) => {
    const x = M + i * (col + 12); let yy = top - 14;
    txt(tit, x, yy, N, 9.5);
    if (dec) { yy -= 14; const box = (bx, on, s) => { pag.drawRectangle({ x: bx, y: yy - 1, width: 8, height: 8, borderColor: negro, borderWidth: .7 }); if (on) { pag.drawLine({ start: { x: bx + 1.5, y: yy + 3 }, end: { x: bx + 3.5, y: yy + .8 }, thickness: 1.2, color: negro }); pag.drawLine({ start: { x: bx + 3.5, y: yy + .8 }, end: { x: bx + 7, y: yy + 6.5 }, thickness: 1.2, color: negro }); } txt(s, bx + 11, yy, R, 8.5); };
      box(x, fi && fi.decision === 'aprobado', 'Aprobado'); box(x + 70, fi && fi.decision === 'no_aprobado', 'No aprobado'); }
    else { yy -= 14; txt('Solicito las fechas indicadas.', x, yy, R, 8.5); }
    if (fi && fi.png) { const img = await pdf.embedPng(fi.png); const h = 46, w = Math.min(col, h * img.width / img.height); pag.drawImage(img, { x, y: yy - 8 - h, width: w, height: h }); }
    else txt(vacia || 'Pendiente', x, yy - 34, R, 8.5, gris);
    yy -= 57; pag.drawLine({ start: { x, y: yy + 4 }, end: { x: x + col, y: yy + 4 }, thickness: .5, color: linea });
    yy -= 8; partir('Aclaración: ' + (fi ? fi.aclaracion : ''), R, 8.5, col).forEach(l => { txt(l, x, yy, R, 8.5); yy -= 11; });
    txt('Fecha: ' + (fi ? fechaHora(fi.fecha) : ''), x, yy, R, 8.5);
    if (fi && fi.nota) { yy -= 11; partir('Comentario: ' + fi.nota, R, 8, col).slice(0, 3).forEach(l => { txt(l, x, yy, R, 8, gris); yy -= 10; }); }
  };
  await caja(0, 'EMPLEADO/A', f.empleado, false);
  // Las de quien firma por RR. HH.: las aprueban los socios (dos firmas: la persona y uno de los socios).
  if (d.socios) await caja(1, 'SOCIOS', f.rrhh, true);
  else if (d.servicio) await caja(1, 'RR. HH.', f.rrhh, true);   // los servicios fijos: RR. HH. directo
  else {
    await caja(1, 'JEFE DIRECTO', f.jefe || (sinJefe && f.rrhh ? Object.assign({}, f.rrhh, { nota: '' }) : null), true, sinJefe ? 'Firma RR. HH.' : 'Pendiente');
    await caja(2, 'RR. HH.', f.rrhh, true);
  }
  const pie = ['Firmada electrónicamente en convocatorias.show-bs.com. El informe de auditoría con la trazabilidad de cada firma está en la página siguiente.', 'ID de la solicitud: ' + (d.transaccion_id || d.id) + ' · ' + estadoTxt(d.estado, d.socios) + '.'];
  let yp = 70; pie.forEach(p => partir(p, R, 7.5, W).forEach(l => { txt(l, M, yp, R, 7.5, gris); yp -= 9.5; }));
  // Página 2: el informe de auditoría (como el de los contratos).
  const h2 = hoja('INFORME DE AUDITORÍA', '', 'Solicitud de vacaciones · ' + d.nombre);
  let y2 = h2.y; const t2 = h2.txt, p2 = h2.pag;
  const fila2 = (k, v) => { const ls = partir(v, R, 9.5, W - 150); y2 -= 15; t2(k, M, y2, R, 9, gris); ls.forEach((l, i) => { if (i) y2 -= 12; t2(l, M + 150, y2, R, 9.5); }); };
  y2 -= 16; fila2('ID de la solicitud', d.transaccion_id || d.id); fila2('Huella del contenido', d.hash || '');
  fila2('Estado', estadoTxt(d.estado, d.socios)); fila2('Método', d.socios ? 'La persona entra con un código enviado a su mail; uno de los socios firma con el link enviado a los mails de los socios o entrando con un código enviado a su mail.' : d.servicio ? 'La persona entra con un código enviado a su mail; RR. HH. firma con un link personal enviado a su mail o entrando con un código enviado a su mail.' : 'La persona entra con un código enviado a su mail; el jefe directo y RR. HH. firman con links personales enviados a su mail o entrando con un código enviado a su mail.');
  y2 -= 26; t2('PASOS', M, y2, N, 10.5); y2 -= 7; p2.drawLine({ start: { x: M, y: y2 }, end: { x: M + W, y: y2 }, thickness: .5, color: suave });
  y2 -= 16; [['Fecha y hora', 0], ['Paso', 92], ['Detalle', 190]].forEach(([s, x]) => t2(s, M + x, y2, N, 8.5, gris));
  for (const e of d.eventos || []) {
    if (y2 < 90) break;
    const det = [e.quien, e.detalle].filter(Boolean).join(' · '), ext = [e.ip ? 'IP ' + e.ip : '', uaCorto(e.user_agent)].filter(Boolean).join(' · ');
    const ls = partir(det, R, 8.3, W - 190).concat(ext ? partir(ext, R, 7.6, W - 190).map(l => '\u0000' + l) : []);
    y2 -= 6; p2.drawLine({ start: { x: M, y: y2 + 2 }, end: { x: M + W, y: y2 + 2 }, thickness: .3, color: rgb(.9, .9, .9) }); y2 -= 10;
    t2(fechaHora(e.fecha), M, y2, R, 8.3); t2(PASOS_TIPO[e.tipo] || e.tipo, M + 92, y2, N, 8.3);
    ls.forEach((l, i) => { if (i) y2 -= 10.5; const chico = l[0] === '\u0000'; t2(chico ? l.slice(1) : l, M + 190, y2, R, chico ? 7.6 : 8.3, chico ? gris : negro); });
  }
  const b64 = await pdf.saveAsBase64();
  return { base64: b64, nombre: 'Solicitud de vacaciones - ' + d.nombre + '.pdf' };
}

window.VacPdf = { CONDICIONES, armar: armarPdf };
})();
