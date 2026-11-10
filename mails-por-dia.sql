-- Cuántos mails salieron por día, según lo que queda registrado (sólo lectura).
--
-- Resend cuenta los mails por día UTC (de 21:00 a 21:00 hora argentina). En el plan
-- gratis el tope es 100 por día: si algún día figura con más de 100, la cuenta está
-- en un plan pago y el tope que saltó es otro (el mensual, o la velocidad).
--
-- Acá se cuentan los que dejan rastro en la base: los contratos y documentos
-- mandados desde el panel (eventos 'enviado' y 'reenviado') y los códigos de firma
-- ('codigo_enviado'). Las confirmaciones sin contrato y el link de disponibilidad
-- no se registran, así que el total real de cada día es mayor que el de acá.
--
-- Se corre en Supabase → SQL Editor. No cambia nada.

select (fecha at time zone 'UTC')::date                                   as dia_resend_utc,
       count(*) filter (where tipo in ('enviado', 'reenviado'))           as contratos_y_documentos,
       count(*) filter (where tipo = 'codigo_enviado')                    as codigos_de_firma,
       count(*)                                                           as registrados,
       min(fecha at time zone 'America/Argentina/Buenos_Aires')::time(0)  as primero_hora_arg,
       max(fecha at time zone 'America/Argentina/Buenos_Aires')::time(0)  as ultimo_hora_arg
from public.contrato_eventos
where tipo in ('enviado', 'reenviado', 'codigo_enviado')
  and fecha >= now() - interval '45 days'
group by 1
order by 1 desc;
