# Cierre general PARTE 1 - Bloque D

## Hallazgo

El inventario comercial tenia tres representaciones activas:

- `productos.stock`: saldo agregado que consume la UI y los flujos de venta.
- `kardex_inventario`: ledger historico de movimientos.
- `lotes` e `inventory_lots`: proyecciones de lote/vencimiento con esquemas
  historicos distintos.

Tambien se encontro un bug real en traslado de bodega: cuando el destino no
tenia fila en `stock_bodega`, `procesarTrasladoBodega()` insertaba solo
`company_id`, `producto_id`, `bodega_id` y `cantidad`, pero omitía
`actualizado_en`, columna `NOT NULL`.

## Decisión

No se borran `lotes` ni `inventory_lots` porque todavia hay pantallas y alertas
que las leen. Quedan formalmente como proyecciones de compatibilidad. La fuente
auditable de verdad es `kardex_inventario`; `productos.stock` es la proyeccion
operativa para consultas rapidas; ambas se escriben dentro de la misma
transaccion.

`InventoryMovementService.record()` queda como punto unico para:

- insertar `movimientos_inventario`;
- insertar `kardex_inventario`;
- sincronizar `lotes` legacy;
- sincronizar `inventory_lots` avanzado, soportando tanto el esquema nuevo
  `quantity/received_at` como el historico `current_quantity/expiration_date`.

Se elimino del flujo de venta el descuento manual de `lotes`; ahora venta solo
actualiza `productos.stock` y delega lotes/Kardex al servicio comun.

## Cambios

- `lib/inventory/application/inventory_movement_service.dart`
  - sincroniza entradas/salidas con `lotes` e `inventory_lots`;
  - mantiene compatibilidad con ambos esquemas de `inventory_lots`;
  - evita doble consumo de lotes.
- `lib/inventory/application/inventory_reconciliation_service.dart`
  - compara `productos.stock`, Kardex, `lotes` e `inventory_lots`.
- `lib/sales/application/create_sale_use_case.dart`
  - elimina el descuento FEFO manual distribuido.
- `lib/db_helper.dart`
  - corrige `procesarTrasladoBodega()` para escribir `actualizado_en` y `costo`
    al crear stock de destino.
- `lib/inventory/application/advanced_inventory_service.dart`
  - documenta que es fachada de compatibilidad, no fuente primaria.

## Evidencia cruda

### Analisis dirigido

Comando:

```powershell
dart analyze lib\inventory\application\inventory_movement_service.dart lib\inventory\application\inventory_reconciliation_service.dart lib\sales\application\create_sale_use_case.dart test\commercial_inventory_block2_test.dart
```

Salida:

```text
Analyzing inventory_movement_service.dart, inventory_reconciliation_service.dart, create_sale_use_case.dart, commercial_inventory_block2_test.dart...
No issues found!
```

Tras corregir `db_helper.dart`:

```text
Analyzing inventory_movement_service.dart, inventory_reconciliation_service.dart, create_sale_use_case.dart, db_helper.dart, commercial_inventory_block2_test.dart...

   info - lib\db_helper.dart:875:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\db_helper.dart:891:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print

2 issues found.
```

Los dos issues son preexistentes en `db_helper.dart`.

### Test de inventario

Comando:

```powershell
flutter test test\commercial_inventory_block2_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/commercial_inventory_block2_test.dart
00:00 +0: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:03 +0: el dominio de costeo no expone LIFO
00:03 +1: compra, venta y ajuste dejan productos y Kardex reconciliados
00:03 +2: compra, venta, ajuste y traslado reconcilian stock, Kardex y lotes
00:03 +3: (tearDownAll)
00:03 +3: All tests passed!
```

### flutter analyze completo

Comando:

```powershell
flutter analyze > bloque_d_analyze.txt 2>&1
```

Resultado:

```text
239 issues found. (ran in 7.2s)
```

`Select-String` sobre `bloque_d_analyze.txt` encontro `0` lineas `error -`.
No hubo issues en `inventory_movement_service.dart`,
`inventory_reconciliation_service.dart`, `create_sale_use_case.dart` ni en el
test de inventario.
