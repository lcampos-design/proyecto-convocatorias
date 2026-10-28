// El link para que cada uno actualice sus datos (convocatorias.show-bs.com/mis-datos).
//
// La persona pone su CUIL; si está inscripta, le llega un link a la casilla
// que dejó al inscribirse. Con el CUIL solo no alcanza para cambiar nada: si
// alcanzara, cualquiera podría cambiarle el CBU a otro. El link vence en 24
// horas y la base guarda sólo su huella (ver mis-datos.sql).
//
// Desde el panel, un admin también se lo puede mandar a alguien (por ejemplo,
// para que complete la fecha de nacimiento o los estudios): misma página,
// otro texto en el mail.
//
// Pedir el link necesita la clave de servidor de Supabase (la función que lo
// crea no la puede llamar nadie más) y la de Resend, para mandar el mail. Las
// dos van como variables de entorno en Vercel, nunca en el código.

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SB_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5rbW1pZnl6bGlpaW1tdGx6ZXFvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjM0MTAsImV4cCI6MjA5NjY5OTQxMH0.QU5JBRH_rbTzUu12oeWmCDmJv6B3UUVKPA5HyeuuzSg';
const SITIO = 'https://convocatorias.show-bs.com';
const ROLES_ADMIN = ['admin', 'admin_movistar', 'admin_externos'];

// Para invitar desde el panel: logueado y con ficha de admin.
async function verificarAdmin(req) {
  const token = String(req.headers['authorization'] || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return { ok: false, status: 401, error: 'Falta sesión de admin' };
  try {
    const userRes = await fetch(`${SB_URL}/auth/v1/user`, { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } });
    if (!userRes.ok) return { ok: false, status: 401, error: 'Sesión inválida o vencida' };
    const user = await userRes.json();
    const perfilRes = await fetch(`${SB_URL}/rest/v1/user_profiles?id=eq.${encodeURIComponent(user.id)}&select=rol`,
      { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } });
    if (!perfilRes.ok) return { ok: false, status: 403, error: 'No se pudo verificar el permiso' };
    const perfil = await perfilRes.json();
    const rol = Array.isArray(perfil) && perfil[0] ? perfil[0].rol : null;
    if (!ROLES_ADMIN.includes(rol)) return { ok: false, status: 403, error: 'Tu usuario no tiene permiso para mandar este link' };
    return { ok: true, user };
  } catch (_) {
    return { ok: false, status: 401, error: 'No se pudo validar la sesión' };
  }
}

// "maria.perez@gmail.com" → "ma***@gmail.com": que sepa a dónde fue, sin mostrar la casilla entera.
export function enmascarar(email) {
  const [u, dom] = String(email || '').split('@');
  if (!dom) return '';
  return u.slice(0, Math.min(2, u.length)) + '***@' + dom;
}

const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// El mail: corto, con el botón y la aclaración de que vence.
export function armarMail({ nombre, link, invitado }) {
  const hola = nombre ? `Hola, ${String(nombre).trim().split(/\s+/)[0]}` : 'Hola';
  const intro = invitado
    ? 'Necesitamos que revises y completes tus datos (la fecha de nacimiento, los estudios, la cuenta para pagarte…). Te lleva un par de minutos.'
    : 'Pediste cambiar tus datos de inscripción. Desde este link podés actualizarlos.';
  const text = `${hola}:\n\n${intro}\n\n${link}\n\nEl link es personal y vence en 24 horas. Si no lo pediste vos, ignorá este mail: tus datos no cambian.\n\nShow Business Solutions`;
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;margin:0 auto;color:#111827">
  <p style="font-size:15px">${esc(hola)}:</p>
  <p style="font-size:15px;line-height:1.5">${esc(intro)}</p>
  <p style="margin:24px 0"><a href="${esc(link)}" style="background:#534AB7;color:#fff;text-decoration:none;padding:12px 22px;border-radius:8px;font-weight:bold;display:inline-block">Actualizar mis datos</a></p>
  <p style="font-size:13px;color:#6b7280;line-height:1.5">El link es personal y vence en 24 horas. Si no lo pediste vos, ignorá este mail: tus datos no cambian.</p>
  <p style="font-size:13px;color:#6b7280">Show Business Solutions</p>
</div>`;
  return { subject: invitado ? 'Actualizá tus datos — Show Business Solutions' : 'Tu link para actualizar tus datos', text, html };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') { res.setHeader('Allow', 'POST'); return res.status(405).json({ error: 'Método no permitido' }); }
  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '', resend = process.env.RESEND_API_KEY || '';
  if (!servicio || !resend) return res.status(500).json({ error: 'Falta configurar el servidor (SUPABASE_SERVICE_ROLE_KEY o RESEND_API_KEY en Vercel)' });

  const cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
  const cuit = String(cuerpo.cuit || '').replace(/\D/g, '');
  if (cuit.length !== 11) return res.status(400).json({ error: 'El CUIL tiene que tener 11 números.' });
  const invitado = !!cuerpo.invitar;
  let pedidoPor = 'persona';
  if (invitado) {
    const auth = await verificarAdmin(req);
    if (!auth.ok) return res.status(auth.status).json({ error: auth.error });
    pedidoPor = auth.user.email || 'admin';
  }

  // El link (lo crea la base; esta función sólo la puede usar el servidor).
  let r;
  try {
    const resp = await fetch(`${SB_URL}/rest/v1/rpc/mis_datos_link`, {
      method: 'POST',
      headers: { 'apikey': servicio, 'Authorization': `Bearer ${servicio}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_cuit: cuit, p_pedido_por: pedidoPor })
    });
    r = await resp.json();
    if (!resp.ok) return res.status(500).json({ error: 'No se pudo crear el link' + (r && r.message ? ': ' + r.message : '') });
  } catch (err) {
    return res.status(500).json({ error: 'No se pudo crear el link' });
  }
  if (!r || !r.ok) {
    const m = r && r.motivo;
    if (m === 'no_encontrado') return res.status(404).json({ error: invitado ? 'Esa persona no tiene un mail cargado.' : 'No encontramos una inscripción con ese CUIL. Revisá los números o inscribite en el formulario.' });
    if (m === 'muchos') return res.status(429).json({ error: `Ya te mandamos varios links en la última hora a ${enmascarar(r.email)}. Revisá tu casilla (y el correo no deseado) o probá más tarde.` });
    if (m === 'ocupado') return res.status(429).json({ error: 'Estamos recibiendo muchos pedidos. Probá de nuevo en un rato.' });
    return res.status(400).json({ error: 'Revisá el CUIL.' });
  }

  // El mail, desde la casilla del área.
  const link = `${SITIO}/mis-datos?t=${encodeURIComponent(r.token)}`;
  const mail = armarMail({ nombre: r.nombre, link, invitado });
  const from = r.area === 'movistar_arena' ? 'convocatorias.arena@show-bs.com' : 'convocatorias.externos@show-bs.com';
  try {
    const envio = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${resend}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: [r.email], subject: mail.subject, text: mail.text, html: mail.html })
    });
    if (!envio.ok) return res.status(502).json({ error: 'No se pudo mandar el mail. Probá de nuevo en un rato.' });
  } catch (_) {
    return res.status(502).json({ error: 'No se pudo mandar el mail. Probá de nuevo en un rato.' });
  }
  return res.status(200).json({ ok: true, email: enmascarar(r.email) });
}
