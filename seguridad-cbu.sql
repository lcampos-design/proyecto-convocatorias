-- ============================================================
--  SEGURIDAD: QUE NADIE PUEDA CAMBIARLE EL CBU A OTRO
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--  No toca ningún dato: sólo agrega una regla y cambia una función.
--
--  El agujero (30-oct): el formulario de inscripción frena una segunda
--  inscripción con el mismo CUIL, pero sólo en el navegador. Alguien podía
--  mandarla igual (con la clave pública, sin pasar por la página) con el CUIL
--  de otra persona y SU mail. Después, en /mis-datos, el link salía al mail de
--  la inscripción más nueva —la suya— y desde ahí cambiaba el CBU de la otra.
--  Le pasaba a quien no tiene un mail cargado en la nómina.
--
--  El arreglo, en dos partes:
--   1) La base no deja crear una segunda inscripción con el mismo documento
--      (la misma regla que ya tenía el formulario: una persona, una sola
--      inscripción). Si a alguien se le rechaza, la inscripción se borra y se
--      puede volver a inscribir, como hasta ahora.
--   2) El link de /mis-datos sale al mail de la nómina o, si no tiene, al de
--      su inscripción MÁS VIEJA (la suya de verdad), nunca a una más nueva.
-- ============================================================

-- ── 1) UNA SOLA INSCRIPCIÓN POR DOCUMENTO ──
--  Argentina (Movistar Arena y Externos): por los números del documento, como
--  lo compara el panel (doc_nucleo, de mis-datos.sql). España usa DNI/NIE y
--  queda como estaba.
create or replace function public.solicitudes_un_documento()
returns trigger
language plpgsql security definer set search_path = public as $$
declare v_nuc text := public.doc_nucleo(new.cuit);
begin
  if coalesce(new.area, '') <> 'espana' and v_nuc is not null and exists (
       select 1 from public.solicitudes s
        where coalesce(s.area, '') <> 'espana' and public.doc_nucleo(s.cuit) = v_nuc
          and s.id is distinct from new.id) then
    raise exception 'Ya hay una inscripción con ese documento. Para cambiar tus datos, entrá a convocatorias.show-bs.com/mis-datos.'
      using errcode = 'unique_violation';
  end if;
  return new;
end;
$$;
revoke execute on function public.solicitudes_un_documento() from public, anon, authenticated;

drop trigger if exists solicitudes_un_documento on public.solicitudes;
create trigger solicitudes_un_documento
  before insert on public.solicitudes
  for each row execute function public.solicitudes_un_documento();

-- ── 2) EL LINK DE /mis-datos, AL MAIL DE SIEMPRE ──
--  Igual que en mis-datos.sql, salvo el orden: de las inscripciones, la más vieja.
create or replace function public.mis_datos_link(p_cuit text, p_pedido_por text default 'persona')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_nuc    text := public.doc_nucleo(p_cuit);
  v_email  text;
  v_nombre text;
  v_area   text;
  v_token  text;
begin
  if v_nuc is null or length(regexp_replace(coalesce(p_cuit, ''), '\D', '', 'g')) <> 11 then
    return jsonb_build_object('ok', false, 'motivo', 'cuil');
  end if;
  -- El mail: el de la nómina o, si no está, el de su inscripción MÁS VIEJA
  -- (una más nueva con el mismo documento la pudo haber mandado otro).
  select email, nombre, area into v_email, v_nombre, v_area from public.personas
   where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' and coalesce(btrim(email), '') <> ''
   order by created_at desc nulls last limit 1;
  if v_email is null then
    select email, nombre, area into v_email, v_nombre, v_area from public.solicitudes
     where public.doc_nucleo(cuit) = v_nuc and area <> 'espana' and coalesce(btrim(email), '') <> ''
     order by created_at asc limit 1;
  end if;
  if v_email is null then return jsonb_build_object('ok', false, 'motivo', 'no_encontrado'); end if;
  if (select count(*) from public.datos_links where nucleo = v_nuc and creado > now() - interval '1 hour') >= 3 then
    return jsonb_build_object('ok', false, 'motivo', 'muchos', 'email', v_email);
  end if;
  if (select count(*) from public.datos_links where creado > now() - interval '1 hour') >= 300 then
    return jsonb_build_object('ok', false, 'motivo', 'ocupado');
  end if;
  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.datos_links (token_hash, nucleo, pedido_por)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_nuc, coalesce(nullif(btrim(p_pedido_por), ''), 'persona'));
  return jsonb_build_object('ok', true, 'token', v_token, 'email', v_email, 'nombre', v_nombre, 'area', v_area);
end;
$$;
revoke execute on function public.mis_datos_link(text, text) from public, anon, authenticated;
grant  execute on function public.mis_datos_link(text, text) to service_role;

-- ── CÓMO QUEDÓ ──
--  La regla, puesta; y las personas que YA tienen más de una inscripción con
--  el mismo documento (para revisarlas a mano: ¿son la misma persona?).
select 'regla puesta' as que, tgname::text as detalle, null::bigint as cuantas
  from pg_trigger where tgname = 'solicitudes_un_documento'
union all
select 'documento con varias inscripciones', public.doc_nucleo(cuit), count(*)
  from public.solicitudes
 where coalesce(area, '') <> 'espana' and public.doc_nucleo(cuit) is not null
 group by public.doc_nucleo(cuit) having count(*) > 1
order by 1, 3 desc nulls last;

-- ── PARA VOLVER ATRÁS, SI ALGO DEJA DE ANDAR ──
--   drop trigger if exists solicitudes_un_documento on public.solicitudes;
--   (y volver a correr la parte 4 de mis-datos.sql)
