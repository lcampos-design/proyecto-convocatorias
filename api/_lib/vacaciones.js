// La solicitud de vacaciones del personal corporativo (24-nov, Thomas): los mails del circuito.
// Lo llama api/mis-datos.js (Vercel está en el tope de funciones): { vacaciones: 'codigo', email } o
// { vacaciones: 'aviso', id }. La base (vacaciones.sql) decide qué toca y devuelve los links; acá sólo se manda.
//
//  · codigo: el código de 6 números para entrar, al mail de la persona.
//  · aviso: una vez por paso. Jefe o RR. HH.: a quien firma, con su link (va sola al jefe del área) y, la primera
//    vez, a la persona (que la recibimos). Nueva (un área que no está en la lista): a RR. HH., para derivarla.
//    Al final, a la persona con el PDF firmado, con copia al jefe y a las casillas de la config ('copias').
//    Cancelada o cambiada (antes de que firmen): a quien la tenía para firmar, si hace falta.
// Quién aprueba (los mails) está en la base (config 'vacaciones'), no en el código.

import { armarMail, SITIO } from './mail-sbs.js';
export { armarMail };

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
// Sale de la casilla general de RR. HH. y Legales, y las respuestas van ahí (25-nov, Thomas: "que sea el área general,
// no individualicemos en una persona"). Quien firma por RR. HH. (config 'rrhh') recibe sólo los mails para firmar.
const RRHH_GENERAL = 'rrhh@show-bs.com';
const DE = 'Recursos Humanos · SBS <' + RRHH_GENERAL + '>';

const DIAS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
export function fechaCorta(f) { const d = new Date(String(f).slice(0, 10) + 'T12:00:00'); return isNaN(d) ? String(f || '') : DIAS[d.getDay()] + ' ' + d.getDate() + '/' + (d.getMonth() + 1) + '/' + d.getFullYear(); }
// Los tramos como filas de datos: [['Tramo 1', 'del lun 4/1/2027 al dom 17/1/2027 · 14 días'], …, ['Total', '21 días corridos']].
export function filasTramos(datos) {
  const t = (datos && datos.tramos) || [];
  return t.map((x, i) => ['Tramo ' + (i + 1), 'Del ' + fechaCorta(x.desde) + ' al ' + fechaCorta(x.hasta) + ' · ' + x.dias + ' días'])
    .concat([['Total', ((datos && datos.total) || 0) + ' días corridos']],
      // Lo que pasa de 14 es sin goce de sueldo (25-nov): lo pidió y lo firmó la persona.
      ((datos && datos.total) || 0) > 14 ? [['Sin goce de sueldo', (datos.total - 14) + ' días (los que pasan de 14), sujetos a aprobación']] : []);
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

const KICKER = 'Vacaciones 2026/2027';
// La fecha en que mandó la que modifica ("24/11"), en hora de Argentina.
const diaMes = f => { const d = new Date(f); return isNaN(d) ? '' : d.toLocaleDateString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires', day: 'numeric', month: 'numeric' }); };
const reemplaza = a => a.datos && a.datos.reemplaza;
const avisos = a => ((a.datos && a.datos.avisos) || []).map(x => ['Aviso', x]).concat(a.datos && a.datos.nota ? [['Nota', a.datos.nota]] : []);
// Los mails de cada paso (separados para poder verlos sin mandarlos). Un mail por persona (25-nov, Thomas): a quien
// firma le llega uno, con el nombre de la persona de título; el texto no repite el título ni lo de arriba.
export const MAILS = {
  codigo: codigo => armarMail({ kicker: KICKER, titulo: 'Tu código', hola: 'Hola', parrafos: ['Usá este código para entrar a la solicitud:'], codigo,
    pie: 'Vence en 30 minutos. Si no lo pediste vos, ignorá este mail.' }),
  // Sólo si eligió un área que no está en la lista: RR. HH. la deriva desde el panel.
  nuevaRrhh: a => armarMail({ kicker: KICKER, titulo: a.nombre, hola: 'Hola',
    parrafos: [reemplaza(a) ? `Cambió la solicitud que mandó el ${diaMes(reemplaza(a).fecha)} y la volvió a firmar (la anterior quedó cancelada).`
      : a.fuera_de_lista ? `Mandó su solicitud, firmada, con un área que no está en la lista: ${a.area}.` : `Mandó su solicitud, firmada (${a.area}).`,
      'Derivala desde el panel al jefe que corresponde, o elegí "Su jefe directo es RR. HH.".'],
    datos: filasTramos(a.datos).concat(avisos(a)), boton: 'Derivarla en el panel', link: `${SITIO}/admin#vacaciones` }),
  // A la persona, la primera vez: a quién le llegó y que la puede cambiar hasta que la firmen.
  recibida: a => armarMail({ kicker: KICKER, titulo: reemplaza(a) ? 'Recibimos el cambio' : 'Recibimos tu solicitud', hola: 'Hola, ' + primerNombre(a.nombre),
    parrafos: [(reemplaza(a) ? 'La anterior quedó cancelada. ' : '') + (a.paso === 'jefe' ? 'Le llegó a tu jefe directo para que la apruebe; después la firma RR. HH.'
      : a.paso === 'rrhh' ? (a.es_jefe ? 'Como sos jefe de área, dependés de RR. HH.: le llegó directo para que la apruebe y la firme.' : 'Le llegó a RR. HH. (tu jefe directo) para que la apruebe y la firme.') : 'RR. HH. se la manda a tu jefe directo para que la apruebe.')],
    datos: filasTramos(a.datos), boton: 'Ver mi solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.ver)}`,
    pie: 'Las fechas quedan sujetas a la confirmación de RR. HH. según tu saldo. Hasta que la firmen, la podés modificar o cancelar desde la página; al final te llega el PDF con todas las firmas.' }),
  // A quien la tenía para firmar: la canceló, o la cambió y la nueva va a otro lado.
  cancelada: a => armarMail({ kicker: KICKER, titulo: a.nombre, hola: 'Hola',
    parrafos: a.reemplazada
      ? ['Cambió su solicitud antes de que la firmaras, y el link que te mandamos quedó sin efecto. Si la nueva te toca a vos, te llega otro mail.']
      : ['Canceló su solicitud, y el link para firmarla quedó sin efecto. No hace falta hacer nada.'],
    datos: [['Área', a.area]].concat(a.reemplazada ? filasTramos(a.datos).map(([k, v]) => [k + ' (la anterior)', v]) : filasTramos(a.datos), a.motivo ? [['Motivo', a.motivo]] : []) }),
  // A quien firma: el jefe ("es de tu equipo") o RR. HH. ("su jefe ya la aprobó"; o "es de tu equipo", si su jefe directo es RR. HH.).
  firmar: a => armarMail({ kicker: KICKER, titulo: a.nombre, hola: 'Hola',
    parrafos: [(a.es_jefe && a.paso === 'rrhh' ? 'Es jefe de área, depende de vos, y ya firmó su solicitud.' : (a.equipo != null ? a.equipo : (a.paso === 'jefe' || !a.con_jefe)) ? 'Es de tu equipo y ya firmó su solicitud.' : `Ya firmó su solicitud y su jefe directo${a.jefe_nombre ? ', ' + a.jefe_nombre + ',' : ''} la aprobó.`)
      + (reemplaza(a) ? ` Es un cambio de la que mandó el ${diaMes(reemplaza(a).fecha)}: el link anterior ya no sirve.` : ''),
      'Firmá vos para aprobarla (o no).' + (a.paso === 'jefe' ? ' Después le llega a RR. HH.' : ' Al firmar, le llega el PDF con todas las firmas.')],
    datos: [['Área', a.area]].concat(filasTramos(a.datos), avisos(a)), boton: 'Ver y firmar', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.token)}`,
    pie: (a.paso === 'rrhh' ? 'Revisá el saldo: si se tomó días a cuenta, aprobala con un comentario con los días que le quedan, o no la apruebes para que mande otra. ' : '') + 'El link es personal y vence en 30 días.' }),
  // Al final, a la persona (con copia a quien firmó antes y a las casillas de RR. HH., legales y socios).
  // A la persona, cuando su jefe la aprueba (25-nov, Thomas: que le vaya llegando cómo va): ahora le toca a RR. HH.
  avance: a => armarMail({ kicker: KICKER, titulo: 'Tu jefe la aprobó', hola: 'Hola, ' + primerNombre(a.nombre),
    parrafos: [(a.jefe_nombre ? a.jefe_nombre + ' la firmó como tu jefe directo.' : 'Tu jefe directo ya la firmó.') + ' Ahora le llega a RR. HH. para la firma final.'],
    datos: filasTramos(a.datos), boton: 'Ver mi solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.avance)}`,
    pie: 'Cuando firme RR. HH., te llega el PDF con todas las firmas.' }),
  fin: a => { const si = a.estado === 'aprobada';
    return armarMail({ kicker: KICKER, titulo: si ? 'Todo aprobado' : 'No aprobadas', hola: 'Hola, ' + primerNombre(a.nombre),
      parrafos: [si ? (a.con_jefe ? 'RR. HH. también la aprobó. ' : a.con_jefe === false ? 'RR. HH. la aprobó. ' : '') + 'Te mandamos adjunto el formulario con todas las firmas.' : 'Tu solicitud no fue aprobada.' + (a.nota ? '' : ' Si querés, mandá otra con otras fechas.')],
      datos: filasTramos(a.datos).concat(a.nota ? [['Comentario', a.nota]] : []), boton: 'Ver la solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.ver)}`,
      pie: si ? 'RR. HH. te confirma la fecha de pago del plus vacacional y del adelanto.' : 'Si tenés dudas, respondé este mail.' }); }
};

export async function manejarVacaciones(cuerpo, res, { servicio, resend }) {
  try {
    if (cuerpo.vacaciones === 'codigo') {
      const r = await rpc(servicio, 'vacaciones_codigo', { p_email: String(cuerpo.email || '') });
      if (!r || !r.ok) return res.status(400).json({ error: (r && r.error) || 'Revisá tu mail.' });
      const m = MAILS.codigo(r.codigo);
      const ok = await enviar(resend, { to: [r.email], reply_to: RRHH_GENERAL, subject: 'Tu código de vacaciones: ' + r.codigo, text: m.text, html: m.html });
      return ok ? res.status(200).json({ ok: true }) : res.status(502).json({ error: 'No se pudo mandar el código. Probá de nuevo en un rato.' });
    }
    if (cuerpo.vacaciones === 'aviso') {
      const a = await rpc(servicio, 'vacaciones_aviso', { p_id: String(cuerpo.id || '') });
      if (!a || !a.ok) return res.status(200).json({ ok: true, ya: true });   // ya salió ese aviso (o no hace falta)
      const asunto = 'Vacaciones - ' + a.nombre, enviados = [];
      // La confirmación a la persona (la primera vez que sale un aviso de su solicitud).
      // Cómo va, a la persona: su jefe la aprobó (sale con el aviso a RR. HH.).
      const avance = async () => { if (!a.avance) return; const c = MAILS.avance(a);
        enviados.push(await enviar(resend, { to: [a.email], reply_to: RRHH_GENERAL, subject: 'Tu jefe aprobó tus vacaciones', text: c.text, html: c.html })); };
      const confirmar = async () => { if (!a.ver || a.paso === 'fin') return; const c = MAILS.recibida(a);
        enviados.push(await enviar(resend, { to: [a.email], reply_to: RRHH_GENERAL, subject: 'Recibimos tu solicitud de vacaciones', text: c.text, html: c.html })); };
      if (a.paso === 'nueva') {
        const m = MAILS.nuevaRrhh(a);
        enviados.push(await enviar(resend, { to: [a.para], reply_to: a.email, subject: asunto, text: m.text, html: m.html }));
        await confirmar();
      } else if (a.paso === 'cancelada') {
        const m = MAILS.cancelada(a);
        enviados.push(await enviar(resend, { to: [a.para], reply_to: a.email, subject: asunto + (a.reemplazada ? ' (cambiada)' : ' (cancelada)'), text: m.text, html: m.html }));
      } else if (a.paso === 'jefe' || a.paso === 'rrhh') {
        const m = MAILS.firmar(a);
        enviados.push(await enviar(resend, { to: [a.para], reply_to: a.paso === 'jefe' ? RRHH_GENERAL : a.email, subject: asunto, text: m.text, html: m.html }));
        await confirmar();
        await avance();
      } else {
        const si = a.estado === 'aprobada', m = MAILS.fin(a);
        const adj = a.pdf ? [{ filename: 'Solicitud de vacaciones - ' + a.nombre + '.pdf', content: a.pdf }] : undefined;
        enviados.push(await enviar(resend, { to: [a.para], cc: (a.copia || []).filter(x => x && x !== a.para), reply_to: RRHH_GENERAL, subject: asunto + (si ? ' (aprobadas)' : ' (no aprobadas)'), text: m.text, html: m.html, attachments: adj }));
      }
      return res.status(200).json({ ok: enviados.every(Boolean), paso: a.paso });
    }
    return res.status(400).json({ error: 'Pedido desconocido' });
  } catch (_) {
    return res.status(502).json({ error: 'Ahora no pudimos mandarlo. Probá de nuevo en un rato.' });
  }
}
