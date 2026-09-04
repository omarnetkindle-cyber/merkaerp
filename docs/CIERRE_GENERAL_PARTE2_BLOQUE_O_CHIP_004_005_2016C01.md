# Cierre general PARTE 2 - Bloque O - CHIP 004/005/2016C01

## Fuentes investigadas

- La categoria CHIP/CGN publica vigente identifica formatos contables como
  `CGN2015_001_SALDOS_Y_MOVIMIENTOS`, `CGN2015_002_OPERACIONES_RECIPROCAS` y
  `CGN2016_01_VARIACIONES_TRIMESTRALES_SIGNIFICATIVAS`.
- El modelo local historico de MerkaERP ya tenia formularios llamados
  `CGN2015_004` (ejecucion presupuestal), `CGN2015_005` (deuda publica) y
  `CGN2016C01` (consolidado/variaciones). La implementacion conserva esos
  nombres locales para no romper UI ni reportes persistidos, pero documenta que
  no son una transmision certificada al portal CHIP.

## Decision conservadora

Se implemento generacion local desde datos persistidos, sin entradas manuales:

- `CGN2015_004`: se alimenta de `apropiaciones`, `rps`, `obligaciones` y
  `pagos`.
- `CGN2015_005`: se alimenta de `saldos_cuentas` con prefijos CGC locales de
  deuda publica (`2313`, `2314`) y servicio de deuda (`5320`, `5802`).
- `CGN2016C01`: genera variaciones significativas comparando `saldos_cuentas`
  de la vigencia actual contra la anterior.

No se invento una tabla nueva de deuda publica ni se simula transmision remota.
Si la entidad necesita un archivo CHIP certificado por taxonomia CGN exacta, aun
debe validarse contra el portal/herramientas oficiales de la CGN.

## Archivos modificados

- `lib/sector_publico/auditoria/services/chip_reporter_service.dart`
- `test/sector_publico/auditoria/chip_datos_sistema_integracion_test.dart`

## Evidencia cruda

### flutter test test\sector_publico\auditoria\chip_datos_sistema_integracion_test.dart --reporter expanded

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/auditoria/chip_datos_sistema_integracion_test.dart
00:00 +0: (setUpAll)
00:00 +0: CGN 2015_001 a 003 reflejan fuentes persistidas del sistema
00:00 +1: (tearDownAll)
00:00 +1: All tests passed!
```

### flutter analyze

```text
225 issues found. (ran in 10.8s)
EXIT_CODE=1
ERROR_COUNT=0
```

## Estado

Bloque O completo para generacion local verificable desde datos reales:
`generarReportesDesdeDatosSistema` ahora produce 001, 002, 003, 004, 005 y
2016C01. Queda fuera de alcance la certificacion/transmision contra el portal
CHIP remoto.
