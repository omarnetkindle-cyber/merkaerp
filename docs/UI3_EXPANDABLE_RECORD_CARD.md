# UI-3: tarjetas expandibles para registros densos

## Diseño

`ExpandableRecordCard` es un widget compartido en
`lib/ui/widgets/expandable_record_card.dart`. Recibe `criticalFields`,
`secondaryFields` y `actions`. Los campos críticos permanecen visibles en
estado contraído; los secundarios aparecen en el mismo lugar al expandir la
tarjeta. La expansión usa `AnimatedSize` y no abre un modal ni cambia de
pantalla.

Cada campo se representa con `RecordCardField` (`label`, `value`, icono
opcional y énfasis). Cada acción se representa con `RecordCardAction`. Una
acción puede ser un callback local o un `commandId` asociado a un
`CommandRegistry` explícito. En el segundo caso, la visibilidad y ejecución
usan el mismo filtro RBAC de la paleta de comandos UI-2. Las tarjetas usan
`ThemeData` y `MerkaThemeTokens`; no introducen una paleta paralela.

## Superficies migradas

| Superficie | Campos críticos | Campos secundarios | Acciones conservadas | Estado |
|---|---|---|---|---|
| Presupuesto - apropiaciones | Vigencia, rubro, apropiado, saldo disponible | Nombre, pagado, CDP/RP acumulados, fuente, sector/programa, acto administrativo | Ninguna nueva; mantiene la interacción existente de la pestaña | Migrada |
| Presupuesto - CDP | Número CDP, rubro, valor, saldo | Vigencia, vencimiento, funcionarios, objeto, contrato, estado | Ninguna nueva; mantiene la interacción existente | Migrada |
| Presupuesto - RP | Número RP, rubro, valor, saldo | CDP, contrato, vigencia, vencimiento, funcionario, objeto, estado | Ninguna nueva; mantiene la interacción existente | Migrada |
| HRM - aprobaciones | Empleado, tipo de ausencia, periodo, días | ID de solicitud, estado de aprobación | Aprobar/rechazar, visibles solo cuando `canApprove` es verdadero; el contexto global HRM sigue disponible | Migrada |
| MRP - órdenes de producción | Orden, producto, cantidad, estado/bloqueo de stock | BOM, costos de material/operación/total, bodegas, fecha límite | Iniciar, completar y ver BOM; iniciar queda oculto si falta stock | Migrada |
| Cartera - cuentas por cobrar | Cliente, venta, saldo, estado | Total, fecha, vencimiento, descripción | Cobrar y ver historial | Migrada |

Las acciones de MRP continúan pasando por `MrpWorkOrderService.transition`,
y las acciones de HRM por `HrmLeaveService`; la tarjeta solo reorganiza la
presentación y no duplica reglas de negocio.

## Candidatos pendientes

- `lib/cuentas_por_pagar_page.dart`: lista densa con acciones por cuenta; es
  el siguiente candidato comercial natural.
- `lib/sector_publico/contratacion/pages/contratacion_publica_page.dart`:
  procesos, contratos y pólizas tienen varias columnas normativas y requieren
  definir qué campos deben prevalecer por etapa.
- `lib/sector_publico/activos/pages/activos_estado_page.dart`: inventario de
  activos y FUT; requiere conservar acciones/exportaciones específicas.
- `lib/erp_readiness_page.dart`: tablas de diagnóstico con muchas columnas;
  conviene migrarla junto con su navegación de detalle.
- En presupuesto, las listas de obligaciones y pagos siguen con su
  representación anterior; no se marcaron como migradas en esta fase.

## Evidencia

- `flutter analyze`: 241 issues, 0 errores; no quedaron hallazgos en el
  componente ni en las cuatro superficies migradas.
- Pruebas dirigidas: `flutter test test/ui/expandable_record_card_test.dart
  test/core/commands/command_registry_test.dart`: 5 pruebas, todas pasan.
- Suite completa: 266 pruebas pasan, 3 omitidas de la línea base, 0 fallas.
- `flutter build windows`: `Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe`.
