-- ============================================================
--  CENTRO DE CONTROL: el plano del anillo, editable desde el panel
--  Correr en Supabase → SQL Editor → Run. Se puede volver a correr.
--
--  Guarda lo que hay en el anillo del Arena (puertas, gastronomía, baños,
--  enfermería y otros puntos) tal como se arma en el panel: Centro de
--  Control → "Plano del Arena". Lo cambia sólo el panel; lo leen la tablet
--  del supervisor y la gerencia. Mientras no se guarde nada, todos ven el
--  plano de siempre.
--
--  No guarda datos de nadie: sólo nombres de lugares y su posición.
-- ============================================================

-- ── 1) LA TABLA: una sola fila con la lista de puestos ──
create table if not exists public.arena_plano (
  id          smallint primary key default 1 check (id = 1),
  lugares     jsonb not null default '[]'::jsonb
              check (jsonb_typeof(lugares) = 'array' and jsonb_array_length(lugares) <= 80),
  updated_at  timestamptz not null default now(),
  updated_por text
);

--  Sin usuario: nada. Con usuario: sólo el panel (admin) la cambia.
alter table public.arena_plano enable row level security;
revoke all on public.arena_plano from anon, public;
grant select, insert, update, delete on public.arena_plano to authenticated;
drop policy if exists arena_plano_admin on public.arena_plano;
create policy arena_plano_admin on public.arena_plano
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ── 2) PARA LEERLA: la tablet, la gerencia y el panel ──
--  Cualquiera que entró con usuario ve el plano (no tiene nada privado).
create or replace function public.plano_arena()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null then null
    else (select jsonb_build_object('lugares', p.lugares, 'updated_at', p.updated_at)
          from public.arena_plano p where p.id = 1) end;
$$;
revoke execute on function public.plano_arena() from public, anon;
grant  execute on function public.plano_arena() to authenticated;

-- ── CÓMO QUEDÓ ──
select (select count(*) from public.arena_plano)                              as planos_guardados,
       has_function_privilege('authenticated', 'public.plano_arena()', 'execute') as con_usuario,
       has_function_privilege('anon', 'public.plano_arena()', 'execute')          as sin_usuario;
--  Tiene que dar 0 planos guardados (hasta que guardes uno desde el panel),
--  con_usuario en true y sin_usuario en false.
