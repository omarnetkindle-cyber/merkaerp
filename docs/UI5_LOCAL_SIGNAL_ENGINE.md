# UI-5: motor local de señales

## Modelo

`Signal` vive en `lib/core/signals/signal.dart` y normaliza una alerta local
con `id`, `source`, `priority`, título, detalle, entidad relacionada,
módulo de navegación, acción sugerida, comando contextual y permiso RBAC.
La acción no se considera disponible solo porque exista en el modelo: la UI
la pasa por `CommandRegistry`, que aplica el mismo filtro de autorización de
UI-2. Si no está autorizada, queda disponible únicamente la navegación al
módulo relacionado.

`SignalAggregator` vive en `lib/core/signals/signal_aggregator.dart`. Recibe
fuentes registrables, las consulta en orden, combina sus resultados y ordena
por prioridad. Un fallo de una fuente no descarta las señales de las demás.
Los adaptadores solo llaman las consultas y validaciones existentes; no
reimplementan reglas de inventario, permisos, ausencias o ejecución
presupuestaria.

## Fuentes conectadas

| Fuente existente | Consulta reutilizada | Normalización |
|---|---|---|
| `MerkaIntelligenceService` | `operationalAlerts()` | Lotes por vencer, stock crítico y cartera pendiente; navegan a inventario o cartera. |
| HRM | `HrmLeaveService.pendingForApproval()` | Ausencias pendientes; ofrece `hrm.leave.approve` solo si el CommandRegistry autoriza `AppAction.approve`. |
| MRP | `MrpWorkOrderService.list()` + `hasSufficientStock()` | Órdenes en borrador/no iniciadas bloqueadas por inventario insuficiente; navegan a producción. |
| Planeación/presupuesto | `TrazabilidadPlanPresupuestoService.consultarSeguimiento()` | Publica solo metas con `alertaDesviacion`, es decir, diferencia financiera/física mayor a 20%; navega a planeación. |

La fuente presupuestaria consulta los proyectos MGA de la entidad activa y
reutiliza el resultado ya calculado por el servicio de trazabilidad. No
calcula una segunda desviación en el agregador.

## Interfaz

El centro de notificaciones existente en `workspace_widgets.dart` ahora abre
inmediatamente y muestra el fallback histórico mientras las fuentes locales
terminan. Cuando llegan señales, las reemplaza por `ExpandableRecordCard` de
UI-3. Cada tarjeta muestra prioridad, origen y título de forma compacta; al
expandir muestra detalle, entidad y permiso requerido. Puede ejecutar el
comando contextual autorizado o abrir el módulo relacionado. El tema y los
tokens visuales son los mismos de UI-1/UI-3.

## Evidencia

- Tests de fuentes, agregación, desviación >20% y RBAC: 7 pasan en
  `test/core/signals/signal_aggregator_test.dart`.
- Workspace existente y tarjeta compartida: pasan en la prueba dirigida del
  workspace junto con las pruebas de UI-3.
- `flutter analyze`: 241 issues, 0 errores.
- Suite completa y `flutter build windows`: se registran en el cierre del
  commit de esta fase.

Este agregador es la base local para UI-6 (simulador de impacto) y para la
futura Cápsula de Evidencia. No usa IA externa ni llamadas de red en runtime.
