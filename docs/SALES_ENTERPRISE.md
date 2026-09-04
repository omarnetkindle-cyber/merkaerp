# SALES Enterprise Context

## Alcance operativo

SALES ahora incluye un vertical slice empresarial para documentos comerciales:
cotizaciones, pedidos, facturas, transacciones POS, notas credito y devoluciones.
El agregado `SalesDocument` controla lineas, descuentos, impuestos calculados por
documento, terminos de pago, cliente, empresa, sucursal, bodega y centro de
costo.

## Maquina de estados

Estados soportados:

- `draft`
- `pending`
- `approved`
- `posted`
- `cancelled`
- `reversed`

Transiciones principales:

- `draft -> pending -> approved -> posted`
- `draft/pending/approved -> cancelled`
- `posted -> reversed`

Los documentos `posted` y `reversed` son inmutables. Los cambios posteriores se
realizan mediante reversos trazables con nota credito.

## Persistencia

SQLite v37 agrega:

- `sales_documents`
- `sales_document_lines`
- `sales_document_audit`
- `sales_analytics_read_model`

La migracion PostgreSQL en `backend/migrations/001_platform.sql` contiene las
tablas equivalentes con tipos `UUID`, `JSONB`, `TIMESTAMPTZ` y `NUMERIC`.

## Application Layer

- `SalesCommandHandlers`
  - crea documentos comerciales
  - postea documentos con aprobacion automatica si aplica
  - reversa documentos posted
  - registra auditoria sensible
  - emite eventos de dominio
  - encola sync cuando se provee `SyncOrchestrator`
  - registra telemetry estructurada
- `SalesQueryHandlers`
  - lista documentos filtrados por alcance activo
  - calcula analitica comercial por empresa, sucursal y bodega

## Eventos y CQRS

Eventos emitidos:

- `SalePostedEvent`
- `TaxCalculatedEvent`
- `sales.reversed`

Proyeccion:

- `SalesAnalyticsProjection` materializa ventas e impuestos posteados/reversados
  en `sales_analytics_read_model`.

## Endpoints REST internos

- `GET /api/v1/sales/documents`
- `POST /api/v1/sales/documents`
- `POST /api/v1/sales/documents/post`
- `POST /api/v1/sales/documents/reverse`
- `GET /api/v1/sales/analytics`

Todos pasan por `ApiContract`, `ApiDispatcher` y `PermissionService`.

## Permisos

Acciones granulares agregadas:

- `sales.create`
- `sales.post`
- `sales.reverse`

`administrador` conserva acceso total. `contador` puede postear y reversar; los
roles operativos mantienen permisos acotados.

## Validacion

Cobertura agregada en `test/sales_enterprise_test.dart`:

- maquina de estados e inmutabilidad
- command handlers, auditoria, eventos y analitica
- endpoints enterprise de SALES en `ApiDispatcher`
