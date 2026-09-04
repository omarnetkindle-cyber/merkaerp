# Cierre general PARTE 2 - Bloque J

Fecha: 2026-08-13

## Alcance

Backlog explicito de CRM:

- Campanas de marketing asociables a leads y oportunidades.
- Territorios de venta por geografia/sector y vendedor asignado.
- Forecasting por pipeline ponderado por probabilidad.
- Reporte de embudo lead -> oportunidad -> venta.

## Fuentes consultadas

- SuiteCRM, Campaigns: https://docs.suitecrm.com/user/core-modules/campaigns/
- SuiteCRM, Reports: https://docs.suitecrm.com/user/advanced-modules/reports/
- Urdhva Tech, SuiteCRM Sales Forecast User Guide: https://www.urdhva-tech.com/suitecrm-sales-forecast-user-guide

Decision conservadora: implementar el backlog como capacidades internas de MerkaERP sin copiar codigo ni UX de SuiteCRM. El forecast usa la regla de negocio comun de CRM: monto de oportunidad * probabilidad / 100, con MoneyValue en centavos.

## Implementacion

- `crm_campaigns`: campanas con tipo, estado, fechas, presupuesto, ingreso esperado y vendedor asignado.
- `crm_territories`: territorios con pais/departamento/ciudad/sector, vendedor asignado y estado activo.
- Columnas defensivas:
  - `crm_leads.campaign_id`
  - `crm_leads.territory_id`
  - `crm_opportunities.campaign_id`
  - `crm_opportunities.territory_id`
  - `clientes.territory_id`
- Servicios:
  - `CrmCampaignService`
  - `CrmTerritoryService`
  - `CrmSalesAnalyticsService`
- Modelos:
  - `CrmCampaign`
  - `CrmTerritory`
  - `CrmLead` ahora conserva campana/territorio.
  - `CrmOpportunity` ahora conserva campana/territorio.
- Migracion:
  - `db_helper.dart` sube a version 102 y ejecuta `SchemaCrm.crearBacklogComercial`.

## Evidencia cruda - test del bloque

Comando:

```powershell
flutter test test\crm\crm_backlog_comercial_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart
00:00 +0: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:03 +0: campanas, territorios, forecasting y embudo usan datos reales
00:03 +1: CRM backlog bloquea datos invalidos con mensajes especificos
00:03 +2: (tearDownAll)
00:03 +2: All tests passed!
```

## Evidencia cruda - regresion CRM base + backlog

Comando:

```powershell
flutter test test\crm\crm_module_test.dart test\crm\crm_backlog_comercial_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:03 +0: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: CrmAccount usa clientes y conserva la bandera de entidad
00:03 +1: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: CrmContact queda relacionado con una cuenta existente
00:03 +2: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: CRM valida cuentas padre, nombres y montos cero
00:03 +3: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: las lineas de oportunidad usan el catalogo y calculan total exacto
00:03 +4: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: CRM rechaza supervisor de otra cuenta y conserva contacto sin supervisor
00:04 +5: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: Lead se convierte atomica y unicamente una vez
00:04 +6: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: La conversion de lead hace rollback si falla la oportunidad
00:04 +7: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: Lead marcado no convertible no crea entidades
00:04 +8: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: Las siete etapas tienen probabilidad automatica y no se puede retroceder
00:04 +9: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: Opportunity aplica probabilidad y enlaza Closed Won con ventas
00:04 +10: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: CustomerInteraction queda persistida en crm_interactions
00:04 +11: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_module_test.dart: (tearDownAll)
00:04 +11: loading C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart
00:05 +11: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:08 +11: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: campanas, territorios, forecasting y embudo usan datos reales
00:09 +12: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: CRM backlog bloquea datos invalidos con mensajes especificos
00:09 +13: C:/Users/PC/Desktop/Caja_simple/test/crm/crm_backlog_comercial_test.dart: (tearDownAll)
00:09 +13: All tests passed!
```

## Evidencia cruda - analisis dirigido

Comando:

```powershell
dart analyze lib\crm\database\schema_crm.dart lib\crm\domain\crm_account.dart lib\crm\domain\crm_lead.dart lib\crm\domain\crm_opportunity.dart lib\crm\domain\crm_campaign.dart lib\crm\domain\crm_territory.dart lib\crm\application\crm_campaign_service.dart lib\crm\application\crm_territory_service.dart lib\crm\application\crm_sales_analytics_service.dart lib\db_helper.dart test\crm\crm_backlog_comercial_test.dart
```

Salida:

```text
Analyzing schema_crm.dart, crm_account.dart, crm_lead.dart, crm_opportunity.dart, crm_campaign.dart, crm_territory.dart, crm_campaign_service.dart, crm_territory_service.dart, crm_sales_analytics_service.dart, db_helper.dart, crm_backlog_comercial_test.dart...

   info - lib\db_helper.dart:876:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\db_helper.dart:892:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print

2 issues found.
```

## Evidencia cruda - flutter analyze global

Comando:

```powershell
flutter analyze 1> bloque_j_analyze.txt 2> bloque_j_analyze_error.txt
```

Resultado observado:

```text
EXIT_CODE=1
ERROR_COUNT=0
flutter : 235 issues found. (ran in 9.7s)
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

Completo. La prueba dirigida confirma campanas, territorios, forecast ponderado y embudo con datos reales en SQLite y MoneyValue. No se implementaron funciones avanzadas de automatizacion de marketing; quedan fuera porque el backlog pedido era campana/territorio/forecast/embudo, no motor de envios.
