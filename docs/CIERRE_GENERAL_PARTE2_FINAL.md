# Cierre general - Parte 2 de 2

Fecha de cierre: 2026-08-14

## Bloques cerrados

| Bloque | Alcance | Commit main |
| --- | --- | --- |
| G | Exportacion ICA PDF/XML local desde datos reales | `aed5c0a` |
| H | Trazabilidad PDT/MGA -> apropiacion/CDP/RP | `9df1678` |
| I | Actas de responsabilidad de activos/cuentadantes | `86100e4` |
| J | CRM: campanas, territorios, forecast y embudo | `d2ad7a7` |
| K | MRP: subcontratacion, rutas alternativas y turnos | `a35fc1e` |
| L | Backend JWT RS256 documentado desde rama backend | `5a6d8f0` |
| M | Sync: allowlist explicita de tablas permitidas | `a99c101` |
| N | Catalogos oficiales CUPS/CIE-10 offline | `a430c0d` |
| O | CHIP 004/005/2016C01 desde datos reales SQLite | `5a44ac7` |

## Ajuste final de suite

La primera corrida completa despues del bloque O termino con 10 fallas:

```text
05:32 +340 ~3 -10: Some tests failed.
```

Causa raiz:

- `activos_estado_page_test.dart` seguia esperando el banner obsoleto de "Pendiente: asignacion de Actas de Responsabilidad", aunque el bloque I ya cerro esa funcionalidad.
- Los tests de presupuesto/contratacion/vigencias que ejercen `PresupuestoService.expedirRP` no inicializaban `SchemaPlaneacion`; despues del bloque H, el servicio consulta `cdp_meta_trazabilidad` al encadenar CDP/RP.

Correccion aplicada:

- El test de Activos ahora verifica el banner operativo de actas activas.
- Los fixtures de contratacion, pago presupuestal, presupuesto publico page y vigencias futuras inicializan `SchemaPlaneacion.crearTablas(db)`.

Prueba dirigida:

```text
flutter test test\sector_publico\activos\activos_estado_page_test.dart test\sector_publico\contratacion\contratacion_flujo_rp_integracion_test.dart test\sector_publico\presupuesto\presupuesto_pago_integracion_test.dart test\sector_publico\presupuesto\presupuesto_publico_page_test.dart test\sector_publico\presupuesto\vigencias_futuras_integracion_test.dart --reporter expanded

00:22 +13: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_publico_page_test.dart: Presupuesto Público Page Tests Crear obligación válida con acta de recibo y verificar en base de datos
00:24 +14: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/presupuesto_publico_page_test.dart: (tearDownAll)
00:24 +14: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/vigencias_futuras_integracion_test.dart
00:25 +14: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/vigencias_futuras_integracion_test.dart: municipio autorizado recorre compromiso obligacion y pago por anualidad
00:26 +15: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/vigencias_futuras_integracion_test.dart: ESE configurada autoriza y compromete; ESE incompleta se deniega fail-closed
00:26 +16: C:/Users/PC/Desktop/Caja_simple/test/sector_publico/presupuesto/vigencias_futuras_integracion_test.dart: bloquea falta/exceso de autorizacion, RBAC y pago de recibido irregular
00:26 +17: All tests passed!
```

## Verificacion final

Suite completa:

```text
flutter test --reporter compact

04:58 +349 ~3: C:/Users/PC/Desktop/Caja_simple/test/widget_test.dart: workspace renderiza en dark high contrast sin overflow
04:59 +349 ~3: C:/Users/PC/Desktop/Caja_simple/test/widget_test.dart: workspace renderiza en dark high contrast sin overflow
04:59 +350 ~3: C:/Users/PC/Desktop/Caja_simple/test/widget_test.dart: workspace renderiza en dark high contrast sin overflow
04:59 +350 ~3: C:/Users/PC/Desktop/Caja_simple/test/widget_test.dart: (tearDownAll)
04:59 +350 ~3: 3 skipped tests.

04:59 +350 ~3: All other tests passed!
```

Analyze:

```text
flutter analyze

225 issues found. (ran in 8.1s)
EXIT_CODE=1
ERROR_COUNT=0
```

Build Windows:

```text
flutter build windows

Building Windows application...
Nuget.exe not found, trying to download or use cached version.
Building Windows application...                                    96.8s
√ Built build\windows\x64\runner\Release\MerkaERP.exe
EXIT_CODE=0
```

## Pendientes reales que quedan fuera de esta parte

- Transmision real DIAN: el algoritmo CUFE/UBL local quedo implementado, pero el envio sigue dependiendo de certificado/credenciales reales.
- Backend anidado: los cambios RS256 y allowlist quedaron en ramas remotas (`codex/backend-rs256-jwt` y `codex/backend-sync-allowed-tables`) porque `backend/origin/main` esta divergente; requiere merge humano en el repositorio backend.
- Credenciales/tokens externos: rotacion de cualquier token expuesto y configuracion por ambiente deben hacerlas Omar/operacion, no el cliente Flutter.
- Certificacion remota de reportes oficiales: ICA/CHIP/SIIF/FUT generan estructuras locales verificadas; cualquier recepcion oficial ante plataforma externa queda fuera sin credenciales y ambiente habilitado.
