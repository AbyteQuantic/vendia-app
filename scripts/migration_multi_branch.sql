-- ============================================================================
-- VendIA — Multi-Branch (Sucursales) Architecture
-- DDL Migration: branches table + FK columns on employees & inventories
-- Target: PostgreSQL 14+ (Supabase)
-- Author: Equipo VendIA
-- Date: 2026-04-22
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TABLA: branches
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS branches (
    id              UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Identificación de la sede
    name            VARCHAR(255) NOT NULL,           -- "Sede Principal", "Sede Norte"
    address         TEXT,                            -- Dirección física (opcional)
    latitude        DOUBLE PRECISION,                -- GPS lat
    longitude       DOUBLE PRECISION,                -- GPS lng

    -- Flags
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,  -- Única sede por defecto por tenant
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Auditoría
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Cada tenant tiene máximo UN default
    CONSTRAINT uq_branches_default_per_tenant UNIQUE (tenant_id, is_default)
        DEFERRABLE INITIALLY DEFERRED
);

-- Índices de búsqueda frecuente
CREATE INDEX IF NOT EXISTS idx_branches_tenant  ON branches (tenant_id);
CREATE INDEX IF NOT EXISTS idx_branches_active  ON branches (tenant_id, is_active);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Trigger: updated_at automático para branches
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_branches_updated_at ON branches;
CREATE TRIGGER trg_branches_updated_at
    BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Seed: Sede Principal automática para tenants existentes
--    (ejecutar UNA sola vez después de crear la tabla)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO branches (tenant_id, name, is_default, is_active)
SELECT
    id          AS tenant_id,
    'Sede Principal' AS name,
    TRUE        AS is_default,
    TRUE        AS is_active
FROM tenants
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Función RPC para crear tenant + sede default en un solo TX
--    Llamada por el backend Go al registrar un nuevo tenant (Fase 1).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_tenant_with_default_branch(
    p_tenant_id   UUID,
    p_branch_name TEXT DEFAULT 'Sede Principal'
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_branch_id UUID;
BEGIN
    INSERT INTO branches (tenant_id, name, is_default, is_active)
    VALUES (p_tenant_id, p_branch_name, TRUE, TRUE)
    RETURNING id INTO v_branch_id;
    RETURN v_branch_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. ALTER: employees — agregar branch_id (FK, nullable para legacy rows)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE employees
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id) ON DELETE SET NULL;

-- Backfill: asignar la sede por defecto a todos los empleados sin branch_id
UPDATE employees e
SET branch_id = b.id
FROM branches b
WHERE b.tenant_id = e.tenant_id
  AND b.is_default = TRUE
  AND e.branch_id IS NULL;

-- Índice para consultas de "empleados por sede"
CREATE INDEX IF NOT EXISTS idx_employees_branch ON employees (branch_id);
CREATE INDEX IF NOT EXISTS idx_employees_tenant_branch ON employees (tenant_id, branch_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. ALTER: inventories — agregar branch_id (FK, NOT NULL con backfill previo)
-- ─────────────────────────────────────────────────────────────────────────────

-- Paso 6a: agregar nullable
ALTER TABLE inventories
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id) ON DELETE SET NULL;

-- Paso 6b: backfill con la sede por defecto
UPDATE inventories i
SET branch_id = b.id
FROM branches b
WHERE b.tenant_id = i.tenant_id
  AND b.is_default = TRUE
  AND i.branch_id IS NULL;

-- Paso 6c: convertir a NOT NULL (falla si quedaron filas sin asignar — intencionado)
ALTER TABLE inventories
    ALTER COLUMN branch_id SET NOT NULL;

-- Índices
CREATE INDEX IF NOT EXISTS idx_inventories_branch ON inventories (branch_id);
CREATE INDEX IF NOT EXISTS idx_inventories_tenant_branch ON inventories (tenant_id, branch_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Row Level Security (Supabase RLS) — solo si RLS está habilitado
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

-- Política: solo el tenant dueño puede ver sus propias sedes
CREATE POLICY branches_tenant_isolation ON branches
    USING (tenant_id = (current_setting('app.current_tenant_id'))::UUID);

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. RESUMEN DE ENDPOINTS NUEVOS (referencia para el equipo Go)
-- ─────────────────────────────────────────────────────────────────────────────
-- | Método | Ruta                          | Auth  | Descripción                         |
-- |--------|-------------------------------|-------|-------------------------------------|
-- | GET    | /api/v1/store/branches        | JWT   | Listar sedes del tenant             |
-- | GET    | /api/v1/store/branches/:id    | JWT   | Detalle de una sede                 |
-- | POST   | /api/v1/store/branches        | JWT   | Crear nueva sede (PRO/TRIAL)        |
-- | PATCH  | /api/v1/store/branches/:id    | JWT   | Editar nombre/dirección/coords      |
-- | DELETE | /api/v1/store/branches/:id    | JWT   | Eliminar sede (no default, sin emp) |
-- ─────────────────────────────────────────────────────────────────────────────
-- NOTAS IMPORTANTES:
-- • La sede por defecto (is_default=TRUE) NO puede eliminarse (422).
-- • Una sede con empleados activos NO puede eliminarse (422).
-- • Al crear un nuevo tenant, el backend DEBE llamar a
--   create_tenant_with_default_branch(tenant_id) en la misma TX.
-- • Todos los endpoints de lectura (inventario, ventas, KDS) aceptan
--   ?branch_id=<uuid> para filtrar por sede. Si se omite, retornan
--   los datos de la sede por defecto del tenant.
-- ─────────────────────────────────────────────────────────────────────────────
