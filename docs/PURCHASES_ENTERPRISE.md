# PURCHASES Enterprise Context

## Alcance operativo

PURCHASES ahora opera como bounded context enterprise para solicitudes de
compra, RFQ, ordenes, recepciones de mercancia, facturas proveedor, notas debito
y devoluciones. Sigue el patron de SALES: agregado rico, comandos, queries,
eventos, CQRS, persistencia SQLite, compatibilidad PostgreSQL, auditoria,
telemetry, permisos y sync hooks.

## Agregado

`PurchaseDocument` controla:

- empresa, sucursal, bodega y centro de costo
- proveedor y vencimiento
- presupuesto disponible
- lineas con costo, cantidades ordenadas y recibidas
- impuestos dinamicos y retenciones
- aprobaciones multinivel con SLA y escalamiento
- reversos e inmutabilidad para documentos posted/reversed

Estados:

- `draft`
- `pendingApproval`
- `approved`
- `partiallyReceived`
- `received`
- `posted`
- `cancelled`
- `reversed`

## Integraciones

- Tax engine: `PurchaseTaxService` usa catalogo activo tenant/company-aware y
  reglas country-aware para aplicar impuestos y retenciones sin hardcodear tasas
  en el handler.
- Inventory: `PurchaseCommandHandlers.receive` puede usar `StockLedgerService`
  para crear lotes warehouse-aware en recepciones parciales o totales.
- Accounting: `PurchaseCommandHandlers.post` puede usar
  `AccountingPostingService` para journal entries con inventario, impuesto
  descontable, retenciones y proveedor.
- Treasury/AP: `supplier_balances` registra saldo proveedor y forecast CXP.
- Sync: comandos crean envelopes incrementales cuando reciben `SyncOrchestrator`.

## Persistencia

SQLite v38 agrega:

- `purchase_documents`
- `purchase_document_lines`
- `purchase_approval_steps`
- `purchase_document_audit`
- `supplier_balances`
- `purchase_analytics_read_model`

PostgreSQL equivalente en `backend/migrations/001_platform.sql`.

## Eventos

- `PurchaseApprovedEvent`
- `GoodsReceivedEvent`
- `SupplierInvoicePostedEvent`
- `PurchaseReversedEvent`
- `SupplierBalanceUpdatedEvent`

`PurchaseAnalyticsProjection` materializa eventos en
`purchase_analytics_read_model` y participa del dispatcher asincrono existente,
con retries, dead letters y replay ya provistos por `EventDispatcher`.

## Endpoints

- `GET /api/v1/purchases/documents`
- `POST /api/v1/purchases/documents`
- `POST /api/v1/purchases/documents/approve`
- `POST /api/v1/purchases/documents/receive`
- `POST /api/v1/purchases/documents/post`
- `POST /api/v1/purchases/documents/reverse`
- `GET /api/v1/purchases/analytics`

## Permisos

- `purchases.create`
- `purchases.approve`
- `purchases.receive`
- `purchases.post`
- `purchases.reverse`

Las acciones sensibles escriben en `purchase_document_audit` y en el pipeline
global `auditoria_eventos`.

## Validacion

Cobertura en `test/purchases_enterprise_test.dart`:

- maquina de estados, recepciones parciales, posting e inmutabilidad
- aprobaciones multinivel con SLA
- eventos, auditoria, saldo proveedor y analytics
- endpoints enterprise de compras en `ApiDispatcher`
