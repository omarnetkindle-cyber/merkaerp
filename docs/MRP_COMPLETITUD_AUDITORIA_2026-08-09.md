# Auditoria de completitud MRP

Fuente: `MerkaERP_Modulos_CRM_HRM_MRP_v1.md`, seccion Modulo 3, y el codigo
actual de `lib/mrp/`. La especificacion original usa nombres SQL singulares,
pero el proyecto ya tenia tablas plurales (`mrp_boms`, `mrp_work_orders`, etc.);
se conserva esa convencion y no se duplican tablas.

## Auditoria por entidad

| Entidad | Campo o requisito | Estado | Evidencia |
|---|---|---|---|
| MrpWorkstation | id, name, company_id | Implementado | modelo, `mrp_workstations` |
| MrpWorkstation | hour_rate | Implementado | `MoneyValue`, INTEGER y costeo por operacion |
| MrpWorkstation | production_capacity | Implementado parcialmente | existe como entero generico; no significa horas |
| MrpWorkstation | status | Implementado | produccion/detenido/mantenimiento en tabla y modelo |
| MrpWorkstation | warehouse asociado | Implementado | `warehouse_id` |
| MrpWorkstation | capacidad temporal | Implementado en esta ronda | `available_hours_per_day`, nullable y migracion v83 |
| MrpWorkstation | ficha/configuracion UI | Implementado en esta ronda | tercera pestaña Workstations en `mrp_page.dart` |
| MrpRouting | id, name | Implementado | `MrpRouting` y repositorio |
| MrpRouting | descripcion | Implementado | columna y modelo |
| MrpRouting | reutilizacion por BOM | Implementado | `routing_id` y `mrp_operations` |
| MrpOperation | routing_id, workstation_id | Implementado | FKs y validacion de servicio |
| MrpOperation | operation_name, sequence_order, time_minutes | Implementado | modelo, tabla y costeo |
| MrpBom | item, quantity, uom, active/default | Implementado | `MrpBom`, `mrp_boms` |
| MrpBom | routing, raw/operating/total cost | Implementado | costos en INTEGER y `recalculate()` |
| MrpBom | items hijos | Implementado | `MrpBomItem` y recalculo |
| MrpBomItem | item_code/item_id, qty, uom, rate, amount | Implementado | modelo, tabla y `MoneyValue` |
| MrpBomItem | source_warehouse, is_sub_assembly_item | Implementado | explosion multinivel y bodega origen |
| MrpWorkOrder | production_item, bom, qty planned/produced | Implementado | modelo, tabla y servicio |
| MrpWorkOrder | status y transiciones | Implementado | maquina de estados y bloqueos |
| MrpWorkOrder | bodegas WIP/FG y fechas | Implementado | columnas y transferencias reales |
| MrpWorkOrder | required_items / explosion | Implementado | explosion multinivel con deteccion de ciclos |
| MrpWorkOrder | cierre parcial | Implementado en esta ronda | `transition(... producedQty:)` y stock FG parcial |
| MrpWorkOrderItem | item, required/transferred/consumed qty | Implementado | modelo, tabla y rastreo de traslado |
| MrpWorkOrderItem | source warehouse | Implementado | columna y uso de `WarehouseStockService` |

## Cobertura funcional

El flujo activo selecciona una sola BOM activa por subensamble y una sola ruta
por BOM. La explosion es multinivel, la transferencia origen-WIP y WIP-FG usa
el servicio de stock existente, y una orden puede terminar con menos unidades
que las planeadas pasando la cantidad producida explicita. El simulador UI-6
ahora lee horas diarias configuradas, pero no convierte pipeline monetario a
unidades porque CRM aun no relaciona oportunidad con producto y cantidad.

Actualizacion 2026-08-14: el backlog posterior de MRP ya implemento
subcontratacion por operacion, rutas alternativas por producto y calendarios
de turnos por Workstation (`docs/CIERRE_GENERAL_PARTE2_BLOQUE_K_MRP_BACKLOG.md`).
Siguen fuera del alcance feriados, mantenimientos y programacion fina multi-dia
con job cards; requieren una ronda de planificacion de capacidad mas detallada.

## Cambios de esta ronda

- Migracion v83 defensiva: agrega `mrp_workstations.available_hours_per_day`
  sin modificar datos existentes; NULL conserva el estado no configurado.
- `MrpWorkstation`, servicio y repositorio persisten y validan horas positivas.
- UI MRP agrega configuracion de workstation con costo/hora y horas por dia.
- `MrpWorkOrderService` permite cierre parcial con `producedQty`, validando
  rango y moviendo solo la produccion real a la bodega de producto terminado.
- `WarehouseStockService.consume` y el cierre de Work Order descuentan la
  materia prima consumida de WIP y actualizan `consumed_qty`; el remanente de
  una orden parcial permanece trazable en WIP.
- UI-6 muestra horas diarias, estaciones configuradas y estado total/parcial.

## Evidencia

- `test/mrp/mrp_capacity_migration_test.dart`: migracion v83 preserva filas y
  deja NULL la capacidad nueva de datos legados.
- `test/mrp/mrp_module_test.dart`: capacidad temporal y cierre parcial.
- `test/impact/impact_simulator_service_test.dart`: snapshot de capacidad real,
  calculo exacto y libro de escenarios sin mutar tablas operativas.
