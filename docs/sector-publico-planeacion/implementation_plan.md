# Plan de Implementación: Consolidación e Integración de la Base de Datos del Sector Público

Este plan define las acciones para integrar de forma definitiva los 11 esquemas del módulo de Sector Público dentro del flujo de inicialización principal del ERP (POS) en `merka_erp_test_fresco.db`, resolviendo las colisiones de nombres de tablas y asegurando que las pantallas del Lote 1 se comuniquen correctamente con la base de datos real.

## User Review Required

> [!IMPORTANT]
> **Colisiones de Nombres Resueltas con Renombrado:**
> Para evitar interferencias con las tablas del POS principal (`asientos_contables` y `empleados`), las tablas correspondientes del Sector Público se renombrarán a:
> * `asientos_contables` (Público) $\rightarrow$ `asientos_contables_sp`
> * `empleados` (Público) $\rightarrow$ `empleados_sp`
>
> Esto requiere actualizar todas las referencias de cadenas SQL en los esquemas, páginas y servicios del Sector Público.

> [!WARNING]
> **Eliminación del Inicializador Huérfano:**
> El archivo `lib/sector_publico/database/database_initializer.dart` será deprecado y eliminado del flujo de código del Sector Público para evitar confusiones de mantenimiento futuras.

---

## Open Questions

No hay preguntas abiertas. El reporte de diagnóstico previo confirmó que el Sector Público debe compartir la base de datos física del POS debido a claves foráneas cruzadas y que no hay datos de clientes reales en el archivo huérfano.

---

## Proposed Changes

### Componente 1: Base de Datos Core

#### [MODIFY] [db_helper.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/db_helper.dart)
* Incrementar la versión de la base de datos a `61`.
* Importar los 11 archivos de esquema del Sector Público.
* Añadir bloque `if (oldVersion < 61)` en `onUpgrade` para ejecutar las llamadas de creación de tablas de los 11 esquemas del Sector Público.

#### [MODIFY] [database_initializer.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/core/database/database_initializer.dart)
* Invocar los métodos `crearTablas` de los 11 esquemas de Sector Público dentro del método `_crearDB` para asegurar que las instalaciones nuevas inicialicen todo el diccionario de datos consolidado.

---

### Componente 2: Esquemas del Sector Público (Renombrado de Tablas Colisionadas)

#### [MODIFY] [schema_multi_tenant.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/database/schema_multi_tenant.dart)
* Renombrar tabla `funcionarios_entidad`'s foreign key de `entidades_territoriales(id)` si aplica, y asegurar compatibilidad de referencias.

#### [MODIFY] [schema_contabilidad.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/contabilidad/database/schema_contabilidad.dart)
* Renombrar la definición de `asientos_contables` a `asientos_contables_sp`.
* Actualizar referencias del foreign key en `detalles_asientos` y `cierres_vigencia` hacia `asientos_contables_sp(id)`.

#### [MODIFY] [schema_nomina.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/nomina/database/schema_nomina.dart)
* Renombrar la definición de `empleados` a `empleados_sp`.
* Actualizar referencias del foreign key en `liquidaciones_nomina` y `retroactivos` hacia `empleados_sp(id)`.

---

### Componente 3: Páginas y Servicios del Sector Público

Actualizar todas las consultas e inserciones SQL de `asientos_contables` y `empleados` a `asientos_contables_sp` y `empleados_sp` en los siguientes archivos:

#### [MODIFY] [contabilidad_nicsp_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/contabilidad/services/contabilidad_nicsp_service.dart)
#### [MODIFY] [cierre_vigencia_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/contabilidad/services/cierre_vigencia_service.dart)
#### [MODIFY] [depreciacion_job_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/contabilidad/services/depreciacion_job_service.dart)
#### [MODIFY] [flujo_efectivo_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/contabilidad/services/flujo_efectivo_service.dart)
#### [MODIFY] [provisiones_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/contabilidad/services/provisiones_service.dart)

#### [MODIFY] [nomina_publica_page.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/nomina/pages/nomina_publica_page.dart)
#### [MODIFY] [auxilio_alimentacion_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/nomina/services/auxilio_alimentacion_service.dart)
#### [MODIFY] [nomina_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/nomina/services/nomina_service.dart)
#### [MODIFY] [retroactivos_service.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/nomina/services/retroactivos_service.dart)
#### [MODIFY] [transparencia_page.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/transparencia/pages/transparencia_page.dart)

#### [DELETE] [database_initializer.dart](file:///C:/Users/PC/Desktop/Caja_simple/lib/sector_publico/database/database_initializer.dart)
* Eliminación definitiva del archivo de inicialización huérfano.

---

## Verification Plan

### Automated Tests
* Ejecutar las suites de pruebas unitarias existentes del Sector Público adaptadas a los nuevos nombres de tablas:
  * `test/sector_publico/funcionarios_duplication_test.dart`
* Crear un test de integración que certifique la migración incremental de la base de datos POS real (`merka_erp_test_fresco.db`) a la versión `61`, comprobando la creación física y la lectura/escritura de las nuevas tablas.
  ```bash
  flutter test test/sector_publico/consolidation_migration_test.dart
  ```

### Manual Verification
* Lanzar la aplicación en entorno de desarrollo.
* Navegar por las pantallas de Lote 1 (Contabilidad, Nómina, Contratación, PAC, Transparencia, Auditoría Forense y Presupuesto) verificando que carguen datos y realicen transacciones sin errores de SQLite.
