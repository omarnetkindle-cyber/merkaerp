# Arquitectura de Features de MerkaERP

MerkaERP usa una arquitectura basada en capacidades empresariales. La empresa
no se clasifica con un tipo rigido como `restaurant`; en su lugar se activan
features como `inventory_enabled`, `pos_enabled`, `payroll_enabled` o
`multi_branch_enabled`.

## Capas

- `lib/features/feature_key.dart`: claves estables de capabilities.
- `lib/features/feature_registry.dart`: catalogo central de features, nombres,
  descripciones, valores por defecto y dependencias.
- `lib/features/module_definition.dart`: definicion de cada modulo visible en
  el menu.
- `lib/features/company_configuration_service.dart`: cache y resolucion de la
  configuracion activa de la empresa.
- `lib/db_helper.dart`: persistencia SQLite, migraciones y validaciones locales.
- `lib/onboarding/onboarding_page.dart`: wizard de configuracion inicial.

## Persistencia

La migracion v29 agrega:

- `companies`
- `company_profiles`
- `company_features`
- `company_settings`
- `company_templates`

Se mantienen `empresa_config`, `empresas` y `app_config` por compatibilidad con
funcionalidades existentes.

La migracion v34 agrega complementos de madurez ERP:

- `bodegas`
- `centros_costo`
- `reglas_impuestos_empresa`
- `reglas_retenciones_empresa`
- `documentos_compra_flujo`
- `documentos_compra_flujo_lineas`
- `documentos_venta_flujo`
- `documentos_venta_flujo_lineas`
- `kardex_inventario`
- `sync_outbox`
- `api_clients`

La migracion v35 agrega la base distribuida:

- `branches`
- columnas `branch_id`, `warehouse_id`, `cost_center_id` en entidades
  operativas
- `sync_inbox`
- `sync_queue`
- `sync_events`
- `sync_conflicts`
- `sync_metadata`
- `tenant_licenses`
- `remote_support_sessions`
- `telemetry_events`
- `workflow_definitions`
- `workflow_steps`
- `workflow_conditions`
- `workflow_actions`
- `rule_definitions`
- `scheduler_jobs`
- `notifications`
- `plugin_registry`

La migracion v36 consolida arquitectura event-driven, CQRS, ledger e inventario
empresarial:

- `event_store`
- `event_dispatch_queue`
- `event_dead_letters`
- `cqrs_projection_offsets`
- `executive_kpi_read_model`
- `accounting_journal_entries`
- `accounting_journal_lines`
- `inventory_lots`
- `inventory_reservations`

Estas tablas quedan indexadas por empresa, sucursal, agregados, cola de
despacho, cuentas contables y producto/bodega para soportar reintentos,
replay, dashboards, contabilidad inmutable y stock por lotes.

## Reglas de acceso

El acceso a un modulo se resuelve con:

1. rol del usuario en `AppSession`
2. feature activa en `CompanyConfigurationService`
3. flags operativos existentes, como bloqueo de caja o periodos cerrados

El menu oculta modulos deshabilitados y las operaciones criticas validan
features desde la capa local de datos.
