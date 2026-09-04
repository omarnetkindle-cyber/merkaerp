# Cierre general PARTE 2 - Bloque N - Catalogos CUPS/CIE-10

## Fuentes oficiales verificadas

- CUPS: pagina oficial de MinSalud "Actualizacion CUPS", enlace "Resolucion
  2706 de 2025 y sus anexos". El ZIP descargado desde `minsalud.gov.co`
  contiene `Anexos tecnicos Resolucion 2706 de 2025_23122025.xlsx`.
- CIE-10: Catalogo de Datos del Ministerio de Salud y Proteccion Social
  (`Catalogo-datos.zip`) referencia la tabla estandarizada CIE10 en
  `https://www.minsalud.gov.co/Documentos%20y%20Publicaciones/C%C3%B3digos%20MIPRES.zip`.
  Ese ZIP oficial contiene `Codigos MIPRES V1.41.xlsx`, hoja `2.CIE-10`.

## Hallazgo

El esquema local de salud ya tenia `catalogo_cups` y `catalogo_cie10`, pero
solo sembraba 2 codigos CUPS y 2 codigos CIE-10. Eso hacia que la validacion
local RIPS/FEV funcionara tecnicamente, pero no contra catalogos oficiales
completos.

## Decision conservadora

Se reemplazo el seed parcial por un seed generado desde fuentes oficiales y
comprimido en Dart para que MerkaERP siga funcionando 100% offline:

- CUPS: 13.629 codigos desde anexos 2-7 de Resolucion 2706 de 2025.
- CIE-10: 12.545 codigos habilitados desde Codigos MIPRES V1.41.

No se consulta red en runtime ni en tests. La validacion RIPS sigue rechazando
codigos ausentes del catalogo local. Para compatibilidad con capturas historicas
de RIPS que usen categorias CIE-10 de 3 caracteres, el servicio acepta el codigo
si existe al menos un subcodigo oficial habilitado con ese prefijo; los tests
normativos usan el codigo completo oficial (`J00X`).

## Archivos modificados

- `lib/sector_publico/salud/database/catalogos_salud_seed.dart`
- `lib/sector_publico/salud/database/schema_salud.dart`
- `lib/sector_publico/salud/services/rips_service.dart`
- `test/sector_publico/salud/rips_fev_glosas_integracion_test.dart`

## Evidencia cruda

### Generacion del seed oficial

```text
cups_rows 13629
cie10_rows 12545
out lib\sector_publico\salud\database\catalogos_salud_seed.dart
cups_b64_chars 202680
cie_b64_chars 176456
```

### flutter test test\sector_publico\salud\rips_fev_glosas_integracion_test.dart --reporter expanded

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/salud/rips_fev_glosas_integracion_test.dart
00:00 +0: genera RIPS-JSON 948 con CUPS y CIE-10 catalogados
00:00 +1: rechaza RIPS-JSON con CUPS no catalogado
00:01 +2: alerta glosa pendiente al vencer cinco dias habiles
00:02 +3: migracion conserva glosas legadas y agrega fecha limite y catalogos
00:03 +4: All tests passed!
```

### flutter analyze

```text
225 issues found. (ran in 55.1s)
EXIT_CODE=1
ERROR_COUNT=0
```

## Estado

Bloque N completo: los catalogos parciales fueron reemplazados por catalogos
offline generados desde fuentes publicas oficiales, y la validacion RIPS/FEV
queda probada contra esos catalogos.
