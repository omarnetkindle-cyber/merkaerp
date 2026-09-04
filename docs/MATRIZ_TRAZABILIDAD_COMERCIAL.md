# Matriz de trazabilidad comercial

**Corte de auditoría:** 2026-08-01  
**Alcance:** código comercial de MerkaERP (`lib/` y pruebas comerciales en `test/`). Se excluye la implementación del sector público.  
**Propósito:** relacionar requisito normativo/funcional, código, prueba ejecutada, evidencia y estado real. Este documento no certifica cumplimiento legal; identifica qué está respaldado por código y pruebas y qué requiere corrección o validación especializada.

## Criterio de estados

- **Completo:** implementación y prueba ejecutada cubren específicamente el requisito.
- **Parcial:** existe implementación, pero falta cobertura, integración o exactitud normativa.
- **Pendiente:** no existe una implementación utilizable o la existente no cumple el requisito esencial.
- **No verificable sin más contexto:** faltan datos de configuración, clasificación del contribuyente o una decisión contable/tributaria para evaluar el requisito.

## Resumen ejecutivo

1. No existe una política monetaria central: dinero, cantidades, impuestos y saldos usan `double` en Dart y `REAL` en SQLite. Un probe reprodujo `10000 x 99.99 = 999899.99999992212` y una diferencia de COP 0,01 entre redondeo de IVA por línea y por documento.
2. ReteICA en ventas POS ya se calcula exclusivamente desde una regla empresarial activa y aplicable a ventas; sin regla, el valor es cero. Dos casos de integración verifican ambos caminos.
3. Los borradores F300/F350 siguen sin ser confiables: F300 supone que toda venta incluye IVA 19 % y F350 distribuye retenciones con porcentajes arbitrarios 40/30/20. La consulta de nómina del reporte fiscal ya usa la columna real `neto_pagar` y tiene prueba de integración.
4. La facturación electrónica es local/simulada. El cliente activo es `NoOp`; el supuesto CUFE es Base64 más un sufijo, no SHA-384 conforme al anexo técnico DIAN vigente; no hay CUDE.
5. La partida doble se valida en servicios, pero no en SQLite. Un probe insertó por SQL directo un asiento con débito 100 y crédito 0.
6. Inventarios mezclan promedio ponderado, FEFO y un stock ledger separado que incluso expone LIFO. El flujo POS no consume ese ledger y `kardex_inventario` no tiene escritores activos.
7. Nómina privada contiene tarifas base razonables, pero calcula IBC sobre salario básico, ignora exoneraciones, provisiona mal intereses de cesantías y no tiene configuración operativa visible ni pruebas directas de esos cálculos laborales.

## Evidencia ejecutada de esta auditoría

| ID | Comando / prueba | Resultado |
|---|---|---|
| EV-01 | Probe Dart temporal de precisión IEEE-754 | `0.1 + 0.2 = 0.30000000000000004`; `10000 x 99.99 = 999899.99999992212`; IVA de tres líneas de 100,01: 57,00 redondeando por línea frente a 57,01 redondeando al final. El probe fue eliminado después de ejecutarse. |
| EV-02 | `flutter test test/accounting_rules_test.dart test/accounting_report_test.dart test/architectural_consolidation_test.dart test/core/invoicing/cufe_test.dart test/core/invoicing/crear_factura_integration_test.dart test/core/invoicing/dian_transmission_client_noop_test.dart test/enterprise_services_test.dart test/purchase_repository_test.dart test/sales_repository_test.dart` | **27 pruebas pasaron** (`All tests passed!`). |
| EV-03 | `flutter test test/sales_flow_test.dart --reporter expanded` | **2 pruebas pasaron**: sin regla activa la venta conserva total 5.000 y ReteICA cero; con regla activa de la empresa al 1,1 %, ignora reglas inactivas/de otra empresa y registra ReteICA 110 sobre base 10.000. |
| EV-04 | `flutter test test/commercial_security_test.dart` | **5 pasaron, 1 falló**. La sexta reutiliza la misma base `:memory:` y falla al crear de nuevo `app_config`; no certifica el escenario fail-closed que declara. |
| EV-05 | Probe Flutter/SQLite temporal sobre esquema de instalación nueva | **2 pruebas pasaron**. Confirmó que `nomina_liquidaciones` contiene `neto_pagar` y no `neto`, que `obtenerReporteFiscal()` lanza `DatabaseException`, y que SQL directo persiste un asiento con `debito=100.0, credito=0.0`. El probe fue eliminado. |
| EV-06 | `flutter test test/reporte_fiscal_nomina_integration_test.dart --reporter expanded` | **1 prueba pasó**: `liquidarNomina()` creó una liquidación real con `neto_pagar=920000`; `obtenerReporteFiscal()` devolvió exactamente `nomina=920000` y `obtenerNomina()` leyó periodo/devengado/deducciones/neto desde las columnas reales sin excepción. |

## 1. Matemática financiera y precisión numérica

| Requisito / criterio | Norma o referencia | Archivo(s) que lo implementan | Test que lo cubre | Evidencia | Estado |
|---|---|---|---|---|---|
| Representar dinero sin error binario acumulativo y con una escala explícita. | Criterio de integridad financiera; el anexo técnico de facturación exige reglas explícitas de precisión y redondeo [N6]. | `sales/domain/sales_document.dart`; `purchases/domain/purchase_document.dart`; `accounting/domain/journal_entry.dart`; `inventory/domain/stock_ledger.dart`; `db_helper.dart` (`REAL` en importes). | Ninguna prueba fija una política monetaria global. | Inspección: uso transversal de `double`/`REAL`, sin `Decimal`, fixed-point ni enteros en centavos. EV-01 cuantifica el error. | **Parcial:** los cálculos funcionan para casos simples, pero no existe representación exacta ni normalización al persistir. |
| Aplicar una única política de redondeo a subtotal, IVA, retenciones, costos y total del documento. | Anexo técnico DIAN: reglas de redondeo y campos de ajuste [N6]. | `create_sale_use_case.dart`; `create_purchase_use_case.dart`; `sales_document.dart`; `purchase_document.dart`; `cufe.dart`. | `cufe_test.dart` solo verifica `toStringAsFixed(2)` dentro del identificador local. | EV-01 muestra diferencia de COP 0,01 según el punto de redondeo. No se encontraron `round`, `floor` o normalización monetaria en los cálculos transaccionales. | **Pendiente:** no hay regla común por línea/documento ni persistencia normalizada. |
| Evitar tolerancias que acepten asientos materialmente distintos por acumulación. | Partida doble e integridad contable; la materialidad no sustituye igualdad aritmética en el registro. | `JournalEntry.balanced`, `TrialBalance.balanced`, `DatabaseHelper.registrarAsientoContable()` usan tolerancia de COP 0,01. | `architectural_consolidation_test.dart`; `accounting_report_test.dart`. | EV-02 pasa casos exactos; no prueba acumulaciones masivas ni límites de la tolerancia. | **Parcial:** hay control de tolerancia en servicios, pero depende de `double` y no existe control SQL. |

**Resumen D1:** 0 Completos / 2 Parciales / 1 Pendiente.

## 2. Impuestos y normativa DIAN

| Requisito / criterio | Norma o referencia | Archivo(s) que lo implementan | Test que lo cubre | Evidencia | Estado |
|---|---|---|---|---|---|
| Manejar IVA 0 %, 5 % y 19 % según clasificación real del bien/servicio. | ET arts. 468 y 468-1; reglas de bienes excluidos/exentos y descontables [N1][N2]. | `catalog/domain/master_catalog.dart:57-62`; `db_helper.dart:3908-3943`; campos `productos.impuesto_pct` y líneas de venta/compra. | No hay prueba de clasificación tributaria por producto. | Inspección: existen 0/5/19, pero `EXEMPT` mezcla exento, excluido y no gravado; también aparece `IVA_8` sin semántica separada de INC. La tarifa es selección/manual, no deriva de clasificación fiscal. | **Parcial:** catálogo básico presente, clasificación normativa ausente. |
| Separar IVA generado en ventas e IVA descontable procedente en compras y producir F300 por tarifa/periodicidad. | ET arts. 485 y 488; formulario y periodicidad dependen de la responsabilidad tributaria [N1][N2]. | `AccountingEngine.sale/purchase`; `DatabaseHelper.obtenerReporteFiscal()`; `obtenerBorradorFormulario300()`. | `commercial_security_test.dart` solo prueba aislamiento con un esquema artificial; no prueba F300 ni procedencia del descuento. | `obtenerReporteFiscal()` suma todo IVA de compras como descontable. F300 calcula `baseGravada = ventas / 1.19`, por lo que falla con tarifas mixtas, ventas excluidas o valores sin IVA incluido. EV-05 confirma que el reporte falla en una instalación nueva por `neto` vs. `neto_pagar`. | **Parcial:** separación contable nominal, borrador fiscal no confiable. |
| Aplicar ReteFuente por concepto, calidad del beneficiario, base mínima y UVT vigentes. | DUR 1625/2016 arts. 1.2.4.9.1, 1.2.4.4.14 y reglas de honorarios/servicios; UVT 2026 COP 52.374 [N3][N4][N5]. | `db_helper.dart:2078-2098`, `2330-2343`, `3946-3974`; `create_sale_use_case.dart:120-165`; `compras_page.dart`; `ventas_page.dart`. | Ninguna prueba normativa por concepto/base. | Código usa `1090 * 47062` como umbral y comenta “UVT 2024”; la UVT vigente es 52.374. Las reglas semilla tienen `base_minima=0`; compras reciben retenciones manuales. F350 reparte el total 40 % servicios, 30 % honorarios y 20 % arrendamientos sin datos fuente. | **Parcial:** tarifas nominales 2,5/3,5/4/6/10/11 existen, pero bases, vigencia, concepto y reporte están desalineados. |
| Calcular ReteICA desde reglas por empresa/municipio, no desde una tarifa global. | Ley 14/1983: tarifa determinada territorialmente por concejos dentro del marco legal [N7]. | `reglas_retenciones_empresa`; `create_sale_use_case.dart`; `obtenerBorradorICA()`. | `sales_flow_test.dart`: `venta POS descuenta inventario, registra caja y asiento contable`; `venta POS aplica ReteICA solo desde regla activa de ventas`. | EV-03 confirma filtrado por `company_id`, `activo=1` y `aplica_ventas=1`, conversión de la tasa porcentual y ReteICA cero cuando no existe regla aplicable. | **Completo:** el flujo POS queda gobernado por la regla empresarial y ambos caminos están probados. |
| Transmitir factura UBL 2.1 a DIAN/PTA con autenticación, validación previa y respuesta persistida. | Resolución DIAN 000165/2023, anexo 1.9, modificada por resoluciones posteriores listadas por DIAN [N6]. | `dian_transmission_client.dart`; `dian_transmission_client_noop.dart`; `dian_transmission_client_registry.dart`; `facturacion_electronica_page.dart`. | `dian_transmission_client_noop_test.dart`. | EV-02 confirma únicamente estados de configuración del NoOp. El registro global instancia `NoOpDianTransmissionClient`; `transmitInvoice()` devuelve `simulated` y no hace red. | **Pendiente:** no existe cliente DIAN/PTA real. |
| Generar CUFE/CUDE conforme al algoritmo y campos del anexo técnico vigente. | Resolución 000165/2023 v1.9 y procedimiento CUFE; DIAN confirma SHA-384 [N6][N8]. | `core/invoicing/cufe.dart`; `core/invoicing/xml/generator.dart`. | `cufe_test.dart`; `crear_factura_integration_test.dart`. | EV-02 pasa consistencia interna, no conformidad DIAN. `computeCufe()` aplica Base64 a `Venta|Total|Fecha|PIN` y añade `fe2026dian`; no usa SHA-384 ni la cadena normativa. No se encontró generador CUDE. XML es “UBL-like” mínimo y omite bloques fiscales obligatorios. | **Pendiente:** identificador y documento no son certificables ante DIAN. |
| Manejar Impuesto Nacional al Consumo sin confundirlo con IVA. | ET arts. 512-1, 512-2 y 512-9: restaurantes 8 %, telefonía/datos 4 %, con reglas de base y responsables [N9][N10]. | `tax_parameters.inc_restaurant_rate/inc_telecom_rate`; `MasterCatalog.IVA_8`. | Sin pruebas. | Las tasas existen solo como parámetros; no se consumen en ventas, contabilidad, XML ni formulario 310. `IVA_8` se trata como impuesto genérico, no como INC. | **Parcial:** metadatos presentes, flujo tributario ausente. |

**Resumen D2:** 1 Completo / 4 Parciales / 2 Pendientes.

### Actualización del Bloque 1 (2026-08-09)

La fila de ReteFuente permanece **Parcial** porque la captura de retenciones
de compras sigue permitiendo ingreso manual y la certificación final depende de
la responsabilidad tributaria y del concepto real del contribuyente. Se cerró
la brecha concreta identificada en la auditoría: la UVT 2026 quedó centralizada
en `RetentionPolicy` (COP 52.374), con bases de 2 UVT para servicios, 10 UVT
para otros ingresos y sin base mínima para honorarios; la semilla
`RTFTE_COMPRAS_25` conserva 10 UVT en centavos. Cada venta/compra nueva guarda
concepto, base y tarifa aplicada, y F350 agrega los importes por esos datos en
vez de repartir 40/30/20.

Evidencia ejecutada: `flutter test test/commercial_tax_block1_test.dart
test/sales_flow_test.dart --reporter expanded` — **6 pruebas pasaron**. La
prueba `commercial_tax_block1_test.dart` verifica UVT/base exactas, la semilla,
la aplicación POS de 2 UVT/4 % y el desglose F350 de tres transacciones.

### Actualización del Bloque 2 (2026-08-09)

La política de inventario comercial queda en **promedio ponderado** como costo
contable operativo: compras actualiza `productos.costo` y POS toma ese costo
persistido, no el costo enviado por el carrito. La opción LIFO fue retirada de
`InventoryCostMethod`; FEFO permanece únicamente como orden físico de lotes
para productos con vencimiento. `kardex_inventario` ahora recibe, en la misma
transacción, los movimientos de compra, venta, anulación, ajuste, traslado y
operaciones por bodega junto con `movimientos_inventario`.

Evidencia ejecutada: `flutter test test/commercial_tax_block1_test.dart
test/commercial_inventory_block2_test.dart test/sales_flow_test.dart
test/architectural_consolidation_test.dart test/inventory_legacy_money_test.dart
--reporter expanded` — **16 pruebas pasaron**. El test de Bloque 2 verifica
compra → venta → ajuste, saldo de `productos` = suma firmada de Kardex y que
el costo de venta no proviene del carrito.

Pendiente ajeno a este bloque: el camino completo de `CreatePurchaseUseCase`
con crédito tropieza en una instalación fresca porque `cuentas_por_pagar` no
tiene todavía `proveedor_id`/`compra_id`; no se alteró esa tabla al no ser un
problema de costeo/Kardex.

### Actualización del Bloque 3 (2026-08-09)

F300 ahora obtiene la base y el IVA desde las líneas de ventas/compras y
separa las tarifas 0 %, 5 % y 19 %. Las líneas nuevas persisten `impuesto_pct`
e `impuesto_total`; los documentos históricos sin detalle usan únicamente sus
propios campos de encabezado como fallback. Ya no se divide el total de ventas
entre 1,19 ni se toma todo el IVA de compras sin procedencia.

Evidencia ejecutada: `flutter test test/commercial_tax_block1_test.dart
test/commercial_inventory_block2_test.dart test/commercial_f300_block3_test.dart
test/sales_flow_test.dart test/architectural_consolidation_test.dart
--reporter expanded` — **14 pruebas pasaron**. `commercial_f300_block3_test.dart`
verifica bases 0/5/19 exactas, IVA generado 67.000, IVA descontable 19.000 y
saldo 48.000.

## 3. Lógica contable comercial

| Requisito / criterio | Norma o referencia | Archivo(s) que lo implementan | Test que lo cubre | Evidencia | Estado |
|---|---|---|---|---|---|
| Seleccionar y aplicar coherentemente Grupo 1 (NIIF plenas), Grupo 2 (NIIF para PYMES) o Grupo 3. | Decreto 2420/2015 y anexos 1, 2 y 3 [N11][N12][N13]. | `companies.niif_group`; `financial_framework.dart`; `financial_framework_schema_migration.dart`; `DatabaseHelper.configurarGrupoNiif()` y `obtenerPoliticaMarcoContable()`. | `commercial_niif_block6_test.dart`. | EV-09 verifica migración v91, fallback defensivo a Grupo 2 para instalaciones antiguas y políticas visibles distintas para Grupo 1 y Grupo 3. La selección es declarada por empresa; faltan clasificación automática por umbrales/relaciones y revelaciones completas. | **Parcial:** configuración y política por marco disponibles; cumplimiento automático y reportes completos pendientes. |
| Garantizar partida doble en todos los caminos de escritura. | Principio de doble partida e integridad del libro. | `JournalEntry.post()`; `DatabaseHelper.registrarAsientoContable()`; `_registrarAsientoConCodigos()`. | `architectural_consolidation_test.dart`; `accounting_report_test.dart`. | EV-02 pasa controles de servicio. EV-05 demuestra que SQL directo persiste débito 100/crédito 0; no hay trigger/constraint SQL que valide el conjunto del asiento. | **Parcial:** control de aplicación, sin garantía de base de datos. |
| Cerrar periodos por empresa e impedir contabilización posterior. | Control contable de corte y trazabilidad; marco NIIF aplicable [N11][N12]. | `_crearTablasPeriodos()`; `cerrarPeriodoContable()`; `_validarPeriodoAbierto()`; `periodos_contables_page.dart`; `AccountingPeriodSchemaMigration`. | `commercial_accounting_close_block4_test.dart`. | EV-07 confirma que dos empresas pueden abrir el mismo periodo y que la consulta de la empresa activa queda aislada. El test aún no cubre todos los caminos UI de escritura posterior al cierre. | **Parcial:** esquema tenant-correcto y aislamiento probados; falta cobertura completa de bloqueo mensual en todos los consumidores. |
| Cerrar el ejercicio y trasladar ingresos/gastos a resultado y ganancias acumuladas. | Presentación de resultados y patrimonio bajo el marco seleccionado [N11][N12]. | `DatabaseHelper.cerrarEjercicioContable()`; `AccountingPeriodSchemaMigration`; cuentas `3605`, `3610`, `3705`. | `commercial_accounting_close_block4_test.dart`. | EV-07 crea ingreso de 100.000 y gasto de 30.000 centavos, ejecuta el cierre en una transacción, verifica utilidad de 70.000, dos asientos registrados y `3705` con crédito exacto de 70.000; los tests contables también pasan con el trigger v76 activo. | **Completo.** |
| Presentar saldos de naturaleza acreedora con signo correcto y cuadrar Activo = Pasivo + Patrimonio + resultado. | Decreto 2420, estado de situación financiera y estado de resultados [N11][N12]. | `accounting_report_repository.dart`; `db_helper.dart:8071-8097`; `obtenerEstadosFinancieros():7198-7244`; `estados_financieros_page.dart`. | `accounting_report_test.dart` prueba saldo por naturaleza y balance simple; no prueba estados completos. | La consulta invierte correctamente crédito-débito para naturaleza acreedora y `cuadre` incorpora utilidad. No se reprodujo el bug de signo de NICSP 1, pero falta prueba integrada con clases 1-6 y cierre. | **Parcial:** lógica inspeccionada coherente, cobertura insuficiente. |

**Resumen D3:** 1 Completo / 4 Parciales / 0 Pendientes.

### Actualización del Bloque 6 (2026-08-09)

La migración v91 agrega `companies.niif_group` con fallback defensivo
`grupo_2` para filas existentes y permite seleccionar explícitamente `grupo_1`,
`grupo_2` o `grupo_3` por empresa. `FinancialFrameworkPolicy` expone el marco,
el perfil de revelación y la política de deterioro de inventarios asociada.
`commercial_niif_block6_test.dart` verifica que las políticas de Grupo 1 y
Grupo 3 difieren materialmente. Esto no certifica una clasificación legal
automática ni todas las revelaciones: ambos quedan como trabajo posterior.
Evidencia: `flutter test test/commercial_niif_block6_test.dart ...` — 21
pruebas pasaron; EV-09 en `docs/evidencias/auditoria_comercial_bloque_6/`.

### Actualización del Bloque 4 (2026-08-09)

La migración v89 agrega `company_id` a `periodos_contables` y reemplaza la
unicidad global por `UNIQUE(company_id, anio, mes)`. Las filas legacy se
conservan y, cuando no tenían empresa, se atribuyen a la empresa activa. El
cierre anual comercial registra dos asientos balanceados en una sola
transacción: ingresos/gastos contra `3605`/`3610`, y traslado a `3705`
(resultados acumulados). También se corrigió el consecutivo del primer
comprobante de un tipo nuevo para que dos comprobantes del mismo tipo no
reutilicen `DOC-000001`.

Evidencia ejecutada: `flutter test
test/commercial_accounting_close_block4_test.dart test/accounting_report_test.dart
test/accounting_rules_test.dart test/commercial_security_test.dart
--reporter compact` — **13 pruebas pasaron**. El test del bloque verifica
aislamiento por empresa, migración legacy, utilidad exacta de 70.000 centavos,
dos asientos de cierre y saldo final de `3705` por 70.000 centavos.

## 4. Inventario y costeo

| Requisito / criterio | Norma o referencia | Archivo(s) que lo implementan | Test que lo cubre | Evidencia | Estado |
|---|---|---|---|---|---|
| Usar una fórmula permitida y consistente: FIFO/PEPS o promedio ponderado; no LIFO/UEPS. | NIIF para PYMES 13.18 y NIC 2.25; LIFO no permitido [N12][N14]. | `create_purchase_use_case.dart:172-205` usa promedio ponderado; `create_sale_use_case.dart:300-367` usa costo recibido y FEFO físico; `stock_ledger.dart` expone `fifo`, `lifo`, `average`. | `enterprise_services_test.dart` prueba promedio; `architectural_consolidation_test.dart` prueba FIFO aislado. | EV-02 pasa ambos cálculos aislados. El ledger avanzado no tiene consumidor productivo; LIFO existe como opción de dominio aunque hoy solo FIFO aparece en test. No hay política única por empresa/producto. | **Parcial:** caminos válidos existen, pero están duplicados/desconectados y LIFO debe eliminarse o bloquearse. |
| Mantener Kardex completo para compra, venta, anulación, ajuste y traslado. | Sistema permanente y trazabilidad de inventarios [N12][N13]. | `movimientos_inventario` en venta, compra, anulaciones y traslado; tabla `kardex_inventario`; `StockLedgerService`. | `sales_flow_test.dart` pretende cubrir venta; pruebas puras de ledger/promedio. | EV-03 falla antes de completar sus aserciones por la ReteICA. `kardex_inventario` solo aparece en esquema/backup, sin escritor activo. Los lotes `inventory_lots`, `lotes` y el stock de `productos` forman tres representaciones no reconciliadas. | **Parcial:** hay movimientos operativos, no un Kardex único certificado. |
| Valorar inventario del balance con la misma fórmula de costo y reconocer deterioro/valor neto realizable. | NIIF PYMES 13.18-13.19; NIC 2 [N12][N14]. | `InventoryControlService.analyze()` y `FinancialConsolidationService` calculan `stock * costo`; compra actualiza `productos.costo` por promedio. | `enterprise_services_test.dart` solo prueba un promedio exacto. | Coherente únicamente para el camino principal de promedio ponderado. No concilia lotes FIFO/FEFO, no hay prueba balance-vs-Kardex y no se encontró deterioro a valor neto realizable. | **Parcial.** |

**Resumen D4:** 0 Completos / 3 Parciales / 0 Pendientes.

## 5. Multiempresa y multisucursal

| Requisito / criterio | Norma o referencia | Archivo(s) que lo implementan | Test que lo cubre | Evidencia | Estado |
|---|---|---|---|---|---|
| Aislar operaciones y reportes por empresa/sucursal. | Integridad de tenant y estados separados; Decreto 2420 según marco de cada entidad [N11]. | `CompanyContextService`; repositorios de venta/compra; `BranchContextService`; múltiples filtros `company_id`. | `sales_repository_test.dart`, `purchase_repository_test.dart`, `accounting_report_test.dart`; partes 1-5 de `commercial_security_test.dart`. | EV-02 pasa repositorios por empresa. EV-04 deja un escenario fail-closed sin certificar. Hay brechas: `periodos_contables` global y métodos legacy sin filtro consistente. | **Parcial.** |
| Consolidar empresas con alcance contable, eliminaciones y periodo coherente. | Estados consolidados bajo el marco NIIF aplicable [N11][N12]. | `core/multi_company/financial_consolidation.dart`. | Sin pruebas ni consumidor UI. | Suma ventas, gastos, inventario, CxC y CxP por IDs; no consolida asientos, no elimina operaciones intercompañía, no aplica moneda ni políticas homogéneas. `rg` no encontró consumidores fuera del propio archivo. | **Parcial:** servicio huérfano y agregación gerencial, no consolidación NIIF. Conectarlo bien es esfuerzo **grande**: modelo de grupo/participación, eliminaciones, periodos, moneda, pruebas y UI. |
| Ejecutar transferencias interempresa de forma autorizada, atómica y contablemente simétrica. | Segregación, integridad de inventario/caja y trazabilidad. | `core/multi_company/transfer_service.dart`. | Sin pruebas ni consumidor UI. | No exige estado aprobado antes de completar, no usa transacción, puede dejar stock negativo y `products` llama la transferencia completa dentro de cada iteración. No genera asientos contables. | **Pendiente para uso real:** código huérfano con riesgos. Cablear solo UI sería pequeño, pero hacerlo operable es esfuerzo **medio/grande** por transacción, RBAC, mapeo de productos y contabilidad bilateral. |

**Resumen D5:** 0 Completos / 2 Parciales / 1 Pendiente.

## 6. Nómina comercial privada

| Requisito / criterio | Norma o referencia | Archivo(s) que lo implementan | Test que lo cubre | Evidencia | Estado |
|---|---|---|---|---|---|
| Configurar parámetros anuales y determinar IBC salarial correctamente. | Salud sobre IBC: Ley 1122/2007 art. 10; pensión 16 %; auxilio de transporte no integra IBC [N15][N16][N17]. | `payroll_parameters`; `payroll_novelties`; `DatabaseHelper.liquidarNomina()`. | `commercial_payroll_block5_test.dart`. | EV-08 suma novedades `horas_extra` y `bonificacion_salarial` al IBC, excluye el auxilio de transporte y verifica salud/pensión sobre la base variable. Sigue pendiente clasificar todas las novedades salariales/no salariales y una UI de parámetros. | **Parcial:** el camino variable probado está conectado, pero la configuración integral aún no está certificada. |
| Calcular salud 4 % trabajador/8,5 % empleador y pensión 4 %/12 %, respetando exoneraciones. | Ley 1122/2007; Ley 100/1993; ET art. 114-1 [N15][N16][N18]. | Defaults de `payroll_parameters`; `liquidarNomina()`. | `commercial_payroll_block5_test.dart`. | EV-08 verifica IBC variable, el caso exonerado deja salud empleador en 0, SENA/ICBF en 0 y conserva caja 4 %, y el caso no exonerado conserva las tarifas. | **Parcial:** falta probar todas las condiciones documentales del contribuyente previstas por el ET. |
| Calcular ARL según clase y sobre IBC correcto. | Decreto 1072/2015: tasas iniciales I-V 0,522 %, 1,044 %, 2,436 %, 4,350 %, 6,960 % [N19]. | Defaults `arl_level_1_rate` a `arl_level_5_rate`; switch en `liquidarNomina():6252-6270`. | Sin pruebas comerciales. | Las tasas default coinciden, pero se aplican solo al salario básico, no al IBC completo; no hay validación de actividad económica/clase asignada. | **Parcial.** |
| Calcular cesantías, prima, intereses y vacaciones sobre bases y tiempo causado correctos. | CST arts. 186, 249 y 306; intereses 12 % anual sobre cesantías [N20][N21]. | `liquidarNomina():6277-6281`; parámetros 8,33 %, 8,33 %, 1 % y 4,17 %. | Sin pruebas. | Cesantías y prima usan solo salario y omiten auxilio de transporte/variables cuando corresponda; no consideran días. `interesesCesantias = cesantias * 0.01` aplica 1 % a la provisión de cesantías, no 12 % anual sobre el saldo, quedando aproximadamente 12 veces por debajo de la provisión mensual usual. | **Parcial:** error material identificado. |
| Calcular parafiscales 2 % SENA, 3 % ICBF y 4 % caja con exoneración aplicable. | Reglas 2/3/4 y ET art. 114-1 [N18][N22]. | Defaults y `liquidarNomina():6272-6275`. | Sin pruebas. | Tasas default correctas, pero se aplican siempre. No se usa `health_exonerated`, no hay bandera de contribuyente ni regla de menos de 10 SMMLV; tampoco base salarial configurable. | **Parcial.** |
| Obtener neto correcto, aplicar retención laboral y ejecutar liquidación de forma atómica. | Reglas laborales/tributarias y trazabilidad transaccional. | `liquidarNomina()`; `PayrollWithholding`; migración v90. | `commercial_payroll_block5_test.dart`; `reporte_fiscal_nomina_integration_test.dart`. | EV-08 verifica la tabla progresiva del artículo 383 con UVT exacta, cargas/provisiones patronales en el asiento y rollback de movimiento/liquidación cuando el asiento falla por periodo cerrado. | **Parcial:** falta parametrizar deducciones laborales adicionales y certificar todos los escenarios de retención. |
| Integrar nómina con reportes fiscales sin romper el esquema real. | Integridad de declaraciones e información contable. | `obtenerReporteFiscal()`; `obtenerNomina()`; esquema `nomina_liquidaciones.neto_pagar`. | `reporte_fiscal_nomina_integration_test.dart`: `obtenerReporteFiscal suma neto_pagar de una liquidacion real`. | EV-06 crea la liquidación mediante `liquidarNomina()`, verifica `neto_pagar=920000`, confirma el mismo total en el reporte fiscal y lee el historial con los nombres reales del esquema. | **Completo:** consulta e historial alineados con el esquema real y flujo integrado probado. |

**Resumen D6:** 1 Completo / 6 Parciales / 0 Pendientes.

### Actualización del Bloque 5 (2026-08-09)

`liquidarNomina()` v90 ahora suma novedades salariales de
`payroll_novelties` al IBC, respeta la exclusión del auxilio de transporte,
lee `health_exonerated`, calcula la retención laboral con la tabla progresiva
del artículo 383 usando la UVT configurada, registra cargas/provisiones del
empleador y persiste los IDs de caja/asiento. El flujo completo está dentro
de una transacción.

Evidencia: `flutter test test/commercial_payroll_block5_test.dart
test/reporte_fiscal_nomina_integration_test.dart
test/hrm/hrm_payroll_integration_test.dart --reporter compact` — **11 pruebas
pasaron**. La deducción de retención y la base disponible para el sistema
están probadas; deducciones laborales adicionales no capturadas siguen siendo
una brecha explícita.

## Resumen por dominio

| Dominio | Completos | Parciales | Pendientes | Diagnóstico |
|---|---:|---:|---:|---|
| 1. Precisión numérica | 0 | 2 | 1 | Sin tipo monetario ni política de redondeo. |
| 2. Impuestos y DIAN | 1 | 4 | 2 | ReteICA POS corregida; F300/F350 y DIAN siguen sin ser certificables. |
| 3. Contabilidad | 0 | 3 | 2 | Servicios validan, pero DB/cierre/marco NIIF incompletos. |
| 4. Inventario | 0 | 3 | 0 | Tres representaciones y métodos desconectados; no hay Kardex único. |
| 5. Multiempresa | 0 | 2 | 1 | Aislamiento parcial; consolidación y transferencias huérfanas. |
| 6. Nómina privada | 1 | 5 | 1 | Reporte fiscal alineado; bases, provisiones y transacción siguen incorrectas o sin prueba. |
| **Total** | **3** | **21** | **4** | **La configuración NIIF por empresa tiene evidencia de política visible; clasificación automática, revelaciones completas y demás brechas de dominio permanecen abiertas.** |

## Brechas críticas priorizadas

1. **Detener cálculos tributarios automáticos incorrectos restantes:** umbral ReteFuente y borradores F300/F350. Son cifras fiscales visibles al cliente.
2. **Definir y migrar una política monetaria exacta:** fixed-point/enteros por unidad mínima o biblioteca decimal, escalas por moneda y redondeo DIAN centralizado.
3. **Reemplazar CUFE/XML local y NoOp por un flujo DIAN/PTA certificable:** anexo técnico 1.9 vigente, SHA-384, UBL completo, firma, CUDE, transmisión y respuestas.
4. **Corregir y probar nómina privada:** IBC de novedades, exoneración, prestaciones, retención laboral, asientos patronales y transacción atómica.
5. **Blindar partida doble en persistencia:** impedir por diseño que SQL directo deje asientos incompletos/desbalanceados; definir estrategia compatible con inserción transaccional por cabecera/líneas.
6. **Unificar inventario/Kardex y costeo:** retirar LIFO, elegir política por naturaleza de inventario, conectar POS al ledger y reconciliar lotes/stock/costo/contabilidad.
7. **Mantener y ampliar el cierre contable por empresa y ejercicio:** el núcleo v89 ya está implementado y probado; falta cubrir todos los consumidores de bloqueo mensual y el cierre desde UI.
8. **Decidir multiempresa:** mantener consolidación/transferencias como backlog o convertirlas en flujos contables seguros antes de exponer UI.

## Fuentes normativas y técnicas

- **[N1]** [Ley 1819 de 2016, modificación del ET art. 468: IVA general 19 %](https://normograma.dian.gov.co/dian/compilacion/docs/ley_1819_2016.htm).
- **[N2]** [Estatuto Tributario compilado, arts. 485 y 488 sobre impuestos descontables](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=6533).
- **[N3]** [DIAN, Concepto 6251 de 2024: retención por otros ingresos, art. 1.2.4.9.1 DUR 1625](https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_6251_2024.htm).
- **[N4]** [DIAN, Concepto 6491 de 2025: servicios 4 %/6 % y base en UVT](https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_6491_2025.htm).
- **[N5]** [DIAN, Resolución 000238 de 2025: UVT 2026 = COP 52.374](https://normograma.dian.gov.co/dian/compilacion/docs/resolucion_dian_0238_2025.htm).
- **[N6]** [DIAN, Resolución 000165 de 2023 y Anexo Técnico FEV 1.9](https://normograma.dian.gov.co/dian/compilacion/docs/resolucion_dian_0165_2023.htm); [micrositio técnico vigente](https://micrositios.dian.gov.co/sistema-de-facturacion-electronica/documentacion-tecnica/).
- **[N7]** [Ley 14 de 1983, ICA y tarifas territoriales](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=267).
- **[N8]** [DIAN, Oficio 901212 de 2022: CUFE mediante SHA-384](https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_901212_2022.htm).
- **[N9]** [DIAN, ET art. 512-9: INC restaurantes 8 %](https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_902460_2022.htm).
- **[N10]** [DIAN, ET arts. 512-1/512-2: INC telefonía, datos e internet móvil 4 %](https://normograma.dian.gov.co/dian/compilacion/docs/oficio_dian_8274_2019.htm).
- **[N11]** [Decreto 2420 de 2015, marcos técnicos de los grupos contables](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=76745).
- **[N12]** [Decreto 2420 de 2015, Anexo 2: NIIF para PYMES](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=74535).
- **[N13]** [Decreto 2420 de 2015, Anexo 3: marco para microempresas](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=76055).
- **[N14]** [Decreto 2420 de 2015, Anexo 1: NIC 2, FIFO/promedio ponderado](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=76054).
- **[N15]** [Ley 1122 de 2007 art. 10: salud 12,5 %, distribución 8,5 %/4 %](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=22600).
- **[N16]** [Función Pública, Concepto 164481 de 2024: salud 12,5 % y pensión 16 %](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=259976).
- **[N17]** [Consejo de Estado, Sentencia 90064 de 2016: auxilio de transporte fuera de bases de aportes](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=71191).
- **[N18]** [Estatuto Tributario art. 114-1: exoneración de salud, SENA e ICBF](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=6533).
- **[N19]** [Decreto 1072 de 2015: tasas iniciales ARL por clase](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=72173).
- **[N20]** [Código Sustantivo del Trabajo: vacaciones, cesantías y prima de servicios](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=199983).
- **[N21]** [Decreto 116 de 1976: intereses de cesantías del 12 % anual](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=3285).
- **[N22]** [Ley 1233 de 2008: distribución parafiscal 3 % ICBF, 2 % SENA y 4 % caja](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=31586).
- **[N23]** [DIAN, Compilación Jurídica del Decreto 2250 de 2017: tabla del artículo 383 para pagos laborales](https://normograma.dian.gov.co/dian/compilacion/docs/decreto_2250_2017.htm).

## Regla de mantenimiento

Al corregir una brecha, agregar el test específico y su comando a “Evidencia ejecutada”, actualizar únicamente las filas que ese test cubra y subir a **Completo** solo cuando la prueba reproduzca el requisito normativo/funcional completo. Una prueba de estructura, aislamiento o ausencia de excepción no sustituye una prueba de exactitud de cifras.
