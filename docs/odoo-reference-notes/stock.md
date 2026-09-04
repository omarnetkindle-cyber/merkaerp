# Módulo: stock
## Origen en Odoo
- Módulo Odoo de referencia: `stock` (Inventory)
- Versión revisada: Odoo 19.0 (referencia funcional, no copia de código)
## Propósito funcional
Gestionar existencias, movimientos, ubicaciones, lotes/seriales, pickings (recepciones/entregas), ajustes físicos, reglas de reabastecimiento y control por almacen/centro de costo. Proveer trazabilidad por lote/serial y estados de flujo para integrarse con `purchase` y `sale`.
## Modelos de datos (nombres propios de MerkaERP, no los de Odoo)
| Entidad | Campos clave | Relaciones |
| - | - | - |
| `StockMove` | `id`, `product_id`, `quantity`, `source_location_id`, `destination_location_id`, `move_type`, `origin`, `state`, `created_at` | pertenece a `Product`, referencia `Location` origen/destino |
| `Location` | `id`, `name`, `location_type`, `warehouse_id`, `active` | puede pertenecer a `Warehouse` |
| `StockPicking` | `id`, `company_id`, `warehouse_id`, `picking_type`, `state`, `origin`, `scheduled_date` | tiene muchas `StockMove` |
| `StockQuant` | `id`, `product_id`, `location_id`, `quantity`, `lot_id`, `cost` | representación ledger por ubicación y lote |
| `StockLot` | `id`, `company_id`, `product_id`, `batch_number`, `serial_number`, `received_at`, `expires_at` | asociado a `StockQuant` y `StockMove` |
| `Warehouse` | `id`, `company_id`, `name`, `address`, `default_location_id` | contenedor de `Location` |
| `ReorderRule` | `id`, `product_id`, `warehouse_id`, `min_qty`, `max_qty`, `multiple` | reglas para generar `purchase`/procurement |
## Flujo de estados
- `StockMove`: `draft` → `waiting` → `confirmed` → `done` / `cancelled`.
- `StockPicking`: `draft` → `assigned` → `partially_done` → `done` / `cancelled`.
- `StockQuant`: siempre refleja estado materializado (solo `quantity` y `location`).
- Transiciones disparan eventos: reservar, transferir, validar recepción, crear asiento de costo (opcional).
## Reglas de negocio críticas
- Las transferencias deben validar disponibilidad (reservas) antes de confirmar.
- Movimientos `incoming` generados desde `purchase` deben agrupar en `StockPicking` por orden y warehouse.
- Los cambios de `StockMove` a `done` actualizan `StockQuant` y `InventoryLots` (trazabilidad).
- Integración con `purchase` y `sale`: confirmar órdenes genera pickings; recepción en picking confirma movimientos y actualiza costos.
- Reglas de reabastecimiento: activar `ReorderRule` genera `purchase` o `procurement` según configuración.
## Adaptaciones para sector público colombiano
- Normativa aplicable:
  - Procedimientos de control de inventarios para entidades públicas (auditoría fiscal)
  - RIPS y trazabilidad para bienes sanitarios (salud)
  - Ley 1712 y requisitos de transparencia para registros y trazabilidad
- Diferencias respecto al comportamiento estándar de Odoo:
  - Registro obligatorio de lotes y seriales para insumos críticos (medicamentos) con fechas de caducidad.
  - Reportes exportables en formatos requeridos por auditoría fiscal y control interno.
  - Niveles de permiso y segregación de funciones más estrictos sobre movimientos entre bodegas y reposiciones.
  - Integración con evidencias de recepción (actas, soportes contractuales) y vinculación a procesos de contratación (Ley 80/1150).
## Diagnóstico del código existente
- ¿Ya existía algo equivalente en MerkaERP? (sí)
  - `backend/src/modules/stock/models/Stock.js` con `StockMove` y `Location` implementados (CRUD básico, `validateMove`, `getProductQuantity`).
- Decisión: extender lo existente (no crear módulo paralelo). Añadir `StockPicking`, `StockQuant`, `StockLot`, `Warehouse`, `ReorderRule` y endpoints asociados.
## Estado de implementación
- [x] Diagnóstico completo
- [ ] Especificación completa
- [ ] Modelos de datos actualizados o creados
- [ ] Lógica de negocio implementada (extendida o nueva)
- [ ] Compatibilidad comercial/privada verificada (no se rompió nada existente)
- [ ] Pruebas
- [ ] Documentado

---
Generado en PASO A por el asistente. Siguiente: PASO B — implementar migraciones, modelos, rutas y pruebas básicas manteniendo retrocompatibilidad.
