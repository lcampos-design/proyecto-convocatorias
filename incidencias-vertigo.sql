-- Incidencias: "Vértigo" como tipo propio (19-nov-2026), Médica, criticidad Media como "Desmayo / descompensación".
-- Pedido de Thomas: "los chicos ponen desmayo/descompensación pero en realidad es vértigo".
-- Sólo actualiza el criterio fijo de la base (incidencias-criterio.sql). No toca las ya cargadas. Se puede volver a correr.

create or replace function public.incidencia_nivel(p_tipo text, p_acciones jsonb, p_actual int)
returns smallint
language sql immutable set search_path = public as $$
  select greatest(
    coalesce(
      (select t.n from (values
        ('Desmayo / descompensación', 2), ('Vértigo', 2), ('Lesión o caída', 2), ('Persona alcoholizada o intoxicada', 2), ('Emergencia médica grave', 3),
        ('Pelea o agresión', 3), ('Persona agresiva o molesta', 2), ('Ingreso indebido / sin entrada', 2), ('Objeto prohibido', 1), ('Robo o hurto', 2),
        ('Fila larga en el ingreso', 1), ('Fila de ingreso desbordada', 2), ('Molinete o lector de entradas que no anda', 2),
        ('Demora en la apertura de puertas', 2), ('Amontonamiento o empujones en el ingreso', 3),
        ('Cambio de ubicación', 1), ('Ubicación ocupada', 1), ('Entrada duplicada', 2), ('Persona fuera de su sector', 1),
        ('Derrame / piso resbaladizo', 1), ('Butaca o baranda rota', 1), ('Baño fuera de servicio', 1), ('Falla eléctrica o de iluminación', 2),
        ('Salida obstruida', 3),
        ('Falta personal en el sector', 2), ('Personal descompuesto', 2), ('Problema de conducta o uniforme', 1),
        ('Acompañamiento a ubicación accesible', 1), ('Salida diferenciada', 1), ('Asistencia a persona con discapacidad', 1),
        ('Falla de la impresora', 2), ('Falla del lector', 2), ('Falla del sistema', 2), ('Problema con pulseras o credenciales', 1),
        ('Otra incidencia', 1)
      ) t(tipo, n) where t.tipo = btrim(coalesce(p_tipo, ''))),
      least(greatest(coalesce(p_actual, 1), 1), 3)),
    case when coalesce(p_acciones, '[]'::jsonb) ?| array['Se derivó en ambulancia (SAME)', 'Se dio aviso a la policía'] then 3 else 1 end
  )::smallint
$$;
revoke execute on function public.incidencia_nivel(text, jsonb, int) from public, anon;
grant  execute on function public.incidencia_nivel(text, jsonb, int) to authenticated, service_role;

-- Cómo quedó: vertigo 2 · desmayo 2 · con_ambulancia 3.
select public.incidencia_nivel('Vértigo', '[]'::jsonb, 1) as vertigo,
       public.incidencia_nivel('Desmayo / descompensación', '[]'::jsonb, 1) as desmayo,
       public.incidencia_nivel('Vértigo', '["Se derivó en ambulancia (SAME)"]'::jsonb, 1) as con_ambulancia;
