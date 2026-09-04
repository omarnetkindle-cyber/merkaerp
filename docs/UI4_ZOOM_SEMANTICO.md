# UI-4: Zoom semántico

## Diseño

`SemanticZoomRecordList<T>` recibe una colección ya cargada, una función
`statusOf` y un builder de la tarjeta individual. El slider usa cinco niveles:

| Nivel | Presentación |
| --- | --- |
| 1 | Un resumen por estado, solo con el conteo. |
| 2 | Grupos por estado con una explicación resumida y el conteo. |
| 3 | Grupos por estado con las tarjetas individuales. |
| 4 | Tarjetas individuales colapsadas con sus acciones. |
| 5 | Tarjetas individuales expandidas con sus campos secundarios y acciones. |

El cambio es puramente de presentación: el widget no conoce `Database`,
`DatabaseExecutor` ni servicios de dominio. Cambiar el slider solo cambia su
`State` y vuelve a agrupar la lista recibida.

## Superficies activadas

- **Cartera/cuentas por cobrar:** agrupa por estado de la cuenta (`pendiente`,
  `parcial`, `pagada`), manteniendo Cobrar, historial y Ver hilo de
  trazabilidad en los niveles individuales.
- **Órdenes MRP:** agrupa por estado real y por el estado derivado de stock
  insuficiente. La disponibilidad se consulta una sola vez en la carga de
  órdenes y queda en `_MrpOrderViewData`; el zoom no vuelve a ejecutar
  `hasSufficientStock()`.

Presupuesto público y aprobaciones HRM ya usan tarjetas UI-3, pero quedan como
superficies opcionales para una siguiente activación. El componente no requiere
cambios en el motor de datos para incorporarlas.
