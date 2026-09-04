# Fase 3B: inventario publico de dinero

Fecha: 2026-08-08  
Base: manifiesto v75 del commit `004db33`; Fase 3A comercial cerrada en `999dcbb`.

## Estado y alcance

Este documento congela el inventario de trabajo de la Fase 3B. En esta etapa
solo se inspeccionaron el manifiesto, el codigo publico y las referencias a
columnas monetarias. No se modificaron archivos de `lib/` ni de `test/`.

La reconciliacion del manifiesto completo dio:

```text
Tablas totales:                 125
Columnas monetarias totales:    355
Tablas comerciales:              74
Columnas comerciales:           197
Tablas sector publico:           51
Columnas sector publico:        158
Consumidores publicos directos:  90 archivos Dart candidatos
```

El conteo de 90 es una superficie de consumidores, no un conteo de tablas ni
de columnas. Incluye modelos que serializan/deserializan importes, servicios
que calculan o persisten importes y paginas que convierten importes para UI.
No incluye archivos que solo declaran el esquema, RBAC, auditoria generica o
la matriz de visibilidad. Cada archivo se volvera a validar al convertirlo;
si una referencia resulta ser un DTO secundario o un falso positivo, se
marcara en el log y se reconciliara el total antes del cierre.

## Convencion de conversion publica

El sector publico opera exclusivamente en COP con escala fija de 2 decimales,
segun el diseno aprobado en `MIGRACION_DINERO_CENTAVOS_DISENO.md`. La
conversion no usara `MoneyCurrencyResolver`, la moneda de empresa comercial ni
un default configurable. Se usara una instancia/helper explicito de moneda
publica `COP`, escala 2, y todos los valores persistidos seran unidades
menores enteras.

La frontera sera:

- SQLite: `INTEGER` en la misma columna SQL, conservando su nombre.
- Dominio y calculos: `MoneyValue` con moneda COP resuelta explicitamente.
- UI, Excel, CHIP, FUT, SIA Observa, SIIF y RIPS-JSON: conversion a pesos o
  al formato externo solamente en el borde de salida/captura.
- No se aceptaran `/ 100.0`, `* 100.0` ni casts a `double` como puente en la
  logica monetaria.

## Manifiesto publico: 51 tablas y 158 columnas

| Tabla | Columnas monetarias |
|---|---|
| `activos_estado` | `depreciacion_acumulada`, `valor_adquisicion`, `valor_libros`, `valor_neto`, `valor_residual` |
| `acuerdos_pago` | `saldo_pendiente`, `valor_cuota`, `valor_original`, `valor_pagado` |
| `apropiaciones` | `saldo_disponible`, `valor_apropiado`, `valor_cdp`, `valor_inicial`, `valor_obligado`, `valor_pagado`, `valor_rp` |
| `asientos_contables_sp` | `total_credito`, `total_debito` |
| `autorizaciones_vigencias_futuras` | `apropiacion_vigencia_actual`, `monto_total` |
| `avisos_tablero` | `impuesto_aviso`, `tarifa`, `valor_aviso` |
| `bienios_sgr` | `monto_ejecutado_bienio`, `monto_presupuestado_bienio` |
| `cdps` | `saldo_disponible`, `valor_cdp`, `valor_comprometido_rp` |
| `censo_ica` | `ingresos_anuales_estimados` |
| `compromisos_vigencias_futuras` | `monto_comprometido`, `monto_obligado`, `monto_pagado` |
| `conciliaciones_reciprocas` | `diferencia_monto_validada`, `monto_conciliado`, `tolerancia_monto` |
| `conciliaciones_reciprocas_partidas` | `monto_eliminar` |
| `configuracion_depreciacion_unidades` | `costo_depreciable`, `costo_por_unidad`, `depreciacion_acumulada`, `valor_adquisicion`, `valor_residual` |
| `consolidaciones_nicsp40` | `valor_ejecutado`, `valor_no_ejecutado`, `valor_transferido` |
| `contratos` | `valor_contrato` |
| `contratos_eps_adres` | `monto_contrato`, `monto_facturado` |
| `declaraciones_ica` | `base_gravable`, `impuesto_ica`, `ingresos_exentos`, `ingresos_gravables`, `ingresos_no_gravables`, `intereses_mora`, `total_pagar` |
| `detalles_asientos` | `credito`, `debito` |
| `embargos_judiciales` | `valor_embargo` |
| `empleados_sp` | `salario_basico` |
| `facturas_salud` | `monto_glosado`, `monto_pagado`, `monto_total` |
| `fondo_unidad_tesoreria` | `saldo_disponible`, `valor_ejecutado`, `valor_inicial` |
| `glosas` | `valor_aceptado`, `valor_glosado`, `valor_rechazado` |
| `horas_extra` | `salario_hora`, `valor_recargo`, `valor_total` |
| `liquidaciones_nomina` | `auxilio_alimentacion`, `auxilio_transporte`, `caja_compensacion`, `fondo_solidaridad`, `horas_extra`, `icbf`, `neto_pagar`, `pension`, `recargo_nocturno`, `riesgos_laborales`, `salario_basico`, `salario_devengado`, `salud`, `sena`, `total_aportes`, `total_devengado` |
| `liquidaciones_prediales` | `avaluo_catastral`, `descuento_pronto_pago`, `impuesto_base`, `intereses_mora`, `total_pagar` |
| `obligaciones` | `saldo_pendiente`, `valor_obligacion`, `valor_pagado` |
| `obligaciones_vigencias_futuras` | `monto_obligado`, `monto_pagado` |
| `pac` | `saldo_disponible`, `valor_ejecutado`, `valor_programado` |
| `pagos` | `valor_pago` |
| `pagos_ica` | `valor_pagado` |
| `polizas` | `valor_asegurado` |
| `predios` | `avaluo_anterior`, `avaluo_catastral` |
| `procesos_cobro_coactivo` | `saldo_pendiente`, `valor_deuda`, `valor_recuperado` |
| `procesos_contratacion` | `valor_estimado` |
| `procesos_disciplinarios` | `monto_sancion` |
| `provisiones` | `saldo_disponible`, `valor_provision`, `valor_utilizado` |
| `proyectos_mga` | `saldo_por_ejecutar`, `valor_ejecutado`, `valor_total` |
| `proyectos_ocad` | `monto_aprobado`, `monto_giro_spgr` |
| `recargos` | `salario_hora`, `valor_recargo` |
| `recepciones_satisfaccion` | `valor_recibido`, `valor_reconocido` |
| `regalias` | `valor_asignado`, `valor_distribuido`, `valor_ejecutado`, `valor_estimado`, `valor_recibido` |
| `registros_produccion` | `costo_por_unidad`, `depreciacion_periodo` |
| `reteica` | `valor_retenido` |
| `retroactivos` | `diferencia_mensual`, `salario_anterior`, `salario_nuevo`, `saldo_pendiente`, `valor_pagado`, `valor_total` |
| `revalorizaciones` | `incremento`, `valor_anterior`, `valor_nuevo` |
| `rips` | `valor_copago`, `valor_modera`, `valor_neto`, `valor_servicio` |
| `rps` | `saldo_disponible`, `valor_obligado`, `valor_rp` |
| `saldos_cuentas` | `saldo_acreedor`, `saldo_deudor`, `saldo_neto` |
| `sgp` | `saldo_disponible`, `valor_asignado`, `valor_ejecutado`, `valor_recibido`, `valor_transferido` |
| `vigencias_futuras_distribucion` | `monto_autorizado`, `monto_comprometido`, `monto_obligado`, `monto_pagado`, `saldo_disponible` |

## Consumidores directos congelados: 90 archivos

### 1. Presupuesto, PAC, vigencias futuras y flujo de pago

1. `lib/sector_publico/presupuesto/models/apropiacion.dart`
2. `lib/sector_publico/presupuesto/models/cdp.dart`
3. `lib/sector_publico/presupuesto/models/obligacion.dart`
4. `lib/sector_publico/presupuesto/models/pac.dart`
5. `lib/sector_publico/presupuesto/models/pago.dart`
6. `lib/sector_publico/presupuesto/models/rp.dart`
7. `lib/sector_publico/presupuesto/services/pac_service.dart`
8. `lib/sector_publico/presupuesto/services/presupuesto_service.dart`
9. `lib/sector_publico/presupuesto/services/vigencias_futuras_service.dart`
10. `lib/sector_publico/presupuesto/pages/pac_tesoreria_page.dart`
11. `lib/sector_publico/planeacion/services/trazabilidad_plan_presupuesto_service.dart`
12. `lib/sector_publico/planeacion/models/proyecto_mga.dart`
13. `lib/sector_publico/planeacion/services/banco_proyectos_service.dart`
14. `lib/sector_publico/planeacion/services/dnp_service.dart`

Riesgo: es el flujo con la cadena CDP -> RP -> obligacion -> pago, saldos,
PAC y autorizaciones plurianuales. Debe conservar las validaciones de
segregacion, cupo, cascada y transaccion que ya fueron corregidas.

### 2. Contabilidad NICSP, activos y consolidacion

15. `lib/sector_publico/contabilidad/models/asiento_contable.dart`
16. `lib/sector_publico/contabilidad/models/cuenta_contable.dart`
17. `lib/sector_publico/contabilidad/pages/conciliacion_reciproca_dialog.dart`
18. `lib/sector_publico/contabilidad/pages/contabilidad_nicsp_page.dart`
19. `lib/sector_publico/contabilidad/services/cierre_vigencia_service.dart`
20. `lib/sector_publico/contabilidad/services/conciliacion_reciprocas_service.dart`
21. `lib/sector_publico/contabilidad/services/consolidacion_jerarquica_service.dart`
22. `lib/sector_publico/contabilidad/services/contabilidad_nicsp_service.dart`
23. `lib/sector_publico/contabilidad/services/depreciacion_job_service.dart`
24. `lib/sector_publico/contabilidad/services/flujo_efectivo_service.dart`
25. `lib/sector_publico/contabilidad/services/provisiones_service.dart`
26. `lib/sector_publico/activos/models/activo_estado.dart`
27. `lib/sector_publico/activos/models/fondo_unidad_tesoreria.dart`
28. `lib/sector_publico/activos/services/activos_service.dart`
29. `lib/sector_publico/activos/services/depreciacion_unidades_service.dart`
30. `lib/sector_publico/activos/services/fondo_unidad_tesoreria_service.dart`
31. `lib/sector_publico/activos/services/revalorizacion_service.dart`
32. `lib/sector_publico/transparencia/models/consolidacion_nicsp40.dart`
33. `lib/sector_publico/transparencia/services/nicsp40_service.dart`

Riesgo: un error de signo o escala desbalancea saldos, estados financieros,
depreciacion o eliminaciones reciprocas. La validacion de partida doble SQL
queda fuera de la migracion monetaria salvo que pueda reforzarse sin ampliar
la frontera.

### 3. Rentas, ICA, predial y cobro coactivo

34. `lib/sector_publico/rentas/models/acuerdo_pago.dart`
35. `lib/sector_publico/rentas/models/liquidacion_predial.dart`
36. `lib/sector_publico/rentas/models/predio.dart`
37. `lib/sector_publico/rentas/models/proceso_cobro_coactivo.dart`
38. `lib/sector_publico/rentas/pages/predial_ica_page.dart`
39. `lib/sector_publico/rentas/services/cobro_coactivo_service.dart`
40. `lib/sector_publico/rentas/services/ica_service.dart`
41. `lib/sector_publico/rentas/services/intereses_moratorios_service.dart`
42. `lib/sector_publico/rentas/services/predial_service.dart`
43. `lib/sector_publico/rentas_departamentales/services/rentas_departamentales_service.dart`

Riesgo: intereses, descuentos, bases e impuestos pueden sufrir redondeos
acumulativos. Las tasas y porcentajes siguen siendo parametros, no columnas
monetarias, y no se convertiran a centavos.

### 4. Regalias, SGR/SGP y reportes de asignacion

44. `lib/sector_publico/regalias/models/bienio_sgr.dart`
45. `lib/sector_publico/regalias/models/proyecto_ocad.dart`
46. `lib/sector_publico/regalias/models/regalia.dart`
47. `lib/sector_publico/regalias/models/reporte_sicodis.dart`
48. `lib/sector_publico/regalias/models/sgp.dart`
49. `lib/sector_publico/regalias/pages/regalias_sgp_page.dart`
50. `lib/sector_publico/regalias/services/regalias_service.dart`
51. `lib/sector_publico/regalias/services/sgp_service.dart`
52. `lib/sector_publico/regalias/services/sicodis_service.dart`
53. `lib/sector_publico/regalias/services/spgr_service.dart`
54. `lib/sector_publico/regalias/services/validacion_distribucion_service.dart`

Riesgo: no se deben mezclar componentes SGP/SGR ni confundir saldos
asignados, recibidos, ejecutados o transferidos. Se conservaran los bloqueos
de destinacion ya verificados.

### 5. Nomina publica

55. `lib/sector_publico/nomina/models/empleado.dart`
56. `lib/sector_publico/nomina/models/liquidacion_nomina.dart`
57. `lib/sector_publico/nomina/models/retroactivo.dart`
58. `lib/sector_publico/nomina/pages/horas_extra_form_page.dart`
59. `lib/sector_publico/nomina/pages/nomina_publica_page.dart`
60. `lib/sector_publico/nomina/services/auxilio_alimentacion_service.dart`
61. `lib/sector_publico/nomina/services/horas_extra_service.dart`
62. `lib/sector_publico/nomina/services/nomina_service.dart`
63. `lib/sector_publico/nomina/services/pila_service.dart`
64. `lib/sector_publico/nomina/services/regimen_docente_service.dart`
65. `lib/sector_publico/nomina/services/retroactivos_service.dart`

Riesgo: salario, devengados, aportes, retroactivos y horas extra deben
mantener exactitud y las reglas ya corregidas de regimenes publicos. La
conversion no alterara porcentajes de aporte ni escalas normativas.

### 6. Contratacion y ciclo SECOP local

66. `lib/sector_publico/contratacion/models/contrato.dart`
67. `lib/sector_publico/contratacion/models/poliza.dart`
68. `lib/sector_publico/contratacion/models/proceso_contratacion.dart`
69. `lib/sector_publico/contratacion/pages/contratacion_publica_page.dart`
70. `lib/sector_publico/contratacion/services/interventoria_liquidacion_service.dart`
71. `lib/sector_publico/contratacion/services/secop_service.dart`

Riesgo: valor contractual, polizas y liquidacion deben seguir respetando el
orden contrato firmado -> RP asociado -> polizas -> legalizacion. No se
implementara integracion remota de SECOP en esta fase.

### 7. Salud publica, RIPS, FEV y glosas

72. `lib/sector_publico/salud/models/contrato_eps.dart`
73. `lib/sector_publico/salud/models/factura_salud.dart`
74. `lib/sector_publico/salud/models/rips.dart`
75. `lib/sector_publico/salud/models/rips_fev.dart`
76. `lib/sector_publico/salud/pages/salud_publica_page.dart`
77. `lib/sector_publico/salud/services/facturacion_salud_service.dart`
78. `lib/sector_publico/salud/services/glosas_service.dart`
79. `lib/sector_publico/salud/services/rips_service.dart`

Riesgo: copagos, moderadoras, valores de servicio, facturacion y glosas se
convertiran sin aparentar validacion CUPS/CUM/CIE-10 inexistente.

### 8. Activos y reportes operativos especiales

80. `lib/sector_publico/auditoria/models/reporte_chip.dart`
81. `lib/sector_publico/auditoria/models/reporte_sia_observa.dart`
82. `lib/sector_publico/auditoria/pages/auditoria_forense_page.dart`
83. `lib/sector_publico/auditoria/services/chip_reporter_service.dart`
84. `lib/sector_publico/auditoria/services/fut_territorial_service.dart`
85. `lib/sector_publico/auditoria/services/sia_observa_service.dart`
86. `lib/sector_publico/siif/services/siif_service.dart`
87. `lib/sector_publico/transparencia/models/proceso_disciplinario.dart`
88. `lib/sector_publico/transparencia/pages/transparencia_page.dart`
89. `lib/sector_publico/transparencia/services/disciplinario_service.dart`
90. `lib/sector_publico/services/migracion_datos_service.dart`

Estos archivos se ordenan despues de los flujos transaccionales porque son
salidas, migracion o modelos de reportes. Se revisara especialmente el riesgo
de exportar pesos ya enteros como si fueran pesos mayores, el bug de Excel
100x identificado en Fase 3A y el formato exigido por SIIF, FUT, CHIP, SIA y
RIPS-JSON.

## Superficie monetaria adicional fuera del manifiesto directo

La busqueda por las 158 columnas no captura todos los nombres de propiedades
monetarias derivadas. Durante la inspeccion aparecieron DTOs y agregados como
`estado_financiero.dart`, totales de `siif_service.dart`, agregados de
validacion de regalias, valores calculados en `chip_reporter_service.dart` y
campos de formulacion MGA. No se deben ignorar: se auditaran junto al bloque
que los consume, aunque no representen una de las 158 columnas de la tabla
v75. Si requieren una columna nueva o una fuente que no existe, se anotara
como brecha y no se fabricara un valor.

## Metodologia y reglas de verificacion

Para cada bloque se verificara:

1. Que el valor leido de SQLite se interprete como `minorUnits` entero COP.
2. Que las operaciones se hagan con `MoneyValue`, sin conversiones manuales
   dispersas.
3. Que la salida UI/exportacion convierta una sola vez al formato requerido.
4. Que los tests dirigidos ejecuten el servicio o widget real, no solo un
   constructor aislado.
5. Que las reglas de saldo, signo, doble conteo, RBAC y transaccion existentes
   sigan pasando.

La verificacion alternativa de esta fase usara `dart format --output=none
--set-exit-if-changed`, tests dirigidos y compilacion indirecta a traves de
tests. El entorno sandbox ya dejo documentado que `flutter analyze` y
`flutter build windows` pueden no producir salida; al cierre Omar debe correr
manualmente:

```powershell
flutter analyze
flutter build windows
flutter test --reporter expanded
```

## Criterio de cierre

El estado solo podra declararse:

```text
Fase 3B: X/X consumidores publicos convertidos - COMPLETA
```

cuando X sea el total reconciliado del inventario de consumidores directos y
la auditoria secundaria de DTOs monetarios no deje consumidores omitidos. Las
17 fallas conocidas de la suite de Fase 3A se compararan al cierre; una falla
que mencione un esquema ajeno al dinero (`hash_actual`, `funcionarios_entidad`,
`contratos`, etc.) se mantendra como pendiente separada y no se maquillara
como resuelta por esta migracion.

## Cierre del inventario

Estado: **Inventario congelado; conversion no iniciada**.

Conteo base: **51 tablas / 158 columnas / 90 consumidores directos
candidatos**. El backend es un submodulo con cambios locales preexistentes y
no fue tocado.
