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
export function tramosTexto(datos) {
  const t = (datos && datos.tramos) || [];
  return t.map((x, i) => 'Tramo ' + (i + 1) + ': del ' + fechaCorta(x.desde) + ' al ' + fechaCorta(x.hasta) + ' (' + x.dias + ' días corridos)');
}
const primerNombre = n => String(n || '').trim().split(/\s+/)[0] || '';

// El mail, con el mismo estilo que los de Mis datos: corto, con un botón.
export function armarMail({ hola, parrafos, boton, link, pie }) {
  const text = [hola + ':', ''].concat(parrafos.map(p => Array.isArray(p) ? p.map(x => '· ' + x).join('\n') : p), link ? ['', link] : [], ['', pie || '', 'Recursos Humanos · Show Business Solutions']).join('\n');
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:0 auto;color:#111827">
  <p style="font-size:15px">${esc(hola)}:</p>
  ${parrafos.map(p => Array.isArray(p) ? `<ul style="font-size:15px;line-height:1.6;padding-left:20px">${p.map(x => `<li>${esc(x)}</li>`).join('')}</ul>` : `<p style="font-size:15px;line-height:1.5">${esc(p)}</p>`).join('\n  ')}
  ${link ? `<p style="margin:24px 0"><a href="${esc(link)}" style="background:#1a1a1a;color:#fff;text-decoration:none;padding:12px 22px;border-radius:8px;font-weight:bold;display:inline-block">${esc(boton)}</a></p>` : ''}
  ${pie ? `<p style="font-size:13px;color:#6b7280;line-height:1.5">${esc(pie)}</p>` : ''}
  <p style="font-size:13px;color:#6b7280">Recursos Humanos · Show Business Solutions</p>
</div>`;
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

export async function manejarVacaciones(cuerpo, res, { servicio, resend }) {
  try {
    if (cuerpo.vacaciones === 'codigo') {
      const r = await rpc(servicio, 'vacaciones_codigo', { p_email: String(cuerpo.email || '') });
      if (!r || !r.ok) return res.status(400).json({ error: (r && r.error) || 'Revisá tu mail.' });
      const m = armarMail({ hola: 'Hola', parrafos: [`Tu código para entrar a la solicitud de vacaciones es ${r.codigo}.`, 'Vence en 30 minutos. Si no lo pediste vos, ignorá este mail.'] });
      const ok = await enviar(resend, { to: [r.email], subject: 'Tu código de vacaciones: ' + r.codigo, text: m.text, html: m.html });
      return ok ? res.status(200).json({ ok: true }) : res.status(502).json({ error: 'No se pudo mandar el código. Probá de nuevo en un rato.' });
    }
    if (cuerpo.vacaciones === 'aviso') {
      const a = await rpc(servicio, 'vacaciones_aviso', { p_id: String(cuerpo.id || '') });
      if (!a || !a.ok) return res.status(200).json({ ok: true, ya: true });   // ya salió ese aviso
      const asunto = 'Vacaciones - ' + a.nombre, tramos = tramosTexto(a.datos), total = (a.datos && a.datos.total) || 0;
      const enviados = [];
      if (a.paso === 'nueva') {
        // A RR. HH., para derivarla desde el panel; y a la persona, que la recibimos.
        const m = armarMail({ hola: 'Hola', parrafos: [`${a.nombre} (${a.area}) mandó su solicitud de vacaciones, firmada:`, tramos, `En total, ${total} días corridos.`,
          'Entrá al panel para derivarla al jefe que corresponde (o firmarla directamente, si depende de RR. HH.).'],
          boton: 'Derivarla en el panel', link: `${SITIO}/admin#vacaciones` });
        enviados.push(await enviar(resend, { to: [a.para], reply_to: a.email, subject: asunto, text: m.text, html: m.html }));
        const c = armarMail({ hola: 'Hola, ' + primerNombre(a.nombre), parrafos: ['Recibimos tu solicitud de vacaciones:', tramos,
          'RR. HH. se la manda a tu jefe directo para que la apruebe y la firme. Cuando esté, te llega el PDF firmado.'],
          boton: 'Ver mi solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.ver)}` });
        enviados.push(await enviar(resend, { to: [a.email], reply_to: a.rrhh, subject: 'Recibimos tu solicitud de vacaciones', text: c.text, html: c.html }));
      } else if (a.paso === 'jefe' || a.paso === 'rrhh') {
        const m = armarMail({ hola: 'Hola', parrafos: [`${a.nombre} (${a.area}) pidió vacaciones${a.paso === 'rrhh' && a.con_jefe ? ' y su jefe directo ya las aprobó' : ''}:`, tramos, `En total, ${total} días corridos.`,
          a.paso === 'jefe' ? 'Como su jefe directo, entrá para aprobarlas (o no) y firmar. Después le llega a RR. HH.' : 'Entrá para aprobarlas (o no) y firmar. Al terminar, le llega el PDF firmado a la persona.'],
          boton: 'Ver y firmar', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.token)}`, pie: 'El link es personal y vence en 30 días.' });
        enviados.push(await enviar(resend, { to: [a.para], reply_to: a.paso === 'jefe' ? a.rrhh : a.email, subject: asunto, text: m.text, html: m.html }));
      } else {
        const si = a.estado === 'aprobada';
        const m = armarMail({ hola: 'Hola, ' + primerNombre(a.nombre), parrafos: [si ? 'Tus vacaciones están aprobadas:' : 'Tu solicitud de vacaciones no fue aprobada:', tramos].concat(a.nota ? ['Comentario: ' + a.nota] : [],
          [si ? 'Te mandamos el formulario con las firmas. RR. HH. te confirma la fecha de pago del plus vacacional y el adelanto.' : 'Si tenés dudas, respondé este mail y lo vemos con RR. HH.']),
          boton: 'Ver la solicitud', link: `${SITIO}/vacaciones?t=${encodeURIComponent(a.ver)}` });
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
