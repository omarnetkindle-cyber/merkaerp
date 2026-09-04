# Sesion autonoma - 2026-07-31 tarde

## Resumen ejecutivo de la ronda R-W

- R Salud: parcial implementado. RIPS-JSON FEV, validacion local CUPS/CIE-10 parcial y alerta de glosas; faltan catalogos completos, CUM/MUV y conciliacion.
- S Nomina: parcial implementado. Aportes comunes 2026 y seis regimenes trazables; faltan escalas, primas, convenciones institucionales y PILA certificada.
- T Planeacion: parcial implementado. Vinculo proyecto-rubro-meta y alerta financiera/fisica; faltan UI, metas PDT completas y obligacion de vinculo.
- U SGR/SGP: parcial implementado. OCAD captura acta/fuente/ejecutor y SGP bloquea rubros no autorizados; falta homologacion con presupuesto y controles de ejecucion SGR.
- V NICSP 40/Transparencia: requiere decision humana. No hay contraparte/identificador reciproco para eliminar sin riesgo; el portal requiere contrato/API/credenciales de entidad.
- W Rentas: parcial implementado. Ruta ordinaria de cobro sin saltos; falta tabla e importacion completa del historico oficial de tasas y pruebas de expediente extremo a extremo.

Decisiones humanas prioritarias: definir el mecanismo de conciliacion de reciprocas NICSP 40 y entregar contrato/configuracion de portal; decidir el proceso de carga y custodia del historico oficial de tasas para liquidaciones retroactivas.


## Subtarea W - Rentas: transiciones de cobro y tasas historicas

### Hallazgo, implementacion y decision

El proceso tenia seis etapas pero el servicio aceptaba cualquier salto. Se restringio la ruta ordinaria a mandamiento -> embargo/secuestro -> remate -> devolucion -> archivo; prescripcion queda como cierre excepcional cuando hay saldo. No se implanto una tabla con tasas historicas: existe fuente oficial de Superfinanciera, pero no una serie completa cargada y verificable. El diseno y la fuente quedaron en `TASAS_MORATORIAS_HISTORICAS_PENDIENTE.md`.

### Evidencia cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/proceso_cobro_coactivo_transiciones_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/proceso_cobro_coactivo_transiciones_test.dart: la ruta ordinaria de cobro coactivo no permite saltar etapas
00:00 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/proceso_cobro_coactivo_transiciones_test.dart: la prescripcion es un cierre excepcional con saldo pendiente
00:00 +2: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/intereses_moratorios_service_test.dart
00:01 +5: All tests passed!
```

### Cierre de la subtarea W

Estado: parcial implementado y verificado. Commit de implementacion: `c2f00e3 fix(rentas): bloquear saltos en etapas de cobro coactivo`. La serie historica de tasas requiere importacion oficial completa.


## Subtarea V - Transparencia y consolidacion NICSP 40

### Hallazgo, decision y limite

Se inspecciono `ConsolidacionJerarquicaService`: suma los saldos de la entidad padre y sus hijas sin contraparte, identificador comun ni relacion entre asientos. No se puede eliminar una reciproca sin inferirla por monto/fecha/cuenta, lo que puede borrar operaciones distintas. Se documento la decision humana requerida en `NICSP40_RECIPROCAS_Y_PORTAL_DECISION.md`: tabla de conciliacion aprobada o campos de contraparte/grupo reciproco, siendo la primera opcion mas conservadora para datos existentes.

`PortalTransparenciaService` sigue huerfano de la UI: `transparencia_page.dart` usa el servicio local y el portal remoto conserva URL de ejemplo, `<CONFIGURAR_EN_CENTRO_DE_INTEGRACIONES>` y persistencia pendiente. Se detiene esta parte porque requiere contrato y credenciales externas de la entidad.

### Cierre de la subtarea V

Estado: requiere decision humana. No se implementaron eliminaciones contables ni llamadas externas.

+## Subtarea U - SGR y SGP: destinacion por componente y datos OCAD

### Hallazgo, implementacion y decision

El presupuesto SGR ya estaba separado en `bienios_sgr`, `regalias` y `proyectos_ocad`, pero OCAD no guardaba acto, fuente ni ejecutor. SGP solo descontaba saldo sin saber en que rubro se ejecutaba. La migracion v72 agrega los tres datos trazables de OCAD y la tabla `sgp_destinaciones_rubro`. `registrarEjecucion` ahora exige que el rubro este autorizado para el componente de la asignacion: el cruce se bloquea antes de descontar saldo.

Decision conservadora: no se invento una homologacion de rubros nacionales ni se mezclaron las tablas SGR con presupuesto ordinario. Los registros OCAD legados quedan con los tres campos nulos hasta que la entidad los complete; la migracion no fabrica actos, fuentes ni ejecutores.

### Evidencia cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/regalias/spgr_service_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/regalias/spgr_service_test.dart: (setUpAll)
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/regalias/spgr_service_test.dart: SPGRService crea Bienio SGR, proyecto OCAD vinculado a MGA y genera reporte SPGR
00:00 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/regalias/spgr_service_test.dart: (tearDownAll)
00:00 +1: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/regalias/sgp_destinacion_rubro_test.dart
00:01 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/regalias/sgp_destinacion_rubro_test.dart: bloquea ejecucion SGP en rubro no autorizado y acepta su componente autorizado
00:02 +2: All tests passed!
```

### Evidencia cruda: flutter build windows

```text
Building Windows application...
Building Windows application... 77.9s
Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe
Nuget.exe not found, trying to download or use cached version.
```

### Evidencia cruda: flutter analyze

```text
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:799:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:815:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:93:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:150:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:201:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:237:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:279:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:318:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:82:7 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:451:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:460:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:508:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:576:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:585:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:633:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:796:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:805:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:851:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:1044:17 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:1065:21 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:14:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:84:7 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:540:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:552:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:577:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:649:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:661:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:699:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:791:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:803:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:897:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:1042:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1051:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1082:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable
flutter : 201 issues found. (ran in 7.1s)
En línea: 2 Carácter: 68
+ ... rvice.dart; flutter analyze > subtarea_U_analyze_final.txt 2> subtare ...
+                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (201 issues found. (ran in 7.1s):String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
```

### Cierre de la subtarea U

Estado: parcial implementado y verificado. Commit de implementacion: `a97f659 feat(sgr-sgp): bloquear destinacion por componente y completar datos OCAD`.


+## Subtarea T - Planeacion: trazabilidad proyecto-rubro-meta

### Hallazgo, implementacion y decision

La relacion existente entre MGA y presupuesto era texto libre: el proyecto guardaba codigos CDP/RP y la apropiacion un campo `proyecto`, sin clave ni avance fisico. Se incorporo la migracion v71 con `proyecto_rubros_metas`, que vincula entidad, proyecto MGA, apropiacion y meta. El servicio calcula ejecucion financiera desde `valor_pagado / valor_apropiado` y alerta cuando la distancia absoluta respecto al avance fisico reportado supera 20 puntos porcentuales.

Decision conservadora: se guarda el avance fisico declarado y su fecha, sin inventar indicadores PDT ni bloquear apropiaciones existentes. La interfaz de seguimiento y volver obligatorio el vinculo al crear una apropiacion quedan pendientes.

### Evidencia cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/planeacion/trazabilidad_plan_presupuesto_test.dart
00:00 +0: vincula proyecto, rubro y meta y alerta desviacion mayor a 20 puntos
00:00 +1: no alerta cuando la diferencia financiera-fisica es de 20 puntos o menos
00:00 +2: All tests passed!
```

### Evidencia cruda: flutter build windows

```text
Building Windows application...
Building Windows application... 68.9s
Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe
Nuget.exe not found, trying to download or use cached version.
```

### Evidencia cruda: flutter analyze

```text
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:799:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:815:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:93:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:150:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:201:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:237:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:279:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:318:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:14:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:84:7 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:540:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:552:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:577:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:649:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:661:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:699:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:791:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:803:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:897:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:1042:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1051:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1082:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable
```

### Cierre de la subtarea T

Estado: parcial implementado y verificado. Commit de implementacion: `af7f7d6 feat(planeacion): vincular proyecto MGA, rubro y meta de seguimiento`.


+## Subtarea S - Nomina publica: aportes 2026 y seis regimenes

### Hallazgo, implementacion y decision

La liquidacion anterior incluia el auxilio de transporte en el IBC, descontaba del neto las cargas patronales y aplicaba ARL como si toda persona estuviera en clase V. Se corrigio con las tarifas comunes vigentes: salario minimo 2026 de $1.750.905 (Decreto 1469 de 2025) y auxilio de transporte de $249.095 (Decreto 1470 de 2025); salud 8,5% patronal/4% trabajador y pension 12%/4% conforme a MinSalud; ARL por clase I-V y aportes parafiscales conforme a sus normas de fuente, citadas en el servicio.

La migracion v70 agrega `regimen_nomina` y `clase_riesgo_arl` preservando los registros existentes con valores conservadores de carrera administrativa y clase I. Se modelaron los seis regimenes solicitados: carrera administrativa, libre nombramiento y remocion, trabajador oficial, docente territorial, salud ESE y judicial/Fiscalia. No se inventaron escalas, primas, convenciones o reglas especiales de una entidad concreta: esos datos requieren los actos administrativos o convenciones de cada cliente. Por ello M5 permanece parcial y PILA no se certifica.

Fuentes oficiales consultadas:

1. https://www.suin-juriscol.gov.co/viewDocument.asp?id=30055940
2. https://www.suin-juriscol.gov.co/clp/contenidos.dll/Decretos/30055941
3. https://www2.minsalud.gov.co/salud/Documents/Contenidos/aseguramiento-salud.aspx

### Evidencia cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/nomina/nomina_service_test.dart
00:00 +0: liquida IBC sin auxilio y no descuenta aportes patronales del neto
00:00 +1: aplica ARL por clase y solidaridad gradual desde 16 SMMLV
00:00 +2: conserva tratamiento trazable para los seis regimenes publicos
00:00 +3: All tests passed!
```

### Evidencia cruda: flutter build windows

```text
Building Windows application...
Building Windows application... 77.0s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
Nuget.exe not found, trying to download or use cached version.
```

### Evidencia cruda: flutter analyze

```text
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:799:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:815:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:93:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:150:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:201:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:237:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:279:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:318:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:14:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:84:7 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:540:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:552:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:577:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:649:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:661:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:699:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:791:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:803:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:897:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:1042:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1051:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1082:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable
```

### Cierre de la subtarea S

Estado: parcial implementado y verificado. Commit de implementacion: `312c872 feat(nomina): corregir aportes 2026 y modelar seis regimenes publicos`. Ninguna tarifa o escala propia de entidad fue inventada.



## Subtarea R - Salud: RIPS-JSON FEV y alertas de glosas

### Hallazgo, implementacion y decision

La Resolucion 0948 de 2026 derogo expresamente la Resolucion 2275 de 2023. El Documento Tecnico 1 v003, publicado el 15-07-2026 en SISPRO, exige JSON como soporte del RIPS de la FEV, con objeto raiz de transaccion, arreglo `usuarios` y objeto `servicios`; el Documento Tecnico 2 v001 ubica el CUCON en los campos adicionales XML de la FEV. El plano semicolon-delimited previo y sus validadores se retiraron del flujo de exportacion.

Se creo la migracion v69: conserva `rips` y `glosas` legadas, agrega `fecha_limite_respuesta`, `rips_fev_documentos`, `catalogo_cups` y `catalogo_cie10`. La semilla incluye los codigos reales CUPS 890201/890301 y CIE-10 A09/J00. Es deliberadamente parcial: debe ampliarse con la lista tabular oficial de CUPS (Resolucion 2706 de 2025) y el catalogo CIE-10 que SISPRO publique, antes de pretender cobertura total. La validacion local rechaza CUPS/CIE-10 fuera de esos catalogos; el MUV y la transmision siguen siendo externos y requieren credenciales de la entidad.

La alerta de glosas persiste la fecha limite y calcula cinco dias de lunes a viernes. No inventa calendario de festivos: falta incorporar uno oficial antes de usarlo como computo juridico definitivo. La conciliacion formal sigue pendiente.

Fuentes oficiales consultadas:

1. https://www.minsalud.gov.co/sites/rid/Lists/BibliotecaDigital/RIDE/DE/DIJ/resolucion-0948-de-2026.pdf
2. https://www.minsalud.gov.co/sites/rid/Lists/BibliotecaDigital/RIDE/DE/OT/doc-tec1-tecnicas-datos-validacion-rips-fev-salud.pdf
3. https://www.minsalud.gov.co/sites/rid/Lists/BibliotecaDigital/RIDE/DE/OT/doc-tec2-campos-datos-sector-salud-generacion-fev.pdf
4. https://www.sispro.gov.co/central-financiamiento/Pages/facturacion-electronica.aspx

### Evidencia cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/salud/rips_fev_glosas_integracion_test.dart
00:00 +0: genera RIPS-JSON 948 con CUPS y CIE-10 catalogados
00:00 +1: rechaza RIPS-JSON con CUPS no catalogado
00:00 +2: alerta glosa pendiente al vencer cinco dias habiles
00:00 +3: migracion conserva glosas legadas y agrega fecha limite y catalogos
00:00 +4: All tests passed!
```

### Evidencia cruda: flutter build windows

```text
Building Windows application...
Building Windows application...                                    82.6s
Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe
Nuget.exe not found, trying to download or use cached version.
```

### Evidencia cruda: flutter analyze

```text
+Exit code: 0
Wall time: 0.6 seconds
Output:
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:799:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:815:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:93:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:150:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:201:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:237:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:279:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:14:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:84:7 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:540:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:552:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:577:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:649:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:661:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:699:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:791:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:803:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:897:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:1042:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1051:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1082:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable



```

### Cierre de la subtarea R

Estado: **Parcial implementado**. RIPS cambia a JSON estructurado y valida contra un subconjunto oficial local; queda pendiente solamente la ampliacion de catalogos, el modelado exhaustivo de los seis tipos y la validacion/transmision MUV que depende de credenciales de cada entidad. Commit: `b330362` (enmendado a continuacion para fijar este hash en el log).

## Subtarea L - Planeacion y Banco de Proyectos (MGA/PDT)

### Hallazgo y decision conservadora

La integracion solicitada no es segura con el modelo actual. `proyectos_mga` almacena el proyecto, `valor_ejecutado`, `codigo_cdp` y `codigo_rp` (`schema_planeacion.dart:10-31`); las asociaciones en `BancoProyectosService` solo escriben esos codigos libres (`banco_proyectos_service.dart:98-173`) y la ejecucion es un valor financiero manual agregado (`176-226`). La tabla `apropiaciones` no referencia `proyecto_id`, y no hay tabla ni campos de meta fisica, unidad, linea base, periodo o avance fisico. La pagina conserva el banner explicito de motor pendiente.

**Decision:** no se agrega una alerta de 20% ni se infiere una relacion rubro-proyecto. Hacerlo con coincidencias por codigo/nombre fabricaria trazabilidad y podria bloquear ejecucion real incorrectamente.

### Diseno requerido antes de implementar

1. Crear una relacion versionada `proyecto_rubros_presupuestales` (`entidad_id`, `proyecto_id`, `codigo_rubro`, `vigencia`, `monto_programado`, `vigente`, auditoria), con unica activa por proyecto/rubro/vigencia.
2. Crear metas PDT persistidas por proyecto (`meta_id`, indicador, unidad, linea_base, meta_total, periodo) y avances por corte (`avance_fisico`, fecha_corte, soporte, responsable), sin convertir importes financieros en porcentajes fisicos.
3. Calcular ejecucion financiera desde obligaciones/pagos aprobados de los rubros asociados, y generar una alerta solo cuando ambos porcentajes tengan el mismo corte y `financiero - fisico > 20` puntos porcentuales.
4. La migracion debe iniciar sin asociaciones ni metas inventadas; la carga/mapeo de datos existentes necesita decision humana del responsable de planeacion.

### Evidencia cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/planeacion/planeacion_page_test.dart
00:00 +0: (setUpAll)
00:00 +0: PlaneacionPage renders tabs, banner TODO and handles empty state
00:01 +1: (tearDownAll)
00:01 +1: All tests passed!
```

### Evidencia de verificacion

`flutter analyze` completo: 184 issues, 0 errores. La salida cruda completa se guardo durante la subtarea como `subtarea_l_analyze_output.txt`. `flutter build windows` completo:

```text
Building Windows application...
flutter : Nuget.exe not found, trying to download or use cached version.
Building Windows application...                                    20.6s
Built build\windows\x64\runner\Release\MerkaERP.exe
```

### Cierre de la subtarea L

Estado: **Pendiente - REQUIERE DECISION HUMANA DE DISENO Y CARGA DE DATOS**. No se implemento codigo porque no existe una relacion persistida y auditable entre rubro, proyecto, meta y avance fisico. Commit: pendiente de crear al momento de esta anotacion.

## Subtarea Q - Transparencia y consolidacion NICSP 40

### Hallazgo y decision conservadora

`ConsolidacionJerarquicaService` resuelve padre/hijas por `gobernacion_id` y suma saldos/presupuesto por entidad. Las tablas y asientos no contienen contraparte relacionada, identificador comun de operacion ni marca intra-grupo. Las transferencias de `NICSP40Service` identifican origen/destino como texto, pero no se relacionan con los asientos que la consolidacion suma. No es posible emparejar ni eliminar reciprocas de manera determinista; hacerlo por valor, fecha o descripcion puede eliminar operaciones validas distintas.

`PortalTransparenciaService` esta huerfano de UI: `TransparenciaPage` crea `TransparenciaService`, no el cliente de portal. Ademas usa una URL ilustrativa y `<CONFIGURAR_EN_CENTRO_DE_INTEGRACIONES>`. El modulo disciplinario se muestra en la pagina de transparencia, pero la deteccion forense solo construye una lista de alertas y nunca crea una queja preliminar.

### Diseno requerido

1. Modelar grupo de consolidacion y relaciones intra-grupo vigentes.
2. Propagar `operacion_grupo_id`, contraparte y clase de eliminacion desde el asiento origen hasta el destino, con una tabla de propuesta/aprobacion de eliminaciones; no borrar asientos fuente.
3. Definir una regla auditable de anomalia a queja, con severidad, evidencia, deduplicacion, reserva y aprobacion humana previa a abrir expediente.
4. Sustituir el portal por un contrato inyectable/noop y configuracion cifrada por entidad antes de conectarlo a UI.

### Cierre de la subtarea Q

Estado: **Parcial/Pendiente - REQUIERE DECISION HUMANA DE GOBIERNO DE DATOS**. Se mantienen las funciones locales existentes, pero no se implemento eliminacion reciproca ni publicacion/red/quejas automaticas sin identificadores y reglas de negocio. Commit: pendiente de crear al momento de esta anotacion.

## Subtarea P - SGR y SGP: bloqueos duros entre componentes

### Hallazgo y decision conservadora

El modelo SGP conserva `tipo_participacion` por asignacion y saldo por `sgpId`; `registrarEjecucion` solo recibe ese identificador y monto. `ValidacionDistribucionService.validarDistribucionSGP` valida porcentajes de entrada y no se conecta a compromisos, rubros ni pagos. En consecuencia, no existe la informacion necesaria para distinguir ni bloquear una ejecucion de educacion pagada con salud: imponerlo ahora bloquearia por una etiqueta sin trazabilidad financiera.

El almacenamiento SGR si esta separado del presupuesto ordinario: `bienios_sgr`, `regalias` y `proyectos_ocad` son tablas propias. Pero `proyectos_ocad` no guarda acta de aprobacion, fuente de financiacion ni entidad ejecutora, y no hay enlace al flujo SGR CDP-RP-obligacion-pago.

### Diseno requerido

Agregar una asignacion fuente-componente-rubro vigente por bienio y propagar su identificador al CDP/RP/obligacion/pago SGR; el bloqueo se aplicaria al comparar componente de la fuente con el del rubro. Para OCAD se requieren acto/acta, fecha, fuente(s), ejecutor y soporte, sin completar datos existentes de forma inventada.

### Cierre de la subtarea P

Estado: **Pendiente - REQUIERE DECISION HUMANA DE CLASIFICACION Y MIGRACION**. No se implemento bloqueo duro sin una relacion fuente-rubro verificable. Commit: pendiente de crear al momento de esta anotacion.

## Subtarea O - Salud publica: RIPS y facturacion EPS

### Hallazgo y decision conservadora

El modelo actual no implementa seis archivos reglamentarios: `TipoRIPS` conserva ocho etiquetas legacy (`af`, `ac`, `ap`, `at`, `au`, `am`, `ah`, `an`) y una fila generica contiene campos de todos los casos. `generarArchivoPlanoRIPS` emite un texto propio; por ejemplo no emite `FECHA_CONSULTA`, pero `_validarRIPSAC` la exige. `registrarRIPS` admite `codigoServicio` y diagnosticos libres y `FacturacionSaludService` no exige RIPS antes de facturar. No hay catalogos CUPS, CUM ni CIE-10 sembrados.

La solicitud menciona Resolucion 2275/2023, pero la fuente oficial de MinSalud confirma que la Resolucion 0948 de 2026 la derogó y rige la reglamentacion/anexo tecnico actualizado. Se detiene la implementacion para no consolidar un formato ya sustituido ni inventar catalogos parciales.

`GlosasService` registra `fecha_respuesta` al responder, pero no hay entidad `glosas_conciliacion`, calculo de dias habiles, tarea programada ni alerta de vencimiento. Por tanto los cinco dias no son una regla real hoy.

### Cierre de la subtarea O

Estado: **Pendiente - REQUIERE DECISION HUMANA DE FUENTE NORMATIVA Y CATALOGOS**. Diseno requerido: proveedor versionado de catalogos oficiales, modelo RIPS/FEV conforme al anexo vigente, enlace factura-RIPS y politica de dias habiles/calendario para glosas. No se modifico codigo ni se ejecutaron pruebas que pudieran aparentar certificacion. Commit: pendiente de crear al momento de esta anotacion.

## Subtarea N - Nomina publica: regimenes salariales y PILA

### Hallazgo y decision conservadora

Solo el regimen docente tiene un servicio propio. El modelo contiene `TipoVinculacion.carrera` y `libreNombramiento`, pero `NominaService` aplica una sola formula; no se localizaron motores para trabajadores oficiales, salud ni Fiscalia/Rama Judicial. Las tarifas de aportes estan codificadas en `nomina_service.dart:92-102`; PILA solamente agrega esos resultados y los serializa, sin catalogo versionado ni formato certificado de operador.

La prueba de liquidacion estaba desalineada con el esquema actual. Al completar de forma temporal su fixture para que use `empleados_sp` y `configuracion_entidad`, llego a las aserciones y fallo en tres valores: salud 170.000 esperado/183.770 actual; solidaridad intermedia 45.426,30/0; solidaridad alta 327.069,36/163.534,68. Se retiro el ajuste temporal para no mezclar esta investigacion con una redefinicion no aprobada de aportes.

### Evidencia cruda: flutter test

```text
00:00 +0 -1: Debe liquidar nomina completa y calcular aportes parafiscales [E]
Expected: a numeric value within <0.01> of <170000.0>
Actual: <183770.0>
00:00 +0 -2: Debe aplicar fondo de solidaridad 1% para salario entre 4 y 16 SMMLV [E]
Expected: a numeric value within <0.01> of <45426.3>
Actual: <0.0>
00:00 +0 -3: Debe aplicar fondo de solidaridad 2% para salario very alto [E]
Expected: a numeric value within <0.01> of <327069.36>
Actual: <163534.68>
00:00 +1 -3: Some tests failed.
```

### Cierre de la subtarea N

Estado: **Pendiente - REQUIERE DECISION HUMANA NORMATIVA**. No se cambiaron tarifas ni se afirmo compatibilidad PILA; hace falta definir fuente/versionado de aportes y los cinco regimenes ausentes. Commit: pendiente de crear al momento de esta anotacion.

## Subtarea M - Rentas: cobro coactivo e intereses moratorios

### Hallazgo y decision

El servicio tenia tasa de usura menos dos puntos, pero la convertia a diaria como `tasa_mensual / 30` (`intereses_moratorios_service.dart:45-48,159-163`), incompatible con el articulo 635 ET: la tasa diaria debe ser equivalente a la EA. Se corrigio localmente a `((1 + tasaEA)^(1/365)) - 1`, sin fijar una tasa nueva. La fuente oficial consultada fue Funcion Publica, Ley 1819 de 2016, art. 279 (art. 635 ET), y Decreto 2106 de 2019, que explicita `T = tasa / 365 o 366` en `K x T x t`.

`CobroCoactivoService` conserva seis valores de etapa, pero no constituye un procedimiento certificable: `avanzarEtapa` acepta una `nuevaEtapa` arbitraria (`cobro_coactivo_service.dart:113-192`), sin secuencia, acto/notificacion ni plazos. La tasa se consulta por SODA3 solo en memoria: no se conserva fecha de vigencia, fuente ni tasa usada por cada liquidacion. Se documentan ambas brechas, sin inventar plazos territoriales ni una tasa fija adicional.

### Evidencia cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/intereses_moratorios_service_test.dart
00:00 +0: (setUpAll)
00:00 +0: Validaciones Normativas Duras - Fase 4 convierte la tasa EA de mora a tasa diaria equivalente
00:00 +1: Validaciones Normativas Duras - Fase 4 Calculo de intereses de mora segun formula I = K x T x t
00:00 +2: Validaciones Normativas Duras - Fase 4 Debe calcular intereses de mora con fecha de vencimiento especifica
00:00 +3: (tearDownAll)
00:00 +3: All tests passed!
```

### Evidencia de verificacion

`flutter analyze` completo: 184 issues, 0 errores. `flutter build windows` completo: `Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe` (NuGet intento descargar/usar cache antes de compilar).

### Cierre de la subtarea M

Estado: **Parcial**. Se corrigio el factor diario y se certifico con valor exacto. **REQUIERE DECISION HUMANA** para la fuente/historial de tasas y para concretar plazos y procedimiento de cobro aplicables por entidad territorial. Commit: pendiente de crear al momento de esta anotacion.

## Alcance y criterio

- Objetivo: cerrar en orden las subtareas A-D del Sistema Financiero Integrado y, solo si hay margen suficiente, evaluar E-F.
- Regla de evidencia: no se eleva una fila de la matriz a `Completo` sin una prueba ejecutada que cubra especificamente el requisito.
- Regla de decisiones: ante ambiguedades, se usa la opcion conservadora y se documenta. Credenciales externas, llamadas reales o cambios irreversibles sobre datos reales se registran como `requiere decision humana` y no se ejecutan.
- Nota de hashes: un commit no puede contener su propio hash sin cambiarlo. El hash de cada subtarea se registrara en la siguiente actualizacion del log; el resumen final consolidara todos los hashes publicados.

## Inicio de sesion

- Estado inicial: `main` sincronizada con `origin/main` tras `db75535`.
- Subtarea en curso: A - cierre de vigencia y vigencias futuras.

## Subtarea A - Cierre de vigencia y vigencias futuras

### Hallazgo y decision

- `CierreVigenciaService._calcularReservas` no consulta `obligaciones`. Solo suma los saldos de cuentas cuyo codigo inicia por `24` y las provisiones activas. Eso no demuestra reservas presupuestales basadas en obligaciones sin pago.
- No existe tabla o flujo sectorial para registrar bienes o servicios recibidos sin obligacion. Los soportes de recibo y factura viven dentro de la propia tabla `obligaciones`, por lo que no hay fuente de datos que permita calcular ese subconjunto de cuentas por pagar sin inventar datos.
- No se encontro implementacion de vigencias futuras, autorizacion Confis, MFMP ni compromiso plurianual en `lib/sector_publico` o `test/sector_publico`.
- Decision autonoma conservadora: no se implemento una formula ni una prueba de integracion que aparentara cubrir el requisito. Se mantuvo M2 como `Parcial` y se documento la brecha especifica en la matriz. Implementar las dos fuentes de datos y las reglas de autorizacion es una decision de diseno y normativa que requiere revision humana.

### Pruebas

- No se ejecuto una prueba de cierre: una prueba verde solo validaria la suma actual de saldos 24 y provisiones, no el requisito solicitado de reservas presupuestales y recibidos sin obligacion.
- La evidencia de analisis y build se registra a continuacion.

### Salida cruda: flutter analyze

```text
Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:509:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:673:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:211:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:237:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:245:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:297:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:430:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable

flutter : 184 issues found. (ran in 8.8s)
En línea: 2 Carácter: 1
+ flutter analyze *> A_analyze_output.txt; exit $LASTEXITCODE
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (184 issues found. (ran in 8.8s):String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
```

### Salida cruda: flutter build windows

```text
Building Windows application...
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> A_build_windows_output.txt; exit $LASTEXITCO ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

Building Windows application...                                    20.9s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
```

## Subtarea B - NICSP 2: flujo de efectivo

### Cierre de la subtarea A
- Commit publicado: `47f2e3e docs(financiero): documentar brecha de cierre de vigencia`.

### Hecho
- RBAC conservado: `estado_flujos_efectivo` usa `visible()` con `AppSession.puedeAbrirModulo`, vuelve a validarse en `main.dart` y exige `Permiso.consultarEstadosFinancieros`.
- Se agrego una pestana dedicada con selector de mes, vigencia y metodo, conectada a `FlujoEfectivoService`; el modulo abre la pestana con `initialTabIndex: 4`.
- Prueba de integracion: efectivo inicial 1000, operacion 300, inversion 70, financiacion 230, variacion 600, efectivo final 1600 y auditoria.

### Decision conservadora
NICSP 2 permanece **Parcial**: el test certifica implementacion actual y UI/RBAC, no la validacion normativa de clasificacion CGC fija ni el metodo indirecto basico.

### Salida cruda: flutter test
```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contabilidad/flujo_efectivo_service_test.dart
00:00 +0: (setUpAll)
00:00 +0: genera NICSP 2 directo con movimientos conocidos del periodo
00:00 +1: (tearDownAll)
00:00 +1: All tests passed!

```

### Salida cruda: flutter analyze
```text
Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:509:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:673:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:430:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable

flutter : 184 issues found. (ran in 8.6s)
En línea: 2 Carácter: 1
+ flutter analyze *> B_analyze_output.txt; exit $LASTEXITCODE
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (184 issues found. (ran in 8.6s):String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 

```

### Salida cruda: flutter build windows
```text
Building Windows application...
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> B_build_windows_output.txt; exit $LASTEXITCO ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

Building Windows application...                                    83.9s
√ Built build\windows\x64\runner\Release\MerkaERP.exe

```

## Cierre de la subtarea B

- Commit publicado: `0500265 feat(contabilidad): conectar estado NICSP 2 a la interfaz`.
- Push confirmado: `47f2e3e..0500265 main -> main`.
- La subtarea queda parcial en la matriz solo por la validacion normativa pendiente del calculo NICSP 2, no por falta de conexion, prueba o build.

## Subtarea C - Catalogo General de Cuentas

### Hallazgo y decision

- La semilla de `SchemaMultiTenant.insertarDatosSemillaCGC` contiene exactamente las cuentas clave exigidas por el plan para clases 1, 2, 3, 4, 5, 6, 8 y 9. No falta ninguna de las cuentas enumeradas: 1110, 1415, 1640, 1920; 2401, 2410, 2510; 3105, 3115, 3120; 4111, 4115, 4401, 4802; 5101, 5111, 5120, 5310; 6101, 6310; 8110, 8390; 9110, 9390.
- Decision conservadora: no se agrega migracion ni se altera el catalogo. El plan exige esas cuentas clave, que ya existen; agregar auxiliares no exigidos sin una fuente CGN verificada ampliaria el catalogo sin evidencia.
- Se confirmo que `ContabilidadNICSPService` genera asientos de obligacion y pago. La prueba los genera usando 5101, 2401 y 1110 y verifica que todos sus detalles existen en el CGC de la entidad.

### Salida cruda: flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contabilidad/catalogo_cgc_test.dart
00:00 +0: (setUpAll)
00:00 +0: siembra las cuentas CGC clave de las clases 1, 2, 3, 4, 5, 6, 8 y 9
00:00 +1: asientos NICSP de obligacion y pago usan cuentas del catalogo
00:00 +2: (tearDownAll)
00:00 +2: All tests passed!

```

### Salida cruda: flutter analyze

```text
Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:509:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:673:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:430:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable


```

### Salida cruda: flutter build windows

```text
Building Windows application...                                 
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> C_build_windows_output.txt; exit $LASTEXITCO ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

Building Windows application...                                    68.8s
√ Built build\windows\x64\runner\Release\MerkaERP.exe

```

## Cierre de la subtarea C

- Commit: pendiente de registrar en el siguiente cierre o resumen ejecutivo por la regla de autorreferencia del log; el commit no puede contener su propio hash sin modificarlo.
- Estado: completada. Se actualizo M2 a 2 Completos / 8 Parciales / 0 Pendientes.

## Subtarea D - NICSP 1: estados financieros basicos

### Hallazgo y decision

- `CierreVigenciaService` implementa `generarEstadoSituacionFinanciera` y `generarEstadoResultado`. Ambos consultan `saldos_cuentas`, que se actualiza cuando `ContabilidadNICSPService.generarAsientoPresupuestal` registra un asiento.
- Brecha encontrada: los saldos se guardan como debito menos credito. El generador suma directamente los saldos de clase 2 y 3, conservando signo acreedor negativo; tampoco incorpora el resultado corriente de clases 4/5 al patrimonio. Por ello un estado derivado de asientos normales no satisface Activo = Pasivo + Patrimonio.
- Decision autonoma conservadora: no se escribio un test que normalizara o aceptara una formula contable incorrecta, ni se cambio la formula sin una definicion normativa y de presentacion aprobada. La fila NICSP 1 se mantiene Parcial y se anota la brecha concreta.

### Pruebas

- No se ejecuto una prueba de estado financiero: el resultado actual no puede certificarse como estado basico cuadrado. No existe un test previo identificado para esta ruta.

### Salida cruda: flutter analyze

```text
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:509:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:673:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:430:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable


```

### Salida cruda: flutter build windows

```text
Building Windows application...                                 
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> D_build_windows_output.txt; exit $LASTEXITCO ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

Building Windows application...                                    20.8s
√ Built build\windows\x64\runner\Release\MerkaERP.exe

```

## Cierre de la subtarea D

- Commit de la subtarea C publicado: `6a8612f test(contabilidad): certificar catalogo CGC publico`.
- Estado D: parcial documentada; no se introdujo codigo ni test para ocultar la brecha de signo y resultado acumulado.
- Commit D: pendiente de registrar en el resumen ejecutivo por la regla de autorreferencia del log.
## Pausa de diseno - reservas, cuentas por pagar y vigencias futuras

### Propuesta conservadora

- Obligaciones sin pagar al 31-dic: pueden derivarse de `obligaciones` con `fecha_reconocimiento <= corte` y `saldo_pendiente > 0`, separando el saldo pendiente por RP/apropiacion. Esa consulta no debe confundirse con una reserva presupuestal: es una cuenta por pagar ya reconocida.
- Bienes/servicios recibidos sin obligacion: no puede derivarse de forma confiable. `acta_recibo_numero` y `factura_numero` se guardan solo al crear la obligacion. Se requiere una tabla nueva, por ejemplo `recepciones_satisfaccion`, con entidad, contrato/RP, tercero, acta, fecha de recibido, valor recibido, valor reconocido, estado y auditoria; la obligacion debe vincularla de forma opcional y consumir su saldo.
- Vigencias futuras: requiere tablas nuevas de autorizacion plurianual y compromisos anuales, con autoridad autorizadora, acto, vigencias, cupo autorizado/comprometido, fuente, proyecto y estado. No se implementa sin definir autoridad y reglas de disponibilidad.

### Radio de cambio estimado

- Migracion versionada para `recepciones_satisfaccion`, autorizaciones y compromisos de vigencias futuras; indices por entidad, RP y vigencia.
- Cambios en `schema_presupuesto.dart`, `db_helper.dart`, modelos/servicios/paginas de presupuesto, cierre de vigencia, auditoria y pruebas de integracion. El flujo de obligacion debe validar y actualizar el recibido; el cierre debe separar reserva, cuenta por pagar y recibido pendiente.
- Estado: requiere decision humana antes de abrirlo como proyecto aparte. No se modificaron datos ni esquemas en esta pausa.

## Resumen ejecutivo de la ronda retomada

- C - CGC: completada y publicada en `6a8612f`. La prueba cubre las cuentas clave del plan por clases y los asientos NICSP de obligacion/pago contra el catalogo.
- D - NICSP 1: parcial y publicada en `967bb5a`. Existen generadores, pero los signos acreedores y el resultado corriente impiden cuadrar estados derivados de asientos normales; no se certifico ni se oculto con pruebas.
- Pausa de diseno: completada como documentacion; requiere decision humana para crear el dominio de recibido sin obligacion y vigencias futuras.
- E - CHIP: no iniciada para evitar dejar una subtarea de prueba/evidencia sin cerrar.
- F - depreciacion/FUT: no iniciada por la misma razon.
- Decision autonoma principal para revisar: distinguir reservas presupuestales, cuentas por pagar reconocidas y recibidos sin obligacion mediante datos separados; no usar la suma actual de saldos clase 24 como sustituto.

## Evidencia final de la ronda retomada

### Salida cruda: git log origin/main -10

```text
commit 286f0ddbf2b65b8f702cf499357486994c895696
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 19:04:45 2026 -0500

    docs(presupuesto): proponer diseno de reservas y vigencias futuras
    
    - Separa cuentas por pagar reconocidas de recibidos sin obligacion.
    - Documenta tablas, migracion y radio de cambio necesarios.
    - Cierra la ronda retomada con el estado real de C a F.

commit 967bb5a6e22d2bedf081ad26c352222c6b4702e7
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 19:03:18 2026 -0500

    docs(contabilidad): documentar brecha de estados NICSP 1
    
    - Registra que los generadores existen sobre saldos de asientos.
    - Documenta el signo acreedor y resultado no integrado que impiden cuadrar.
    - Mantiene M2 parcial con evidencia de inspeccion, analisis y build.

commit 6a8612f8cae525bd2d66700622e722112d8be527
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 19:00:26 2026 -0500

    test(contabilidad): certificar catalogo CGC publico
    
    - Verifica las cuentas clave de las clases 1, 2, 3, 4, 5, 6, 8 y 9.
    - Confirma que los asientos NICSP de obligacion y pago usan cuentas del CGC.
    - Actualiza matriz y bitacora con evidencia ejecutada.

commit 0500265c89fe9f5e01ba5d743db37ff6904325d4
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 14:13:24 2026 -0500

    feat(contabilidad): conectar estado NICSP 2 a la interfaz
    
    - Abre el modulo protegido estado_flujos_efectivo en su pestana dedicada.
    - Agrega selector de periodo y metodo para FlujoEfectivoService.
    - Cubre el calculo directo y la auditoria con una prueba de integracion.
    - Actualiza la matriz y el log de la sesion autonoma con evidencia cruda.

commit 47f2e3e962680277419fed5dcdc17a07730db2f3
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 14:02:17 2026 -0500

    docs(financiero): documentar brecha de cierre de vigencia
    
    - confirmar que el calculo actual no cubre reservas presupuestales
    - registrar ausencia de recibidos sin obligacion y vigencias futuras
    - mantener M2 parcial con evidencia de inspeccion y build

commit db755353dd3f74dc5c8ff9c719114636ee25866d
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 13:46:28 2026 -0500

    fix(presupuesto): integrar ejecucion de pago con PAC y NICSP
    
    - agregar migracion v67 y persistir mes_pac en pagos
    - exigir pago aprobado y ejecutar cascada atomica de pago, obligacion,
      apropiacion, PAC, auditoria y asiento NICSP
    - permitir DatabaseExecutor en servicios transaccionales sin romper
      consumidores existentes basados en Database
    - cubrir flujo feliz y cinco bloqueos con pruebas de integracion
    - actualizar la matriz M2 con evidencia ejecutada del flujo completo

commit e8b6a27c72bdf51655e8a4909c0c090a2d7bd28d
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 13:14:02 2026 -0500

    docs(sector-publico): agregar matriz de trazabilidad verificable
    
    - mapear requisitos del plan v1.1 a codigo, pruebas y evidencia
    - distinguir evidencia ejecutada de inspeccion de codigo
    - corregir referencias de pruebas que no cubren el requisito citado

commit d7fd19f2f40681dded5668f7cb51b7d0f41d4c3f
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 12:54:18 2026 -0500

    docs(sector-publico): actualizar estado real de las fases
    
    - documentar avances parciales de las fases 1 a 11
    - registrar auditoria inmutable y configuracion de entidad versionada

commit 68ffaa0a5fcb3d5fc2f47290f0ef85c231bc0a45
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 12:54:18 2026 -0500

    feat(configuracion): migrar onboarding publico legado
    
    - migrar company_settings publico al esquema configuracion_entidad
    - conservar company_settings como fuente de solo lectura
    - agregar prueba de municipio legado y matriz sectorial

commit ad10a3e0018aaaaf1ab3bf3f5722c5b4e92a5a03
Author: MerkaERP <merkaerp@example.com>
Date:   Fri Jul 31 07:38:02 2026 -0500

    feat(configuracion): versionar entidad y persistir matriz de modulos
    
    - agregar historial vigente para configuracion_entidad
    - conservar configuracion_legal de Nomina por parametro
    - sembrar y consultar modulos_por_tipo_entidad desde SQLite
    - extender tipos compatibles hospital ESE y otro ente
```

### Salida cruda: git status

```text
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
```

## Subtarea E - Formularios CHIP

### Hallazgo y decision

- Ningun formulario CHIP tiene fuente de datos real completa. CHIPReporterService recibe DTOs desde la UI y solo los persiste/exporta; no lee contabilidad, presupuesto, terceros ni estados financieros.
- La taxonomia no esta alineada con el plan: el modelo llama CGN2015_001 a informacion de entidad, mientras el plan lo describe como situacion financiera, y los otros contenidos tampoco se mapean 1:1.
- Decision conservadora: no se escribio un test que inyectara DTOs y aparentara validar datos reales. La brecha queda explicita en M7.

### Pruebas

- No se ejecuto test CHIP: no hay fuente real ni estructura oficial integrada que permita certificar contenido normativo.

### Salida cruda: flutter analyze

```text
Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:509:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:673:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:430:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable


```

### Salida cruda: flutter build windows

```text
Building Windows application...                                 
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> E_build_windows_output.txt; exit $LASTEXITCO ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
Building Windows application...                                    31.8s
√ Built build\windows\x64\runner\Release\MerkaERP.exe

```

## Cierre de la subtarea E

- Estado: parcial documentada; requiere mapeo de fuentes reales y alineacion con formularios CGN antes de una prueba funcional.
- Commit: pendiente de registrar en el cierre siguiente por la regla de autorreferencia del log.
## Subtarea F - Activos, depreciacion y FUT

- El test `depreciacion_job_service_test.dart` paso: calcula 20.0, actualiza el activo y genera asiento 620101/160401.
- FUT ya consulta fuentes reales y usa `consultarAuditoria`; el modulo existente `fut` ahora abre directamente la pestana Integridad donde se genera, manteniendo el RBAC de `AppSession.puedeAbrirModulo` y `_openModule`.
- `flutter analyze`: 184 avisos base, sin errores nuevos. `flutter build windows`: correcto.

## Cierre de la subtarea F

## Subtarea G - Investigacion normativa de vigencias futuras

- Decision: no se implementa esquema ni flujo. Se documento `VIGENCIAS_FUTURAS_HALLAZGOS_Y_DISENO.md` con Ley 819/2003, Ley 1483/2011, Decreto 2767/2012, EOP y fuentes CGN/MinHacienda.
- Hallazgo: municipios y departamentos requieren iniciativa del gobierno local, aprobacion previa del CONFIS territorial o equivalente y autorizacion de concejo/asamblea. Las ordinarias inician con apropiacion actual; las excepcionales territoriales solo aplican a sectores y requisitos de Ley 1483/2011.
- Decision conservadora: `hospitalEse` no determina por si solo el autorizador; se exigira regimen presupuestal y acto local que identifique la autoridad competente antes de habilitar solicitudes.
- Hallazgo contable: un bien o servicio recibido a satisfaccion puede generar pasivo por devengo; la ausencia de obligacion presupuestal sera incidente bloqueante y auditable, no camino ordinario ni pasivo contingente automatico.
- Matriz M2 actualizada: permanece Parcial; la investigacion no es evidencia de implementacion.

## Cierre de la subtarea G

- Resultado: investigacion normativa y propuesta de diseno cerradas; no se implementaron tablas ni flujos.
- Verificacion: `flutter analyze` conserva 184 issues de linea base y 0 errores; `flutter build windows` produjo `MerkaERP.exe`.
- Commit y push: se registran en la evidencia Git de cierre de esta ronda; este mismo archivo no puede contener su propio hash final sin crear un commit adicional.

## Subtarea H - Rol publico para gestion de usuarios y roles

- Decision: se agrega `secretarioGeneral`, no un rol generico ni `jefeTalentoHumano`. Ley 909/2004, art. 15, ubica la gestion de personal en la unidad competente, pero no asigna RBAC informatico; Decreto Ley 785/2005 incluye Secretario General en la nomenclatura territorial. La asignacion a una persona debe respetar el manual de funciones de cada entidad.
- Permisos: exclusivamente `gestionarUsuarios` y `asignarRoles`; sin permisos fiscales, operativos, contables ni de consulta general.
- Limite conservador: no se conecta `UsuariosPage`, porque es un modulo comercial global que exige administrador y no esta aislado por entidad. No existe aun pagina ni servicio publico de usuarios al cual aplicar estos permisos sin ampliar el alcance y romper el aislamiento multi-entidad.
- Matriz M7: evidencia de prueba pendiente de ejecucion.

## Cierre de la subtarea H

- Resultado: rol `secretarioGeneral` agregado con exactamente dos permisos administrativos; el test confirma la ausencia de facultades fiscales.
- Verificacion: prueba RBAC paso; `flutter analyze` conserva 184 issues de linea base y 0 errores; `flutter build windows` produjo `MerkaERP.exe`.
- Limite pendiente: construir un modulo publico de usuarios aislado por entidad; no se autorizo el modulo comercial global.
- Commit y push: se registran en la evidencia Git de cierre de esta ronda; este mismo archivo no puede contener su propio hash final sin crear un commit adicional.

## Subtarea I - Validaciones locales SECOP/contratacion

- Hallazgo bloqueante: el flujo actual es circular. La UI crea contrato solo con un RP ya existente; endurecer RP para exigir contrato firmado y endurecer contrato para exigir RP valido deja cero camino feliz.
- Evidencia: `crearContrato` crea estado `enFirma`; no hay ninguna transicion persistida a `firmado`; `legalizarContrato` solo acepta `firmado`.
- Decision conservadora: no se insertaron contratos o RPs ficticios, no se aplicaron validaciones parciales y no se escribio una prueba que aparentara cubrir el flujo. Se documento el diseno requerido: contrato firmado -> RP asociado -> polizas vigentes -> legalizacion.
- Matriz M4: sigue Parcial y registra el bloqueo explicito.

## Cierre de la subtarea I

- Estado: requiere decision humana sobre el nuevo flujo persistido y migracion de `rp_id`/`numero_rp` antes de implementar las tres validaciones.
- No se ejecutaron tests de integracion ni se modifico codigo: hacerlo habria certificado un flujo imposible. La verificacion de codigo de la ronda anterior conserva 184 issues de linea base y 0 errores.

### Evidencia cruda - flutter test test/sector_publico/security/roles_permisos_service_test.dart

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart
00:00 +0: Validaciones Normativas Duras - Fase 0 NO debe permitir que tesorero apruebe pagos
00:00 +1: Validaciones Normativas Duras - Fase 0 NO debe permitir que tesorero se auto-apruebe en segregación de funciones
00:00 +2: Validaciones Normativas Duras - Fase 0 NO debe permitir que contador expida RP según negacionesPorRol
00:00 +3: Validaciones Normativas Duras - Fase 0 Debe permitir que secretario de hacienda apruebe pagos
00:00 +4: Validaciones Normativas Duras - Fase 0 Secretario de Hacienda NO puede expedir CDP ni RP
00:00 +5: Validaciones Normativas Duras - Fase 0 Jefe de Presupuesto puede expedir CDP y RP
00:00 +6: Validaciones Normativas Duras - Fase 0 Secretario General administra usuarios sin facultades fiscales
00:00 +7: Validaciones Normativas Duras - Fase 0 NO debe permitir acción si el rol no tiene permiso
00:00 +8: Validaciones Normativas Duras - Fase 0 Solo alcalde y secretario de hacienda pueden configurar entidad
00:00 +9: All tests passed!


```

### Evidencia cruda - flutter analyze

```text
+Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:430:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable




[stderr]
184 issues found. (ran in 158.6s)


```

### Evidencia cruda - flutter build windows

```text
+Building Windows application...                                 
Building Windows application...                                    35.8s
âˆš Built build\windows\x64\runner\Release\MerkaERP.exe



[stderr]
Nuget.exe not found, trying to download or use cached version.


```
## Subtarea I - Flujo contractual firmado -> RP -> polizas -> legalizacion

### Verificacion de datos existentes

- Base de desarrollo inspeccionada: `C:\\Users\\PC\\Documents\\merka_erp_test_fresco.db`.
- Resultado: `contratos: 0`, `rps: 0`, `procesos_contratacion: 0`.
- Decision: v68 no reetiqueta ni inventa valores para instalaciones desplegadas. Reconstruye `contratos` y `polizas` con copia explicita de todas sus columnas, preservando las referencias legacy; solo elimina la obligatoriedad de `rp_id` y `numero_rp` para nuevos contratos firmados.

### Implementacion

- Migracion v68: `rp_id` y `numero_rp` pasan a ser anulables; la reconstruccion conserva contratos y polizas existentes.
- `crearContrato` registra el estado `firmado` sin RP. Si se provee RP por compatibilidad, valida existencia, numero y CDP del proceso.
- `asociarRPAContrato` opera en una unica transaccion: exige contrato firmado sin RP, proceso adjudicado y CDP coincidente; expide RP, actualiza contrato y audita dentro de la misma transaccion.
- `legalizarContrato` exige RP asociado y al menos una poliza registrada, vigente y dentro de su periodo.
- UI: el formulario registra el contrato firmado sin selector de RP y el detalle ofrece la accion separada `Expedir y asociar RP`.

### Evidencia cruda - flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_migracion_v68_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_migracion_v68_test.dart: (setUpAll)
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_migracion_v68_test.dart: v68 conserva contratos y polizas legacy y permite contrato firmado sin RP
00:00 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_migracion_v68_test.dart: (tearDownAll)
00:00 +1: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_flujo_rp_integracion_test.dart
00:01 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_flujo_rp_integracion_test.dart: (setUpAll)
00:01 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_flujo_rp_integracion_test.dart: proceso adjudicado, contrato firmado, RP, poliza y legalizacion
00:01 +2: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_flujo_rp_integracion_test.dart: bloquea RP sin contrato firmado, RP ajeno y legalizacion sin poliza
00:01 +3: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contratacion/contratacion_flujo_rp_integracion_test.dart: (tearDownAll)
00:01 +3: All tests passed!
```

### Evidencia cruda - flutter analyze

```text
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:799:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:815:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:464:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable
184 issues found. (ran in 8.2s)
```

### Evidencia cruda - flutter build windows

```text
Building Windows application...                                 
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> contratacion_v68_build_output.txt; exit $LAS ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
Building Windows application...                                    94.4s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
```
 
### Cierre de la subtarea I
 
- Resultado: implementacion y migracion verificadas. `flutter test`: 3 pruebas aprobadas. `flutter analyze`: 184 issues, 0 errores (linea base preservada). `flutter build windows`: exitoso.
- MATRIZ_TRAZABILIDAD.md: M4 conserva estado Parcial; ahora cita la prueba integral para la cadena contractual. No se elevo a Completo porque ejecucion, poscontractual, seis modalidades y SECOP II real siguen sin certificarse.
- Commit: pendiente de crear y publicar.

- Estado: parcial; job y ruta FUT integrados, pero faltan validacion normativa completa de tasas/tipos y cobertura de todas las categorias FUT.

+## Subtarea J - NICSP 1: estado de situacion financiera cuadrado

- Hallazgo confirmado: `saldo_neto` se guarda como debito menos credito. El ESF acumulaba ese valor para pasivo y patrimonio, por lo que presentaba los saldos acreedores como negativos y no sumaba el resultado del periodo.
- Decision: conservar el saldo firmado en base de datos y convertirlo solo para presentacion. Las clases 2, 3 y 4 se invierten conforme al CGC semilla (`Acreedora`); las clases 1, 5, 6 y 7 se mantienen deudoras. El resultado del periodo se presenta como renglon derivado de patrimonio, sin crear un asiento.

### Evidencia cruda - flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contabilidad/estado_financiero_nicsp1_integracion_test.dart
00:00 +0: (setUpAll)
00:00 +0: NICSP 1 presenta creditos positivos e integra resultado al patrimonio
00:00 +1: (tearDownAll)
00:00 +1: All tests passed!
```

### Evidencia cruda - flutter analyze

```text
Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable
184 issues found. (ran in 53.9s)
```

### Evidencia cruda - flutter build windows

```text
Building Windows application...                                 
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> nicsp1_build_output.txt; exit $LASTEXITCODE
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
Building Windows application...                                    97.5s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
```

### Cierre de la subtarea J

- Resultado: se corrigio la presentacion de saldos acreedores y se integro el resultado del periodo al patrimonio sin mutar saldos ni crear asientos. El test de integracion verifica exactamente `1000 = 400 + 600`.
- MATRIZ_TRAZABILIDAD.md: NICSP 1 permanece Parcial; el ESF y resultado estan certificados, pero faltan pruebas de los demas estados basicos.
- Commit: registrado en el commit que versiona este cierre: `fix(contabilidad): cuadrar estado financiero NICSP 1`.

### Anexo de evidencia cruda - Subtarea H

La evidencia G previa quedo fisicamente despues del encabezado H por el orden
historico de insercion. Este anexo identifica sin ambiguedad las ejecuciones de H.

#### flutter analyze

```text
+Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:87:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:144:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:195:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:231:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:273:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:430:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable




[stderr]
184 issues found. (ran in 8.4s)


```

#### flutter build windows

```text
+Building Windows application...                                 
Building Windows application...                                    76.6s
âˆš Built build\windows\x64\runner\Release\MerkaERP.exe



[stderr]
Nuget.exe not found, trying to download or use cached version.


```



## Subtarea K - CHIP desde datos persistidos

- Hallazgo: los seis generadores recibian DTOs manuales. La UI escribia CGN 2015_002 y 003 desde controladores y fabricaba CGN 2015_004 con totales contables; CGN 2015_005 se emitia con ceros.
- Decision conservadora: CGN 2015_001 a 003 ahora se generan desde fuentes persistidas. CGN 2015_004, 005 y 2016C01 no se emiten hasta que existan fuentes/modelos suficientes; no se convierten ceros en reportes oficiales.
- Fuentes conectadas: 001 usa entidades_territoriales y funcionarios_entidad; 002 usa saldos_cuentas; 003 reutiliza CierreVigenciaService. Se corrigio tambien la serializacion JSON de reportes_chip, cuya columna datos es TEXT.
- Brechas documentadas: 004 no guarda adiciones, reducciones, creditos y contracreditos; 005 no tiene deuda publica persistida; 2016C01 carece de estructura/fuente consolidada. En 002 siguen pendientes las taxonomias contables persistidas para regalias y gasto de inversion.

### Evidencia cruda - flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/auditoria/chip_datos_sistema_integracion_test.dart
00:00 +0: (setUpAll)
00:00 +0: CGN 2015_001 a 003 reflejan fuentes persistidas del sistema
00:00 +1: (tearDownAll)
00:00 +1: All tests passed!
```

### Evidencia cruda - flutter analyze

```text
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:93:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:150:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:201:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:237:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:279:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable

flutter : 184 issues found. (ran in 7.6s)
En línea: 2 Carácter: 1
+ flutter analyze *> chip_datos_sistema_analyze_output.txt; exit $LASTE ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (184 issues found. (ran in 7.6s):String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
```

### Evidencia cruda - flutter build windows

```text
Building Windows application...
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> chip_datos_sistema_build_output.txt; exit $L ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

Building Windows application...                                    75.7s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
```

### Cierre de la subtarea K

- Resultado: CGN 2015_001, 002 y 003 quedan cubiertos por una prueba de integracion con datos de entidad, funcionarios y saldos contables. El caso verifica 700 de ingresos, 300 de gastos y 1.100 = 400 + 700.
- MATRIZ_TRAZABILIDAD.md: CHIP sigue Parcial; la evidencia no se extiende a CGN 2015_004, CGN 2015_005 ni CGN 2016C01.
- Commit: registrado en el commit que versiona este cierre: `feat(auditoria): generar CHIP desde datos persistidos`.

### Correccion de cierre K - UI sin entradas manuales

- Se retiro el formulario heredado que solicitaba montos financieros manuales. La pantalla deja solo la vigencia y llama a generarReportesDesdeDatosSistema.
- La evidencia se repitio despues de este ajuste de UI.

#### flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/auditoria/chip_datos_sistema_integracion_test.dart
00:00 +0: (setUpAll)
00:00 +0: CGN 2015_001 a 003 reflejan fuentes persistidas del sistema
00:00 +1: (tearDownAll)
00:00 +1: All tests passed!
```

#### flutter analyze

```text
Analyzing Caja_simple...

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:675:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:689:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:93:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:150:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:201:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:237:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:279:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:321:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:391:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:462:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:602:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:769:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:12:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:450:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:522:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:617:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:754:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:375:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:445:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable

flutter : 184 issues found. (ran in 7.5s)
En línea: 2 Carácter: 1
+ flutter analyze *> chip_datos_sistema_analyze_output.txt; exit $LASTE ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (184 issues found. (ran in 7.5s):String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
```

#### flutter build windows

```text
Building Windows application...
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> chip_datos_sistema_build_output.txt; exit $L ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError

Building Windows application...                                    74.8s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
```


## Subtarea Q - Conciliacion de operaciones reciprocas NICSP 40

### Hallazgo y decision

Se implemento la opcion 2 aprobada: una capa de conciliacion separada que vincula partidas concretas de dos o mas asientos existentes. La relacion registra aprobador, fecha, tolerancias de monto y dias, diferencias efectivamente validadas, monto eliminado y soporte. No modifica ni borra asientos o detalles fuente.

La aprobacion requiere el permiso dedicado `Permiso.aprobarConciliacionReciproca`, asignado solo a `RolSectorPublico.contador`. La eleccion conserva a `jefeControlInterno` como instancia independiente de consulta y auditoria, sin facultad para alterar la presentacion contable consolidada.

La migracion v73 crea `conciliaciones_reciprocas` y `conciliaciones_reciprocas_partidas`. Un trigger impide sobreeliminar una partida aun cuando existan conciliaciones parciales sucesivas. La pantalla NICSP 40 permite seleccionar manualmente partidas reales y declarar montos y tolerancias; no infiere coincidencias.

### Evidencia cruda

#### flutter test

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/consolidacion_jerarquica_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/consolidacion_jerarquica_test.dart: 1. Agregación contable correcta de Entidad Padre + 2 Hijas
00:00 +1: C:/Users/PC/Desktop/Caja_simple/test/consolidacion_jerarquica_test.dart: 2. Fail-Closed se dispara si la entidad no existe o no tiene hijas
00:00 +2: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contabilidad/conciliacion_reciprocas_integracion_test.dart
00:01 +2: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/contabilidad/conciliacion_reciprocas_integracion_test.dart: NICSP 40 conserva la reciproca sin conciliar y la elimina solo tras aprobacion contable
00:01 +3: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart
00:01 +3: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir que tesorero apruebe pagos
00:01 +4: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir que tesorero se auto-apruebe en segregación de funciones
00:02 +5: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir que contador expida RP según negacionesPorRol
00:02 +6: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Debe permitir que secretario de hacienda apruebe pagos
00:02 +7: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Secretario de Hacienda NO puede expedir CDP ni RP
00:02 +8: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Jefe de Presupuesto puede expedir CDP y RP
00:02 +9: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Secretario General administra usuarios sin facultades fiscales
00:02 +10: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir acción si el rol no tiene permiso
00:02 +11: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Solo alcalde y secretario de hacienda pueden configurar entidad
00:02 +12: All tests passed!

```

#### flutter analyze

```text
Analyzing Caja_simple...                                        

   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\activos_fijos_page.dart:171:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:367:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\commissions_page.dart:369:41 - deprecated_member_use
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\comprobantes_page.dart:111:25 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\conciliacion_bancaria_page.dart:98:7 - use_build_context_synchronously
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:98:13 - unused_local_variable
warning - The value of the local variable 'data' isn't used - lib\core\api\endpoints\sales_api.dart:124:13 - unused_local_variable
   info - Don't invoke 'print' in production code - lib\core\database\database_initializer.dart:207:5 - avoid_print
warning - The declaration '_migrarDB' isn't referenced - lib\core\database\database_initializer.dart:234:10 - unused_element
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:154:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:157:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:160:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:163:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:166:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:171:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\core\logging\logging_service.dart:216:5 - avoid_print
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:122:37 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:315:36 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:431:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:437:19 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:443:16 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\core\theme\app_theme.dart:449:18 - deprecated_member_use
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:65:7 - unreachable_switch_default
warning - This default clause is covered by the previous cases - lib\core\theme\theme_service.dart:94:7 - unreachable_switch_default
warning - The receiver can't be 'null' because of short-circuiting, so the null-aware operator '?.' can't be used - lib\core\workspace\selector_modo_screen.dart:80:58 - invalid_null_aware_operator
   info - Don't invoke 'print' in production code - lib\db_helper.dart:799:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\db_helper.dart:815:7 - avoid_print
   info - 'Table.fromTextArray' is deprecated and shouldn't be used. Use TableHelper.fromTextArray() instead - lib\declaraciones_tributarias_page.dart:97:15 - deprecated_member_use
   info - The constant name 'presupuesto_publico' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:22:16 - constant_identifier_names
   info - The constant name 'contabilidad_nicsp' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:23:16 - constant_identifier_names
   info - The constant name 'contratacion_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:24:16 - constant_identifier_names
   info - The constant name 'nomina_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:25:16 - constant_identifier_names
   info - The constant name 'auditoria_forense' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:26:16 - constant_identifier_names
   info - The constant name 'rentas_departamentales' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:28:16 - constant_identifier_names
   info - The constant name 'activos_estado' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:30:16 - constant_identifier_names
   info - The constant name 'salud_publica' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:31:16 - constant_identifier_names
   info - The constant name 'consolidacion_nicsp_40' isn't a lowerCamelCase identifier - lib\features\feature_key.dart:34:16 - constant_identifier_names
warning - The value of the local variable 'tipoDocCtrl' isn't used - lib\nomina_page.dart:50:11 - unused_local_variable
   info - Don't use 'BuildContext's across async gaps, guarded by an unrelated 'mounted' check - lib\nomina_page.dart:419:36 - use_build_context_synchronously
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\nomina_page.dart:586:72 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:307:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:308:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:320:15 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:321:15 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:340:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:341:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:350:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:351:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:360:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:361:17 - deprecated_member_use
   info - 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup ancestor to manage group value instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:370:17 - deprecated_member_use
   info - 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to handle value change instead. This feature was deprecated after v3.32.0-0.0.pre - lib\onboarding\onboarding_page.dart:371:17 - deprecated_member_use
warning - The value of the local variable 'ivaGeneralRate' isn't used - lib\sales\application\create_sale_use_case.dart:120:11 - unused_local_variable
warning - The value of the local variable 'ivaReducedRate' isn't used - lib\sales\application\create_sale_use_case.dart:121:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices1' isn't used - lib\sales\application\create_sale_use_case.dart:125:11 - unused_local_variable
warning - The value of the local variable 'retefuenteServices2' isn't used - lib\sales\application\create_sale_use_case.dart:126:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries1' isn't used - lib\sales\application\create_sale_use_case.dart:127:11 - unused_local_variable
warning - The value of the local variable 'retefuenteHonoraries2' isn't used - lib\sales\application\create_sale_use_case.dart:128:11 - unused_local_variable
warning - Unused import: '../models/acta_responsabilidad.dart' - lib\sector_publico\activos\pages\activos_estado_page.dart:15:8 - unused_import
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:324:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:467:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\activos\pages\activos_estado_page.dart:541:19 - deprecated_member_use
warning - The value of the local variable 'idCtrl' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:608:11 - unused_local_variable
warning - The value of the local variable 'dep' isn't used - lib\sector_publico\activos\pages\activos_estado_page.dart:631:29 - unused_local_variable
warning - The value of the local variable 'depreciacionAnual' isn't used - lib\sector_publico\activos\services\activos_service.dart:40:11 - unused_local_variable
   info - The type name 'DatosCGN2015_001' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:93:7 - camel_case_types
   info - The type name 'DatosCGN2015_002' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:150:7 - camel_case_types
   info - The type name 'DatosCGN2015_003' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:201:7 - camel_case_types
   info - The type name 'DatosCGN2015_004' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:237:7 - camel_case_types
   info - The type name 'DatosCGN2015_005' isn't an UpperCamelCase identifier - lib\sector_publico\auditoria\models\reporte_chip.dart:279:7 - camel_case_types
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:512:17 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\auditoria\pages\auditoria_forense_page.dart:676:52 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\fut_territorial_service.dart:5:8 - unused_import
warning - Unused import: 'dart:convert' - lib\sector_publico\auditoria\services\sia_observa_service.dart:5:8 - unused_import
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:226:19 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:252:50 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:260:51 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\contabilidad\pages\contabilidad_nicsp_page.dart:312:15 - unnecessary_string_interpolations
warning - The value of the local variable 'fechaUltimoDia' isn't used - lib\sector_publico\contabilidad\services\depreciacion_job_service.dart:29:11 - unused_local_variable
   info - Unnecessary use of string interpolation - lib\sector_publico\contratacion\pages\contratacion_publica_page.dart:429:19 - unnecessary_string_interpolations
warning - The value of the field '_uuid' isn't used - lib\sector_publico\contratacion\services\secop_service.dart:20:14 - unused_field
   info - Use the null-aware marker '?' rather than a null check via an 'if' - lib\sector_publico\contratacion\services\secop_service.dart:43:7 - use_null_aware_elements
   info - Unnecessary use of string interpolation - lib\sector_publico\nomina\pages\nomina_publica_page.dart:318:15 - unnecessary_string_interpolations
warning - Unused import: '../models/liquidacion_nomina.dart' - lib\sector_publico\nomina\services\pila_service.dart:8:8 - unused_import
   info - The constant name 'en_revision' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\formulacion_mga_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_tecnica' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:13:3 - constant_identifier_names
   info - The constant name 'revision_financiera' isn't a lowerCamelCase identifier - lib\sector_publico\planeacion\services\viabilizacion_service.dart:14:3 - constant_identifier_names
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:329:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:330:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:331:71 - unnecessary_string_interpolations
   info - Unnecessary use of string interpolation - lib\sector_publico\presupuesto\pages\pac_tesoreria_page.dart:423:15 - unnecessary_string_interpolations
warning - The value of the field '_titulos' isn't used - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:34:22 - unused_field
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:695:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:875:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1031:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1207:28 - use_build_context_synchronously
   info - Don't use 'BuildContext's across async gaps - lib\sector_publico\presupuesto\pages\presupuesto_publico_page.dart:1416:28 - use_build_context_synchronously
warning - The value of the local variable 'fechaModificacion' isn't used - lib\sector_publico\presupuesto\services\pac_service.dart:274:11 - unused_local_variable
warning - Unused import: '../models/reporte_spgr.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:16:8 - unused_import
warning - Unused import: '../models/reporte_sicodis.dart' - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:17:8 - unused_import
warning - The value of the field '_bienios' isn't used - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:46:19 - unused_field
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:454:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:581:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:803:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\regalias\pages\regalias_sgp_page.dart:1053:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:793:19 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\rentas\pages\predial_ica_page.dart:864:19 - deprecated_member_use
warning - The value of the field '_dio' isn't used - lib\sector_publico\rentas\services\intereses_moratorios_service.dart:14:13 - unused_field
warning - The declaration '_validarPermiso' isn't referenced - lib\sector_publico\rentas\services\predial_service.dart:27:28 - unused_element
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:84:7 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:540:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:552:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:577:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:649:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:661:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:699:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:791:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:803:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:897:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\salud\pages\salud_publica_page.dart:1042:19 - deprecated_member_use
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1051:23 - curly_braces_in_flow_control_structures
   info - Statements in an if should be enclosed in a block - lib\sector_publico\salud\pages\salud_publica_page.dart:1082:19 - curly_braces_in_flow_control_structures
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:199:17 - deprecated_member_use
   info - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre - lib\sector_publico\siif\pages\siif_page.dart:268:17 - deprecated_member_use
warning - Unused import: 'dart:convert' - lib\sector_publico\siif\services\siif_service.dart:5:8 - unused_import
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\sector_publico\transparencia\pages\transparencia_page.dart:404:56 - deprecated_member_use
   info - Unnecessary use of string interpolation - lib\sector_publico\transparencia\pages\transparencia_page.dart:489:23 - unnecessary_string_interpolations
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:16:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:17:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:18:5 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:22:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:30:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:40:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:42:9 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:54:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:110:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:124:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:143:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:164:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:188:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:354:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:357:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:489:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:492:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:506:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:509:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:510:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:513:7 - avoid_print
   info - Don't invoke 'print' in production code - lib\seed_operations.dart:516:3 - avoid_print
warning - The value of the local variable 'body' isn't used - lib\services\api_router.dart:539:13 - unused_local_variable
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:26:17 - deprecated_member_use
   info - 'RawKeyboard' is deprecated and shouldn't be used. Use HardwareKeyboard instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:5 - deprecated_member_use
   info - 'instance' is deprecated and shouldn't be used. Use HardwareKeyboard.instance instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:31:17 - deprecated_member_use
   info - 'RawKeyEvent' is deprecated and shouldn't be used. Use KeyEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:36:24 - deprecated_member_use
   info - 'RawKeyDownEvent' is deprecated and shouldn't be used. Use KeyDownEvent instead. This feature was deprecated after v3.18.0-2.0.pre - lib\services\barcode_scanner_service.dart:38:19 - deprecated_member_use
   info - Don't invoke 'print' in production code - lib\services\barcode_scanner_service.dart:117:7 - avoid_print
   info - The constant name 'forzar_respaldo' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:10:3 - constant_identifier_names
   info - The constant name 'reiniciar_sesiones' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:11:3 - constant_identifier_names
   info - The constant name 'actualizar_modulos' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:12:3 - constant_identifier_names
   info - The constant name 'enviar_log' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:13:3 - constant_identifier_names
   info - The constant name 'mensaje_admin' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:14:3 - constant_identifier_names
   info - The constant name 'bloquear_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:15:3 - constant_identifier_names
   info - The constant name 'activar_instalacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:16:3 - constant_identifier_names
   info - The constant name 'forzar_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:17:3 - constant_identifier_names
   info - The constant name 'rollback_actualizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:18:3 - constant_identifier_names
   info - The constant name 'forzar_sincronizacion' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:20:3 - constant_identifier_names
   info - The constant name 'actualizar_licencia' isn't a lowerCamelCase identifier - lib\services\cc_commands_processor.dart:21:3 - constant_identifier_names
warning - The value of the field '_claveComandosPendientes' isn't used - lib\services\cc_commands_processor.dart:128:23 - unused_field
warning - The value of the field '_versionActual' isn't used - lib\services\health_reporter.dart:81:23 - unused_field
warning - The value of the local variable 'memoriaTotal' isn't used - lib\services\health_reporter.dart:217:13 - unused_local_variable
warning - The value of the local variable 'metricas' isn't used - lib\services\health_reporter.dart:287:11 - unused_local_variable
warning - The value of the local variable 'recordId' isn't used - lib\services\hybrid_sync_service.dart:182:13 - unused_local_variable
warning - The value of the local variable 'lastSyncRecordId' isn't used - lib\services\hybrid_sync_service.dart:239:14 - unused_local_variable
warning - The value of the local variable 'currentFingerprint' isn't used - lib\services\licencia_service.dart:322:11 - unused_local_variable
warning - The value of the field '_publicKeyPEM' isn't used - lib\services\license_validation_service.dart:11:23 - unused_field
warning - The value of the local variable 'headerEncoded' isn't used - lib\services\license_validation_service.dart:23:13 - unused_local_variable
warning - The value of the local variable 'signatureEncoded' isn't used - lib\services\license_validation_service.dart:25:13 - unused_local_variable
   info - The constant name 'en_proceso' isn't a lowerCamelCase identifier - lib\services\produccion_service.dart:6:3 - constant_identifier_names
   info - The constant name 'metro_cuadrado' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:54 - constant_identifier_names
   info - The constant name 'metro_cubico' isn't a lowerCamelCase identifier - lib\services\recetas_service.dart:4:70 - constant_identifier_names
   info - The constant name 'en_curso' isn't a lowerCamelCase identifier - lib\services\rutas_service.dart:4:30 - constant_identifier_names
warning - The value of the local variable 'db' isn't used - lib\services\sync_aware_db_helper.dart:180:11 - unused_local_variable
warning - The value of the field '_currentVersion' isn't used - lib\services\update_service.dart:120:23 - unused_field
warning - Dead code - lib\services\update_service.dart:198:7 - dead_code
   info - Don't use 'BuildContext's across async gaps - lib\transferencias_page.dart:93:21 - use_build_context_synchronously
warning - The declaration '_marcarPasoCompletado' isn't referenced - lib\ui\onboarding_widget.dart:64:8 - unused_element
   info - Don't use 'BuildContext's across async gaps - lib\ui\onboarding_widget.dart:70:28 - use_build_context_synchronously
warning - The member 'setState' can only be used within instance members of subclasses of 'State' - lib\ui\widgets\workspace_widgets.dart:255:39 - invalid_use_of_protected_member
warning - The declaration '_DesktopModuleDirectory' isn't referenced - lib\ui\widgets\workspace_widgets.dart:1125:7 - unused_element
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:442:22 - deprecated_member_use
   info - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss - lib\warranties_page.dart:444:41 - deprecated_member_use
warning - The value of the local variable 'contabilidadService' isn't used - test\sector_publico\security\rbac_segregacion_test.dart:18:33 - unused_local_variable

flutter : 193 issues found. (ran in 6.6s)
En línea: 2 Carácter: 1
+ flutter analyze *> nicsp40_reciprocas_analyze_output.txt; exit $LASTE ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (193 issues found. (ran in 6.6s):String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 

```

Conteo verificado: 193 issues, 0 errores. Se mantiene la linea base.

#### flutter build windows

```text
Building Windows application...                                 
flutter : Nuget.exe not found, trying to download or use cached version.
En línea: 2 Carácter: 1
+ flutter build windows *> nicsp40_reciprocas_build_output.txt; exit $L ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Nuget.exe not f...cached version.:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
Building Windows application...                                    69.0s
√ Built build\windows\x64\runner\Release\MerkaERP.exe

```

### Cierre de la subtarea Q

Estado: **Parcial implementado y verificado**. Sin conciliacion, el consolidado conserva gasto 100 e ingreso -100; tras aprobacion contable, ambos quedan en 0 y los asientos fuente permanecen identicos. El test tambien confirma denegacion a Control Interno y registro en auditoria.

Commit de implementacion: `0651851 feat(contabilidad): conciliar operaciones reciprocas NICSP 40`.

Pendiente: sugerencia automatica de candidatos con confirmacion humana. El portal de transparencia conserva su brecha separada de configuracion y credenciales externas por entidad.

## Subtarea X - Vigencias futuras y recibidos sin obligacion

### Hallazgo y decision

Se implemento el diseno aprobado en `VIGENCIAS_FUTURAS_HALLAZGOS_Y_DISENO.md` mediante la migracion v74. Las autorizaciones conservan versiones inmutables enlazadas; una nueva version revoca la anterior en la misma transaccion. Municipio exige actos separados de CONFIS y concejo, departamento exige CONFIS y asamblea, y ESE falla cerrado si faltan `estatuto_presupuestal_ese`, `autoridad_competente_ese` o `acto_delegacion_ese`.

La distribucion anual registra monto autorizado, comprometido, obligado, pagado y saldo. Un RP de vigencia posterior no se expide sin autorizacion y su creacion/compromiso es atomica. Obligaciones y pagos se enlazan por IDs explicitos, sin inferencias por monto o fecha. Un recibido a satisfaccion sin obligacion se reconoce como pasivo por devengo, crea incidente auditable y bloquea el pago; no fabrica CDP, RP ni obligacion retroactiva.

RBAC: `alcaldeRepresentanteLegal`, `secretarioHacienda` y `jefePresupuesto` reciben solo `registrarAutorizacionVigenciaFutura`. Los dos primeros registran los actos externos y la coordinacion fiscal; el tercero realiza el registro tecnico y conserva `expedirRP`. El cambio no concede a alcalde ni secretario la expedicion de RP, aprobacion adicional de pagos ni otra facultad operativa.

### Evidencia cruda

#### flutter test test/sector_publico/presupuesto/vigencias_futuras_integracion_test.dart

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/vigencias_futuras_integracion_test.dart
00:00 +0: municipio autorizado recorre compromiso obligacion y pago por anualidad
00:00 +1: ESE configurada autoriza y compromete; ESE incompleta se deniega fail-closed
00:00 +2: bloquea falta/exceso de autorizacion, RBAC y pago de recibido irregular
00:00 +3: All tests passed!
```

#### Regresion de presupuesto y RBAC

Comando: `flutter test test/sector_publico/security/roles_permisos_service_test.dart test/sector_publico/security/rbac_segregacion_test.dart test/sector_publico/presupuesto/presupuesto_service_test.dart`

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir que tesorero apruebe pagos
00:00 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir que tesorero se auto-apruebe en segregación de funciones
00:00 +2: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir que contador expida RP según negacionesPorRol
00:00 +3: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Debe permitir que secretario de hacienda apruebe pagos
00:00 +4: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Secretario de Hacienda NO puede expedir CDP ni RP
00:00 +5: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Jefe de Presupuesto puede expedir CDP y RP
00:00 +6: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Secretario General administra usuarios sin facultades fiscales
00:00 +7: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 NO debe permitir acción si el rol no tiene permiso
00:00 +8: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/roles_permisos_service_test.dart: Validaciones Normativas Duras - Fase 0 Solo alcalde y secretario de hacienda pueden configurar entidad
00:00 +9: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/rbac_segregacion_test.dart
00:01 +9: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/rbac_segregacion_test.dart: Segregación de Funciones y Reglas Fail-Closed RBAC por Módulo 1. Tesoreria/Presupuesto: Un Tesorero NO puede aprobar su propio pago (Segregación de Funciones)
00:01 +10: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/rbac_segregacion_test.dart: Segregación de Funciones y Reglas Fail-Closed RBAC por Módulo 2. Presupuesto/Tesorería: Un Contador NO puede ejecutar pagos (Negación Explícita)
00:01 +11: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/rbac_segregacion_test.dart: Segregación de Funciones y Reglas Fail-Closed RBAC por Módulo 3. Auditoría: El Jefe de Control Interno tiene acceso SOLO LECTURA y NO puede expedir CDP ni reversar asientos
00:01 +12: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/security/rbac_segregacion_test.dart: Segregación de Funciones y Reglas Fail-Closed RBAC por Módulo 4. Seguridad Fail-Closed: Un usuario SIN funcionario vinculado es bloqueado inmediatamente
00:01 +13: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart
00:02 +13: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: (setUpAll)
00:02 +13: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: Validaciones Normativas Duras - Fase 1 NO debe poder expedir CDP sin disponibilidad en rubro
00:02 +14: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: Validaciones Normativas Duras - Fase 1 NO debe poder expedir RP sin CDP previo
00:02 +15: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: Validaciones Normativas Duras - Fase 1 NO debe poder expedir RP si CDP está vencido
00:02 +16: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: Validaciones Normativas Duras - Fase 1 NO debe poder expedir RP si valor excede saldo CDP
00:02 +17: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: Validaciones Normativas Duras - Fase 1 NO debe poder crear obligación sin RP previo
00:02 +18: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: Validaciones Normativas Duras - Fase 1 NO debe poder crear pago sin obligación previa
00:02 +19: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_service_test.dart: (tearDownAll)
00:02 +19: All tests passed!
```

El test historico `presupuesto_pago_integracion_test.dart` no se usa como evidencia de esta subtarea: actualmente falla antes del flujo de pago porque su fixture no crea la tabla `contratos`, exigida por el cambio SECOP ya publicado. No es una regresion introducida por v74.

#### flutter analyze

```text
Analyzing Caja_simple...
flutter : 193 issues found. (ran in 6.3s)
```

Conteo verificado: 193 issues, 0 errores; no hay hallazgos en los archivos tocados.

#### flutter build windows

```text
Building Windows application...
flutter : Nuget.exe not found, trying to download or use cached version.
Building Windows application...                                    69.9s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
```

### Cierre de la subtarea X

Estado: **Parcial implementado y verificado**. El dominio de autorizaciones, distribucion anual, compromiso, obligacion, pago y recibido irregular queda probado. M2 permanece Parcial porque cierre anual/reservas, UI administrativa, revocacion de negocio y validaciones adicionales por estatuto territorial no estan certificadas.

Commit de implementacion: `e7f44b3 feat(presupuesto): implementar vigencias futuras y recibidos excepcionales`.
