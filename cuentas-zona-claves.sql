-- ============================================================
--  LAS CONTRASEÑAS DE LAS CUENTAS POR ZONA, A LA VISTA EN EL PANEL
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--  No toca ningún dato.
--
--  6-nov-2026, Thomas: "necesito que desde la página de admin podamos ver
--  los usuarios y contraseñas, porque son usuarios de la empresa; van a ser
--  contraseñas genéricas". Las de las siete cuentas por zona (cuentas-zona.sql)
--  quedan guardadas acá cada vez que se crean o se cambian desde el panel,
--  y el panel las muestra en Supervisores → Cuentas por zona.
--
--  Sólo las de las cuentas por zona (las de cada persona y las de la
--  gerencia no se guardan). Las lee únicamente el equipo del panel: sin
--  usuario, los supervisores y la gerencia no pueden. Las escribe sólo el
--  servidor (/api/supervisor), al crear o cambiar la contraseña.
-- ============================================================

create table if not exists public.cuentas_zona_claves (
  zona        text primary key,
  usuario     text not null,
  clave       text not null,
  actualizada timestamptz not null default now(),
  por         text                                  -- quién la puso (el mail del panel)
);
alter table public.cuentas_zona_claves enable row level security;
revoke all on public.cuentas_zona_claves from anon;
revoke insert, update, delete on public.cuentas_zona_claves from authenticated;
grant select on public.cuentas_zona_claves to authenticated;
drop policy if exists cuentas_zona_claves_ver on public.cuentas_zona_claves;
create policy cuentas_zona_claves_ver on public.cuentas_zona_claves for select to authenticated using (public.es_admin());
drop policy if exists solo_admin on public.cuentas_zona_claves;
create policy solo_admin on public.cuentas_zona_claves as restrictive to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ── CÓMO QUEDÓ ──
--  Tiene que dar: la_tabla = true, sin_usuario_no_se_ve = true, el_panel_solo_la_lee = true.
select exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'cuentas_zona_claves') as la_tabla,
       not has_table_privilege('anon', 'public.cuentas_zona_claves', 'select') as sin_usuario_no_se_ve,
       has_table_privilege('authenticated', 'public.cuentas_zona_claves', 'select')
         and not has_table_privilege('authenticated', 'public.cuentas_zona_claves', 'insert')
         and not has_table_privilege('authenticated', 'public.cuentas_zona_claves', 'update') as el_panel_solo_la_lee;
