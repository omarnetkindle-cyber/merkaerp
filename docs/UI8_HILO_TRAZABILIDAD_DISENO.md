# UI-8: Hilo de trazabilidad y bloqueo

## Modelo

`ChainStep` representa un registro real dentro de una cadena causal. Cada paso
contiene `entityType`, `recordId`, estado (`Completo`, `Bloqueado` o
`Pendiente`), la regla que lo bloquea, el rol responsable, el módulo de
navegación, el comando opcional y el tipo de evidencia que puede exportarse.
`TraceabilityChain` contiene el registro raíz y una lista ordenada de pasos.

`TraceabilityChainService` funciona como un registro de proveedores. Cada
proveedor conoce una cadena, pero solo consulta vínculos y estados persistidos;
las reglas de creación, saldos, PAC, inventario y contabilidad siguen viviendo
en sus servicios originales.

## Cadenas implementadas

### Presupuesto público

`apropiaciones -> cdps.apropiacion_id -> rps.cdp_id -> obligaciones.rp_id ->
pagos.obligacion_id -> asientos_contables_sp`.

El proveedor también resuelve la cadena hacia adelante cuando la consulta parte
de la apropiación. La ausencia de un eslabón muestra la regla exacta que impide
continuar, por ejemplo: `No existe un CDP expedido contra la apropiación.`
Los comandos existentes de apropiación, CDP y RP se muestran únicamente cuando
`CommandRegistry` los hace visibles para el usuario y contexto actuales.

### Comercial

`ventas -> cuentas_por_cobrar.venta_id -> abonos_cxc.cuenta_id ->
movimientos_inventario.motivo`.

La salida POS se vincula con la referencia existente `FACTURA POS #<venta_id>`;
no se creó una relación paralela ni se duplicó la lógica de inventario.

## UI y evidencia

`TraceabilityChainPage` presenta una línea temporal vertical usando
`ExpandableRecordCard`, tokens del tema y los estados del esquema de color de
Material. Cada paso puede mostrar su bloqueo, responsable, abrir el registro y,
cuando existe un comando autorizado, resolverlo desde el mismo
`CommandRegistry` de la paleta global. Los pasos de apropiación/CDP/RP incluyen
la exportación JSON de la Cápsula de Evidencia de UI-7.

Las tarjetas de apropiaciones, CDP, RP y cuentas por cobrar ahora incluyen
`Ver hilo de trazabilidad` junto a `Exportar evidencia` cuando esta última está
disponible.

## Extensión pendiente

CRM (`lead -> oportunidad -> venta`), MRP (`orden -> consumo -> producción`) y
HRM (`ausencia -> nómina`) quedan como proveedores futuros. Para agregarlos no
se modifica el motor ni la pantalla: se implementa `TraceabilityChainProvider`,
se registra en `TraceabilityChainService.standard()` y se agregan sus relaciones
reales y tests dirigidos.
