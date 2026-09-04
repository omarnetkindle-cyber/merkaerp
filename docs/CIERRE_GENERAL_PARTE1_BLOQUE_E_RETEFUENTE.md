# Cierre general Parte 1 - Bloque E: Configuracion tributaria completa de ReteFuente

Fecha: 2026-08-13

## Investigacion normativa y fuentes

Fuentes consultadas:

- DIAN, Decreto 1625 de 2016, Decreto Unico Reglamentario en materia tributaria: https://normograma.dian.gov.co/dian/compilacion/docs/decreto_1625_2016.htm
- DIAN, Decreto 0572 de 2025, ajuste de bases minimas en UVT para retencion en la fuente: https://normograma.dian.gov.co/dian/compilacion/docs/decreto_0572_2025.htm
- DIAN, Concepto 10721 de 2025, arrendamiento de bienes inmuebles: https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_10721_2025.htm
- DIAN, Concepto 12329 de 2025, tarifas 3.5% y bases minimas: https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_12329_2025.htm
- DIAN, Concepto 5224 de 2026, servicios temporales, aseo/vigilancia y arrendamiento de bienes muebles: https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_5224_2026.htm
- DIAN, Decreto 3715 de 1986 compilado, rendimientos financieros 7%: https://normograma.dian.gov.co/dian/compilacion/docs/decreto_3715_1986.htm
- DIAN, Oficio 902027 de 2022, otros ingresos tributarios 2.5% / 3.5%: https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_902027_2022.htm

Decision conservadora:

- Mantener `reglas_retenciones_empresa` como fuente configurable por empresa.
- Sembrar conceptos comunes de ReteFuente sin bloquear que el usuario ajuste tarifa/base si su regimen tributario difiere del general.
- No usar `tax_parameters.reteica_base_rate` ni parametros globales para ReteFuente/ReteICA en ventas POS.
- Separar codigos `RTFTE_*` de `RTEICA*` para evitar que una regla de ReteFuente sea aplicada como ReteICA.

## Implementacion

Archivos principales:

- `lib/taxes/retention_rule_service.dart`
- `lib/taxes/retention_policy.dart`
- `lib/taxes/retention_schema_migration.dart`
- `lib/db_helper.dart`
- `lib/sales/application/create_sale_use_case.dart`
- `lib/configuracion_page.dart`
- `test/commercial_tax_block1_test.dart`

Cambios:

- Migracion v99: siembra defensiva de reglas RTFTE por empresa.
- POS/ventas: ReteFuente se calcula desde `reglas_retenciones_empresa`, filtrando por concepto, declarante/no declarante, `activo=1` y `aplica_ventas=1`.
- ReteICA: sigue leyendo solo reglas `RTEICA%`, evitando mezclar conceptos.
- UI Configuracion: se agrego seccion editable "ReteFuente por concepto" para modificar tarifa, base minima y estado activo.
- Tests: se agrego prueba de ajuste usuario para tarifa/base por concepto y se extendio la prueba de bases UVT por concepto.

## Evidencia cruda

### Test del bloque

Comando:

```powershell
flutter test test\commercial_tax_block1_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/commercial_tax_block1_test.dart
00:00 +0: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:02 +0: usa UVT 2026 y bases legales por concepto sin pasar por double
00:02 +1: la semilla de compras usa 10 UVT sin pisar una base configurada
00:02 +2: F350 conserva concepto, base y tarifa de cada transacción
00:02 +3: POS aplica base de servicios de 2 UVT y tarifa configurable
00:02 +4: usuario puede ajustar tarifa/base de ReteFuente por concepto
00:03 +5: (tearDownAll)
00:03 +5: All tests passed!
```

### Analyze dirigido

Comando:

```powershell
dart analyze lib\taxes\retention_rule_service.dart lib\taxes\retention_policy.dart lib\taxes\retention_schema_migration.dart lib\sales\application\create_sale_use_case.dart lib\configuracion_page.dart test\commercial_tax_block1_test.dart
```

Salida:

```text
Analyzing retention_rule_service.dart, retention_policy.dart, retention_schema_migration.dart, create_sale_use_case.dart, configuracion_page.dart, commercial_tax_block1_test.dart...
No issues found!
```

### Flutter analyze global

Comando:

```powershell
flutter analyze > bloque_e_analyze.txt 2>&1
```

Resultado:

```text
240 issues found. (ran in 8.4s)
Errores: 0
```

Los 240 issues corresponden a warnings/info de linea base del proyecto; no hay errores del Bloque E.

