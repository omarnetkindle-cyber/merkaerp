# Cierre de auditoría comercial - sesión 2026-08-09

Este log registra los seis bloques solicitados en orden. Cada bloque debe
tener su propio commit, evidencia cruda y sección literal de cierre antes de
iniciar el siguiente.

## Bloque 1 - UVT y ReteFuente

### Hallazgo y decisión

- El umbral de POS usaba `47062`, presentado como UVT 2024. Se sustituyó por
  una política central con UVT 2026 de COP 52.374, soportada por la Resolución
  DIAN 000238 de 2025.
- La política usa 2 UVT para servicios, 10 UVT para otros ingresos y ninguna
  base mínima para honorarios, conforme al cambio normativo de 2025 consultado
  en los conceptos DIAN 8536/2025 y 5224/2026. La semilla de
  `RTFTE_COMPRAS_25` quedó en 10 UVT expresadas en centavos; una base no nula
  configurada por una empresa no se sobrescribe durante la migración.
- POS selecciona tarifa por concepto y calidad del beneficiario. Compras
  conserva la captura manual existente, pero cada fila nueva registra
  concepto, base y tarifa aplicada cuando se conocen.
- F350 ya no reparte el total 40/30/20: lee las transacciones y acumula por
  `compras`, `servicios`, `honorarios`, `arrendamientos` u
  `otros_ingresos`. Las filas antiguas sin metadatos usan su subtotal como
  base de compatibilidad y no reciben una clasificación inventada.
- El requisito normativo completo permanece Parcial porque la captura manual
  de compras y la responsabilidad tributaria concreta de cada contribuyente
  todavía requieren configuración/validación especializada.

### Archivos

- `lib/taxes/retention_policy.dart`
- `lib/taxes/retention_schema_migration.dart`
- `lib/db_helper.dart` y `lib/core/database/database_initializer.dart`
- `lib/sales/application/create_sale_use_case.dart`
- `lib/purchases/application/create_purchase_use_case.dart`
- `lib/declaraciones_tributarias_page.dart`
- `test/commercial_tax_block1_test.dart`
- `docs/MATRIZ_TRAZABILIDAD_COMERCIAL.md`

### Evidencia cruda

Los archivos siguientes contienen la salida completa, sin resumir, de la
verificación final del bloque:

- `docs/evidencias/auditoria_comercial_bloque_1/block1_tests.txt`
- `docs/evidencias/auditoria_comercial_bloque_1/block1_analyze_final.txt`
- `docs/evidencias/auditoria_comercial_bloque_1/block1_build_final.txt`

El test dirigido terminó así:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/commercial_tax_block1_test.dart
00:00 +0: ... (setUpAll)
00:02 +0: ... usa UVT 2026 y bases legales por concepto sin pasar por double
00:02 +1: ... la semilla de compras usa 10 UVT sin pisar una base configurada
00:02 +2: ... F350 conserva concepto, base y tarifa de cada transacción
00:02 +3: ... POS aplica base de servicios de 2 UVT y tarifa configurable
00:02 +4: ... (tearDownAll)
00:02 +4: loading C:/Users/PC/Desktop/Caja_simple/test/sales_flow_test.dart
00:03 +4: ... (setUpAll)
00:06 +4: ... venta POS descuenta inventario, registra caja y asiento contable
00:06 +5: ... venta POS aplica ReteICA solo desde regla activa de ventas
00:06 +6: ... (tearDownAll)
00:06 +6: All tests passed!
```

Resultado crudo del comando de análisis: `241 issues found. (ran in 8.0s)`;
salida completa en `block1_analyze_final.txt`. No se introdujeron errores de
compilación en los archivos de este bloque.

Resultado crudo del build:

```text
Building Windows application...
flutter : Nuget.exe not found, trying to download or use cached version.
Building Windows application...                                    78.2s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
```

### Cierre de la subtarea 1

Bloque 1 implementado y verificado. Tests dirigidos: 6 pasaron. Analyze:
241 issues, 0 errores de análisis. Build Windows: exitoso. La matriz fue
actualizada manteniendo ReteFuente en Parcial por la brecha explícita indicada.

Commit: `48e7554`.

## Bloque 2 - Inventario y costeo

### Hallazgo y decisión

- El enum `InventoryCostMethod` exponía `fifo`, `lifo` y `average`; LIFO fue
  retirado por no ser una política seleccionable del sistema. El ledger
  avanzado conserva FIFO para su superficie técnica, y el dominio operativo
  usa promedio ponderado.
- `productos.costo` es la fuente de verdad del costo promedio operativo.
  `lotes` se conserva para FEFO físico y vencimientos. `inventory_lots` queda
  como almacenamiento del ledger avanzado por bodega/branch, sin consumidor
  POS; no se usa para duplicar el saldo operativo.
- `kardex_inventario` se convirtió en el histórico canónico y se alimenta con
  `InventoryMovementService` junto con `movimientos_inventario`, dentro de la
  misma transacción. Se cubrieron compra, venta, anulaciones, ajustes,
  traslados y movimientos de bodega.
- El test de compra mediante `CreatePurchaseUseCase` no pudo usar el camino
  de crédito en una base fresca por una incompatibilidad anterior: la tabla
  `cuentas_por_pagar` no tiene `proveedor_id`/`compra_id`, aunque el caso de
  uso los inserta. El test del bloque siembra la compra con el esquema real y
  valida los escritores de Kardex; esta brecha queda anotada para un frente
  posterior, no se oculta como éxito de compra.

### Evidencia cruda

- `docs/evidencias/auditoria_comercial_bloque_2/block2_tests.txt`
- `docs/evidencias/auditoria_comercial_bloque_2/block2_analyze.txt`
- `docs/evidencias/auditoria_comercial_bloque_2/block2_build.txt`

Resumen crudo de la prueba: `16` pasaron, `All tests passed!`.
Analyze: `240 issues found`, sin errores; build Windows exitoso.

### Cierre de la subtarea 2

Bloque 2 implementado y verificado con 16 pruebas dirigidas y regresiones de
ventas/ledger. La lista de archivos temporales permanentes está en la carpeta
de evidencia indicada. Commit: `451156b`.

## Bloque 3 - F300 confiable

### Hallazgo y decisión

El detalle comercial no guardaba tarifa ni IVA por línea y el borrador
calculaba `baseGravada = ventas / 1.19`. Se agregó la migración v88 con
`impuesto_pct` e `impuesto_total` en `ventas_detalle` y `compras_detalle`.
F300 ahora agrupa bases e IVA generado por 0/5/19 y separa el IVA descontable
por origen de compra. Los encabezados sin detalle se usan solo como fallback
histórico, sin inferir una tarifa distinta.

### Evidencia cruda

- `docs/evidencias/auditoria_comercial_bloque_3/block3_tests_final.txt`
- `docs/evidencias/auditoria_comercial_bloque_3/block3_analyze_final.txt`
- `docs/evidencias/auditoria_comercial_bloque_3/block3_build_final.txt`

La salida de tests terminó en `00:21 +14: All tests passed!`. Analyze terminó
en `240 issues found` y build en `Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe`.

### Cierre de la subtarea 3

Bloque 3 implementado y verificado con 14 pruebas. La regresión de la corrida
conjunta por teardown de fixtures fue corregida antes de esta evidencia final.
Commit: `1bc6901`.

## Bloque 4 - Periodos contables y cierre anual

### Hallazgo y decisión

La tabla `periodos_contables` tenía una unicidad global `(anio, mes)` y no
aislaba por empresa, aunque varios consumidores ya intentaban leer
`company_id`. Se implementó la migración v89, reconstruyendo la tabla cuando
era legacy, preservando sus filas y atribuyendo solo las filas sin empresa a
la empresa activa. El esquema final usa `UNIQUE(company_id, anio, mes)`.

El cierre anual comercial se implementó en `DatabaseHelper.cerrarEjercicioContable`.
Consulta los saldos reales de clases 4 a 7 del año, crea un asiento balanceado
contra `3605` (utilidad) o `3610` (pérdida), y crea un segundo asiento que
traslada el resultado a `3705` (resultados acumulados). Ambos asientos y sus
comprobantes se registran en una sola transacción, compatible con el trigger
v76 de partida doble. La migración asegura las cuentas 37/3705 si faltaban.

Durante el test apareció un bug adicional real en `_tomarConsecutivo`: el
primer comprobante de un tipo nuevo dejaba la secuencia en 1, por lo que el
segundo reutilizaba `DOC-000001`. Se corrigió para dejar `siguiente=2` después
de emitir el primero.

### Evidencia cruda

- `docs/evidencias/auditoria_comercial_bloque_4/block4_tests.txt`
- `docs/evidencias/auditoria_comercial_bloque_4/block4_analyze.txt`
- `docs/evidencias/auditoria_comercial_bloque_4/block4_build.txt`

Salida de tests dirigidos: `commercial_accounting_close_block4_test.dart`,
`accounting_report_test.dart`, `accounting_rules_test.dart` y
`commercial_security_test.dart`; **13 pruebas pasaron, 0 fallas**.

Analyze completo: **240 issues, 0 errores**; el proceso termina con código 1
por las advertencias/info existentes. Build Windows: **exitoso**, con
`Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe`.

### Cierre de la subtarea 4

Bloque 4 implementado y verificado. La fila de cierre anual sube a Completo;
la fila de periodos por empresa permanece Parcial porque aún no existe una
prueba exhaustiva de todos los consumidores de bloqueo mensual. La
validación SQL de partida doble continúa intacta.

Commit: `53af425`.

## Bloque 5 - Nómina privada completa

### Hallazgo y decisión

El cálculo original ignoraba `payroll_novelties`, leía solo el salario base
para aportes, no usaba `health_exonerated`, dejaba `retefuente` en cero y
escribía caja, asiento y liquidación fuera de una transacción. Se corrigió
para sumar novedades salariales explícitas (`horas_extra` y bonificaciones o
comisiones salariales) al IBC, manteniendo el auxilio de transporte fuera de
esa base. Salud, pensión, ARL y parafiscales usan el IBC disponible.

La exoneración configurada deja en cero salud del empleador, SENA e ICBF, y
conserva caja de compensación. La retención laboral usa la tabla progresiva
del artículo 383 del Estatuto Tributario con la UVT almacenada en
`payroll_parameters`, sin pasar por `double`. El sistema todavía no captura
deducciones laborales adicionales del trabajador, por lo que ese límite queda
explícito y no se presenta como una certificación tributaria total.

La migración v90 agrega `movimiento_caja_id` y `asiento_id` a
`nomina_liquidaciones` y siembra las cuentas contables requeridas para cargas
y provisiones patronales. Todo el flujo de persistencia queda dentro de una
transacción; el test fuerza el fallo por periodo cerrado después de insertar
el movimiento y confirma el rollback.

### Evidencia cruda

- `docs/evidencias/auditoria_comercial_bloque_5/block5_tests.txt`
- `docs/evidencias/auditoria_comercial_bloque_5/block5_analyze.txt`
- `docs/evidencias/auditoria_comercial_bloque_5/block5_build.txt`

Salida conjunta: **37 pruebas pasaron, 0 fallas** (`All tests passed!`).
Incluye el test nuevo de variables/exoneración/retención/rollback, nómina
fiscal, ausencia HRM, Bloques 1-4 y seguridad contable.

Analyze completo: **240 issues, 0 errores**; salida con código 1 por warnings
e info existentes. Build Windows: **exitoso**, con
`Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe`.

### Cierre de la subtarea 5

Bloque 5 implementado y verificado. La fila de nómina que exigía atomicidad y
retención deja de estar Pendiente y pasa a Parcial por las deducciones
laborales aún no modeladas; las demás filas conservan estados honestos.

Commit: `2e336b6`.

## Bloque 6 - Marco NIIF configurable por empresa

### Implementacion

Se implemento la migracion v91 con `companies.niif_group`, usando
`grupo_2` como fallback tecnico defensivo para empresas existentes y sin
fabricar una clasificacion legal. Se agregaron `FinancialFrameworkGroup` y
`FinancialFrameworkPolicy`, mas los metodos de `DatabaseHelper` para guardar
el grupo declarado y consultar el marco, el perfil de revelacion y la
politica de deterioro de inventarios. Grupo 1, 2 y 3 quedan diferenciados en
esa politica visible. No se modificaron saldos, consolidacion, transferencias,
revelaciones completas de Grupo 1 ni DIAN/PTA real.

Archivos principales:

- `lib/accounting/financial_framework.dart`
- `lib/accounting/financial_framework_schema_migration.dart`
- `lib/db_helper.dart`
- `lib/core/database/database_initializer.dart`
- `lib/taxes/retention_schema_migration.dart`
- `lib/taxes/tax_report_schema_migration.dart`
- `lib/taxes/payroll_schema_migration.dart`
- `lib/accounting/accounting_period_schema_migration.dart`
- `test/commercial_niif_block6_test.dart`
- `docs/MARCO_NIIF_CONFIGURABLE_BLOQUE_6_DISENO.md`
- `docs/MATRIZ_TRAZABILIDAD_COMERCIAL.md`

### Evidencia cruda

- Tests dirigidos de los seis bloques: `docs/evidencias/auditoria_comercial_bloque_6/block6_tests.txt`.
  Resultado final literal: `00:30 +21: All tests passed!`.
- Analisis Dart completo: `docs/evidencias/auditoria_comercial_bloque_6/block6_analyze.txt`.
  Resultado literal: `240 issues found.` y `[exit_code=2]`; son warnings/info
  existentes, sin errores de compilacion reportados por el analizador.
- `flutter analyze`: `docs/evidencias/auditoria_comercial_bloque_6/block6_flutter_analyze.txt`.
  Resultado literal: `240 issues found. (ran in 6.5s)`; no hay errores de
  analisis en el codigo del bloque.
- Build Windows: `docs/evidencias/auditoria_comercial_bloque_6/block6_build.txt`.
  Resultado literal: `Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe`
  y `[exit_code=0]`.

### Verificacion global y correcciones defensivas

La primera suite completa de esta ronda llego a `309` pruebas pasadas, `3`
omitidas y `3` fallas. Las tres fallas compartian la misma causa: pruebas de
migraciones parciales creaban solo parte del esquema y v87/v88/v89/v90
intentaban alterar tablas ausentes. Se agregaron guardas de existencia, sin
cambiar el esquema cuando la tabla no existe. La regresion dirigida posterior
paso las `8` pruebas de CRM, capacidad MRP y partida doble SQL:
`block6_migration_regressions.txt`.

La repeticion de la suite global no alcanzo un resumen final porque volvio a
quedar bloqueada en `presupuesto_publico_page_test.dart`, al iniciar `Crear
apropiacion y verificar en base de datos`, el bloqueo Fase 3B ya conocido y
ajeno a este bloque comercial. La salida parcial completa esta en
`block6_full_suite_final.txt`; no se presenta como suite limpia. La regresion
comercial aislada si termino con `23` pruebas pasadas en
`block6_commercial_suite_final.txt`.

La evidencia final de analisis y build esta en
`block6_flutter_analyze_final.txt` y `block6_build_final.txt`.

### Cierre de la subtarea 6

Bloque 6 implementado y verificado. La matriz cambia el requisito de marco
NIIF de Pendiente a Parcial y queda en **3 Completos / 21 Parciales / 4
Pendientes**. El estado Parcial es intencional: MerkaERP puede declarar un
marco por empresa y expone politicas distintas, pero aun no clasifica
automaticamente por activos/ingresos/empleados/relaciones ni genera el
conjunto completo de revelaciones de cada grupo.

Commit de implementacion: `845676f`.

## Verificacion final posterior a los seis bloques

### Presupuesto publico: causa y resultado

`git log --follow` y `git blame` confirman que el fixture de
`test/sector_publico/presupuesto/presupuesto_publico_page_test.dart` fue
modificado por `6b3bf5f` y documentado por `0c1c169`; ningun commit de los
seis bloques de esta sesion toco ese archivo ni su fixture. El archivo sigue
usando `databaseFactoryFfiNoIsolate` y `tester.runAsync` alrededor de la
preparacion asincrona.

El test aislado produjo salida cruda en
`docs/evidencias/presupuesto_publico_aislado_2026-08-09.txt`: los 7 tests
pasaron en 11 segundos. No hubo `TimeoutException`, `dart:isolate` ni
`RawReceivePort`. Por tanto no se revirtio el fix ni se cambio el fixture.
La corrida global con `--concurrency=4` tuvo una falla distinta de
interferencia entre pruebas: el `tearDownAll` de `commercial_tax_block1_test.dart`
no pudo borrar una carpeta temporal bloqueada por otra prueba concurrente.
La corrida definitiva serial con `--concurrency=1` si termino limpia.

### Estado especifico de los Bloques 1-5

1. **UVT y ReteFuente.** `RetentionPolicy.currentUvtMajorUnits` es `52374`
   y el test `commercial_tax_block1_test.dart` verifica la UVT 2026, 2 UVT
   para servicios y 10 UVT para la semilla de compras. La busqueda exhaustiva
   no encontro `47062` en `lib/`; los consumidores usan
   `RetentionPolicy`, incluyendo `create_sale_use_case.dart`,
   `purchases/application/create_purchase_use_case.dart`,
   `declaraciones_tributarias_page.dart` y la configuracion de
   `payroll_parameters`. Sigue Parcial la captura normativa completa de
   compras y la responsabilidad tributaria especifica de cada empresa.
2. **Inventario/LIFO.** `InventoryCostMethod` ya solo expone `fifo` y
   `average`; LIFO no es seleccionable. El costeo operativo de compras usa
   promedio ponderado y `productos.costo` sigue siendo el saldo operativo.
   `InventoryMovementService` ya escribe activamente en
   `kardex_inventario` junto con `movimientos_inventario`. No se fusionaron
   fisicamente `inventory_lots`, `lotes` y el stock de `productos`: siguen
   siendo representaciones con responsabilidades distintas, documentadas
   como brecha de reconciliacion completa.
3. **F300.** `obtenerBorradorFormulario300()` lee `impuesto_pct` por linea y
   separa tarifas 0/5/19, IVA generado y descontable por origen. El test
   `commercial_f300_block3_test.dart` verifica exactamente IVA generado de
   10.000 (5 %), 57.000 (19 %), total 67.000 y descontable 19.000. No sigue
   usando 19 % general para el detalle que tiene tarifa.
4. **Cierre contable.** v89 reconstruye `periodos_contables` con
   `company_id` y unicidad `(company_id, anio, mes)`. `cerrarEjercicioContable()`
   crea el asiento de cierre de ingresos/gastos contra resultado y un segundo
   asiento a `3705`; `commercial_accounting_close_block4_test.dart` verifica
   utilidad exacta de 70.000 centavos y el traslado a patrimonio. El bloqueo
   completo de todos los consumidores despues del cierre mensual permanece
   Parcial.
5. **Nomina privada.** `liquidarNomina()` suma novedades salariales de
   `payroll_novelties` al IBC y excluye auxilio de transporte; lee
   `health_exonerated`, calcula retencion con `PayrollWithholding` en vez de
   dejarla en cero, agrega cargas patronales al asiento y ejecuta movimiento,
   asiento y liquidacion dentro de una transaccion. El test
   `commercial_payroll_block5_test.dart` verifica variables, exoneracion,
   tabla progresiva del articulo 383 y rollback cuando el periodo cerrado
   fuerza un fallo. Sigue Parcial por deducciones laborales adicionales no
   capturadas y escenarios tributarios que requieren mas parametrizacion.

### Evidencia final

- Suite global serial: `docs/evidencias/suite_global_verificacion_2026-08-09_serial.txt`;
  `312` pasaron, `3` omitidos, `0` fallas, `All other tests passed!`.
- `flutter analyze`: `docs/evidencias/flutter_analyze_cierre_6_bloques_2026-08-09.txt`;
  `240 issues`, sin errores de analisis.
- `flutter build windows`:
  `docs/evidencias/flutter_build_windows_cierre_6_bloques_2026-08-09.txt`;
  `Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe`, codigo 0.

No hubo correccion adicional de codigo en esta verificacion; solo se
agregaron evidencia y esta documentacion.

## Bloque 6 - Marco NIIF configurable por empresa

### Decision normativa previa

Se revisaron los articulos 1.1.1.1, 1.1.2.1 y 1.1.3.1 del Decreto 2420 de
2015 y los Anexos 1, 2 y 3. Grupo 1 depende de emision/interes publico o de
los umbrales de mas de 200 trabajadores o 30.000 SMMLV junto con una
relacion societaria o comercio exterior relevante; Grupo 2 cubre a quien no
esta en Grupo 1 ni Grupo 3 y permite opcion voluntaria desde Grupo 3; Grupo 3
exige todas las condiciones de microempresa. Los marcos tecnicos y sus
revelaciones son diferentes.

La decision conservadora es configurar el grupo por empresa. No se puede
clasificar automaticamente con los datos actuales porque faltan promedios
anuales y relaciones societarias. La implementacion inicial sera la
configuracion declarada y una politica consultable, no una afirmacion de
cumplimiento completo. Grupo 2/3 reciben el alcance prioritario; Grupo 1
queda disponible con revelaciones completas pendientes.

El detalle normativo y las fuentes oficiales quedan en
`docs/MARCO_NIIF_CONFIGURABLE_BLOQUE_6_DISENO.md`. No se implementan DIAN/PTA
real ni multiempresa/consolidacion/transferencias en este bloque.
