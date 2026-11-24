-- ============================================================
--  CBU INVÁLIDO: NADIE SE INSCRIBE CON UN CBU QUE NO DA (24-nov)
-- ============================================================
--  Mercedes (24-nov): "que cada vez que una persona se anote y declare el CBU verificar que esté ok; si no está ok,
--  que no los deje inscribirse por CBU INVALIDO".
--
--  · Un aviso en solicitudes: al inscribirse, o al cambiar el CBU (desde Mis datos o desde el panel), si los 22 números
--    y los dos dígitos verificadores no dan, no se guarda y vuelve el error "CBU INVALIDO". El formulario ya lo frena
--    antes; esto es para que no pase nunca, aunque alguien se saltee el formulario.
--  · Usa cbu_valido (la de mis-datos.sql, la misma cuenta que el formulario); no la cambia.
--  · Lo que ya está cargado no se toca (cambiar otra cosa de una inscripción con el CBU mal sigue andando): eso se
--    revisa en el panel, Nómina → Herramientas → Revisar los CBU, y se le pide a cada uno que lo corrija.
--  · Que la cuenta sea a nombre de la persona no se puede saber con el número: eso lo dice el banco.
--
--  Se puede correr más de una vez. Al final: si el aviso quedó puesto y cuántos CBU cargados dan y cuántos no
--  (sólo cantidades, sin datos de nadie).
-- ============================================================

create or replace function public.solicitudes_cbu_chequeo()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.cbu is null or btrim(new.cbu) = '' then return new; end if;
  if tg_op = 'UPDATE' and new.cbu is not distinct from old.cbu then return new; end if;
  if not public.cbu_valido(new.cbu) then
    raise exception 'CBU INVALIDO' using errcode = '22023', hint = 'Revisá los 22 números del CBU.';
  end if;
  return new;
end;
$$;
revoke execute on function public.solicitudes_cbu_chequeo() from public, anon, authenticated;

drop trigger if exists solicitudes_cbu_valido on public.solicitudes;
create trigger solicitudes_cbu_valido
  before insert or update of cbu on public.solicitudes
  for each row execute function public.solicitudes_cbu_chequeo();

-- Cómo quedó (sólo cantidades).
select
  (select count(*) from pg_trigger where tgname = 'solicitudes_cbu_valido' and not tgisinternal) = 1 as aviso_puesto,
  count(*) filter (where public.cbu_valido(cbu))     as cbu_que_dan,
  count(*) filter (where not public.cbu_valido(cbu)) as cbu_que_no_dan
from public.solicitudes
where area is distinct from 'espana' and coalesce(btrim(cbu), '') <> '';
