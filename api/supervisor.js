// Alta y baja de supervisores.
//
// Crear o borrar una cuenta necesita la clave de servidor de Supabase, que no
// puede estar en el panel: el panel se descarga entero en el navegador de
// quien lo abre. Por eso pasa por acá, igual que el envío de correo.
//
// Antes esto se intentaba desde el panel con la clave pública, así que nunca
// funcionó; y la contraseña que generaba era al azar y no se mostraba en
// ningún lado, de modo que ni el admin ni el supervisor la sabían.
import { randomInt } from 'crypto';

const SB_URL = 'https://nkmmifyzliiimmtlzeqo.supabase.co';
const SB_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5rbW1pZnl6bGlpaW1tdGx6ZXFvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMjM0MTAsImV4cCI6MjA5NjY5OTQxMH0.QU5JBRH_rbTzUu12oeWmCDmJv6B3UUVKPA5HyeuuzSg';

const ROLES_PERMITIDOS = ['admin', 'admin_movistar', 'admin_externos'];

// Quien llama tiene que estar logueado Y tener ficha de admin. El panel decide
// el rol en el navegador, y ahí no se puede confiar.
async function verificarAdmin(req) {
  const token = String(req.headers['authorization'] || '').replace(/^Bearer\s+/i, '').trim();
  if (!token) return { ok: false, status: 401, error: 'Falta sesión de admin' };
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
      return { ok: false, status: 403, error: 'Tu usuario no tiene permiso para dar de alta supervisores' };
    }
    return { ok: true, user, rol };
  } catch (_) {
    return { ok: false, status: 401, error: 'No se pudo validar la sesión' };
  }
}

// Una contraseña que se pueda dictar por teléfono o pasar por WhatsApp sin
// que nadie se equivoque: sin la ele y el uno, sin la o y el cero, sin la i
// mayúscula. Doce caracteres, elegidos con el generador del sistema.
function generarClave() {
  const minus = 'abcdefghijkmnpqrstuvwxyz';
  const mayus = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const nums  = '23456789';
  const todos = minus + mayus + nums;
  // Se asegura al menos una de cada tipo, que es lo que suelen pedir las
  // reglas de contraseña, y el resto al azar.
  const chars = [
    minus[randomInt(minus.length)],
    mayus[randomInt(mayus.length)],
    nums[randomInt(nums.length)]
  ];
  while (chars.length < 12) chars.push(todos[randomInt(todos.length)]);
  // Mezcla, para que el orden no delate el patrón de arriba.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

const conServicio = clave => ({
  'apikey': clave,
  'Authorization': `Bearer ${clave}`,
  'Content-Type': 'application/json'
});

export default async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'DELETE') {
    res.setHeader('Allow', 'POST, DELETE');
    return res.status(405).json({ error: 'Método no permitido' });
  }

  const auth = await verificarAdmin(req);
  if (!auth.ok) return res.status(auth.status).json({ error: auth.error });

  const servicio = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
  if (!servicio) {
    return res.status(500).json({
      error: 'Falta configurar SUPABASE_SERVICE_ROLE_KEY en Vercel',
      detalle: 'Es la clave "service_role" de Supabase → Settings → API. Va como variable de entorno, nunca en el código.'
    });
  }

  const cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});

  // ── ALTA ──
  if (req.method === 'POST') {
    const email = String(cuerpo.email || '').trim().toLowerCase();
    const nombre = String(cuerpo.nombre || '').trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: 'El mail no parece válido' });
    if (!nombre) return res.status(400).json({ error: 'Falta el nombre' });

    const password = generarClave();
    const crear = await fetch(`${SB_URL}/auth/v1/admin/users`, {
      method: 'POST',
      headers: conServicio(servicio),
      body: JSON.stringify({ email, password, email_confirm: true })
    });
    const creado = await crear.json().catch(() => ({}));
    if (!crear.ok) {
      const msg = String(creado.msg || creado.message || creado.error_description || 'No se pudo crear el usuario');
      const yaExiste = /already|registered|exists/i.test(msg);
      return res.status(crear.status === 422 || yaExiste ? 409 : 500).json({
        error: yaExiste ? 'Ya existe un usuario con ese mail' : msg
      });
    }

    // La ficha es la que lo marca como supervisor. Si esto fallara, quedaría
    // una cuenta sin ficha, que para la base es un admin: por eso, si falla,
    // se borra la cuenta recién creada antes de contestar.
    const perfil = await fetch(`${SB_URL}/rest/v1/user_profiles`, {
      method: 'POST',
      headers: { ...conServicio(servicio), 'Prefer': 'return=minimal' },
      body: JSON.stringify({ id: creado.id, nombre, rol: 'supervisor' })
    });
    if (!perfil.ok) {
      await fetch(`${SB_URL}/auth/v1/admin/users/${creado.id}`, { method: 'DELETE', headers: conServicio(servicio) }).catch(() => {});
      return res.status(500).json({ error: 'Se creó la cuenta pero no la ficha. Se deshizo todo; probá de nuevo.' });
    }

    return res.status(200).json({ ok: true, id: creado.id, email, nombre, password });
  }

  // ── BAJA ──
  // Borrar sólo la ficha dejaba la cuenta viva y sin rol, y una cuenta sin
  // ficha, para la base, es un admin: el supervisor dado de baja terminaba
  // con más permisos que antes. Por eso se borra también la cuenta.
  const id = String(cuerpo.id || '').trim();
  if (!/^[0-9a-f-]{36}$/i.test(id)) return res.status(400).json({ error: 'Falta el id del supervisor' });
  if (id === auth.user.id) return res.status(400).json({ error: 'No podés borrarte a vos mismo' });

  const esSup = await fetch(`${SB_URL}/rest/v1/user_profiles?id=eq.${id}&select=rol`, { headers: conServicio(servicio) });
  const filas = await esSup.json().catch(() => []);
  const rol = Array.isArray(filas) && filas[0] ? filas[0].rol : null;
  if (rol !== 'supervisor') {
    return res.status(400).json({ error: 'Esa cuenta no es de un supervisor. Por acá sólo se dan de baja supervisores.' });
  }

  await fetch(`${SB_URL}/rest/v1/supervisor_convocatorias?supervisor_id=eq.${id}`, { method: 'DELETE', headers: conServicio(servicio) }).catch(() => {});
  await fetch(`${SB_URL}/rest/v1/user_profiles?id=eq.${id}`, { method: 'DELETE', headers: conServicio(servicio) }).catch(() => {});
  const borrar = await fetch(`${SB_URL}/auth/v1/admin/users/${id}`, { method: 'DELETE', headers: conServicio(servicio) });
  if (!borrar.ok) {
    return res.status(500).json({ error: 'Se borró la ficha pero no la cuenta. Borrala a mano en Supabase → Authentication.' });
  }

  return res.status(200).json({ ok: true });
}
