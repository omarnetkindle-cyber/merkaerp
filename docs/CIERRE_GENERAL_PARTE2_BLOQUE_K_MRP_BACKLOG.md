# Cierre general PARTE 2 - Bloque K

Fecha: 2026-08-14

## Alcance

Backlog explicito de MRP:

- Subcontratacion: una operacion de ruta puede tercerizarse con proveedor, costo y plazo.
- Rutas alternativas: mas de una ruta por producto, con default/prioridad/criterio de seleccion.
- Calendarios de turnos: capacidad variable por dia de semana y turno para cada Workstation.

## Fuentes consultadas

- ERPNext Routing: https://docs.frappe.io/erpnext/routing
  - La ruta es una plantilla de operaciones BOM y almacena operaciones, tarifa horaria y tiempo de operacion.
- ERPNext Operation: https://docs.frappe.io/erpnext/operation
  - Una operacion tiene una estacion de trabajo por defecto y se trae hacia BOM/Work Orders.
- ERPNext Capacity Planning: https://docs.frappe.io/erpnext/production-and-material-planning-capacity-planning
  - La capacidad se programa segun tiempos definidos en la Workstation y disponibilidad; el Work Order usa fecha planificada y tiempo de operacion.
- ERPNext Subcontracting Inward: https://docs.frappe.io/erpnext/subcontracting-inward
  - La subcontratacion relaciona servicio/no-stock con producto terminado/BOM; para MerkaERP se implemento como operacion tercerizada dentro de la ruta, sin duplicar inventario.

Decision conservadora: no se copio el flujo completo de ERPNext ni se agregaron documentos de compra nuevos. MerkaERP mantiene su Work Order e inventario actuales; la subcontratacion entra como costo/plazo auditable de una operacion y las transferencias fisicas siguen delegadas a `WarehouseStockService`.

## Implementacion

- Migracion v104:
  - `mrp_routings.item_id`
  - `mrp_routings.priority`
  - `mrp_routings.is_active`
  - `mrp_routings.is_default`
  - `mrp_routings.selection_criteria`
  - `mrp_operations.is_subcontracted`
  - `mrp_operations.supplier_id`
  - `mrp_operations.subcontract_cost`
  - `mrp_operations.lead_time_days`
  - Nueva tabla `mrp_workstation_shifts`.
- `MrpRouting` ahora soporta ruta alternativa por producto, prioridad y default.
- `MrpOperation` ahora soporta operacion subcontratada con proveedor, costo y plazo.
- `MrpWorkstationShift` modela turnos por dia de semana.
- `MrpRoutingService.defaultForProduct` selecciona la ruta activa por default/prioridad.
- `MrpBomService.createDraft` usa la ruta default del producto si existe.
- `MrpBomService.recalculate` suma costo de operacion interna por hora y costo fijo de operacion subcontratada.
- `MrpWorkOrderService.create` valida capacidad por fecha planificada antes de persistir la orden:
  - operaciones internas consumen horas de Workstation;
  - operaciones subcontratadas no consumen capacidad interna;
  - si hay turnos para el dia, usa la suma de turnos;
  - si no hay turnos, usa `available_hours_per_day`.

Correccion defensiva relacionada durante la verificacion: los helpers de migracion de columnas ahora omiten tablas ausentes en bases parciales de prueba. Esto corrigio el caso de `migrarDBForTesting` sobre bases minimas sin CRM/CxP/MRP completas.

## Evidencia cruda - tests del bloque

Comando:

```powershell
flutter test test\mrp\mrp_module_test.dart test\mrp\mrp_capacity_migration_test.dart test\mrp\mrp_backlog_k_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:03 +0: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP crea entidades, calcula costos, explota BOM y mueve stock
00:04 +1: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP rechaza transiciones de orden no permitidas
00:04 +2: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP bloquea BOM circular directa e indirecta sin guardar la orden
00:04 +3: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP calcula y explota BOM multinivel en todos sus niveles
00:04 +4: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP bloquea iniciar una orden si falta stock sin transferencias parciales
00:04 +5: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP revierte material WIP al cancelar una orden en proceso
00:04 +6: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP no permite cambiar una BOM usada por una orden activa
00:04 +7: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: MRP permite cerrar una orden con produccion parcial
00:04 +8: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart: (tearDownAll)
00:04 +8: loading C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_capacity_migration_test.dart
00:05 +8: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_capacity_migration_test.dart: v83 agrega capacidad temporal sin alterar filas existentes
00:05 +9: loading C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_backlog_k_test.dart
00:06 +9: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_backlog_k_test.dart: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:10 +9: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_backlog_k_test.dart: MRP selecciona ruta default, suma subcontratacion y valida turnos
00:10 +10: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_backlog_k_test.dart: v104 agrega rutas alternativas, subcontratacion y turnos
00:10 +11: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_backlog_k_test.dart: (tearDownAll)
00:10 +11: All tests passed!
```

## Evidencia cruda - migraciones parciales

Comando:

```powershell
flutter test test\mrp\mrp_capacity_migration_test.dart test\crm\crm_backlog_comercial_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_capacity_migration_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_capacity_migration_test.dart: v83 agrega capacidad temporal sin alterar filas existentes
00:00 +1: loading C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart
00:01 +1: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:04 +1: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: campanas, territorios, forecasting y embudo usan datos reales
00:05 +2: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: CRM backlog bloquea datos invalidos con mensajes especificos
00:05 +3: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: (tearDownAll)
00:05 +3: All tests passed!
```

## Evidencia cruda - analisis dirigido

Comando:

```powershell
dart analyze lib\mrp\database\schema_mrp.dart lib\mrp\domain\mrp_routing.dart lib\mrp\domain\mrp_operation.dart lib\mrp\domain\mrp_workstation_shift.dart lib\mrp\data\mrp_repositories.dart lib\mrp\application\mrp_services.dart lib\crm\database\schema_crm.dart lib\db_helper.dart test\mrp\mrp_backlog_k_test.dart
```

Salida:

```text
Analyzing schema_mrp.dart, mrp_routing.dart, mrp_operation.dart, mrp_workstation_shift.dart, mrp_repositories.dart, mrp_services.dart, schema_crm.dart, db_helper.dart, mrp_backlog_k_test.dart...

   info - lib\db_helper.dart:876:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\db_helper.dart:892:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print

2 issues found.
```

## Evidencia cruda - flutter analyze global

Comando:

```powershell
flutter analyze 1> bloque_k_analyze.txt 2> bloque_k_analyze_error.txt
```

Resultado observado:

```text
EXIT_CODE=1
ERROR_COUNT=0
225 issues found. (ran in 94.9s)
```

Ultimas lineas:

```text
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:112:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:265:37 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1139:7 - unused_element
   info - Statements in an if should be enclosed in a block - lib\ventas_page.dart:1077:13 - curly_braces_in_flow_control_structures
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - Unused import: 'package:merka_erp/main.dart' - test\login_widget_test.dart:10:8 - unused_import
   info - The import of 'package:sqflite/sqflite.dart' is unnecessary because all of the used elements are also provided by the import of 'package:sqflite_common_ffi/sqflite_ffi.dart' - test\orders_quotes_money_test.dart:7:8 - unnecessary_import
   info - Use interpolation to compose strings and values - test\sector_publico\configuracion\configuracion_general_service_smoke_test.dart:24:14 - prefer_interpolation_to_compose_strings
   info - Use interpolation to compose strings and values - test\sector_publico\configuracion\configuracion_general_service_smoke_test.dart:26:11 - prefer_interpolation_to_compose_strings
   info - Use a function declaration rather than a variable assignment to bind a function to a name - test\sector_publico\contabilidad\estado_financiero_nicsp1_integracion_test.dart:113:7 - prefer_function_declarations_over_variables
warning - Unused import: 'package:merka_erp/core/currency/public_sector_money.dart' - test\sector_publico\regalias\sicodis_service_test.dart:6:8 - unused_import
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:19:33 - unused_local_variable
   info - The import of 'package:sqflite/sqflite.dart' is unnecessary because all of the used elements are also provided by the import of 'package:sqflite_common_ffi/sqflite_ffi.dart' - tool\audit_schema_queries.dart:3:8 - unnecessary_import
   info - Can't use a relative path to import a library in 'lib' - tool\audit_schema_queries.dart:6:8 - avoid_relative_lib_imports
```

## Estado del bloque

Completo. MRP ahora soporta subcontratacion por operacion, rutas alternativas por producto y turnos de Workstation con validacion de capacidad al crear la orden. No se implemento calendario de feriados ni job cards por operacion; quedan como mejora futura porque el alcance pedido fue capacidad variable por dia/turno, no programacion fina multi-dia.
