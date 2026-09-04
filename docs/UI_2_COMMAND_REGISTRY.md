# UI-2: Command Registry

## Estructura

`CommandDefinition` es el contrato extensible de la barra de comandos. Cada
comando tiene un `id`, etiqueta, descripcion, icono, color, modulo, accion
RBAC opcional, tipo de contexto, prioridad y un `handler`. El `handler`
recibe el `BuildContext` de la aplicacion y el `CommandContext` activo.

`CommandContext` identifica el modulo, tipo e id del registro seleccionado y
publica acciones concretas del registro. El registro solo muestra un comando
contextual cuando coinciden `recordType` y `recordId`, y cuando la accion
publicada por la pantalla existe.

## Extensibilidad y seguridad

Los modulos registran comandos con `CommandRegistry.instance.registerAll()`.
La autorizacion global delega en `AppSession.puedeEjecutarAccion`; los
comandos del sector publico pueden agregar validaciones especificas con
`Permiso`. Tanto el listado como `execute()` aplican la misma autorizacion,
por lo que ocultar una opcion no es la unica defensa.

La navegacion del workspace se registra con `registerModuleCommands()` y se
reemplaza al cambiar de conjunto de modulos para no dejar acciones de un modo
anterior visibles.

## Comandos cubiertos

- HRM: aprobar o rechazar la ausencia seleccionada.
- MRP: iniciar o completar la Work Order seleccionada y abrir su BOM.
- CRM: avanzar la oportunidad a la siguiente etapa permitida.
- Presupuesto publico: crear apropiacion, expedir CDP y expedir RP, con el
  permiso del modulo o el permiso fiscal especifico.
- Workspace: abrir los modulos visibles y autorizados del modo activo.

Las acciones de otros modulos siguen disponibles por su navegacion existente,
pero aun no publican comandos contextuales. Quedan pendientes, entre otros,
acciones directas para caja, compras, cartera, contratacion y auditoria.

## Verificacion

`test/core/commands/command_registry_test.dart` cubre el filtrado RBAC, el
bloqueo de ejecucion y la prioridad de un comando contextual sobre uno
generico.
