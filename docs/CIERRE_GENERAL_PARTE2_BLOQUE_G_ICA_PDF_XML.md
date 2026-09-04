# Cierre general Parte 2 - Bloque G: Exportacion ICA PDF/XML

Fecha: 2026-08-13

## Investigacion normativa y tecnica

Fuentes consultadas:

- Ministerio de Hacienda y Credito Publico, carpeta "Formulario de Impuesto de Industria y Comercio": https://www.minhacienda.gov.co/apoyo-fiscal-territorial/formulario-impuesto-de-industria-y-comercio
- Ministerio de Hacienda, Resolucion 4056 de 2017 y "Formato unico ICA diciembre 4 de 2017 version final", publicados en la carpeta anterior.
- Funcion Publica, Ley 14 de 1983: https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=267
- SUIN-Juriscol, jurisprudencia sobre ICA y avisos/tableros: https://www.suin-juriscol.gov.co/viewDocument.asp?id=20007195
- Portal GOV/Funcion Publica, tramite municipal ICA Funza como evidencia de recepcion local/municipal: https://visorsuit.funcionpublica.gov.co/auth/visor?fi=45055

Hallazgo:

- Si existe un Formulario Unico Nacional de ICA publicado por MinHacienda, asociado a Resolucion 4056 de 2017.
- La presentacion operativa, cargue electronico, recibo de pago y validaciones finales siguen dependiendo del portal tributario de cada municipio.
- Por tanto, MerkaERP puede generar un PDF/XML local con los datos normativos minimos y consistentes con el formulario nacional, pero no debe afirmar transmision/cargue oficial municipal sin integracion especifica del municipio.

## Implementacion

Archivos:

- `lib/sector_publico/rentas/services/ica_service.dart`
- `lib/sector_publico/rentas/pages/predial_ica_page.dart`
- `test/sector_publico/rentas/exportacion_declaraciones_test.dart`
- `test/sector_publico/rentas/predial_ica_page_test.dart`

Cambios:

- `ICAService.exportarDeclaracionICAXml()`: genera XML local estructurado con entidad, contribuyente, actividad, periodo, ingresos, base gravable, ICA, ReteICA, mora y total.
- `ICAService.exportarDeclaracionICAPdfBytes()`: genera PDF local basado en el Formulario Unico Nacional de ICA y deja visible la salvedad municipal.
- La UI deja de mostrar "Pendiente" y ofrece exportacion PDF/XML desde cada declaracion ICA.
- Se mantiene `exportarDeclaracionICAAPlano()` por compatibilidad.

## Evidencia cruda

### Tests del bloque

Comando:

```powershell
flutter test test\sector_publico\rentas\exportacion_declaraciones_test.dart test\sector_publico\rentas\predial_ica_page_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/exportacion_declaraciones_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/exportacion_declaraciones_test.dart: Exportación de Liquidación Predial y Declaración ICA a formato plano
Helvetica-Bold has no Unicode support see https://github.com/DavBfr/dart_pdf/wiki/Fonts-Management
Helvetica has no Unicode support see https://github.com/DavBfr/dart_pdf/wiki/Fonts-Management
00:00 +1: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/predial_ica_page_test.dart
00:01 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/predial_ica_page_test.dart: (setUpAll)
00:01 +1: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/predial_ica_page_test.dart: PredialICAPage renders Predial and ICA tabs and TODO banner
00:03 +2: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/rentas/predial_ica_page_test.dart: (tearDownAll)
00:03 +2: All tests passed!
```

### Analyze dirigido

Comando:

```powershell
dart analyze lib\sector_publico\rentas\services\ica_service.dart lib\sector_publico\rentas\pages\predial_ica_page.dart test\sector_publico\rentas\exportacion_declaraciones_test.dart test\sector_publico\rentas\predial_ica_page_test.dart
```

Resultado:

```text
0 errores.
9 issues informativos preexistentes en predial_ica_page.dart: curly_braces_in_flow_control_structures y deprecated_member_use.
```

### Flutter analyze global

Comando:

```powershell
flutter analyze > bloque_g_analyze.txt 2>&1
```

Resultado:

```text
ERROR_COUNT=0
239 issues found. (ran in 10.0s)
```

