// Las fichas técnicas del Movistar Arena (24-nov-2026). El Arena carga una ficha por show en su app ("Ficha de
// Servicios", base44); la lista se lee sin usuario y el Arena dio el OK para leerla en automático (Thomas, 24-nov).
// Con cada ficha, el show del Centro de Control queda al día solo:
//   · el armado del campo, de la "configuración" (Campo Parados → campo único; Parado Dividido → delantero y trasero;
//     Sentado → con asientos). Si alguien lo cambió a mano en el panel, no se pisa;
//   · el horario (puertas e inicio) y el de cada fecha, si no lo tenían;
//   · un resumen de la ficha (convocatorias.ficha): horarios, orientadores que pide, cargas, acta de apertura,
//     capacidad, accesos y notas, prohibidos, menores, alcohol y emergencias; nunca los responsables ni sus datos;
//   · si de esa fecha no hay ningún show del Arena en el panel, se crea (en el Centro de Control, sin publicar).
// Lo usa api/calendario.js (?fichas=1): una vez por día (cron de Vercel) y cuando se abre el panel.

export const FICHAS_URL = 'https://ficha-de-servicios-movistar-arena-873f259f.base44.app/api/apps/6970147234be88a2873f259f/entities/FichaServicio?sort=-fecha_show';
export const FICHA_VER = 'https://ficha-de-servicios-movistar-arena-873f259f.base44.app/VerFicha?id=';

const norm = s => String(s == null ? '' : s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
const FECHA = /^\d{4}-\d{2}-\d{2}$/;

// El armado del campo según la configuración de la ficha (null: no es ninguno de los tres, no se toca).
export function armadoDeConfiguracion(t) {
  const s = norm(t);
  if (!s || /hielo/.test(s)) return null;
  if (/dividid/.test(s)) return 'campos';
  if (/parad/.test(s)) return 'unico';
  if (/sentad|ring|butaca/.test(s)) return 'asientos';
  return null;
}
// Las fechas: la del show, la segunda (fecha_show_fin) y la tercera.
export function fechasDeFicha(f) {
  return [...new Set([f && f.fecha_show, f && f.fecha_show_fin, f && f.fecha_show_tercera].map(x => String(x || '').slice(0, 10)).filter(x => FECHA.test(x)))].sort();
}
// El horario de la fecha i (0, 1 o 2): "Puertas 19:00 · Inicio 21:00".
export function horarioDeFicha(f, i) {
  const suf = i ? '_' + (i + 1) : '';
  const p = String((f && (f['horario_puertas' + suf] || f.horario_puertas)) || '').trim(), n = String((f && (f['horario_inicio' + suf] || f.horario_inicio)) || '').trim();
  return [p && 'Puertas ' + p, n && 'Inicio ' + n].filter(Boolean).join(' · ');
}
const num = v => { const n = Number(String(v == null ? '' : v).replace(/[^\d]/g, '')); return n > 0 ? n : null; };
const txt = (v, max) => { const t = String(v == null ? '' : v).trim(); return t ? t.slice(0, max || 400) : null; };
const nota = (f, k) => (f && f['mostrar_nota_' + k] !== false && txt(f['nota_' + k])) || null;
// Lo que se guarda de la ficha en el show (sin responsables, contactos ni quién la cargó).
export function resumenFicha(f) {
  const fechas = fechasDeFicha(f);
  const limpio = o => { Object.keys(o).forEach(k => { if (o[k] == null || o[k] === '' || (typeof o[k] === 'object' && !Array.isArray(o[k]) && !Object.keys(limpio(o[k])).length)) delete o[k]; }); return o; };
  return limpio({
    id: txt(f.id, 60), url: f.id ? FICHA_VER + encodeURIComponent(f.id) : null, actualizada: txt(f.updated_date, 40), estado: txt(f.estado, 40),
    artista: txt(f.artista, 120), productora: txt(f.productora, 120), configuracion: txt(f.configuracion, 120), armado: armadoDeConfiguracion(f.configuracion),
    fechas, horarios: fechas.map((d, i) => ({ fecha: d, texto: horarioDeFicha(f, i), fin: txt(f['horario_fin' + (i ? '_' + (i + 1) : '')] || f.horario_fin, 20) })),
    orientadores: num(f.staff_orientadores_general), orientadores_premium: num(f.staff_orientadores_premium), cargas: num(f.personal_cargas),
    acta_apertura: txt(f.personal_acta_apertura, 40), capacidad: num(f.capacidad_total), recursos_seguridad: num(f.recursos_seguridad),
    accesos: { campo: txt(f.acceso_campo, 120), platea_baja: txt(f.acceso_platea_baja, 120), platea_alta: txt(f.acceso_platea_alta, 120), premium: txt(f.acceso_premium, 120) },
    notas: { accesos: nota(f, 'accesos'), acreditaciones: nota(f, 'acreditaciones'), seguridad: nota(f, 'seguridad'), staff: nota(f, 'staff'), gastronomia: nota(f, 'gastronomia'), emergencias: nota(f, 'emergencias'), info: nota(f, 'info_importante') },
    elementos_prohibidos: txt(f.elementos_prohibidos), politica_menores: txt(f.politica_menores), limite_alcohol: txt(f.horario_limite_alcohol, 40),
    boleteria: txt(f.horario_boleteria, 60), acciones_especiales: txt(f.acciones_especiales), otros: txt(f.otros_comentarios),
    emergencias: { llegada: txt(f.emergencia_horario_llegada, 20), salida: txt(f.emergencia_horario_salida, 20), bomberos: txt(f.emergencia_bomberos, 120), medico: txt(f.emergencia_medico, 120), ambulancias: txt(f.emergencia_ambulancias, 40), socorrismo: txt(f.emergencia_socorrismo, 120) },
    ocupacion: { campo: num(f.ocupacion_campo_personas), platea_baja: num(f.ocupacion_platea_baja_personas), platea_alta: num(f.ocupacion_platea_alta_personas), premium: num(f.ocupacion_premium_personas) }
  });
}
// El nombre para un show nuevo: "ZZ TOP" → "ZZ Top", "LAS PASTILLAS DEL ABUELO" → "Las Pastillas del Abuelo".
const MINUS = new Set(['de', 'del', 'la', 'las', 'los', 'el', 'y', 'e', 'en', 'con', 'por', 'a']);
export function nombreDeArtista(a) {
  return String(a || '').trim().replace(/\s+/g, ' ').split(' ').map((w, i) => {
    const l = w.toLowerCase();
    if (i && MINUS.has(l)) return l;
    if (/\d/.test(w) || !/[aeiouáéíóú]/i.test(w)) return w.toUpperCase();
    return l.charAt(0).toUpperCase() + l.slice(1);
  }).join(' ');
}
const palabras = s => norm(s).split(' ').filter(w => w.length > 2 && !['movistar', 'arena', 'show', 'tour'].includes(w));
const fechasDeConv = c => String((c && c.fecha) || '').split(',').map(x => x.trim()).filter(x => FECHA.test(x));

// Qué hacer con cada ficha (sin efectos). convs: las del Arena (id, nombre, fecha, turnos, horario, armado_campo,
// centro_control, ficha). hoy: aaaa-mm-dd. Devuelve { cambios: [{ id, cambios, motivo }], crear: [fila], resumen }.
export function planFichas(fichas, convs, hoy) {
  const porId = new Map(), crear = [], usadas = new Set(), resumen = { fichas: 0, armados: 0, horarios: 0, nuevas: 0, sinShow: 0 };
  const cambiosDe = id => { if (!porId.has(id)) porId.set(id, { id, cambios: {}, motivo: [] }); return porId.get(id); };
  const lista = (fichas || []).filter(f => f && !f.is_sample && fechasDeFicha(f).length);
  // Las más nuevas primero (si hay dos fichas para la misma fecha, manda la última que se tocó).
  lista.sort((a, b) => String(b.updated_date || '').localeCompare(String(a.updated_date || '')));
  for (const f of lista) {
    const fechas = fechasDeFicha(f); if (fechas[fechas.length - 1] < hoy) continue;   // sólo lo que viene (y hoy)
    resumen.fichas++;
    const res = resumenFicha(f), w = palabras(f.artista);
    const delDia = convs.filter(c => fechasDeConv(c).some(d => fechas.includes(d)));
    if (!delDia.length) {
      if (fechas[0] < hoy) { resumen.sinShow++; continue; }
      const clave = fechas.join(','); if (usadas.has(clave)) continue; usadas.add(clave);
      crear.push({ nombre: nombreDeArtista(f.artista), fecha: fechas.join(','), area: 'movistar_arena', venue: 'Movistar Arena',
        descripcion: 'Show del Arena para el Centro de Control (creado con la ficha técnica del Arena).',
        turnos: fechas.map((d, i) => ({ fecha: d, horario: horarioDeFicha(f, i) })), horario: horarioDeFicha(f, 0) || null,
        publicada: false, disp_abierta: false, centro_control: true, armado_campo: res.armado || null, ficha: Object.assign({}, res, { tandas: [res] }) });
      resumen.nuevas++; continue;
    }
    // Si ese día hay más de un show del Arena (el del Centro de Control y la convocatoria de personal), van todos;
    // si hay dos shows distintos, el que comparte alguna palabra con el artista.
    const conPalabra = delDia.filter(c => palabras(c.nombre).some(x => w.includes(x)));
    const destino = delDia.length > 1 && conPalabra.length ? conPalabra : delDia;
    for (const c of destino) {
      if (usadas.has('c:' + c.id + ':' + fechas[0])) continue; usadas.add('c:' + c.id + ':' + fechas[0]);
      const x = cambiosDe(c.id), previa = (c.ficha && typeof c.ficha === 'object') ? c.ficha : null;
      // El resumen: de todas las fichas del show (María Becerra tiene tres), una por cada tanda de fechas.
      const fichasPrevias = previa && Array.isArray(previa.tandas) ? previa.tandas.filter(t => !fechas.some(d => (t.fechas || []).includes(d))) : previa && previa.id && !(previa.fechas || []).some(d => fechas.includes(d)) ? [previa] : [];
      const acumulada = x.cambios.ficha ? x.cambios.ficha.tandas.filter(t => t.id !== res.id) : fichasPrevias;
      const tandas = acumulada.concat([res]).sort((a, b) => String((a.fechas || [])[0]).localeCompare(String((b.fechas || [])[0])));
      const nueva = Object.assign({}, tandas.find(t => (t.fechas || []).some(d => d >= hoy)) || res, { tandas });
      if (JSON.stringify(nueva) !== JSON.stringify(previa)) { x.cambios.ficha = nueva; x.motivo.push('ficha'); }
      // El armado: si no tenía, o si tenía el que decía la ficha antes (nadie lo cambió a mano).
      if (c.centro_control && res.armado && c.armado_campo !== res.armado && (!c.armado_campo || (previa && c.armado_campo === previa.armado))) {
        if (!x.cambios.armado_campo) { x.cambios.armado_campo = res.armado; x.motivo.push('armado'); resumen.armados++; }
      }
      // Los horarios que faltan.
      if (!String(c.horario || '').trim() && horarioDeFicha(f, 0) && !x.cambios.horario) { x.cambios.horario = horarioDeFicha(f, 0); x.motivo.push('horario'); resumen.horarios++; }
      const turnos = Array.isArray(x.cambios.turnos) ? x.cambios.turnos : Array.isArray(c.turnos) ? c.turnos : null;
      if (turnos && turnos.some(t => t && fechas.includes(t.fecha) && !String(t.horario || '').trim() && !t.nombre)) {
        x.cambios.turnos = turnos.map(t => t && fechas.includes(t.fecha) && !String(t.horario || '').trim() && !t.nombre ? Object.assign({}, t, { horario: horarioDeFicha(f, fechas.indexOf(t.fecha)) }) : t);
        if (!x.motivo.includes('turnos')) x.motivo.push('turnos');
      }
    }
  }
  return { cambios: [...porId.values()].filter(x => Object.keys(x.cambios).length), crear, resumen };
}
