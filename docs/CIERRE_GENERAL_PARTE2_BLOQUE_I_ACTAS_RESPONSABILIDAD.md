# Bloque I - Actas de responsabilidad de activos

Fecha: 2026-08-13

## Fuentes revisadas

- Contaduria General de la Nacion, `GAD-PRC22 Administracion de Bienes`
  (procedimiento de gestion administrativa). Define la administracion de bienes
  desde ingreso hasta uso por la unidad consumidora, el traslado como cese de
  responsabilidad de quien entrega y actualizacion al nuevo servidor publico, y
  los formatos GAD22-FOR01/FOR02/FOR03 para reintegro, traslado/entrega de
  elementos devolutivos y paz y salvo. Fuente:
  https://www.contaduria.gov.co/documents/d/guest/20241025_procedimientogad-prc22-administracion-de-bienes-docx?download=true
- Procedimientos de inventarios de entidades publicas colombianas consultados
  como referencia operativa: el cuentadante es el servidor publico que tiene a
  cargo y responsabilidad bienes de la entidad para sus funciones; los traslados
  y reintegros requieren soporte firmado y actualizacion del inventario.

## Hallazgo

El sistema ya tenia tabla, modelo, servicio y UI basica para actas de
responsabilidad, pero el aviso visible todavia las marcaba como pendientes y el
modelo no guardaba firma/entrega/hash del acta. Tambien faltaba una transicion
separada para devolucion.

## Implementacion

- Migracion `schemaVersion = 101` con columnas defensivas en
  `actas_responsabilidad`:
  - `fecha_entrega`
  - `firmado_por_funcionario`
  - `fecha_firma_funcionario`
  - `firmado_por_almacen`
  - `fecha_firma_almacen`
  - `hash_acta`
  - `version_formato`
- `ActaResponsabilidad` soporta estado `pendienteFirma`, firmas, entrega, hash
  y `copyWith`.
- `ActaResponsabilidadService` separa el ciclo:
  - `generarActaPendiente`
  - `firmarYEntregarActa`
  - `devolverResponsabilidad`
  - `trasladarResponsabilidad`
- La API vieja `asignarResponsabilidad` queda compatible: genera, firma y
  entrega en una sola llamada, para no romper la UI existente.
- La UI de activos ya no muestra el mensaje "Pendiente"; ahora informa que las
  actas estan activas con firma, entrega, traslado y devolucion auditables.

## Evidencia cruda

Comando:

```powershell
dart analyze lib\sector_publico\activos\database\schema_activos.dart lib\sector_publico\activos\models\acta_responsabilidad.dart lib\sector_publico\activos\services\acta_responsabilidad_service.dart lib\sector_publico\activos\pages\activos_estado_page.dart lib\db_helper.dart test\sector_publico\activos\acta_responsabilidad_service_test.dart
```

Salida:

```text
Analyzing schema_activos.dart, acta_responsabilidad.dart, acta_responsabilidad_service.dart, activos_estado_page.dart, db_helper.dart, acta_responsabilidad_service_test.dart...

   info - lib\db_helper.dart:876:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\db_helper.dart:892:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:240:19 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:395:19 - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:404:23 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:461:19 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:622:19 - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:631:23 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:677:19 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:749:19 - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:756:23 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:803:19 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib\sector_publico\activos\pages\activos_estado_page.dart:948:19 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures

13 issues found.
```

Comando:

```powershell
flutter test test\sector_publico\activos\acta_responsabilidad_service_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/activos/acta_responsabilidad_service_test.dart
00:00 +0: Generar, firmar, entregar y exportar acta de responsabilidad
00:00 +1: Asignar Acta de Responsabilidad conserva API y permite devolver
00:00 +2: All tests passed!
```
