# PROGRESO de módulos Odoo -> MerkaERP

Este archivo registra el avance del proceso de adaptación y extensión de funcionalidades de Odoo hacia MerkaERP.

- account + l10n_co_edi: en progreso
	- scaffold DIAN creado: Connector, xmlGenerator (placeholder), signer (P12), httpClient
	- pendiente: XSD mapping, certificados (P12), credenciales de homologación, pruebas integración
- account_budget: implementado (migraciones, modelos, rutas, pruebas)
- stock: pendiente
 - stock: PASO0 completado; PASO A (especificación) creado
	- PASO B: implementación en progreso
		- migraciones, modelos, rutas y tests básicos creados
		- integración: creación automática de `StockPicking` desde `purchase.confirm` añadida
- purchase: pendiente
- hr + hr_attendance + hr_holidays: parcial; ficha de empleado, calendario mensual de equipo, bandeja de aprobaciones con saldo/solapamiento y asistencia implementadas; altas/edicion avanzadas y politicas de nomina pendientes
- hr_payroll + l10n_co_hr_payroll: parcial; consulta local de ausencias aprobadas expuesta para nomina/DIAN; integracion de transmision electronica DIAN pendiente porque el cliente actual es NoOp
- project + helpdesk: pendiente
- portal: pendiente
- sign: pendiente
- mail.thread / chatter: pendiente
- approvals: pendiente
- documents: pendiente
- base_automation / ir.cron: pendiente
- quality: pendiente
- fleet: pendiente
- maintenance: pendiente
- crm: parcial; entidades CRM, Kanban interactivo y ficha con historial implementados; CRUD completo de cuentas y mantenimiento avanzado del pipeline pendientes
- point_of_sale: pendiente
- website / studio: pendiente

- CRM / CrmAccount / 2026-08-08: completado; reutiliza `clientes` como almacenamiento canonico. Archivos: `lib/crm/domain/crm_account.dart`, `lib/crm/data/crm_account_repository.dart`, `lib/crm/application/crm_account_service.dart`, `lib/crm/database/schema_crm.dart`, `test/crm/crm_module_test.dart`, `test/crm/crm_schema_compatibility_test.dart`.
- CRM / CrmContact / 2026-08-08: completado; tabla `crm_contacts` con cuenta y jerarquia de contactos. Archivos: `lib/crm/domain/crm_contact.dart`, `lib/crm/data/crm_contact_repository.dart`, `lib/crm/application/crm_contact_service.dart`, `lib/crm/database/schema_crm.dart`, `test/crm/crm_module_test.dart`.
- CRM / CrmLead / 2026-08-08: completado; tabla `crm_leads` y conversion atomica a cuenta, contacto y oportunidad. Archivos: `lib/crm/domain/crm_lead.dart`, `lib/crm/data/crm_lead_repository.dart`, `lib/crm/application/crm_lead_service.dart`, `lib/crm/database/schema_crm.dart`, `test/crm/crm_module_test.dart`.
- CRM / CrmOpportunity / 2026-08-08: completado; extiende `crm_opportunities`, con etapas y probabilidad automatica. Archivos: `lib/crm/domain/crm_opportunity.dart`, `lib/crm/data/crm_opportunity_repository.dart`, `lib/crm/application/crm_opportunity_service.dart`, `lib/crm/database/schema_crm.dart`, `lib/crm/pages/crm_pipeline_page.dart`, `lib/core/workspace/workspace_config.dart`, `test/crm/crm_module_test.dart`.
- CRM / CustomerInteraction / 2026-08-08: completado; deja de ser modelo huerfano y persiste en `crm_interactions`. Archivos: `lib/crm/domain/customer_interaction.dart`, `lib/crm/data/crm_interaction_repository.dart`, `lib/crm/application/crm_interaction_service.dart`, `lib/crm/database/schema_crm.dart`, `test/crm/crm_module_test.dart`.
- CRM / Robustez y UI / 2026-08-09: parcial; validaciones de entrada, rollback probado, siete probabilidades de etapa verificadas, Kanban con drag-and-drop/filtro por vendedor e indicadores, ficha de cuenta con historial de contactos/oportunidades/interacciones. Archivos creados/modificados: `lib/crm/application/`, `lib/crm/data/crm_opportunity_repository.dart`, `lib/crm/pages/crm_pipeline_page.dart`, `lib/crm/pages/crm_account_page.dart`, `lib/core/workspace/workspace_config.dart`, `test/crm/crm_module_test.dart`, `test/crm/crm_pipeline_page_test.dart`.
- HRM / HrmJobTitle / 2026-08-08: completado; catalogo de cargos en `hrm_job_titles`. Archivos: `lib/hrm/domain/hrm_job_title.dart`, `lib/hrm/data/hrm_job_title_repository.dart`, `lib/hrm/application/hrm_job_title_service.dart`, `lib/hrm/database/schema_hrm.dart`, `test/hrm/hrm_module_test.dart`.
- HRM / HrmEmployee / 2026-08-08: completado; reutiliza `empleados` y agrega solo columnas HRM faltantes de forma idempotente. Archivos: `lib/hrm/domain/hrm_employee.dart`, `lib/hrm/data/hrm_employee_repository.dart`, `lib/hrm/application/hrm_employee_service.dart`, `lib/hrm/database/schema_hrm.dart`, `test/hrm/hrm_schema_compatibility_test.dart`.
- HRM / HrmLeaveType / 2026-08-08: completado; seed idempotente de ocho tipos colombianos. Archivos: `lib/hrm/domain/hrm_leave_type.dart`, `lib/hrm/data/hrm_leave_type_repository.dart`, `lib/hrm/application/hrm_leave_type_service.dart`, `lib/hrm/database/schema_hrm.dart`, `test/hrm/hrm_module_test.dart`.
- HRM / HrmLeaveEntitlement / 2026-08-08: completado; saldo por empleado/tipo/periodo. Archivos: `lib/hrm/domain/hrm_leave_entitlement.dart`, `lib/hrm/data/hrm_leave_entitlement_repository.dart`, `lib/hrm/application/hrm_leave_entitlement_service.dart`, `lib/hrm/database/schema_hrm.dart`, `test/hrm/hrm_module_test.dart`.
- HRM / HrmLeaveRequest / 2026-08-08: completado; solicitudes asociadas a empleado y tipo de ausencia. Archivos: `lib/hrm/domain/hrm_leave_request.dart`, `lib/hrm/data/hrm_leave_request_repository.dart`, `lib/hrm/application/hrm_leave_request_service.dart`, `lib/hrm/database/schema_hrm.dart`, `test/hrm/hrm_module_test.dart`.
- HRM / HrmLeave / 2026-08-08: completado; aprobacion atomica con `days_used + length_days <= days_total` y consulta de aprobadas por periodo. Archivos: `lib/hrm/domain/hrm_leave.dart`, `lib/hrm/data/hrm_leave_repository.dart`, `lib/hrm/application/hrm_leave_service.dart`, `lib/hrm/database/schema_hrm.dart`, `test/hrm/hrm_module_test.dart`.
- HRM / HrmAttendanceRecord / 2026-08-08: completado; registro de entrada/salida por empleado. Archivos: `lib/hrm/domain/hrm_attendance_record.dart`, `lib/hrm/data/hrm_attendance_record_repository.dart`, `lib/hrm/application/hrm_attendance_service.dart`, `lib/hrm/database/schema_hrm.dart`, `test/hrm/hrm_module_test.dart`.
- MRP / Mejora robustez, funcionalidad y UI / 2026-08-09: completado; evidencia detallada y salidas crudas en `docs/MRP_MEJORAS_2026-08-09.md`.
- HRM / UI / 2026-08-08: parcial; ficha/listado de empleados y calendario mensual de ausencias aprobadas en `lib/hrm/pages/hrm_employee_page.dart` y `lib/hrm/pages/hrm_leave_calendar_page.dart`, disponibles desde `FeatureKey.payroll` en `lib/core/workspace/workspace_config.dart`.
- HRM / Robustez y aprobaciones / 2026-08-09: parcial; validacion de saldo condicional por `requires_entitlement`, solapamientos, rechazo auditable, terminacion bloqueada por ausencias pendientes, turnos abiertos y bandeja protegida por `AppAction.approve`. Archivos: `lib/hrm/application/hrm_leave_service.dart`, `lib/hrm/application/hrm_employee_service.dart`, `lib/hrm/application/hrm_leave_request_service.dart`, `lib/hrm/application/hrm_leave_entitlement_service.dart`, `lib/hrm/application/hrm_attendance_service.dart`, `lib/hrm/database/schema_hrm.dart`, `lib/hrm/domain/hrm_leave.dart`, `lib/hrm/domain/hrm_employee.dart`, `lib/hrm/pages/hrm_employee_page.dart`, `lib/hrm/pages/hrm_leave_calendar_page.dart`, `lib/hrm/pages/hrm_leave_approval_page.dart`, `test/hrm/hrm_module_test.dart`, `test/hrm/hrm_leave_approval_page_test.dart`.
- MRP / MrpWorkstation, MrpRouting, MrpOperation, MrpBom, MrpBomItem, MrpWorkOrder, MrpWorkOrderItem / 2026-08-09: completado; tablas `mrp_*`, explosión multinivel, cálculo de costos, estados de orden e integración con `productos`, `bodegas`, `stock_bodega` y `movimientos_inventario`. Archivos: `lib/mrp/database/schema_mrp.dart`, `lib/mrp/domain/`, `lib/mrp/data/mrp_repositories.dart`, `lib/mrp/application/mrp_services.dart`, `lib/inventory/application/warehouse_stock_service.dart`, `lib/mrp/pages/mrp_page.dart`, `test/mrp/mrp_module_test.dart`.
- MRP / Auditoria de completitud y capacidad temporal / 2026-08-09: parcial completado; migracion v83 con horas disponibles por dia, ficha de workstations, consumo de materia prima en WIP, cierre parcial de ordenes y actualizacion de UI-6. Rutas alternativas, subcontratacion y calendario de turnos quedan como decisiones de producto. Evidencia: `docs/MRP_COMPLETITUD_AUDITORIA_2026-08-09.md`, `test/mrp/mrp_capacity_migration_test.dart`, `test/mrp/mrp_module_test.dart`, `test/impact/impact_simulator_service_test.dart`.
- CRM / CrmOpportunityItem y demanda CRM->MRP / 2026-08-09: completado; linea de producto en `crm_opportunity_items`, precio en `MoneyValue`, ficha editable y demanda ponderada por probabilidad consumida por UI-6. Campanas, territorios, forecasting historico y conversion de embudo quedan como backlog por falta de entidades/periodos especificados. Archivos: `lib/crm/domain/crm_opportunity_item.dart`, `lib/crm/data/crm_opportunity_item_repository.dart`, `lib/crm/application/crm_opportunity_item_service.dart`, `lib/crm/database/schema_crm.dart`, `lib/crm/pages/crm_opportunity_page.dart`, `lib/crm/pages/crm_pipeline_page.dart`, `lib/impact/domain/impact_scenario.dart`, `lib/impact/application/impact_simulator_service.dart`, `lib/impact/pages/impact_simulator_page.dart`, `test/crm/crm_opportunity_items_test.dart`, `test/impact/impact_simulator_service_test.dart`, `docs/CRM_COMPLETITUD_AUDITORIA_2026-08-09.md`.
- HRM / Auditoria de completitud y metadatos / 2026-08-09: parcial; v85 agrega metadatos OrangeHRM de empleado, jerarquia `manager_id`, grado salarial y `exclude_in_reports_if_no_entitlement` en tipos de ausencia, con validacion y pruebas. La tarifa laboral horaria/capacidad vinculada a MRP queda pendiente de decision porque salario mensual no define jornada. Evidencia: `docs/HRM_COMPLETITUD_AUDITORIA_2026-08-09.md`, `test/hrm/hrm_module_test.dart`, `test/hrm/hrm_payroll_integration_test.dart`.
