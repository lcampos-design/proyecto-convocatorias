-- ============================================================
--  CHEQUEO DE LA TRAZABILIDAD DE LOS CONTRATOS FIRMADOS
--
--  Sólo lee: no cambia nada. Se puede correr las veces que haga falta.
--  Correr en Supabase → SQL Editor → Run. Muestra dos resultados; el que se
--  ve en pantalla es el último (el detalle). Para ver el resumen, correr
--  sólo la primera consulta (seleccionarla y Run).
--
--  Qué revisa de cada contrato (o documento) firmado:
--   · la trazabilidad: creado, enviado, abierto, código enviado, código
--     verificado, consentimiento y firmado (los eventos de contrato_eventos);
--   · el código: codigo_verificado (la base lo registró) y codigo_ok (el
--     evento). Los firmados antes del 2-nov-2026 no tenían código: salen
--     como "anterior al código", no como falta;
--   · la firma dibujada, la IP y el dispositivo de la firma;
--   · la huella SHA-256: se recalcula sobre el texto guardado y tiene que
--     coincidir con la que se fijó al firmar (si no coincide, el texto
--     cambió después de la firma);
--   · el PDF firmado guardado (el que baja el panel).
--  La columna "falta" resume: vacía = todo en orden.
-- ============================================================

-- ── 1) RESUMEN ──
with ev as (
  select contrato_id,
         bool_or(tipo = 'codigo_ok')      as codigo_ok,
         bool_or(tipo = 'consentimiento') as consentimiento,
         bool_or(tipo = 'firmado')        as firmado
    from public.contrato_eventos
   group by contrato_id
)
select count(*)                                                                   as firmados,
       count(*) filter (where coalesce(ev.codigo_ok, false))                      as con_codigo,
       count(*) filter (where not coalesce(ev.codigo_ok, false)
                          and c.fecha_firma < timestamptz '2026-11-02 00:00-03')  as anteriores_al_codigo,
       count(*) filter (where not coalesce(ev.codigo_ok, false)
                          and c.fecha_firma >= timestamptz '2026-11-02 00:00-03') as sin_codigo_que_deberian_tenerlo,
       count(*) filter (where c.pdf_firmado is null)                              as sin_pdf,
       count(*) filter (where c.firma_png is null)                                as sin_firma,
       count(*) filter (where c.firma_ip is null)                                 as sin_ip,
       count(*) filter (where not coalesce(ev.consentimiento, false))             as sin_consentimiento,
       count(*) filter (where not coalesce(ev.firmado, false))                    as sin_evento_firmado,
       count(*) filter (where c.hash_texto is distinct from
                              encode(extensions.digest(c.texto_contrato, 'sha256'), 'hex')) as huella_distinta
  from public.contratos c
  left join ev on ev.contrato_id = c.id
 where c.estado = 'firmado';

-- ── 2) EL DETALLE: UNA FILA POR FIRMADO, LOS QUE TIENEN ALGO PRIMERO ──
with ev as (
  select contrato_id,
         bool_or(tipo = 'creado')                   as creado,
         bool_or(tipo in ('enviado', 'reenviado'))  as enviado,
         bool_or(tipo = 'visto')                    as abierto,
         bool_or(tipo = 'codigo_enviado')           as codigo_enviado,
         bool_or(tipo = 'codigo_ok')                as codigo_ok,
         bool_or(tipo = 'consentimiento')           as consentimiento,
         bool_or(tipo = 'firmado')                  as firmado,
         count(*)                                   as eventos
    from public.contrato_eventos
   group by contrato_id
),
fila as (
  select c.nombre,
         c.fecha_firma,
         c.transaccion_id,
         coalesce(c.solo_documentos, false)                                           as solo_documento,
         coalesce(ev.eventos, 0)                                                      as eventos,
         coalesce(ev.creado, false)                                                   as creado,
         coalesce(ev.enviado, false)                                                  as enviado,
         coalesce(ev.abierto, false)                                                  as abierto,
         coalesce(ev.codigo_enviado, false)                                           as codigo_enviado,
         coalesce(ev.codigo_ok, false)                                                as codigo_ok,
         c.codigo_ok_at is not null                                                   as codigo_verificado,
         coalesce(ev.consentimiento, false)                                           as consentimiento,
         coalesce(ev.firmado, false)                                                  as firmado,
         c.firma_png is not null                                                      as firma_guardada,
         c.firma_ip is not null                                                       as ip_firma,
         c.firma_user_agent is not null                                               as dispositivo_firma,
         c.hash_texto = encode(extensions.digest(c.texto_contrato, 'sha256'), 'hex')  as huella_coincide,
         c.pdf_firmado is not null                                                    as pdf_guardado,
         c.fecha_firma < timestamptz '2026-11-02 00:00-03'                            as anterior_al_codigo
    from public.contratos c
    left join ev on ev.contrato_id = c.id
   where c.estado = 'firmado'
)
select nombre, fecha_firma, transaccion_id, solo_documento, eventos,
       creado, enviado, abierto, codigo_enviado, codigo_ok, codigo_verificado, consentimiento, firmado,
       firma_guardada, ip_firma, dispositivo_firma, huella_coincide, pdf_guardado,
       concat_ws(', ',
         case when not codigo_ok and anterior_al_codigo then 'anterior al código' end,
         case when not codigo_ok and not anterior_al_codigo then 'SIN CÓDIGO' end,
         case when codigo_ok and not codigo_verificado then 'código sin registrar en la base' end,
         case when not consentimiento then 'sin consentimiento' end,
         case when not firmado then 'sin evento firmado' end,
         case when not firma_guardada then 'sin firma' end,
         case when not ip_firma then 'sin IP' end,
         case when not huella_coincide then 'HUELLA DISTINTA' end,
         case when not pdf_guardado then 'sin PDF' end,
         case when not enviado then 'sin envío registrado' end,
         case when not abierto then 'sin apertura registrada' end
       ) as falta
  from fila
 order by (concat_ws(', ',
         case when not codigo_ok and not anterior_al_codigo then 'x' end,
         case when not consentimiento then 'x' end,
         case when not firmado then 'x' end,
         case when not firma_guardada then 'x' end,
         case when not huella_coincide then 'x' end,
         case when not pdf_guardado then 'x' end) = '') asc,
       fecha_firma desc;
