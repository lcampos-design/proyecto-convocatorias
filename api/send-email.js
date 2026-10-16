// Misma anon key pública que usa el cliente (admin.html) — no es secreta,
// el acceso real está protegido por RLS en Supabase. Se usa acá solo para
// validar, contra Supabase Auth, que quien llama a este endpoint tiene una
// sesión de admin logueada (evita que cualquiera que conozca esta URL
// pueda mandar mail con la cuenta de Resend de la organización).
const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SB_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5rbW1pZnl6bGlpaW1tdGx6ZXFvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjM0MTAsImV4cCI6MjA5NjY5OTQxMH0.QU5JBRH_rbTzUu12oeWmCDmJv6B3UUVKPA5HyeuuzSg';

// Sólo se puede enviar DESDE estas casillas. Sin esta lista, cualquiera con una
// sesión válida puede mandar correo haciéndose pasar por la empresa.
const REMITENTES_PERMITIDOS = [
  'convocatorias.arena@show-bs.com',
  'convocatorias.externos@show-bs.com'
];
// Tope de destinatarios por llamada: el panel manda de a uno (incluso en el envío
// masivo, que itera). Un pedido con más es señal de abuso, no de uso normal.
const MAX_DESTINATARIOS = 5;
// Roles que pueden enviar correo. Los supervisores no: sólo ven sus convocatorias.
const ROLES_PERMITIDOS = ['admin', 'admin_movistar', 'admin_externos'];

// Acepta 'casilla@dominio' o 'Nombre <casilla@dominio>'.
function casillaDe(remitente) {
  const m = String(remitente || '').match(/<([^>]+)>\s*$/);
  return (m ? m[1] : String(remitente || '')).trim().toLowerCase();
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') { res.status(200).end(); return; }
  if (req.method !== 'POST') { res.status(405).json({ error: 'Method not allowed' }); return; }

  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) { res.status(401).json({ error: 'Falta sesión de admin (Authorization)' }); return; }
  try {
    const userRes = await fetch(`${SB_URL}/auth/v1/user`, {
      headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY }
    });
    if (!userRes.ok) { res.status(401).json({ error: 'Sesión inválida o vencida' }); return; }
    const user = await userRes.json();

    // No alcanza con estar logueado: hay que tener ficha de admin en user_profiles.
    // Sin esta comprobación, cualquier cuenta autenticada podía enviar correo
    // (el panel decide el rol en el navegador, y ahí no se puede confiar).
    const perfilRes = await fetch(
      `${SB_URL}/rest/v1/user_profiles?id=eq.${encodeURIComponent(user.id)}&select=rol`,
      { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } }
    );
    if (!perfilRes.ok) { res.status(403).json({ error: 'No se pudo verificar el permiso' }); return; }
    const perfil = await perfilRes.json();
    const rol = Array.isArray(perfil) && perfil[0] ? perfil[0].rol : null;
    if (!ROLES_PERMITIDOS.includes(rol)) {
      res.status(403).json({ error: 'Tu usuario no tiene permiso para enviar correo' }); return;
    }
  } catch (_) {
    res.status(401).json({ error: 'No se pudo validar la sesión' }); return;
  }

  const { from, to, subject, text, html, attachments } = req.body;
  if (!from || !to || !subject || !text) {
    res.status(400).json({ error: 'Faltan campos requeridos' }); return;
  }

  if (!REMITENTES_PERMITIDOS.includes(casillaDe(from))) {
    res.status(403).json({ error: 'Remitente no permitido' }); return;
  }
  const destinatarios = Array.isArray(to) ? to : [to];
  if (!destinatarios.length || destinatarios.length > MAX_DESTINATARIOS) {
    res.status(400).json({ error: `Cantidad de destinatarios inválida (máximo ${MAX_DESTINATARIOS})` }); return;
  }

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.RESEND_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from, to, subject, text,
        ...(html ? { html } : {}),
        ...(Array.isArray(attachments) && attachments.length ? { attachments } : {})
      })
    });

    const data = await response.json();
    if (!response.ok) { res.status(response.status).json(data); return; }
    res.status(200).json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}
