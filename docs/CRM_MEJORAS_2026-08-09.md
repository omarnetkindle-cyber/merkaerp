# CRM - Ronda de robustez, funcionalidad y UI

Fecha: 2026-08-09
Base: `ce32e75`.

## Parte A - Robustez

Antes de esta ronda, la suite CRM declaraba seis pruebas: cinco en
`test/crm/crm_module_test.dart` y una de compatibilidad de esquema. Cubrian
los caminos felices de las cuatro entidades, CustomerInteraction, la
conversion atomica nominal y el puente Closed Won -> venta, pero no cubrian
rollback ante un error posterior a la creacion de cuenta/contacto, montos
cero, jerarquia de cuentas, supervisor de otra cuenta, validaciones de
nombres ni leads marcados como no convertibles.

Se agregaron validaciones en servicios con mensajes explicitos:

- Cuenta: nombre requerido y cuenta padre existente en la empresa activa.
- Contacto: nombre/cuenta requeridos y `reports_to_id` debe apuntar a un
  contacto de la misma cuenta; `reports_to_id` nulo sigue siendo valido.
- Lead: nombre de cuenta y monto no negativo; estados
  `no_convertible`, `descartado` y `rechazado` bloquean la conversion.
- Oportunidad: cuenta/nombre requeridos y monto no negativo.
- Interaccion: cuenta, asunto y tipo requeridos; las oportunidades tambien
  verifican que la cuenta referenciada exista antes de persistir.

La conversion Lead -> Account + Contact + Opportunity conserva la transaccion
SQLite existente. La prueba de colision de ID de oportunidad fuerza un fallo
despues de insertar cuenta y contacto y confirma que ambos se revierten y el
lead permanece sin convertir.

## Parte B - Funcionalidad

`CrmSalesStage` ya tenia las siete variantes necesarias para representar las
seis etapas del flujo y la bifurcacion final Won/Lost. Se mantuvo la tabla de
probabilidades existente y se verifico explicitamente:

`prospecting=10`, `qualification=25`, `needsAnalysis=40`,
`valueProposition=55`, `negotiationReview=75`, `closedWon=100`,
`closedLost=0`.

Se permite cerrar como Lost desde una etapa abierta, pero una oportunidad
cerrada no puede reabrirse ni retroceder. La probabilidad se recalcula al
mover de etapa.

## Parte C - UI/UX

El Kanban ahora usa `Draggable<CrmOpportunity>` y `DragTarget` para mover
entre etapas a traves de `CrmOpportunityService.moveToStage`, conservando las
validaciones de negocio. Incluye filtro por `assigned_user_id`, monto
formateado con `MoneyValue`, barra de progreso y porcentaje de probabilidad.
Cada tarjeta abre la ficha de la cuenta.

Se agrego `CrmAccountsPage` al workspace y `CrmAccountPage` con historial real
de contactos, oportunidades e interacciones de `crm_contacts`,
`crm_opportunities` y `crm_interactions`. No se duplico la tabla `clientes`.

## Evidencia

Linea base inspeccionada: seis pruebas CRM existentes antes de los cambios.
Resultado posterior: 12 pruebas CRM pasaron.

```text
flutter test test/crm/crm_module_test.dart test/crm/crm_schema_compatibility_test.dart --reporter expanded
00:07 +11: All tests passed!

flutter test test/crm/crm_pipeline_page_test.dart --reporter expanded
00:01 +1: All tests passed!

dart format --output=none --set-exit-if-changed lib/crm test/crm lib/core/workspace/workspace_config.dart
Formatted 22 files (0 changed).

flutter analyze
flutter : 261 issues found. (ran in 12.1s)
Sin errores.

flutter build windows
Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe
```

Los issues de analyze son warnings/info preexistentes; la ronda no agrego
avisos nuevos despues de corregir las cinco advertencias introducidas por la
primera version de la UI.

## Cierre

Parte A cerrada con cobertura de validaciones, errores y atomicidad.
Parte B cerrada para etapas y probabilidades; queda como pendiente de
producto el CRUD avanzado de cuentas y mantenimiento masivo del pipeline.
Parte C cerrada para Kanban operativo y ficha de cuenta con historial.
