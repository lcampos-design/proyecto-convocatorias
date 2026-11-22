-- ============================================================
--  CONTRATO AL CONFIRMAR (Externos, 22-nov-2026)
--  Supabase → SQL Editor → pegar todo → Run. Se puede volver a correr.
--
--  Pedido de RR. HH.: a los coordinadores de acreditación o de servicios, operadores y otros
--  eventuales de varios días, el contrato les sale con el "sí" del mail, no con la P de la planilla.
--  En el panel, el puesto se marca "Contrato al confirmar": al mandarles la confirmación, el contrato
--  queda armado (uno por todo el período, con la remuneración del puesto como total) y sale solo
--  cuando la persona toca ✓ CONFIRMO. Esos contratos llevan origen 'al_confirmar'.
-- ============================================================

-- El tilde del puesto.
alter table public.puestos add column if not exists contrato_al_confirmar boolean not null default false;

-- Para encontrar rápido el contrato de una convocatoria cuando alguien confirma.
create index if not exists contratos_al_confirmar_idx on public.contratos (conv_id) where origen = 'al_confirmar';

-- ── CÓMO QUEDÓ ── tiene que dar true.
select exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'puestos' and column_name = 'contrato_al_confirmar') as puestos_con_el_tilde;
