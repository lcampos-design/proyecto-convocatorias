// La solicitud de vacaciones del personal corporativo (24-nov, Thomas): los mails del circuito.
// Lo llama api/mis-datos.js (Vercel está en el tope de funciones): { vacaciones: 'codigo', email } o
// { vacaciones: 'aviso', id }. La base (vacaciones.sql) decide qué toca y devuelve los links; acá sólo se manda.
//
//  · codigo: el código de 6 números para entrar, al mail de la persona.
//  · aviso: una vez por paso. Nueva: a RR. HH. (para derivarla desde el panel) y a la persona (que la recibimos).
//    Jefe o RR. HH.: a quien firma, con su link. Al final, a todos: aprobada o no, con el PDF firmado.
//    Cancelada (la persona, antes de que firmen): a RR. HH., con copia al jefe; modificada: sólo al jefe (su link no sirve más).
// Quién aprueba (los mails) está en la base (config 'vacaciones'), no en el código.

import { armarMail, SITIO } from './mail-sbs.js';
export { armarMail };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const DE = 'Recursos Humanos · SBS <rrhh@show-bs.com>';

const DIAS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
export function fechaCorta(f) { const d = new Date(String(f).slice(0, 10) + 'T12:00:00'); return isNaN(d) ? String(f || '') : DIAS[d.getDay()] + ' ' + d.getDate() + '/' + (d.getMonth() + 1) + '/' + d.getFullYear(); }
// Los tramos como filas de datos: [['Tramo 1', 'del lun 4/1/2027 al dom 17/1/2027 · 14 días'], …, ['Total', '21 días corridos']].
export function filasTramos(datos) {
  const t = (datos && datos.tramos) || [];
  return t.map((x, i) => ['Tramo ' + (i + 1), 'Del ' + fechaCorta(x.desde) + ' al ' + fechaCorta(x.hasta) + ' · ' + x.dias + ' días'])
    .concat([['Total', ((datos && datos.total) || 0) + ' días corridos']]);
}
const primerNombre = n => String(n || '').trim().split(/\s+/)[0] || '';

// El diseño de los mails (armarMail) está en mail-sbs.js, el mismo para todos los mails.

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
// La fecha en que mandó la que modifica ("24/11"), en hora de Argentina.
const diaMes = f => { const d = new Date(f); return isNaN(d) ? '' : d.toLocaleDateString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires', day: 'numeric', month: 'numeric' }); };
const reemplaza = a => a.datos && a.datos.reemplaza;
// Los mails de cada paso (separados para poder verlos sin mandarlos).
export const MAILS = {
  codigo: codigo => armarMail({ kicker: KICKER, titulo: 'Tu código', hola: 'Hola', parrafos: ['Para entrar a la solicitud de vacaciones, usá este código:'], codigo,
    pie: 'Vence en 30 minutos. Si no lo pediste vos, ignorá este mail.' }),
  nuevaRrhh: a => armarMail({ kicker: KICKER, titulo: reemplaza(a) ? 'Solicitud modificada' : 'Nueva solicitud', hola: 'Hola',
    parrafos: [reemplaza(a) ? `${a.nombre} modificó su solicitud de vacaciones (la que mandó el ${diaMes(reemplaza(a).fecha)}) y la volvió a firmar. La anterior quedó cancelada; ésta es la que vale.`
      : `${a.nombre} mandó su solicitud de vacaciones, firmada.`],
    datos: [['Persona', a.nombre], ['Área', a.area]].concat(filasTramos(a.datos), ((a.datos && a.datos.avisos) || []).map(x => ['Aviso', x])),
    boton: 'Derivarla en el panel', link: `${SITIO}/admin#vacaciones`, pie: 'Derivala al jefe que corresponde (o elegí "La firma sólo RR. HH.", si depende de RR. HH.).' }),
  recibida: a => armarMail({ kicker: KICKER, titulo: reemplaza(a) ? 'Recibimos el cambio' : 'Recibimos tu solicitud', hola: 'Hola, ' + primerNombre(a.nombre),
    parrafos: [reemplaza(a) ? 'Recibimos tu solicitud modificada, firmada. La anterior quedó cancelada:' : 'Recibimos tu solicitud de vacaciones, firmada:'],
    datos: filasTramos(a.datos), boton: 'Ver mi solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.ver)}`,
    pie: 'RR. HH. se la manda a tu jefe directo para que la apruebe y la firme. Hasta que firme, la podés modificar o cancelar desde la página. Cuando esté, te llega el PDF con todas las firmas.' }),
  // La canceló la persona: a RR. HH. (con copia al jefe, si ya la tenía). Si la modificó: sólo al jefe, que su link ya no sirve.
  cancelada: a => a.reemplazada
    ? armarMail({ kicker: KICKER, titulo: 'Solicitud modificada', hola: 'Hola',
        parrafos: [`${a.nombre} modificó su solicitud de vacaciones antes de que la firmaras. El link que te mandamos quedó sin efecto.`,
          'Cuando RR. HH. te derive la nueva, te llega otro mail para aprobarla y firmarla.'],
        datos: [['Persona', a.nombre], ['Área', a.area]].concat(filasTramos(a.datos).map(([k, v]) => [k + ' (anterior)', v])) })
    : armarMail({ kicker: KICKER, titulo: 'Solicitud cancelada', hola: 'Hola',
        parrafos: [`${a.nombre} canceló su solicitud de vacaciones.` + (a.copia && a.copia.length ? ' El link para firmarla quedó sin efecto.' : '')],
        datos: [['Persona', a.nombre], ['Área', a.area]].concat(filasTramos(a.datos), a.motivo ? [['Motivo', a.motivo]] : []),
        pie: 'No hace falta hacer nada más: queda registrada como cancelada, con su trazabilidad.' }),
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
      } else if (a.paso === 'cancelada') {
        const m = MAILS.cancelada(a);
        enviados.push(await enviar(resend, { to: [a.para], cc: (a.copia || []).filter(x => x && x !== a.para), reply_to: a.reemplazada ? a.rrhh : a.email,
          subject: asunto + (a.reemplazada ? ' (modificada)' : ' (cancelada)'), text: m.text, html: m.html }));
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
