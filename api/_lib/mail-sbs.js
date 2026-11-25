// El diseño de los mails de SBS (24-nov, Thomas: "estilo como el informe del Arena", con el template de SBS).
// Lo usan los mails de vacaciones, del contrato (por presente, por período, el recordatorio, el código) y el de
// "mis datos". admin.html tiene su copia (renderEmailHtml) para los que salen desde el panel: si cambia uno, cambiar el otro.
//
// Arriba, la barra negra finita, el logo horizontal y show-bs.com, la línea gris; después, de qué es (en gris) y el
// título; el texto, los datos en filas, el botón negro; la firma de RR. HH. y, abajo, la leyenda de RR. HH. Con
// tablas, que es lo que respetan todos los clientes de correo; Poppins para quien la tenga y, si no, una parecida.
// Sin mayúsculas sostenidas ni repeticiones (25-nov, Thomas): el título no repite lo de arriba, el texto no repite el
// título, y el pie no repite la marca (ya está en el encabezado).

export const SITIO = 'https://convocatorias.show-bs.com';
export const FIRMA_RRHH = `${SITIO}/firmas/firma-rrhh.jpg`;
const F = "Poppins,'Segoe UI',Helvetica,Arial,sans-serif";
export const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Las piezas (cada una ya en HTML).
export const parrafo = t => `<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:#2b2b2b;font-family:${F}">${esc(t)}</p>`;
export const botonHtml = (texto, link) => `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 18px"><tr><td style="background:#1a1a1a;border-radius:10px"><a href="${esc(link)}" style="display:inline-block;padding:14px 26px;color:#ffffff;text-decoration:none;font-size:15px;font-weight:600;font-family:${F}">${esc(texto)}</a></td></tr></table>`;
export const copiarHtml = link => `<p style="margin:0 0 14px;font-size:12.5px;line-height:1.55;color:#6b6b6b;font-family:${F};overflow-wrap:anywhere;word-break:break-all">O copiá este link: <a href="${esc(link)}" style="color:#1a1a1a;text-decoration:underline">${esc(link)}</a></p>`;
export const codigoHtml = c => `<div style="margin:6px 0 20px;padding:18px 10px;border-radius:12px;background:#f2f2f2;text-align:center;font-size:34px;font-weight:700;letter-spacing:10px;color:#1a1a1a;font-family:${F}">${esc(c)}</div>`;
export const pieHtml = t => `<p style="margin:0 0 6px;font-size:12.5px;line-height:1.55;color:#6b6b6b;font-family:${F}">${esc(t)}</p>`;
export function filasHtml(datos) {
  const f = (datos || []).filter(Boolean).map(([k, v]) => `<tr><td style="padding:10px 12px 10px 0;border-bottom:1px solid #e6e6e6;font-size:13px;color:#6b6b6b;vertical-align:top;width:120px;font-family:${F}">${esc(k)}</td>`
    + `<td style="padding:10px 0;border-bottom:1px solid #e6e6e6;font-size:15px;color:#1a1a1a;font-family:${F}">${esc(v)}</td></tr>`).join('');
  return f ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:4px 0 22px;border-top:1px solid #e6e6e6">${f}</table>` : '';
}

// Poppins (25-nov, Thomas): la cargan Mail de iPhone y Mac, Samsung y Thunderbird; Gmail y Outlook no cargan
// tipografías de afuera y usan la que sigue en la lista. Va escondida para Outlook de Windows, que si la ve
// pasa todo a Times New Roman.
export const POPPINS = `<!--[if !mso]><!--><style>@import url('https://fonts.googleapis.com/css2?family=Poppins:wght@400;600;700&display=swap');</style><!--<![endif]-->`;
// "show-bs.com" como link, con su color: si no, Gmail lo pone azul y subrayado.
const sitioSBS = color => `<a href="https://show-bs.com" style="color:${color};text-decoration:none">show-bs.com</a>`;

// El marco: cuerpo (HTML) entre el encabezado y el pie. firma: la imagen de la firma (la de RR. HH.), o nada.
export function marcoMail({ kicker, titulo, cuerpo, firma, instagram }) {
  return `${POPPINS}<div style="background:#ffffff;margin:0;padding:24px 12px;font-family:${F};color:#1a1a1a">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;margin:0 auto;border-collapse:collapse">
  <tr><td style="border-top:4px solid #1a1a1a;padding:22px 0 16px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
      <td><img src="${SITIO}/logo-sbs-horizontal.png" width="170" height="33" alt="SBS Show Business Solutions" style="display:block;border:0;width:170px;height:33px"></td>
      <td align="right" style="font-size:13px;font-weight:600;color:#2b2b2b;font-family:${F}">${sitioSBS('#2b2b2b')}</td>
    </tr></table>
  </td></tr>
  <tr><td style="border-top:1px solid #9a9a9a;padding:28px 0 0">
    ${kicker ? `<div style="font-size:13px;font-weight:600;color:#6b6b6b;font-family:${F}">${esc(kicker)}</div>` : ''}
    ${titulo ? `<div style="font-size:26px;line-height:1.2;font-weight:700;color:#1a1a1a;margin:4px 0 20px;font-family:${F}">${esc(titulo)}</div>` : ''}
    ${cuerpo}
    ${firma ? `<div style="margin-top:26px;padding-top:20px;border-top:1px solid #e6e6e6"><img src="${esc(firma)}" alt="Show Business Solutions · Gerencia de RR. HH." width="260" style="max-width:260px;width:100%;height:auto;display:block;border:0"></div>` : ''}
  </td></tr>
  <tr><td style="padding:30px 0 0">
    <div style="border-top:1px solid #d9d9d9;padding-top:14px;text-align:center;font-size:11px;color:#9a9a9a;font-family:${F}">Proyecto llevado a cabo por la Gerencia de RR. HH.</div>
    ${instagram ? `<div style="text-align:center;font-size:11px;color:#9a9a9a;margin-top:4px;font-family:${F}">Instagram <a href="https://www.instagram.com/showbs/" style="color:#9a9a9a;text-decoration:underline">@showbs</a> · <a href="https://www.instagram.com/showbspain/" style="color:#9a9a9a;text-decoration:underline">@showbspain</a></div>` : ''}
  </td></tr>
</table>
</div>`;
}

// Un mail entero, en el orden de siempre: saludo, párrafos, código, datos, botón (y el link para copiar), pie.
// Devuelve el HTML y el texto plano (para los clientes que no muestran HTML).
export function armarMail({ kicker, titulo, hola, parrafos, datos, codigo, boton, link, copiar, pie, firma, instagram }) {
  const cuerpo = [hola ? parrafo(hola + ':') : '', (parrafos || []).map(parrafo).join('\n    '), codigo ? codigoHtml(codigo) : '', filasHtml(datos),
    link ? botonHtml(boton, link) : '', link && copiar ? copiarHtml(link) : '', pie ? pieHtml(pie) : ''].filter(Boolean).join('\n    ');
  const html = marcoMail({ kicker, titulo, cuerpo, firma, instagram });
  const text = [kicker || '', titulo || '', ''].concat(hola ? [hola + ':', ''] : [], (parrafos || []).flatMap(p => [p, '']),
    codigo ? [codigo, ''] : [], (datos || []).filter(Boolean).map(([k, v]) => k + ': ' + v), datos && datos.length ? [''] : [], link ? [boton + ': ' + link, ''] : [], pie ? [pie, ''] : [],
    ['Recursos Humanos · Show Business Solutions']).join('\n').replace(/^\n+/, '');
  return { text, html };
}
