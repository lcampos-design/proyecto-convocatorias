// Los mails a casillas de Microsoft (Hotmail, Outlook, Live, MSN), por Google (19-nov-2026).
//
// En Resend, los contratos del 18-nov a Hotmail figuran "Delivery Delayed": Microsoft frena lo que llega desde
// los servidores de Resend (los del 17-nov habían llegado). A Google no lo frena. Thomas (19-nov): "que salgan por
// Google". Entonces, a esas casillas no se les manda por Resend: el contrato queda en una fila (un evento
// "por_google" del contrato, con el motivo) y el script de la planilla (cuenta de Google del Arena) los manda con
// MailApp en la misma vuelta y avisa cuáles salieron (api/correo-google.js). Vale para los contratos por presente
// (Arena y Externos), los recordatorios y los reenvíos del panel.

export const TIPO_GOOGLE = 'por_google';
export function esMicrosoft(mail) {
  return /@(hotmail|outlook|live|msn|windowslive|passport)\.[a-z.]{2,}$/i.test(String(mail || '').trim());
}
