# Arquitectura API interna

MerkaERP define una capa API interna para separar la interfaz Flutter de los
servicios que en el futuro podran exponerse por REST, sincronizacion o CLI.

## Piezas principales

- `lib/core/api/api_contract.dart`: catalogo versionado de endpoints, metodo,
  modulo y accion requerida.
- `lib/core/api/api_dispatcher.dart`: despachador de requests. Valida permisos,
  transforma payloads externos a requests de aplicacion, publica eventos de
  integracion y serializa respuestas.
- `lib/core/security/action_permission.dart`: reglas de permisos granulares por
  rol, modulo y accion.
- `lib/core/database/database_gateway.dart`: abstraccion del motor de datos. La
  implementacion actual usa SQLite, pero los repositorios no dependen del API
  directo de `sqflite`.
- `lib/core/company/company_context.dart`: proveedor de empresa activa para
  aislar lecturas y escrituras por `company_id`.
- `lib/core/events/event_store.dart`: event store persistente con idempotencia,
  correlacion, causation y versionado.
- `lib/core/events/event_dispatcher.dart`: cola asincrona con retry,
  dead letters y replay hacia proyecciones.
- `lib/cqrs/application/dashboard_projection.dart`: read model materializado
  para KPIs ejecutivos por empresa y sucursal.

## Endpoints activos

- `GET /api/v1/products`
- `GET /api/v1/sales`
- `POST /api/v1/sales`
- `GET /api/v1/purchases`
- `POST /api/v1/purchases`
- `GET /api/v1/reports/summary`
- `GET /api/v1/accounting/trial-balance`
- `GET /api/v1/reports/tax`
- `GET /api/v1/system/readiness`
- `GET /api/v1/system/data-health`
- `GET /api/v1/security/permissions`
- `GET /api/v1/procurement/workflow`
- `GET /api/v1/sales/workflow`
- `GET /api/v1/inventory/replenishment`
- `GET /api/v1/platform/scope`
- `GET /api/v1/sync/status`
- `GET /api/v1/licensing/status`
- `GET /api/v1/telemetry/health`
- `GET /api/v1/workflows/templates`
- `POST /api/v1/rules/evaluate`
- `GET /api/v1/events`
- `POST /api/v1/events/replay`
- `GET /api/v1/cqrs/executive-dashboard`

Los endpoints de lectura y creacion de ventas/compras pasan por repositorios o
casos de uso. Las mutaciones publican eventos de integracion. Los endpoints de
eventos permiten consultar el log persistente, reprocesar colas y leer el
dashboard ejecutivo desde una proyeccion CQRS materializada.

## Formato de request

El dispatcher acepta campos externos en ingles, por ejemplo:

```json
{
  "payment_method_id": 1,
  "payment_method": "EFECTIVO",
  "client": "Cliente API",
  "items": [
    {
      "product_id": 3,
      "product": "Producto API",
      "quantity": 2,
      "unit_price": 5000,
      "unit_cost": 3000,
      "subtotal": 10000,
      "tax_rate": 19,
      "tax_total": 1900
    }
  ]
}
```

Tambien conserva compatibilidad con mapas legacy usados por la UI Flutter.

## Estado de multiempresa y multisucursal

Inventario, ventas y compras consultan por empresa activa mediante
`CompanyContextProvider`. Las operaciones event-driven usan `BranchScopeProvider`
para incluir `company_id`, `branch_id`, `warehouse_id` y `cost_center_id` en
eventos, ledger e inventario.

## Contratos de operacion

1. Toda mutacion con impacto operativo publica un `IntegrationEvent`.
2. Cada evento persistido recibe `idempotency_key`, `correlation_id`,
   `causation_id`, `trace_id`, version y scope.
3. Las proyecciones deben ser idempotentes usando offsets por
   `projection_name`, empresa y sucursal.
4. Los errores asincronos se retienen en `event_dead_letters` con payload JSON.
5. La contabilidad se escribe como `JournalEntry` posteado, balanceado y
   reversible.
6. El inventario de alta precision se mueve mediante `StockLedger` con lotes,
   reservas y metodo de costeo explicito.

## Contrato distribuido

Toda mutacion futura debe viajar con:

- `tenant_id`
- `company_id`
- `branch_id`
- `warehouse_id` cuando aplique inventario
- `cost_center_id` cuando aplique finanzas
- `idempotency_key`
- `correlation_id`
- `vector_clock`

Esto permite reintentos, replicacion selectiva, resolucion de conflictos y
auditoria entre sedes.
