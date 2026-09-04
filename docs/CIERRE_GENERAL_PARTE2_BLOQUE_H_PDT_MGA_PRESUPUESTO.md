# Bloque H - Vinculacion PDT/MGA -> Presupuesto (CDP/RP)

Fecha: 2026-08-13

## Fuentes revisadas

- Ministerio de Hacienda, pagina oficial CCPET/CUIPO. La DAF expide y actualiza el
  CCPET para unificar conceptos de ingreso y objetos de gasto territoriales,
  estandarizar lenguaje presupuestal y facilitar gestion/consolidacion.
  Fuente: https://www.minhacienda.gov.co/apoyo-fiscal-territorial/estadisticas-de-finanzas-publicas-territoriales/ccpet-cuipo
- DNP, Catalogos para MGA/Presupuesto Orientado a Resultados. Publica catalogos
  para estandarizar bienes/servicios financiables, categorias, subcategorias,
  productos, actividades e indicadores de proyectos de inversion.
  Fuente: https://www.dnp.gov.co/LaEntidad_/subdireccion-general-inversiones-seguimiento-evaluacion/direccion-proyectos-informacion-para-inversion-publica/Paginas/catalagos.aspx
- DNP, Manual de Procedimientos BPIN. BPIN opera como identificador de proyectos
  de inversion para registro/seguimiento en el banco de proyectos.
  Fuente: https://colaboracion.dnp.gov.co/CDT/Inversiones%20y%20finanzas%20pblicas/Manual_de_Procedimientos_del_Bpin_2006.pdf

## Hallazgo

El sistema ya tenia `proyecto_rubros_metas`, que vinculaba manualmente un
proyecto MGA/BPIN, una meta y una apropiacion. Ese vinculo servia para medir
desviacion fisica/financiera, pero no quedaba evidencia de que un CDP o RP
especifico hubiera tomado esa meta como soporte del gasto.

No encontre una regla nacional unica que permita derivar automaticamente cualquier
meta PDT/MGA a cualquier rubro sin decision de la entidad. Lo correcto y
conservador es mantener un vinculo explicito meta-rubro y usarlo para sugerir y
validar al expedir CDP/RP de inversion.

## Implementacion

- `SchemaPlaneacion` crea `cdp_meta_trazabilidad` y
  `rp_meta_trazabilidad`.
- `TrazabilidadPlanPresupuestoService` ahora:
  - sugiere metas vinculadas a una apropiacion;
  - valida que una meta/proyecto pertenezca al rubro antes de usarla en CDP;
  - registra la trazabilidad del CDP;
  - propaga la trazabilidad al RP cuando el CDP la tiene.
- `PresupuestoService.expedirCDP` acepta `proyectoId` y `metaCodigo`
  opcionales. Si uno se envia, ambos son obligatorios y se validan antes de
  insertar el CDP.
- `PresupuestoService.expedirRP` hereda la trazabilidad del CDP si existe; si el
  CDP no era de inversion trazada, no cambia el flujo existente.
- Migracion `schemaVersion = 100` reaplica defensivamente
  `SchemaPlaneacion.migrarTrazabilidadPlanPresupuesto`.

## Evidencia cruda

Comando:

```powershell
dart analyze lib\sector_publico\planeacion\database\schema_planeacion.dart lib\sector_publico\planeacion\services\trazabilidad_plan_presupuesto_service.dart lib\sector_publico\presupuesto\services\presupuesto_service.dart lib\db_helper.dart test\sector_publico\planeacion\trazabilidad_plan_presupuesto_integracion_test.dart
```

Salida:

```text
Analyzing schema_planeacion.dart, trazabilidad_plan_presupuesto_service.dart, presupuesto_service.dart, db_helper.dart, trazabilidad_plan_presupuesto_integracion_test.dart...

   info - lib\db_helper.dart:876:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\db_helper.dart:892:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print

2 issues found.
```

Comando:

```powershell
flutter test test\sector_publico\planeacion\trazabilidad_plan_presupuesto_integracion_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/sector_publico/planeacion/trazabilidad_plan_presupuesto_integracion_test.dart
00:00 +0: (setUpAll)
00:00 +0: meta MGA vinculada a rubro queda trazada en CDP y RP
00:00 +1: CDP con meta no vinculada al rubro se bloquea antes de insertar
00:00 +2: (tearDownAll)
00:00 +2: All tests passed!
```
