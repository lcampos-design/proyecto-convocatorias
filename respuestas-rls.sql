-- ============================================================
--  LOS DOS ERRORES DEL SECURITY ADVISOR
--  Correr en Supabase → SQL Editor → Run.
--  Se puede volver a correr sin problema.
--
--  1) La tabla "respuestas" no tiene el candado puesto.
--     Ahí quedan los mails que llegan a las casillas de convocatorias:
--     nombre, dirección y el texto que escribió cada persona. Sin candado,
--     Supabase se lo muestra a cualquiera que tenga la clave pública, que
--     está a la vista en el código de las páginas.
--
--  2) La vista "feedbacks_con_promedio" corre con los permisos de quien la
--     creó, no de quien la consulta. O sea, deja ver los feedbacks
--     salteándose el candado de la tabla que tiene debajo.
-- ============================================================

-- ── 1) RESPUESTAS ──
alter table public.respuestas enable row level security;

-- El panel las lee y las marca como leídas. Nada más: no borra ninguna.
drop policy if exists respuestas_panel_select on public.respuestas;
create policy respuestas_panel_select on public.respuestas
  for select to authenticated using (true);

drop policy if exists respuestas_panel_update on public.respuestas;
create policy respuestas_panel_update on public.respuestas
  for update to authenticated using (true) with check (true);

--  Los mails los deposita algo de afuera del panel, que entra sin usuario.
--  Se le deja SOLO escribir: puede seguir dejando mensajes, pero ya no puede
--  leer los de nadie ni borrarlos. Eso es lo que estaba abierto.
--  Si más adelante confirmamos que lo que escribe usa la clave de servidor
--  (que no pasa por estas reglas), esta regla se puede sacar y queda cerrado
--  del todo:   drop policy respuestas_entrada on public.respuestas;
drop policy if exists respuestas_entrada on public.respuestas;
create policy respuestas_entrada on public.respuestas
  for insert to anon with check (true);

revoke select, update, delete on public.respuestas from anon;
revoke delete on public.respuestas from authenticated;

-- ── 2) LA VISTA DE FEEDBACKS ──
--  Que use los permisos de quien consulta, no los del que la creó.
--  Hace falta Postgres 15 o más nuevo; si no está, el revoke de abajo
--  igual alcanza, porque nadie que no esté logueado la necesita.
do $$
begin
  execute 'alter view public.feedbacks_con_promedio set (security_invoker = on)';
exception when others then
  raise notice 'No se pudo poner security_invoker (%). Queda el revoke.', sqlerrm;
end $$;

revoke all on public.feedbacks_con_promedio from anon;
grant select on public.feedbacks_con_promedio to authenticated;

-- ── CÓMO QUEDÓ ──
--  respuestas tiene que aparecer con el candado puesto:
select c.relname as tabla, c.relrowsecurity as candado_puesto
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
order by c.relname;
--  (si no devuelve ninguna fila, están todas con candado)

--  Y de respuestas, para anon tiene que quedar sólo la de escribir:
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'respuestas'
order by policyname;

-- ── PARA VOLVER ATRÁS, SI DEJAN DE ENTRAR LOS MAILS ──
--   alter table public.respuestas disable row level security;
--   grant select, insert, update on public.respuestas to anon;
