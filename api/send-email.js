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

// Quien llama tiene que estar logueado Y tener ficha de admin en user_profiles.
// El panel decide el rol en el navegador, y ahí no se puede confiar.
async function verificarAdmin(req) {
  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return { ok: false, status: 401, error: 'Falta sesión de admin (Authorization)' };
  try {
    const userRes = await fetch(`${SB_URL}/auth/v1/user`, {
      headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY }
    });
    if (!userRes.ok) return { ok: false, status: 401, error: 'Sesión inválida o vencida' };
    const user = await userRes.json();

    const perfilRes = await fetch(
      `${SB_URL}/rest/v1/user_profiles?id=eq.${encodeURIComponent(user.id)}&select=rol`,
      { headers: { 'Authorization': `Bearer ${token}`, 'apikey': SB_ANON_KEY } }
    );
    if (!perfilRes.ok) return { ok: false, status: 403, error: 'No se pudo verificar el permiso' };
    const perfil = await perfilRes.json();
    const rol = Array.isArray(perfil) && perfil[0] ? perfil[0].rol : null;
    if (!ROLES_PERMITIDOS.includes(rol)) {
      return { ok: false, status: 403, error: 'Tu usuario no tiene permiso para enviar correo' };
    }
    return { ok: true, user, rol };
  } catch (_) {
    return { ok: false, status: 401, error: 'No se pudo validar la sesión' };
  }
}

// Una clave con permiso "Sending access" sirve para mandar pero no para
// consultar dominios: Resend contesta 401 con este nombre. No es un error.
function esClaveRestringida(cuerpo) {
  const n = (cuerpo && cuerpo.name) || '';
  const m = (cuerpo && cuerpo.message) || '';
  return n === 'restricted_api_key' || /restricted/i.test(m);
}

// ── Diagnóstico ───────────────────────────────────────────────
// Dice por qué no salen los mails sin exponer la clave. Son tres causas
// posibles y cada una se arregla en un lugar distinto; sin esto hay que
// adivinar entre las tres.
async function diagnostico(res) {
  const clave = process.env.RESEND_API_KEY || '';
  if (!clave) {
    res.status(200).json({
      estado: 'sin_clave',
      titulo: 'No hay clave de Resend configurada',
      detalle: 'En Vercel falta la variable de entorno RESEND_API_KEY. Hay que crearla y volver a desplegar.'
    });
    return;
  }
  if (!clave.startsWith('re_')) {
    res.status(200).json({
      estado: 'clave_rara',
      titulo: 'La clave configurada no parece de Resend',
      detalle: 'El valor de RESEND_API_KEY no empieza con "re_". Puede haber quedado un espacio, comillas o un valor pegado de otro lado.'
    });
    return;
  }
  try {
    const r = await fetch('https://api.resend.com/domains', {
      headers: { 'Authorization': `Bearer ${clave}` }
    });
    const cuerpo = await r.json().catch(() => ({}));

    if (r.status === 401 || r.status === 403) {
      if (esClaveRestringida(cuerpo)) {
        res.status(200).json({
          estado: 'ok',
          titulo: 'La clave funciona',
          detalle: 'Es una clave de sólo envío, así que no se puede verificar el dominio desde acá. Si un envío falla, el error va a decir el motivo.'
        });
        return;
      }
      res.status(200).json({
        estado: 'clave_invalida',
        titulo: 'Resend rechaza la clave',
        detalle: 'La clave que hay en Vercel fue revocada o está mal copiada. Hay que generar una nueva en Resend, reemplazarla en Vercel y volver a desplegar.'
      });
      return;
    }

    const dominios = (cuerpo.data || []).map(d => ({ nombre: d.name, estado: d.status }));
    const verificado = dominios.find(d => /show-bs\.com$/i.test(d.nombre || '') && d.estado === 'verified');
    if (verificado) {
      res.status(200).json({ estado: 'ok', titulo: 'El envío de mails está funcionando', dominios });
      return;
    }
    const existe = dominios.find(d => /show-bs\.com$/i.test(d.nombre || ''));
    res.status(200).json({
      estado: existe ? 'dominio_sin_verificar' : 'sin_dominio',
      titulo: existe ? 'El dominio show-bs.com no está verificado' : 'show-bs.com no está cargado en esta cuenta de Resend',
      detalle: existe
        ? `Figura como "${existe.estado}". Hasta que Resend verifique los registros DNS, no deja enviar desde @show-bs.com.`
        : 'La clave es válida pero pertenece a una cuenta de Resend donde no está dado de alta el dominio show-bs.com.',
      dominios
    });
  } catch (err) {
    res.status(200).json({ estado: 'error', titulo: 'No se pudo consultar a Resend', detalle: err.message });
  }
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') { res.status(200).end(); return; }
  if (req.method !== 'POST' && req.method !== 'GET') {
    res.status(405).json({ error: 'Method not allowed' }); return;
  }

  const chk = await verificarAdmin(req);
  if (!chk.ok) { res.status(chk.status).json({ error: chk.error }); return; }

  if (req.method === 'GET') { await diagnostico(res); return; }

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

  if (!process.env.RESEND_API_KEY) {
    res.status(500).json({ error: 'El servidor no tiene configurada la clave de Resend (RESEND_API_KEY en Vercel).' });
    return;
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
    if (!response.ok) {
      // "API key is invalid" sin más contexto no le dice a nadie dónde mirar.
      if (response.status === 401 || response.status === 403) {
        res.status(response.status).json({
          error: 'Resend rechazó la clave: hay que generar una nueva y cargarla en Vercel como RESEND_API_KEY. Probá el diagnóstico desde el Dashboard.',
          resend: data
        });
        return;
      }
      res.status(response.status).json(data);
      return;
    }
    res.status(200).json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}
