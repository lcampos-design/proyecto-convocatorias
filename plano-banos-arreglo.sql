-- ============================================================
--  PLANO DEL ARENA: arreglo de plano-banos-merch.sql (14-nov-2026)
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  El plano guardado sólo tenía, además de las puertas, los baños y las dos
--  barras de ejemplo de la primera versión del editor, sin mover: la página
--  los reemplaza por los del plano de siempre. Al cambiarles el nombre dejaron
--  de reconocerse como "de siempre" y quedaron como puestos sueltos (en P1 y
--  P3); y al sumarle baños accesibles y el merch store, la página dejó de
--  completar con los de siempre los baños de cada piso, los camarines y
--  Acreditaciones. Se vuelve el plano guardado a como estaba (la copia de
--  respaldo): los nombres nuevos, los baños accesibles y el merch store los
--  pone la página, con el plano de siempre. Las incidencias quedan con el
--  nombre nuevo de su lugar (eso estaba bien).
--  Si alguien guardó el plano desde el panel después, no toca nada y avisa.
-- ============================================================

do $$
declare n int;
begin
  if to_regclass('respaldo.plano_banos_2026_11_14') is null then
    raise notice 'No se corrió plano-banos-merch.sql: no hay nada que arreglar.';
    return;
  end if;
  update public.arena_plano p
     set lugares = r.antes->'lugares', updated_at = now(), updated_por = 'plano-banos-arreglo.sql'
    from respaldo.plano_banos_2026_11_14 r
   where r.tabla = 'arena_plano' and r.fila_id = p.id::text
     and p.updated_por = 'plano-banos-merch.sql';
  get diagnostics n = row_count;
  if n > 0 then raise notice 'Listo: el plano guardado volvió a como estaba.';
  elsif exists (select 1 from public.arena_plano where updated_por = 'plano-banos-arreglo.sql') then raise notice 'Ya estaba arreglado: no se cambió nada.';
  else raise notice 'El plano se guardó desde el panel después: no se tocó nada. Avisá.'; end if;
end $$;

-- Cómo quedó: lo que tiene guardado el plano (sin las calles).
select coalesce(e->>'piso', 'PB') as piso, e->>'t' as tipo, string_agg(e->>'id', ' · ' order by (e->>'cy')::numeric, e->>'id') as lugares
  from public.arena_plano p, jsonb_array_elements(p.lugares) e
 where e->>'t' <> 'calle'
 group by 1, 2
 order by 1, 2;
