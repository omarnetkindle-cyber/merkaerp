# Diagnóstico módulo: stock

## ¿Qué existe hoy en el código (archivos, entidades, servicios)?
- Archivo detectado: `backend/src/modules/stock/models/Stock.js`.
  - Contiene dos clases exportadas: `StockMove` y `Location`.
  - `StockMove`: operaciones básicas CRUD en `stock_moves` (create, findById, update, listByState), cálculo de cantidad disponible por producto/ubicación (`getProductQuantity`), y `validateMove` que marca un movimiento como `done`.
  - `Location`: CRUD mínimo para `stock_locations` (create, list, findById).
- No se detectaron controladores/routers HTTP explícitos ni servicios adicionales asociados a `stock` en `backend/src/modules/stock/`.
- No se detectaron migraciones SQL específicas de `stock` en `backend/src/database/migrations/` (revisar manualmente si existen migraciones globales que ya incluyan tablas `stock_moves` y `stock_locations`).

## Para qué caso de uso comercial/privado fue construido (según el código encontrado)
- Manejo básico de movimientos de inventario entre ubicaciones internas y cálculo de cantidades por producto en cada ubicación.
- Soporta estados simples (`draft`, `done`) y tipos de movimiento (`move_type`) y origen (`origin`).

## Qué le falta comparado con el módulo equivalente de Odoo (alto nivel)
- Modelo y flujo de `stock.quant` o ledger de cantidades por lotes/ubicaciones, incluyendo trazabilidad por lot/serial.
- Gestión de reglas de reabastecimiento (`reordering rules`) y rutas de abastecimiento (pull/push rules).
- Recepciones/entregas integradas con `purchase` y `sale` (picking, packing, transferencias agrupadas en `stock_picking`).
- Gestión de inventarios físicos (ajustes), conciliación y ajustes por auditoría.
- Manejo de lotes/seriales, caducidades y control de calidad (quality checks).
- Integración con ubicaciones tipo `supplier`, `customer`, `transit`, y multi-warehouse (warehouses, routes, procurement).
- Interfaz de auditoría y eventos (log de cambios por usuario/registro) y hooks para notificaciones.

## Qué le falta para sector público colombiano (necesidades específicas)
- Control de activos críticos y trazabilidad por lote para bienes sanitarios (medicamentos, insumos médicos) — RIPS y trazabilidad en salud.
- Inventarios por centro de costo/entidad/UD (dependencias internas de una alcaldía/hospital) y permisos por rol/oficina.
- Reglas de control y segregación de funciones (SOX/ISO 27001 relevantes para contratación y almacenamiento de suministros sensibles).
- Reportes obligatorios y exportadores de inventario para auditoría y control fiscal (formatos que cumplan requerimientos de entidades de control).
- Integración con procesos de contratación pública (recepción en SECOP o evidencia documental para contratos).

## Recomendación inicial (decisión sobre extender / crear)
- ¿Ya existía algo equivalente en MerkaERP? Sí — existe implementación básica en `backend/src/modules/stock/models/Stock.js`.
- Decisión: extender lo existente. Mantener compatibilidad con clientes comerciales y añadir extensiones configurables para sector público.

## Siguientes pasos inmediatos (PASO A/B planning)
- PASO A (Especificación): documentar la ficha funcional del módulo `stock` siguiendo el formato requerido (`/docs/odoo-reference-notes/stock.md`).
- PASO B (Implementación):
  - Añadir migraciones para tablas faltantes si no existen (`stock_moves`, `stock_locations`, `stock_pickings`, `stock_quants`, `stock_lots`).
  - Implementar modelos adicionales: `StockPicking`, `StockQuant`, `StockLot/Serial`, `Warehouse`, `ReorderingRule`.
  - Rutas/Controladores HTTP para pickings, ajustes de inventario, consultas por ubicación y movimiento.
  - Tests unitarios básicos y de integración con `purchase` y `sale` para confirming/receiving flows.

## Estado actual (inicial)
- [x] Diagnóstico completo
- [ ] Especificación (PASO A)
- [ ] Implementación (PASO B)
- [ ] Compatibilidad verificada
- [ ] Pruebas
- [ ] Documentado


---
Generado automáticamente durante PASO0 — seguir con PASO A: crear `/docs/odoo-reference-notes/stock.md` con la ficha funcional.