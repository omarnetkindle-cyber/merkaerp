# UI-6: Simulador de impacto

## Alcance y decisiones

El simulador cruza datos operativos reales de CRM, MRP y HRM, pero guarda los
escenarios en una tabla separada (`impact_scenarios`). Guardar una simulacion no
actualiza oportunidades, empleados ni workstations.

### Capacidad productiva

La tabla `mrp_workstations` tiene `hour_rate`, que representa costo por hora,
y `production_capacity`, que sigue siendo una capacidad generica sin semantica
temporal. Desde el esquema v83 cada workstation puede declarar
`available_hours_per_day`; NULL significa que esa estacion aun no esta
configurada. El simulador suma las horas de las workstations en produccion y
las muestra como capacidad diaria real.

Ademas, `crm_opportunity_items` relaciona cada oportunidad con producto,
cantidad, unidad y precio unitario. El simulador pondera las cantidades por la
probabilidad de la etapa. Si existe una BOM activa y operaciones con tiempos,
convierte las unidades ponderadas a horas MRP; sin BOM/ruta informa las unidades
y deja una advertencia, sin inventar capacidad.

### Headcount

`headcount` es el conteo de filas de `empleados` activas (`activo = 1`) para la
empresa activa. El salario base agregado de esas filas se incluye como contexto
de costo laboral. No se filtra por cargo porque no existe hoy una relacion
verificada entre oportunidades y los cargos que las producirian.

## Formula reproducible

Con `uplift_percent` entre 0 y 100, usando siempre unidades menores enteras:

```text
valor_ganado_proyectado = valor_ganado_actual * (100 + uplift_percent) / 100
demanda_ponderada_producto = suma(cantidad_linea * probabilidad / 100)
demanda_escenario_producto = demanda_ponderada_producto * (100 + uplift_percent) / 100
horas_MRP = suma(demanda_escenario_producto * horas_BOM_por_unidad)
```

Los ingresos siguen calculandose con `MoneyValue.multiplyRatio`; las cantidades
son unidades de inventario y no se convierten en dinero. La formula completa
queda guardada en el libro de escenarios.

## Libro de escenarios

`impact_scenarios` almacena empresa, nombre, fecha, input, snapshot de CRM/MRP/
HRM, resultado, formula y SHA-256 de la representacion estructurada. Es una
tabla append-only desde el servicio de simulacion: no se usa como fuente para
liquidar, vender, producir o modificar datos operativos.

La UI `ImpactSimulatorPage` expone el control de incremento, el snapshot,
resultado con estado ambar cuando la capacidad esta incompleta o no puede
compararse con unidades. La entrada de workspace usa `FeatureKey.impactSimulator` y el permiso
existente de Reportes; la consulta y el guardado siguen el alcance RBAC del
workspace.

## Evidencia

El test `test/impact/impact_simulator_service_test.dart` verifica:

- calculo exacto de 100000 a 120000 y demanda incremental de 20000;
- conteo de empleados activos y costo base en unidades menores;
- demanda ponderada exacta por producto y estado sin BOM;
- estado de capacidad no configurada;
- ausencia de mutaciones en CRM, HRM y MRP al guardar;
- persistencia de formula, snapshot y hash del escenario.

## Pendientes

La factibilidad horaria requiere que cada producto relevante tenga BOM y ruta
con tiempos. Campanas, territorios, forecasting historico y conversion de
embudo requieren entidades y periodos que no forman parte del modelo actual.
