# Final Enterprise Execution

## Bounded contexts finalizados

Este cierre completa los contextos restantes sobre la arquitectura existente de
MerkaERP, sin regenerar SALES ni PURCHASES.

Contextos integrados:

- Accounts Receivable
- Accounts Payable
- Treasury
- Bank Reconciliation
- Tax Engine
- Fixed Assets
- CRM Enterprise
- Reporting Engine

## Persistencia

SQLite v39 agrega tablas operativas multi-tenant, company-aware, branch-aware,
warehouse-aware y cost-center-aware para:

- cartera de clientes, aging, promesas, riesgo y bloqueos
- cuentas por pagar, ledger proveedor y programacion de pagos
- bancos, posiciones, transferencias y movimientos
- extractos, conciliaciones y partidas no conciliadas
- reglas tributarias, calculos y retenciones
- activos fijos, depreciacion contable/fiscal y eventos
- oportunidades CRM, timeline y notificaciones
- definiciones, ejecuciones y reportes materializados
- metricas event-driven enterprise

La migracion PostgreSQL equivalente esta en
`backend/migrations/001_platform.sql`.

## Eventos

Eventos criticos emitidos:

- `InvoicePaidEvent`
- `CustomerBlockedEvent`
- `TreasuryTransferCreatedEvent`
- `BankReconciledEvent`
- `AssetDepreciatedEvent`
- `TaxCalculatedEvent`
- `ReportGeneratedEvent`

`FinalEnterpriseProjection` participa en el `EventDispatcher` existente y
materializa metricas por empresa y sucursal en `enterprise_event_metrics`.

## API

Endpoints agregados:

- `GET /api/v1/ar/ledger`
- `GET /api/v1/ar/aging`
- `POST /api/v1/ar/collect`
- `POST /api/v1/ar/payment-promises`
- `POST /api/v1/ar/credit-limit`
- `GET /api/v1/ap/ledger`
- `GET /api/v1/ap/aging`
- `POST /api/v1/ap/schedule-payment`
- `POST /api/v1/ap/pay`
- `GET /api/v1/treasury/dashboard`
- `POST /api/v1/treasury/bank-accounts`
- `POST /api/v1/treasury/transfers`
- `POST /api/v1/bank/statements/import`
- `POST /api/v1/bank/reconcile`
- `GET /api/v1/bank/unmatched`
- `POST /api/v1/tax/rules`
- `POST /api/v1/tax/calculate`
- `GET /api/v1/assets/register`
- `POST /api/v1/assets/register`
- `POST /api/v1/assets/depreciate`
- `GET /api/v1/crm/pipeline`
- `POST /api/v1/crm/opportunities`
- `POST /api/v1/reports/definitions`
- `POST /api/v1/reports/generate`
- `GET /api/v1/reports/materialized`

## Seguridad

Permisos granulares agregados:

- `ar.collect`
- `ar.override_limit`
- `ap.schedule_payment`
- `treasury.transfer`
- `treasury.approve_payment`
- `bank.reconcile`
- `assets.depreciate`
- `crm.manage_pipeline`
- `reports.export`

Todas las acciones sensibles escriben en `enterprise_audit_log` y en el pipeline
global `auditoria_eventos`.

## Integraciones

- SALES genera eventos consumibles para cartera.
- PURCHASES genera eventos consumibles para cuentas por pagar.
- Treasury produce movimientos usados por conciliacion bancaria.
- Tax Engine calcula por reglas configurables, tenant-aware y country-aware.
- Fixed Assets emite depreciacion para integracion contable.
- CRM conserva timeline y notificaciones para seguimiento comercial.
- Reporting materializa datos de tesoreria, CRM, AR/AP y datasets ejecutivos.

## UI enterprise

`lib/erp_readiness_page.dart` ahora funciona como workspace empresarial conectado
al `ApiDispatcher` existente. La pantalla expone:

- dashboard ejecutivo con ventas, compras, inventario y cash flow proyectado
- tableros financieros para AR/AP, aging y ledgers
- tablero de tesoreria y conciliacion con operaciones no conciliadas
- pipeline CRM y funnel por etapa
- registro de activos fijos y depreciacion acumulada
- reportes materializados y superficie de comandos REST
- busqueda global, filtros por area, paleta de comandos y cambio
  empresa/sucursal usando el scope multi-tenant activo

## Validacion

`test/final_enterprise_contexts_test.dart` cubre el recorrido end-to-end por API
para tax, AR, AP, treasury, bank reconciliation, fixed assets, CRM y reporting,
incluyendo eventos enterprise.
