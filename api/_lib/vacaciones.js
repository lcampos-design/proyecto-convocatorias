// La solicitud de vacaciones del personal corporativo (24-nov, Thomas): los mails del circuito.
// Lo llama api/mis-datos.js (Vercel está en el tope de funciones): { vacaciones: 'codigo', email } o
// { vacaciones: 'aviso', id }. La base (vacaciones.sql) decide qué toca y devuelve los links; acá sólo se manda.
//
//  · codigo: el código de 6 números para entrar, al mail de la persona.
//  · aviso: una vez por paso. Nueva: a RR. HH. (para derivarla desde el panel) y a la persona (que la recibimos).
//    Jefe o RR. HH.: a quien firma, con su link. Al final, a todos: aprobada o no, con el PDF firmado.
// Quién aprueba (los mails) está en la base (config 'vacaciones'), no en el código.

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SITIO = 'https://convocatorias.show-bs.com';
const DE = 'Recursos Humanos · SBS <rrhh@show-bs.com>';

const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const DIAS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
export function fechaCorta(f) { const d = new Date(String(f).slice(0, 10) + 'T12:00:00'); return isNaN(d) ? String(f || '') : DIAS[d.getDay()] + ' ' + d.getDate() + '/' + (d.getMonth() + 1) + '/' + d.getFullYear(); }
// Los tramos como filas de datos: [['Tramo 1', 'del lun 4/1/2027 al dom 17/1/2027 · 14 días'], …, ['Total', '21 días corridos']].
export function filasTramos(datos) {
  const t = (datos && datos.tramos) || [];
  return t.map((x, i) => ['Tramo ' + (i + 1), 'Del ' + fechaCorta(x.desde) + ' al ' + fechaCorta(x.hasta) + ' · ' + x.dias + ' días'])
    .concat([['Total', ((datos && datos.total) || 0) + ' días corridos']]);
}
const primerNombre = n => String(n || '').trim().split(/\s+/)[0] || '';

// El mail, con el estilo del informe del Arena y el template de SBS (24-nov, Thomas): la barra negra finita, el logo
// horizontal y show-bs.com, la línea gris; arriba, de qué es (en gris) y el título en mayúsculas; los datos en filas;
// el botón negro; abajo, la línea de la marca y la leyenda de RR. HH. Con tablas, que es lo que respetan todos los
// clientes de correo; Poppins para quien la tenga y, si no, una parecida.
export function armarMail({ kicker, titulo, hola, parrafos, datos, codigo, boton, link, pie }) {
  const F = "Poppins,'Segoe UI',Helvetica,Arial,sans-serif";
  const P = `margin:0 0 14px;font-size:15px;line-height:1.6;color:#2b2b2b;font-family:${F}`;
  const filas = (datos || []).filter(Boolean).map(([k, v]) => `<tr><td style="padding:10px 12px 10px 0;border-bottom:1px solid #e6e6e6;font-size:13px;color:#6b6b6b;vertical-align:top;width:120px;font-family:${F}">${esc(k)}</td>`
    + `<td style="padding:10px 0;border-bottom:1px solid #e6e6e6;font-size:15px;color:#1a1a1a;font-family:${F}">${esc(v)}</td></tr>`).join('');
  const html = `<div style="background:#ffffff;margin:0;padding:24px 12px;font-family:${F};color:#1a1a1a">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;margin:0 auto;border-collapse:collapse">
  <tr><td style="border-top:4px solid #1a1a1a;padding:22px 0 16px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
      <td><img src="${SITIO}/logo-sbs-horizontal.png" width="170" height="33" alt="SBS Show Business Solutions" style="display:block;border:0;width:170px;height:33px"></td>
      <td align="right" style="font-size:13px;font-weight:600;color:#2b2b2b;font-family:${F}">show-bs.com</td>
    </tr></table>
  </td></tr>
  <tr><td style="border-top:1px solid #9a9a9a;padding:28px 0 0">
    ${kicker ? `<div style="font-size:11px;font-weight:600;letter-spacing:.09em;text-transform:uppercase;color:#6b6b6b;font-family:${F}">${esc(kicker)}</div>` : ''}
    ${titulo ? `<div style="font-size:26px;line-height:1.15;font-weight:700;text-transform:uppercase;color:#1a1a1a;margin:6px 0 22px;font-family:${F}">${esc(titulo)}</div>` : ''}
    ${hola ? `<p style="${P}">${esc(hola)}:</p>` : ''}
    ${(parrafos || []).map(p => `<p style="${P}">${esc(p)}</p>`).join('\n    ')}
    ${codigo ? `<div style="margin:6px 0 22px;padding:18px 10px;border-radius:12px;background:#f2f2f2;text-align:center;font-size:34px;font-weight:700;letter-spacing:12px;color:#1a1a1a;font-family:${F}">${esc(codigo)}</div>` : ''}
    ${filas ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:4px 0 22px;border-top:1px solid #e6e6e6">${filas}</table>` : ''}
    ${link ? `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:6px 0 20px"><tr><td style="background:#1a1a1a;border-radius:10px"><a href="${esc(link)}" style="display:inline-block;padding:14px 26px;color:#ffffff;text-decoration:none;font-size:15px;font-weight:600;font-family:${F}">${esc(boton)}</a></td></tr></table>` : ''}
    ${pie ? `<p style="margin:0 0 6px;font-size:12.5px;line-height:1.55;color:#6b6b6b;font-family:${F}">${esc(pie)}</p>` : ''}
  </td></tr>
  <tr><td style="padding:30px 0 0">
    <div style="border-top:1px solid #d9d9d9;padding-top:14px;text-align:center;font-size:10.5px;font-weight:600;letter-spacing:.06em;color:#8a8a8a;font-family:${F}">SHOW BUSINESS SOLUTIONS · show-bs.com · HANDS ON EVERYTHING</div>
    <div style="text-align:center;font-size:11px;color:#9a9a9a;margin-top:4px;font-family:${F}">Proyecto llevado a cabo por la Gerencia de RR. HH.</div>
  </td></tr>
</table>
</div>`;
  const text = [kicker ? kicker.toUpperCase() : '', titulo ? titulo.toUpperCase() : '', ''].concat(hola ? [hola + ':', ''] : [], (parrafos || []).flatMap(p => [p, '']),
    codigo ? [codigo, ''] : [], (datos || []).filter(Boolean).map(([k, v]) => k + ': ' + v), datos && datos.length ? [''] : [], link ? [boton + ': ' + link, ''] : [], pie ? [pie, ''] : [],
    ['Recursos Humanos · Show Business Solutions']).join('\n').replace(/^\n+/, '');
  return { text, html };
}

async function rpc(servicio, nombre, cuerpo) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${nombre}`, { method: 'POST', headers: { apikey: servicio, Authorization: `Bearer ${servicio}`, 'Content-Type': 'application/json' }, body: JSON.stringify(cuerpo) });
  const d = await r.json().catch(() => null);
  if (!r.ok) throw new Error((d && d.message) || 'base');
  return d;
}
// Resend admite 2 pedidos por segundo: si pide ir más despacio, se espera y se prueba otra vez.
async function enviar(resend, mail) {
  for (let intento = 0; intento < 3; intento++) {
    const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: `Bearer ${resend}`, 'Content-Type': 'application/json' }, body: JSON.stringify(Object.assign({ from: DE }, mail)) });
    if (r.ok) return true;
    if (r.status !== 429) return false;
    await new Promise(ok => setTimeout(ok, 1200));
  }
  return false;
}

const KICKER = 'Recursos Humanos · Vacaciones 2026/2027';
// Los mails de cada paso (separados para poder verlos sin mandarlos).
export const MAILS = {
  codigo: codigo => armarMail({ kicker: KICKER, titulo: 'Tu código', hola: 'Hola', parrafos: ['Para entrar a la solicitud de vacaciones, usá este código:'], codigo,
    pie: 'Vence en 30 minutos. Si no lo pediste vos, ignorá este mail.' }),
  nuevaRrhh: a => armarMail({ kicker: KICKER, titulo: 'Nueva solicitud', hola: 'Hola', parrafos: [`${a.nombre} mandó su solicitud de vacaciones, firmada.`],
    datos: [['Persona', a.nombre], ['Área', a.area]].concat(filasTramos(a.datos), ((a.datos && a.datos.avisos) || []).map(x => ['Aviso', x])),
    boton: 'Derivarla en el panel', link: `${SITIO}/admin#vacaciones`, pie: 'Derivala al jefe que corresponde (o elegí "La firma sólo RR. HH.", si depende de RR. HH.).' }),
  recibida: a => armarMail({ kicker: KICKER, titulo: 'Recibimos tu solicitud', hola: 'Hola, ' + primerNombre(a.nombre), parrafos: ['Recibimos tu solicitud de vacaciones, firmada:'],
    datos: filasTramos(a.datos), boton: 'Ver mi solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.ver)}`,
    pie: 'RR. HH. se la manda a tu jefe directo para que la apruebe y la firme. Cuando esté, te llega el PDF con todas las firmas.' }),
  firmar: a => armarMail({ kicker: KICKER, titulo: 'Vacaciones para aprobar', hola: 'Hola',
    parrafos: [a.paso === 'jefe' ? `${a.nombre} pidió vacaciones. Como su jefe directo, entrá para aprobarlas (o no) y firmar. Después le llega a RR. HH.`
      : `${a.nombre} pidió vacaciones${a.con_jefe ? ' y su jefe directo ya las aprobó' : ''}. Entrá para aprobarlas (o no) y firmar. Al terminar, le llega el PDF firmado.`],
    datos: [['Persona', a.nombre], ['Área', a.area]].concat(filasTramos(a.datos)), boton: 'Ver y firmar', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.token)}`,
    pie: 'El link es personal y vence en 30 días.' }),
  fin: a => { const si = a.estado === 'aprobada';
    return armarMail({ kicker: KICKER, titulo: si ? 'Vacaciones aprobadas' : 'Vacaciones no aprobadas', hola: 'Hola, ' + primerNombre(a.nombre),
      parrafos: [si ? 'Tus vacaciones están aprobadas. Te mandamos el formulario con todas las firmas.' : 'Tu solicitud de vacaciones no fue aprobada.'],
      datos: filasTramos(a.datos).concat(a.nota ? [['Comentario', a.nota]] : []), boton: 'Ver la solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.ver)}`,
      pie: si ? 'RR. HH. te confirma la fecha de pago del plus vacacional y el adelanto.' : 'Si tenés dudas, respondé este mail y lo vemos con RR. HH.' }); }
};

export async function manejarVacaciones(cuerpo, res, { servicio, resend }) {
  try {
    if (cuerpo.vacaciones === 'codigo') {
      const r = await rpc(servicio, 'vacaciones_codigo', { p_email: String(cuerpo.email || '') });
      if (!r || !r.ok) return res.status(400).json({ error: (r && r.error) || 'Revisá tu mail.' });
      const m = MAILS.codigo(r.codigo);
      const ok = await enviar(resend, { to: [r.email], subject: 'Tu código de vacaciones: ' + r.codigo, text: m.text, html: m.html });
      return ok ? res.status(200).json({ ok: true }) : res.status(502).json({ error: 'No se pudo mandar el código. Probá de nuevo en un rato.' });
    }
    if (cuerpo.vacaciones === 'aviso') {
      const a = await rpc(servicio, 'vacaciones_aviso', { p_id: String(cuerpo.id || '') });
      if (!a || !a.ok) return res.status(200).json({ ok: true, ya: true });   // ya salió ese aviso
      const asunto = 'Vacaciones - ' + a.nombre, enviados = [];
      if (a.paso === 'nueva') {
        // A RR. HH., para derivarla desde el panel; y a la persona, que la recibimos.
        const m = MAILS.nuevaRrhh(a), c = MAILS.recibida(a);
        enviados.push(await enviar(resend, { to: [a.para], reply_to: a.email, subject: asunto, text: m.text, html: m.html }));
        enviados.push(await enviar(resend, { to: [a.email], reply_to: a.rrhh, subject: 'Recibimos tu solicitud de vacaciones', text: c.text, html: c.html }));
      } else if (a.paso === 'jefe' || a.paso === 'rrhh') {
        const m = MAILS.firmar(a);
        enviados.push(await enviar(resend, { to: [a.para], reply_to: a.paso === 'jefe' ? a.rrhh : a.email, subject: asunto, text: m.text, html: m.html }));
      } else {
        const si = a.estado === 'aprobada', m = MAILS.fin(a);
        const adj = a.pdf ? [{ filename: 'Solicitud de vacaciones - ' + a.nombre + '.pdf', content: a.pdf }] : undefined;
        enviados.push(await enviar(resend, { to: [a.para], cc: (a.copia || []).filter(x => x && x !== a.para), reply_to: a.rrhh, subject: asunto + (si ? ' (aprobadas)' : ' (no aprobadas)'), text: m.text, html: m.html, attachments: adj }));
      }
      return res.status(200).json({ ok: enviados.every(Boolean), paso: a.paso });
    }
    return res.status(400).json({ error: 'Pedido desconocido' });
  } catch (_) {
    return res.status(502).json({ error: 'Ahora no pudimos mandarlo. Probá de nuevo en un rato.' });
  }
}
