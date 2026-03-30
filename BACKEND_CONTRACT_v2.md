# VendIA — Contrato Backend v2: Pánico SOS + Abonos + División de Cuenta + Historial Cliente

> **Para:** Equipo Backend (Go/Fiber + PostgreSQL + Gemini AI + Cloudflare R2)
> **De:** Equipo Frontend (Flutter)
> **Fecha:** 2026-03-29
> **Prioridad:** ALTA (Seguridad) / MEDIA (Abonos/Split)

---

## CONTEXTO

El frontend ya tiene implementadas las pantallas y la lógica UI para 3 módulos nuevos. Necesitamos los endpoints, tablas y lógica del backend. Todo sigue el patrón existente:
- Base: `/api/v1/...`
- Auth: `Authorization: Bearer {access_token}` (JWT con `tenant_id` y `employee_uuid`)
- Responses: `{ "data": {...} }` o `{ "data": [...] }`
- IDs: UUID v4 generados por el backend
- Moneda: COP (enteros, sin decimales, redondeo a $50)
- Multi-tenant: Todo filtrado por `tenant_id` del JWT

---

## MÓDULO 1: BOTÓN DE PÁNICO SILENCIOSO (SOS)

### 1.1 Tablas Necesarias

```sql
-- ══════════════════════════════════════════════════════════
-- TABLA: sos_config (configuración por tenant)
-- ══════════════════════════════════════════════════════════
CREATE TABLE sos_config (
    id              SERIAL PRIMARY KEY,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

    -- Contactos
    police_number   VARCHAR(20) NOT NULL DEFAULT '123',
    family_number   VARCHAR(20),

    -- Métodos de alerta (el tendero elige cuáles activar)
    sms_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    whatsapp_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    call_enabled    BOOLEAN NOT NULL DEFAULT FALSE,

    -- Mensaje personalizado (se pre-arma con datos del onboarding)
    custom_message  TEXT,

    -- Dirección (copiada del tenant para acceso rápido)
    address         TEXT NOT NULL,
    business_name   VARCHAR(255) NOT NULL,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(tenant_id)
);

-- ══════════════════════════════════════════════════════════
-- TABLA: sos_alerts (registro de cada activación del pánico)
-- ══════════════════════════════════════════════════════════
CREATE TABLE sos_alerts (
    id              SERIAL PRIMARY KEY,
    uuid            UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    employee_uuid   UUID REFERENCES employees(uuid),

    -- Ubicación al momento del pánico
    latitude        DOUBLE PRECISION,
    longitude       DOUBLE PRECISION,

    -- Estado del envío
    sms_sent        BOOLEAN DEFAULT FALSE,
    whatsapp_sent   BOOLEAN DEFAULT FALSE,
    call_initiated  BOOLEAN DEFAULT FALSE,

    -- Mensaje que se envió
    message_sent    TEXT NOT NULL,

    -- Para auditoría
    triggered_from  VARCHAR(20) NOT NULL DEFAULT 'pos',  -- 'pos' | 'dashboard'
    resolved_at     TIMESTAMPTZ,
    false_alarm     BOOLEAN DEFAULT FALSE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sos_alerts_tenant ON sos_alerts(tenant_id);
CREATE INDEX idx_sos_alerts_created ON sos_alerts(created_at DESC);
```

### 1.2 Endpoints SOS

#### `GET /api/v1/sos/config` — Obtener configuración SOS
**Auth:** Requerida (admin/owner)

**Response 200:**
```json
{
  "data": {
    "police_number": "123",
    "family_number": "3105551234",
    "sms_enabled": true,
    "whatsapp_enabled": true,
    "call_enabled": false,
    "custom_message": null,
    "address": "Calle 12 #3-45, Barrio El Centro",
    "business_name": "Tienda Don Pedro",
    "is_configured": true
  }
}
```

**Response 404** (primera vez, no configurado):
```json
{
  "data": {
    "is_configured": false,
    "address": "Calle 12 #3-45, Barrio El Centro",
    "business_name": "Tienda Don Pedro"
  }
}
```
> **Nota:** `address` y `business_name` se toman de la tabla `tenants` para pre-armar el mensaje.

---

#### `PUT /api/v1/sos/config` — Guardar/actualizar configuración SOS
**Auth:** Requerida (admin/owner)

**Request Body:**
```json
{
  "police_number": "123",
  "family_number": "3105551234",
  "sms_enabled": true,
  "whatsapp_enabled": true,
  "call_enabled": false,
  "custom_message": "EMERGENCIA en Tienda Don Pedro. Dirección: Calle 12 #3-45, Barrio El Centro. Se requiere presencia policial inmediata."
}
```

**Validaciones:**
- `police_number`: Requerido, 3-20 caracteres, solo dígitos
- `family_number`: Opcional, 7-15 caracteres si se envía
- Al menos un método debe estar habilitado (`sms_enabled || whatsapp_enabled || call_enabled`)

**Response 200:**
```json
{
  "data": {
    "message": "Configuración de seguridad guardada",
    "police_number": "123",
    "family_number": "3105551234",
    "sms_enabled": true,
    "whatsapp_enabled": true,
    "call_enabled": false
  }
}
```

---

#### `POST /api/v1/sos/trigger` — DISPARAR ALERTA DE PÁNICO
**Auth:** Requerida (cualquier rol: admin, cajero)
**Prioridad de procesamiento:** MÁXIMA (async, no bloquear response)

**Request Body:**
```json
{
  "latitude": 4.6097,
  "longitude": -74.0817,
  "triggered_from": "pos"
}
```

**Lógica del Backend (CRÍTICA):**
1. Responder 200 INMEDIATAMENTE al frontend (< 200ms)
2. En goroutine/worker async:
   a. Leer `sos_config` del tenant
   b. Construir mensaje: `custom_message` + coordenadas Google Maps
   c. Si `sms_enabled`: enviar SMS vía Twilio/provider al `police_number` y `family_number`
   d. Si `whatsapp_enabled`: enviar mensaje WA vía API al `police_number` y `family_number`
   e. Si `call_enabled`: iniciar llamada con TTS (Text-to-Speech) al `police_number`
   f. Registrar en `sos_alerts` con los estados de envío
3. **NO** debe fallar aunque el SMS/WA/Call falle — registrar el intento

**Response 200 (inmediata):**
```json
{
  "data": {
    "alert_uuid": "a1b2c3d4-...",
    "status": "dispatching",
    "message": "Alerta enviada. Ayuda en camino."
  }
}
```

**Response 412** (SOS no configurado):
```json
{
  "error": "sos_not_configured",
  "message": "Configure sus contactos de emergencia primero"
}
```

---

#### `GET /api/v1/sos/history` — Historial de alertas
**Auth:** Requerida (admin/owner)
**Query Params:** `page=1&per_page=20`

**Response 200:**
```json
{
  "data": [
    {
      "uuid": "a1b2c3d4-...",
      "employee_name": "Carlos",
      "triggered_from": "pos",
      "sms_sent": true,
      "whatsapp_sent": true,
      "call_initiated": false,
      "false_alarm": false,
      "created_at": "2026-03-29T14:30:00Z"
    }
  ],
  "meta": { "page": 1, "per_page": 20, "total": 3 }
}
```

---

## MÓDULO 2: ABONOS (PAGOS PARCIALES A CUENTAS ABIERTAS)

### 2.1 Tablas Necesarias

```sql
-- ══════════════════════════════════════════════════════════
-- TABLA: order_payments (abonos/pagos parciales por orden)
-- ══════════════════════════════════════════════════════════
CREATE TABLE order_payments (
    id              SERIAL PRIMARY KEY,
    uuid            UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    order_uuid      UUID NOT NULL REFERENCES orders(uuid) ON DELETE CASCADE,

    -- Monto del abono (en COP, entero, múltiplo de 50)
    amount          INTEGER NOT NULL CHECK (amount > 0),

    -- Método de pago
    payment_method  VARCHAR(20) NOT NULL DEFAULT 'efectivo',
    -- 'efectivo' | 'nequi' | 'daviplata' | 'tarjeta' | 'transferencia'

    -- Quién registró el abono
    employee_uuid   UUID REFERENCES employees(uuid),
    employee_name   VARCHAR(255),

    -- Nota opcional
    note            VARCHAR(500),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_payments_order ON order_payments(order_uuid);
CREATE INDEX idx_order_payments_tenant ON order_payments(tenant_id);

-- ══════════════════════════════════════════════════════════
-- Agregar columna a orders existente
-- ══════════════════════════════════════════════════════════
ALTER TABLE orders ADD COLUMN total_paid INTEGER NOT NULL DEFAULT 0;
-- total_paid se actualiza con un trigger o desde el backend
-- saldo_pendiente = total - total_paid (calculado, no almacenado)
```

### 2.2 Endpoints Abonos

#### `POST /api/v1/orders/{orderUuid}/payments` — Registrar abono
**Auth:** Requerida (admin/cajero)

**Request Body:**
```json
{
  "amount": 10000,
  "payment_method": "efectivo",
  "note": "Abono en efectivo"
}
```

**Validaciones:**
- `amount`: Requerido, entero > 0, múltiplo de 50
- `amount` no puede exceder el saldo pendiente (`order.total - order.total_paid`)
- La orden debe existir y pertenecer al `tenant_id` del JWT
- La orden debe tener status `nuevo`, `preparando` o `listo` (no `cobrado` ni `cancelado`)

**Lógica:**
1. Insertar en `order_payments`
2. Actualizar `orders.total_paid += amount`
3. Si `total_paid >= total` → cambiar status a `cobrado` automáticamente

**Response 201:**
```json
{
  "data": {
    "payment_uuid": "p1a2b3c4-...",
    "amount": 10000,
    "payment_method": "efectivo",
    "new_total_paid": 15000,
    "remaining_balance": 30000,
    "order_status": "listo",
    "created_at": "2026-03-29T14:30:00Z"
  }
}
```

**Response 422** (monto excede saldo):
```json
{
  "error": "amount_exceeds_balance",
  "message": "El abono ($15.000) excede el saldo pendiente ($10.000)",
  "remaining_balance": 10000
}
```

---

#### `GET /api/v1/orders/{orderUuid}/payments` — Historial de abonos de una orden
**Auth:** Requerida

**Response 200:**
```json
{
  "data": {
    "order_uuid": "ord-001",
    "order_label": "Mesa 4",
    "total": 45000,
    "total_paid": 15000,
    "remaining_balance": 30000,
    "payments": [
      {
        "uuid": "p1a2b3c4-...",
        "amount": 10000,
        "payment_method": "efectivo",
        "employee_name": "Carlos",
        "note": null,
        "created_at": "2026-03-29T14:30:00Z"
      },
      {
        "uuid": "p2b3c4d5-...",
        "amount": 5000,
        "payment_method": "nequi",
        "employee_name": "Carlos",
        "note": "Abono Nequi",
        "created_at": "2026-03-28T16:15:00Z"
      }
    ]
  }
}
```

---

#### Actualizar endpoint existente `GET /api/v1/orders/open-accounts`

**Response actualizada** (agregar campos de abono):
```json
{
  "data": [
    {
      "uuid": "ord-001",
      "label": "Mesa 4",
      "customer_name": "Juan Pérez",
      "employee_name": "Carlos",
      "status": "listo",
      "type": "mesa",
      "total": 45000,
      "total_paid": 15000,
      "remaining_balance": 30000,
      "item_count": 5,
      "items": [...],
      "created_at": "2026-03-29T12:00:00Z"
    }
  ]
}
```

---

## MÓDULO 3: DIVISIÓN DE CUENTA (SPLIT BILL)

### 3.1 Sin tabla adicional
La división de cuenta es un **cálculo del frontend**. No requiere tabla nueva. Pero el backend debe soportar:

#### `POST /api/v1/orders/{orderUuid}/split-payments` — Registrar pago dividido
**Auth:** Requerida (admin/cajero)

**Caso de uso:** Mesa de 3 personas. Cada una paga $10.000. El cajero registra 3 abonos de una vez.

**Request Body:**
```json
{
  "split_count": 3,
  "amount_per_person": 10000,
  "payments": [
    { "payment_method": "efectivo", "amount": 10000, "payer_name": "Persona 1" },
    { "payment_method": "nequi", "amount": 10000, "payer_name": "Persona 2" },
    { "payment_method": "daviplata", "amount": 10000, "payer_name": "Persona 3" }
  ]
}
```

**Validaciones:**
- `payments.length` debe ser igual a `split_count`
- La suma de `payments[].amount` no puede exceder `remaining_balance`
- Cada `amount` > 0

**Lógica:**
1. Por cada payment, insertar en `order_payments` con `note = "División {n}/{total} - {payer_name}"`
2. Actualizar `orders.total_paid`
3. Si cubre el total → marcar como `cobrado`

**Response 201:**
```json
{
  "data": {
    "split_count": 3,
    "payments_registered": 3,
    "total_collected": 30000,
    "new_total_paid": 30000,
    "remaining_balance": 0,
    "order_status": "cobrado"
  }
}
```

---

## MÓDULO 4: CUENTA REAL-TIME PÚBLICA (ACTUALIZACIÓN)

### 4.1 Tabla nueva para clientes recurrentes

```sql
-- ══════════════════════════════════════════════════════════
-- TABLA: client_sessions (clientes que verifican su celular)
-- ══════════════════════════════════════════════════════════
CREATE TABLE client_sessions (
    id              SERIAL PRIMARY KEY,
    uuid            UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    phone           VARCHAR(20) NOT NULL,

    -- Verificación OTP
    otp_code        VARCHAR(6),
    otp_expires_at  TIMESTAMPTZ,
    verified        BOOLEAN DEFAULT FALSE,

    -- Token de sesión del cliente (JWT simple, 24h)
    session_token   TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(tenant_id, phone)
);

CREATE INDEX idx_client_sessions_phone ON client_sessions(tenant_id, phone);
```

### 4.2 Endpoints Cuenta Pública (actualizar existentes + nuevos)

#### `GET /api/v1/account/{orderUuid}` — Cuenta en tiempo real (ACTUALIZAR)
**Auth:** Pública (sin JWT del tendero)

**Response 200 actualizada** (agregar abonos y split info):
```json
{
  "data": {
    "store_name": "Tienda Don Pedro",
    "store_logo_url": "https://r2.vendia.com/logos/...",
    "order": {
      "uuid": "ord-001",
      "label": "Mesa 4",
      "status": "listo",
      "type": "mesa",
      "items": [
        {
          "product_name": "Cerveza Águila",
          "quantity": 2,
          "unit_price": 5000,
          "subtotal": 10000,
          "emoji": "🍺"
        },
        {
          "product_name": "Empanada",
          "quantity": 3,
          "unit_price": 2500,
          "subtotal": 7500
        }
      ],
      "total": 45000,
      "total_paid": 15000,
      "remaining_balance": 30000,
      "payments": [
        {
          "amount": 10000,
          "payment_method": "efectivo",
          "created_at": "2026-03-29T14:30:00Z"
        },
        {
          "amount": 5000,
          "payment_method": "nequi",
          "created_at": "2026-03-28T16:15:00Z"
        }
      ],
      "created_at": "2026-03-29T12:00:00Z"
    },
    "rockola_enabled": true,
    "whatsapp_receipt_enabled": true
  }
}
```

---

#### `POST /api/v1/account/{orderUuid}/verify` — Verificar celular del cliente (ACTUALIZAR)
**Auth:** Pública

**Request Body (paso 1 — solicitar OTP):**
```json
{
  "phone": "3105551234",
  "action": "request_otp"
}
```

**Response 200:**
```json
{
  "data": {
    "message": "Código enviado por SMS",
    "otp_sent": true,
    "expires_in_seconds": 300
  }
}
```

**Request Body (paso 2 — verificar OTP):**
```json
{
  "phone": "3105551234",
  "action": "verify_otp",
  "otp_code": "847291"
}
```

**Response 200:**
```json
{
  "data": {
    "verified": true,
    "client_token": "eyJ...",
    "message": "Celular verificado. Ahora puede ver su historial."
  }
}
```

---

#### `GET /api/v1/account/history?phone={phone}` — Historial de cuentas del cliente
**Auth:** Requiere `client_token` en header `X-Client-Token: {token}`

**Query Params:**
- `phone`: Número verificado (debe coincidir con el token)
- `page`: default 1
- `per_page`: default 20

**Response 200:**
```json
{
  "data": {
    "phone": "3105551234",
    "store_name": "Tienda Don Pedro",
    "total_visits": 15,
    "total_spent": 450000,
    "accounts": [
      {
        "order_uuid": "ord-001",
        "label": "Mesa 4",
        "total": 45000,
        "total_paid": 45000,
        "remaining_balance": 0,
        "status": "cobrado",
        "item_count": 5,
        "items_summary": "Cerveza Águila x2, Empanada x3, ...",
        "payments": [
          { "amount": 10000, "method": "efectivo", "created_at": "2026-03-29T14:30:00Z" },
          { "amount": 5000, "method": "nequi", "created_at": "2026-03-28T16:15:00Z" },
          { "amount": 30000, "method": "efectivo", "created_at": "2026-03-29T18:00:00Z" }
        ],
        "created_at": "2026-03-29T12:00:00Z",
        "closed_at": "2026-03-29T18:05:00Z"
      },
      {
        "order_uuid": "ord-prev-001",
        "label": "Mesa 2",
        "total": 32000,
        "total_paid": 32000,
        "remaining_balance": 0,
        "status": "cobrado",
        "item_count": 3,
        "items_summary": "Arroz con pollo x1, Gaseosa x2",
        "payments": [
          { "amount": 32000, "method": "efectivo", "created_at": "2026-03-25T13:00:00Z" }
        ],
        "created_at": "2026-03-25T12:30:00Z",
        "closed_at": "2026-03-25T13:05:00Z"
      }
    ]
  },
  "meta": { "page": 1, "per_page": 20, "total": 15 }
}
```

> **Matching:** El backend busca `orders` donde `customer_phone = {phone}` AND `tenant_id` del store. El `tenant_id` se extrae del `client_token` (que se genera al verificar OTP en el contexto de un `orderUuid` específico que pertenece a un tenant).

---

## MÓDULO 5: ACTUALIZAR MODELO `orders` EXISTENTE

### 5.1 Campos nuevos en la tabla `orders`

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total_paid       INTEGER NOT NULL DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_phone   VARCHAR(20);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS closed_at        TIMESTAMPTZ;
```

### 5.2 Trigger para auto-cerrar orden

```sql
-- Cuando total_paid >= total, auto-marcar como cobrado
CREATE OR REPLACE FUNCTION check_order_fully_paid()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.total_paid >= (SELECT total FROM orders WHERE uuid = NEW.order_uuid) THEN
        UPDATE orders
        SET status = 'cobrado', closed_at = NOW()
        WHERE uuid = NEW.order_uuid AND status != 'cobrado';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_fully_paid
AFTER INSERT ON order_payments
FOR EACH ROW
EXECUTE FUNCTION check_order_fully_paid();
```

---

## RESUMEN DE ENDPOINTS NUEVOS

| # | Método | Ruta | Auth | Módulo |
|---|--------|------|------|--------|
| 1 | `GET` | `/api/v1/sos/config` | JWT (admin) | SOS |
| 2 | `PUT` | `/api/v1/sos/config` | JWT (admin) | SOS |
| 3 | `POST` | `/api/v1/sos/trigger` | JWT (cualquier rol) | SOS |
| 4 | `GET` | `/api/v1/sos/history` | JWT (admin) | SOS |
| 5 | `POST` | `/api/v1/orders/{uuid}/payments` | JWT | Abonos |
| 6 | `GET` | `/api/v1/orders/{uuid}/payments` | JWT | Abonos |
| 7 | `POST` | `/api/v1/orders/{uuid}/split-payments` | JWT | Split |
| 8 | `GET` | `/api/v1/account/history` | Client Token | Historial |

### Endpoints existentes a ACTUALIZAR:
| Ruta | Cambio |
|------|--------|
| `GET /api/v1/orders/open-accounts` | Agregar `total_paid`, `remaining_balance` |
| `GET /api/v1/account/{orderUuid}` | Agregar `payments[]`, `total_paid`, `remaining_balance` |
| `POST /api/v1/account/{orderUuid}/verify` | Agregar flujo OTP + `client_token` |

---

## TABLAS NUEVAS RESUMEN

| Tabla | Propósito | FK principal |
|-------|-----------|-------------|
| `sos_config` | Config de emergencia por tenant | `tenants.id` |
| `sos_alerts` | Log de cada activación del pánico | `tenants.id` |
| `order_payments` | Abonos/pagos parciales | `orders.uuid` |
| `client_sessions` | Clientes que verifican celular | `tenants.id` |

## COLUMNAS NUEVAS EN TABLAS EXISTENTES

| Tabla | Columna | Tipo | Propósito |
|-------|---------|------|-----------|
| `orders` | `total_paid` | `INTEGER DEFAULT 0` | Suma de abonos registrados |
| `orders` | `customer_phone` | `VARCHAR(20)` | Para matching de historial |
| `orders` | `closed_at` | `TIMESTAMPTZ` | Timestamp de cierre |

---

## SERVICIOS EXTERNOS NECESARIOS

| Servicio | Uso | Prioridad |
|----------|-----|-----------|
| **Twilio SMS** | Enviar SMS de emergencia + OTP verificación | ALTA |
| **WhatsApp Business API** | Mensajes de emergencia + receipts | ALTA |
| **Twilio Voice / TTS** | Llamada automática con voz IA al 123 | MEDIA |
| **Geolocation** | Coordenadas GPS en alerta de pánico | ALTA |

---

## NOTAS DE IMPLEMENTACIÓN

### Sobre el Pánico:
- El endpoint `POST /sos/trigger` DEBE responder en < 200ms. El envío de SMS/WA/Call va en goroutine async.
- Guardar SIEMPRE el log en `sos_alerts` aunque falle el envío.
- El tendero NO debe saber si falló el SMS — solo sabe que "se envió".
- Rate limit: máximo 3 triggers por tenant en 10 minutos (evitar spam accidental).

### Sobre los Abonos:
- El redondeo a $50 COP lo hace el frontend. El backend valida que sea múltiplo de 50.
- `total_paid` es un campo denormalizado. Opcionalmente se puede recalcular: `SELECT SUM(amount) FROM order_payments WHERE order_uuid = ?`
- Cuando `total_paid >= total`, auto-cambiar status a `cobrado`.

### Sobre el Historial del Cliente:
- El `client_token` es un JWT simple con: `{ tenant_id, phone, exp: 24h }`.
- NO es el mismo JWT del tendero. Es un token liviano para el cliente.
- El OTP expira en 5 minutos. 6 dígitos numéricos.
- Rate limit OTP: máximo 3 envíos por phone por hora.

### Sobre Split:
- El split es cosmético en el frontend (calcula `saldo / n personas`).
- El backend lo recibe como N pagos individuales en un solo request.
- Cada pago puede tener diferente `payment_method` (uno paga efectivo, otro Nequi).
