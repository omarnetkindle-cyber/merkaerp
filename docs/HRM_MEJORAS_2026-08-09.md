# HRM - Ronda de robustez, funcionalidad y UI

Fecha: 2026-08-09
Base: `5f7cecc`.

## Parte A - Robustez

La base tenia tres pruebas: dos en `hrm_module_test.dart` y una de
compatibilidad con empleados/nomina. El camino feliz ejercitaba las siete
entidades, pero faltaban los casos borde solicitados.

Se agregaron pruebas para:

- saldo insuficiente;
- ausencia solapada con otra aprobada del mismo empleado;
- aprobacion sin entitlement;
- tipo `permiso_no_remunerado` con `requires_entitlement = 0`, aprobado sin
  descontar saldo;
- rechazo con responsable, fecha y motivo persistidos;
- terminacion bloqueada cuando existen ausencias pendientes;
- asistencia con `punch_out` nulo y estado `IN_PROGRESS`;
- bandeja de aprobaciones cerrada cuando la sesion no tiene `AppAction.approve`.

Los servicios ahora validan referencias, nombres, duraciones, periodos,
actores y transiciones con `ArgumentError` o `StateError` explicitos. La
aprobacion y el rechazo actualizan ausencia y solicitud dentro de una misma
transaccion. La migracion/version 80 agrega `reviewed_by`, `reviewed_at` y
`rejection_reason` sin perder filas existentes.

## Parte B - Funcionalidad

`HrmLeaveService.approve` consulta el tipo de ausencia antes de revisar saldo.
Los tipos con `requires_entitlement = 0` no requieren ni consumen entitlement;
el seed colombiano deja `permiso_no_remunerado` en esa modalidad. Para los
demás tipos se mantiene `days_used + length_days <= days_total`.

Antes de aprobar se comparan los intervalos de fecha contra ausencias
aprobadas del mismo empleado. Las ausencias cerradas registran aprobador o
rechazador y fecha de revisión. `HrmEmployeeService.terminate` bloquea la
terminación si hay ausencias pendientes y conserva el estado activo.

La consulta `approvedForPeriod` ya estaba conectada al calendario HRM y ahora
el calendario muestra a todo el equipo en una cuadrícula mensual con color por
tipo de ausencia. La consulta está lista para nómina/DIAN, pero no encontré
un consumidor directo desde esos módulos en esta ronda; la integración
automática con liquidación/transmisión sigue pendiente.

## Parte C - UI/UX

`HrmEmployeePage` ahora tiene tres secciones: Empleados, Calendario y
Aprobaciones. La bandeja muestra solicitudes pendientes y permite aprobar o
rechazar con motivo solo si `AppSession.puedeEjecutarAccion('hrm',
AppAction.approve)` es verdadero. Sin ese permiso queda bloqueada y no expone
acciones.

## Evidencia

Antes: 3 pruebas declaradas en la suite HRM.

Despues: 9 pruebas pasaron.

```text
flutter test test/hrm --reporter expanded
00:00 +0: ... hrm_leave_approval_page_test.dart: la bandeja de aprobaciones queda cerrada sin permiso
00:00 +1: ... hrm_module_test.dart: crea solicitud, ausencia, saldo y asistencia
00:04 +2: ... hrm_module_test.dart: bloquea aprobación cuando days_used + length_days excede days_total
00:05 +3: ... hrm_module_test.dart: aprueba un tipo que no requiere entitlement sin descontar saldo
00:05 +4: ... hrm_module_test.dart: bloquea ausencia solapada con otra ya aprobada
00:05 +5: ... hrm_module_test.dart: bloquea aprobacion sin entitlement configurado
00:05 +6: ... hrm_module_test.dart: rechazo deja responsable, fecha y motivo auditables
00:05 +7: ... hrm_module_test.dart: no permite terminar empleado con ausencias pendientes
00:06 +8: ... hrm_schema_compatibility_test.dart: la migracion HRM conserva empleados y filas consumibles por nomina
00:10 +9: All tests passed!

dart format --output=none --set-exit-if-changed lib/hrm test/hrm lib/db_helper.dart
Formatted 29 files (0 changed).

flutter analyze
flutter : 250 issues found. (ran in 10.4s)
0 errores.

flutter build windows
Built build\\windows\\x64\\runner\\Release\\MerkaERP.exe
```

## Cierre

Parte A cerrada con cobertura de saldo, solapamiento, entitlement ausente,
terminacion, turno abierto y errores auditables.
Parte B cerrada para las reglas HRM locales; queda pendiente la integracion
directa del resultado aprobado con liquidacion/transmision DIAN.
Parte C cerrada para calendario de equipo y bandeja protegida de aprobaciones.
