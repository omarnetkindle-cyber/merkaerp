# MRP - mejora de robustez, funcionalidad y UI

Fecha: 2026-08-09

## Parte A - Robustez

La cobertura MRP paso de 2 a 7 pruebas dirigidas. Se cubren BOM circular directa/indirecta, explosion multinivel, stock insuficiente sin transferencias parciales, reversa de material WIP al cancelar y cambio de BOM con una orden activa.

La orden ahora explota la BOM antes de persistirse. Los ciclos y los subensambles sin BOM activa fallan con un `StateError` claro. `enProceso` hace un preflight de todo el stock antes de delegar movimientos a `WarehouseStockService`. Cancelar una orden en proceso revierte el material transferido a su bodega de origen; si existe material consumido, falla cerrado y solicita ajuste manual.

Las transiciones terminales siguen bloqueadas. Una BOM se puede recalcular libremente solo cuando no tiene ordenes activas en `borrador`, `no_iniciada` o `en_proceso`. El costo de la orden queda congelado al crearla para conservar trazabilidad historica; el recalculo de la BOM incorpora materiales y operaciones de todos los niveles.

Se agregaron validaciones de entrada con mensajes claros en estaciones, rutas, operaciones, BOM, componentes y ordenes.

## Parte B - Funcionalidad

La explosion multinivel recorre todos los niveles con un conjunto de visitados. El costo de cada sub-BOM se escala por su cantidad de produccion y suma tanto material como operacion. Las transiciones invalidas siguen rechazadas por la maquina de estados existente.

## Parte C - UI/UX

`lib/mrp/pages/mrp_page.dart` ahora permite abrir la estructura de una BOM, ver componentes y subensambles, agregar componentes y ver el costo total, materiales y operacion despues de cada recalculo. El tablero conserva la agrupacion por los cinco estados y marca con candado las ordenes en borrador/no iniciadas sin stock suficiente.

## Evidencia cruda

Comando: `flutter test test/mrp`

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/mrp/mrp_module_test.dart
00:00 +0: (setUpAll)
00:04 +0: MRP crea entidades, calcula costos, explota BOM y mueve stock
00:05 +1: MRP rechaza transiciones de orden no permitidas
00:05 +2: MRP bloquea BOM circular directa e indirecta sin guardar la orden
00:05 +3: MRP calcula y explota BOM multinivel en todos sus niveles
00:05 +4: MRP bloquea iniciar una orden si falta stock sin transferencias parciales
00:05 +5: MRP revierte material WIP al cancelar una orden en proceso
00:05 +6: MRP no permite cambiar una BOM usada por una orden activa
00:05 +7: (tearDownAll)
00:05 +7: All tests passed!
```

Comando: `flutter analyze`

```text
244 issues found. (ran in 8.9s)
```

El análisis dejó 0 errores de compilacion en el codigo MRP; los 244 hallazgos son avisos/info existentes del repositorio.

Comando: `flutter build windows`

```text
Building Windows application...
Building Windows application...                                    92.4s
Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe
Nuget.exe not found, trying to download or use cached version.
```

## Cierre de la mejora MRP

Estado: **Completo en las tres partes solicitadas**. No se modifico el esquema y se mantuvo la delegacion de movimientos a `WarehouseStockService`. El submodulo `backend` conserva sus cambios locales preexistentes y no fue tocado.
