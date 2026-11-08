// El código para firmar el contrato (convocatorias.show-bs.com/contrato).
//
// Al tocar "Firmar contrato", la página pide acá un código: la base lo crea
// (guarda sólo su huella) y este servidor lo manda al mail del contrato. La
// persona lo escribe en la página y recién ahí puede firmar (ver
// contrato-codigo.sql). Así firma quien tiene acceso a esa casilla, no
// cualquiera que tenga el link.
//
// Firmando desde el celular, ir al mail a copiar el código y volver era un
// lío (y a veces vencía): el mail trae un botón que vuelve al contrato con el
// código ya puesto. El código va después del "#", que no viaja al servidor
// ni queda en los registros; la página lo verifica y lo borra de la dirección.
// El link es siempre el del sitio (nunca el que diga el pedido), así nadie
// puede hacer que el mail apunte a otro lado.
//
// Necesita la clave de servidor de Supabase (la función que crea el código no
// la puede llamar nadie más) y la de Resend, para mandar el mail. Las dos van
// como variables de entorno en Vercel, nunca en el código.

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SITIO = 'https://convocatorias.show-bs.com';

// El link del botón: el contrato, con el código para que se verifique solo.
export function linkConCodigo(token, codigo) {
  return `${SITIO}/contrato?t=${encodeURIComponent(token)}#codigo=${encodeURIComponent(codigo)}`;
}

// "1 hora" / "15 minutos" (lo que diga la base; si no dice, los 15 de antes).
export function cuantoDura(minutos) {
  const m = Math.round(Number(minutos)) > 0 ? Math.round(Number(minutos)) : 15;
  if (m % 60 === 0) return m === 60 ? '1 hora' : (m / 60) + ' horas';
  return m + ' minutos';
}

// "maria.perez@gmail.com" → "ma***@gmail.com": que sepa a dónde fue, sin mostrar la casilla entera.
export function enmascarar(email) {
  const [u, dom] = String(email || '').split('@');
  if (!dom) return '';
  return u.slice(0, Math.min(2, u.length)) + '***@' + dom;
}

const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// El mail: el botón que vuelve al contrato con el código puesto; el código bien grande
// (y en el asunto, para verlo en el aviso del celular) por si lo escribe a mano; cuánto
// dura y qué hacer si no lo pidió.
// Sin contrato (sólo un documento, contrato-solo-documento.sql): el mail dice "documento".
export function armarMailCodigo({ nombre, codigo, link, minutos, documento }) {
  const D = s => documento ? s.replace(/contrato/g, 'documento') : s;
  const hola = nombre ? `Hola, ${String(nombre).trim().split(/\s+/)[0]}` : 'Hola';
  const separado = String(codigo).slice(0, 3) + ' ' + String(codigo).slice(3);
  const dura = cuantoDura(minutos);
  const text = `${hola}:\n\n` + (link ? `Para terminar de firmar tu contrato, entrá a este link (ya lleva el código):\n${link}\n\nO escribí el código en la página del contrato: ${separado}` : `Tu código para firmar el contrato es: ${separado}\n\nEscribilo en la página del contrato.`)
    + `\n\nVence en ${dura}.\n\nSi no estás firmando tu contrato, ignorá este mail: sin el código no se puede firmar.\n\nShow Business Solutions`;
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#111827">
  <p style="font-size:15px">${esc(hola)}:</p>` + (link ? `
  <p style="font-size:15px;line-height:1.5">Para terminar de firmar tu contrato, tocá el botón: vuelve al contrato con el código ya puesto.</p>
  <p style="margin:22px 0"><a href="${esc(link)}" style="display:inline-block;background:#0f1117;color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;padding:14px 26px;border-radius:10px">Volver al contrato y firmar</a></p>
  <p style="font-size:14px;line-height:1.5;color:#374151">O escribí este código en la página del contrato:</p>` : `
  <p style="font-size:15px;line-height:1.5">Tu código para firmar el contrato es:</p>`) + `
  <p style="margin:10px 0 18px;font-size:34px;font-weight:bold;letter-spacing:6px;color:#1a1a1a">${esc(separado)}</p>
  <p style="font-size:15px;line-height:1.5">Vence en ${esc(dura)}.</p>
  <p style="font-size:13px;color:#6b7280;line-height:1.5">Si no estás firmando tu contrato, ignorá este mail: sin el código no se puede firmar.</p>
  <p style="font-size:13px;color:#6b7280">Show Business Solutions</p>
</div>`;
  return { subject: D(`Tu código para firmar el contrato: ${separado}`), text: D(text), html: D(html) };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', resend = process.env.RESEND_API_KEY || '';
  if (!servicio || !resend) return res.status(500).json({ error: 'Ahora no podemos mandarte el código. Probá de nuevo más tarde.' });
  const cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
  const token = String(cuerpo.t || '').trim();
  if (!UUID.test(token)) return res.status(400).json({ error: 'El link no es válido.' });

  // El código (lo crea la base; esta función sólo la puede usar el servidor).
  let r;
  try {
    const resp = await fetch(`${SB_URL}/rest/v1/rpc/contrato_codigo_pedir`, {
      method: 'POST',
      headers: { 'apikey': servicio, 'Authorization': `Bearer ${servicio}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_token: token })
    });
    r = await resp.json();
    if (!resp.ok) return res.status(500).json({ error: 'No pudimos crear el código. Probá de nuevo en un rato.' });
  } catch (_) {
    return res.status(500).json({ error: 'No pudimos crear el código. Probá de nuevo en un rato.' });
  }
  if (!r || !r.ok) {
    const m = r && r.motivo;
    if (m === 'vencido') return res.status(410).json({ error: 'El link para firmar venció.', motivo: 'vencido' });
    if (m === 'ya_firmado') return res.status(409).json({ error: 'Este contrato ya está firmado.', motivo: 'ya_firmado' });
    if (m === 'sin_email') return res.status(400).json({ error: 'Tu contrato no tiene un mail cargado. Escribile a la coordinación.' });
    if (m === 'espera') return res.status(429).json({ error: `Ya te mandamos un código a ${enmascarar(r.email)}. Esperá un minuto para pedir otro.`, email: enmascarar(r.email), motivo: 'espera' });
    if (m === 'muchos') return res.status(429).json({ error: `Ya te mandamos varios códigos hoy a ${enmascarar(r.email)}. Revisá tu casilla (y el correo no deseado) o escribile a la coordinación.` });
    return res.status(404).json({ error: 'No encontramos este contrato.' });
  }

  // El mail, desde la casilla del área.
  const mail = armarMailCodigo({ nombre: r.nombre, codigo: r.codigo, link: linkConCodigo(token, r.codigo), minutos: r.minutos, documento: !!r.solo_documentos });
  const from = r.area === 'movistar_arena' ? 'convocatorias.arena@show-bs.com' : 'convocatorias.externos@show-bs.com';
  try {
    const envio = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${resend}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: [r.email], subject: mail.subject, text: mail.text, html: mail.html })
    });
    if (!envio.ok) return res.status(502).json({ error: 'No pudimos mandarte el código. Probá de nuevo en un rato.' });
  } catch (_) {
    return res.status(502).json({ error: 'No pudimos mandarte el código. Probá de nuevo en un rato.' });
  }
  return res.status(200).json({ ok: true, email: enmascarar(r.email), minutos: Number(r.minutos) > 0 ? Number(r.minutos) : 15 });
}
