# MerkaERP — Contexto completo de estado del proyecto (v7)
### Para continuar esta revisión en OTRA conversación (con Claude u otra IA)
### Actualizado: 2026-07-11 (continuación de v6)
### Agentes de código usados hasta ahora: Cascade (Cognition, SWE-1.6) — DESCARTADO. Antigravity (Google) — funcionó bien, se quedó sin tokens, investigación pendiente. GitHub Copilot Chat en VS Code (modelo Gemini vía Copilot) — en uso actual, sin incidentes de confiabilidad propios en toda la sesión.

---

## ⚡ LO MÁS URGENTE AL RETOMAR

Se acaba de enviar al agente un fix ya diseñado y **autorizado por el usuario** para un bug crítico confirmado (ver sección 2): los triggers de sync de `clientes` y `ventas` referencian columnas que no existen en el esquema actual, y esto **rompe la creación de clientes y ventas en la app real, no solo en tests**. El prompt exacto que se envió está al final de este documento (sección "Prompt que se envió justo antes de cerrar esta sesión"). **Lo primero que hay que hacer al retomar es pedir el resultado literal de ese prompt** (diff aplicado, `flutter analyze`, resultado del test de integración) y revisarlo con el mismo rigor de siempre, antes de autorizar cualquier commit.

---

## Qué cambió respecto a v6 (resumen ejecutivo)

v6 cerró el incidente del commit accidental y dejó pausada, para una fase futura, la investigación del doble sistema de sync (`SyncService` vs `HybridSyncService`). Esta sesión retomó el cierre de Fase 2 (bloque XML) y, al intentar correr el test de integración de facturación, **se topó de frente con una reproducción real y bloqueante del bug de "campos fantasma" documentado desde v4** — resultó no ser un problema abstracto de sync remoto, sino un **trigger de base de datos local roto que impide crear clientes y ventas en la aplicación**, con independencia de cualquier conexión a internet o backend remoto. Se diagnosticó con precisión total (columna por columna, con pruebas empíricas aisladas) y se diseñó un fix acotado, ya autorizado y enviado al agente. El resultado de ese fix es lo que falta confirmar al retomar.

---

## 1. Incidente del commit accidental — CERRADO ✅ (sin cambios desde v6)

Ver v6 sección 1 para el detalle completo. Resumen: `git reset --soft 873cb2e` ejecutado correctamente, `backend_RESPALDO_20260708/` fuera de git y en `.gitignore`, `test_init.dart` borrado, y los dos cambios sin explicar (`secop_service.dart`, `pila_service.dart`) confirmados como legítimos (sintaxis moderna de Dart 3.8+ y limpieza de import muerto, respectivamente — ninguno es un bug).

---

## 2. 🔴 BUG CRÍTICO CONFIRMADO Y DIAGNOSTICADO: triggers de sync rotos rompen creación de clientes y ventas

### Cómo se descubrió

Al intentar cerrar Fase 2 corriendo `test/core/invoicing/crear_factura_integration_test.dart` (ver sección 3), el test falló en `setUpAll` con:

```
SqfliteFfiException(sqlite_error: 1, ...): no such column: identificacion, SQL logic error (code 1)
Causing statement: INSERT INTO local_changes (...) SELECT 'clientes', ... json_object(..., 'identificacion', identificacion, ...) FROM clientes ...
```

Esto resultó ser la primera reproducción real (con stack trace completo) del bug de "triggers de sync desincronizados" que v4 documentaba solo con evidencia de script aislado ("clientes: 7 campos fantasma", "ventas: 6 campos fantasma").

### Diagnóstico completo, confirmado con evidencia literal y pruebas empíricas aisladas

**`clientes`** — el trigger `trg_sync_insert_clientes`/`trg_sync_update_clientes` (en `lib/db_helper.dart`, función `_crearTablasYTriggersDeSincronizacion`) usa un `json_object(...)` con columnas que en su mayoría **no existen** en la tabla real:

| Columna real en `clientes` (según `CREATE TABLE` en `lib/db_helper.dart` ~línea 1352) | ¿La usa el trigger? |
|---|---|
| `id`, `nombre`, `email`, `telefono`, `direccion` | Sí (coinciden) |
| `company_id`, `estado`, `fecha`, `gran_contribuyente`, `autorretenedor`, `regimen_tributario`, `declarante` | No (el trigger nunca las menciona) |
| `documento` | El trigger usa `identificacion`, que **no existe** |
| — | El trigger pide `ciudad`, `tipo_cliente`, `limite_credito`, `saldo_actual`, `activo`, `updated_at` — **ninguna existe** en la tabla actual |

**`ventas`** — mismo patrón, con el `CREATE TABLE` real en `lib/core/database/database_initializer.dart`:

| Columna que usa el trigger | ¿Existe en la tabla real? |
|---|---|
| `fecha`, `subtotal`, `total`, `estado` | Sí |
| `numero_factura`, `cliente_id`, `iva`, `metodo_pago`, `observaciones`, `updated_at` | No (la tabla real tiene en su lugar `producto_id`, `producto`, `cantidad`, `precio_unitario`, `costo_unitario`, `impuesto_pct`, `impuesto_total`, `metodo_pago_id`, `company_id` — un modelo de línea de venta, no de factura con cliente) |

**`productos`** — verificado, **sin ningún problema**: todas las columnas que usa `trg_sync_insert_productos`/`trg_sync_update_productos` existen en la tabla real.

**`ventas_detalle`** (la tabla real detrás de `venta_items` en el trigger) — verificado, **sin ningún problema**: todas las columnas usadas por `trg_sync_insert_venta_items`/`trg_sync_update_venta_items` existen.

### Confirmación empírica del alcance real (no solo en tests)

Se ejecutaron scripts Dart aislados (sqlite3 en memoria, mismo esquema y triggers reales) que confirmaron:
- Un `INSERT` real a `clientes` con el esquema actual **falla siempre**, de forma determinista, con `no such column: NEW.identificacion`.
- Un `INSERT` real a `ventas` con el esquema actual **falla siempre**, de forma determinista, con `no such column: NEW.numero_factura`.

Se revisaron todos los puntos de la app que insertan en `clientes`/`ventas` (`clientes_page.dart`, `seed_operations.dart`, `enterprise_feature_service.dart`, `db_helper.dart:insertarCliente`, `api_router.dart`):
- **Ninguno oculta el error silenciosamente.** La API REST (`api_router.dart`) captura la excepción y la convierte en HTTP 500 explícito (correcto). Los demás puntos no tienen try/catch, así que la excepción se propaga sin disfrazarse. **No se viola la regla de "nunca simular éxito falso"** — el problema es que la función está rota, no que mienta sobre su éxito.
- **Conclusión de alcance:** crear un cliente o una venta desde la app real, hoy, en cualquier flujo que no sea la API REST, debería fallar visiblemente (crash o excepción no manejada). Esto es más grave que "sync con campos fantasma" — es una función core de la app rota.

### Fix diseñado, revisado y AUTORIZADO por el usuario (resultado pendiente de confirmar al retomar)

Alcance del fix: solo corregir que los triggers referencien columnas que existen en el esquema local actual (desbloquea la creación de clientes/ventas). **No** toca la compatibilidad con el backend remoto ni `postgres_service.dart` (que ya hace una traducción `documento`↔`identificacion` en sentido remoto→local) — eso queda para la fase futura de rediseño de sync (sección 4).

El diff exacto autorizado reescribe, en `lib/db_helper.dart` función `_crearTablasYTriggersDeSincronizacion`:
1. `trg_sync_insert_clientes` y `trg_sync_update_clientes` — nuevo `json_object` con: `id, company_id, nombre, documento, telefono, direccion, email, estado, fecha, gran_contribuyente, autorretenedor, regimen_tributario, declarante`.
2. La carga retroactiva (`INSERT...SELECT`) de `clientes` — mismo set de columnas.
3. `trg_sync_insert_ventas` y `trg_sync_update_ventas` — nuevo `json_object` con: `id, company_id, producto_id, producto, cantidad, precio_unitario, costo_unitario, subtotal, impuesto_pct, impuesto_total, total, fecha, metodo_pago_id, estado`.
4. La carga retroactiva (`INSERT...SELECT`) de `ventas` — mismo set de columnas.

No se tocan `productos` ni `venta_items` (ya confirmados sin problema). No se toca nada de `postgres_service.dart` ni del backend remoto.

**El prompt exacto con este fix ya fue enviado al agente al cierre de esta sesión** (ver última sección de este documento). El prompt pide explícitamente: aplicar el cambio, correr `flutter analyze` completo, volver a correr `crear_factura_integration_test.dart`, y **no comitear todavía** — esperar revisión del diff y de ambos resultados antes de autorizar el commit.

**Esto es la primera acción a tomar al retomar: pedir el resultado literal de ese prompt.**

---

## 3. Fase 2 (generador XML) — bloqueada por el bug de la sección 2, no por nada propio del bloque XML

El bloque en sí (contenido, archivos, alcance) sigue exactamente igual que en v6 — no cambió nada de su código. Lo que se descubrió es que **no se puede cerrar Fase 2 sin antes arreglar el bug de triggers de clientes/ventas**, porque el test de integración de facturación depende de poder crear un cliente de prueba, y eso disparaba el trigger roto.

Estado del repo al cierre de esta sesión (`git status --short`):
```
 M .gitignore
M  lib/core/export/export_service.dart
A  lib/core/invoicing/xml/generator.dart
M  lib/db_helper.dart
M  lib/facturacion_electronica_page.dart
 M lib/sector_publico/contratacion/services/secop_service.dart
 M lib/sector_publico/nomina/services/pila_service.dart
A  test/core/invoicing/crear_factura_integration_test.dart
A  test/core/invoicing/xml/generator_test.dart
?? analysis_output.txt
```

Nota de higiene menor: `analysis_output.txt` sigue apareciendo sin trackear desde una sesión anterior — hay que borrarlo o añadirlo a `.gitignore` cuando se retome, para que no se siga arrastrando.

Orden de lo que falta para cerrar Fase 2, actualizado:

1. **Confirmar el resultado del fix de triggers (sección 2)** — esto es lo inmediato, ya en curso.
2. Con el fix aplicado y confirmado, volver a correr `crear_factura_integration_test.dart` y confirmar que pasa sus aserciones (puede que ya se haya hecho como parte del punto 1, según lo que el agente reporte).
3. Revisar el contenido de `test/core/invoicing/xml/generator_test.dart` (nunca visto en detalle en ningún documento de contexto anterior — sigue pendiente, no se tocó en esta sesión).
4. Decidir qué hacer con `analysis_output.txt` (borrar o gitignorar).
5. Solo entonces: recomitear el bloque XML **y el fix de triggers** como commits separados y limpios (son dos bloques de trabajo distintos — no fusionarlos en uno solo, seguir la regla de "un bloque de trabajo = un commit"), cada uno con mensaje propio y autorización explícita antes de ejecutar el commit.

Bloqueo de entorno sin cambios: `sqlite3.dll` en Windows sigue interfiriendo con `flutter test` de forma intermitente (se resolvió esta sesión moviendo/renombrando el artefacto de build bloqueado). Seguir usando el enfoque de scripts Dart aislados con sqlite3 en memoria cuando el bloqueo de `flutter test` reaparezca — ya se usó varias veces con éxito en esta sesión.

---

## 4. Pendiente para una fase futura (no ahora): rediseño de sincronización remota

Sin cambios respecto a v6 — sigue pausado deliberadamente. Incluye:

- Decidir si `SyncService` y `HybridSyncService` (que corren en paralelo, sin coordinarse) deben fusionarse o si uno debe descartarse.
- Corregir que `SyncService._pushChanges()`/`_pullChanges()` llaman a rutas (`installations/sync/push`, `installations/sync/pull`) que no existen en el backend real (`origin/main` del repo `merkaerp-control-center-backend` solo implementa `/api/v1/data/push` y `/api/v1/data/pull`).
- Decidir qué hacer con `processQueue()` (código muerto, no se llama desde ningún lado, usa una tercera ruta distinta `/api/v1/sync/push`).
- Auditar si `HybridSyncService` funciona correctamente de forma aislada.
- Revisar la traducción `documento`↔`identificacion` en `postgres_service.dart` (líneas ~73-77) a la luz del fix de la sección 2 — con el trigger local ya corregido para usar `documento`, confirmar que esa capa de traducción remoto→local sigue siendo necesaria y correcta.
- Confirmar si hay conflictos por tener dos sistemas de sync escribiendo/leyendo las mismas tablas en paralelo.

Contexto adicional ya confirmado (no repetir investigación): el backend en producción (Render, repo `merkaerp-control-center-backend`, rama `origin/main`) está limpio de Odoo — la sospecha original de v4 quedó descartada con evidencia directa (headers HTTP, diff de `package.json`, contenido de `/health`). La rama `rescate-odoo-local` existe en el remoto pero no es lo desplegado.

---

## Fases completadas (sin cambios respecto a v6)

- Fase 0 (triage de compilación) y Fase 0.5 (ajuste de tests): completadas.
- Fase 1 (adelgazar `main.dart` de 1657 a 316 líneas): cerrada, 14 commits.
- Fase 2: en curso, bloqueada por el bug de la sección 2, ver sección 3 para el resto.

---

## Fuera de alcance del plan de desarrollo (sin cambios)

Certificación ISO 27001, migración de datos históricos por cliente, proceso de licitación pública. Backend Node.js/Odoo rescatado (rama `rescate-odoo-local`, confirmado que existe en el remoto pero NO es lo desplegado en producción) — regla de negocio de cero Odoo en la versión de mercado, confirmado que se cumple en producción actual.

---

## Prompt que se envió justo antes de cerrar esta sesión (resultado pendiente de confirmar al retomar)

```
Autorizado: aplica el fix a los triggers de sync de clientes y ventas en
lib/db_helper.dart (función _crearTablasYTriggersDeSincronizacion), usando
exactamente los json_object corregidos que ya definimos, alineados con el
esquema real actual de cada tabla (columnas confirmadas por auditoría directa).

Cambia:
1. trg_sync_insert_clientes y trg_sync_update_clientes
2. La carga retroactiva de clientes (el INSERT...SELECT correspondiente)
3. trg_sync_insert_ventas y trg_sync_update_ventas
4. La carga retroactiva de ventas (el INSERT...SELECT correspondiente)

No toques productos ni venta_items — ya confirmamos que están alineados.
No toques nada relacionado con el backend remoto ni con postgres_service.dart
— eso queda fuera de este fix, es parte de la fase futura de rediseño de sync.

Después de aplicar el cambio:
1. Corre flutter analyze completo y pégame el resultado literal.
2. Vuelve a correr test/core/invoicing/crear_factura_integration_test.dart
   (usando el mismo enfoque que ya funcionó para esquivar el bloqueo de
   sqlite3.dll si vuelve a aparecer) y pégame el resultado literal completo.
3. No hagas commit todavía — quiero ver el diff completo del cambio a
   db_helper.dart y el resultado de ambas pruebas antes de autorizar el commit.
```

## Prompt sugerido para retomar en la nueva conversación

```
Estoy retomando la revisión de MerkaERP. Te acabo de dar el contexto completo (v7).

En la sesión anterior se descubrió y diagnosticó un bug crítico: los triggers
de sync de clientes y ventas en lib/db_helper.dart referencian columnas que no
existen en el esquema actual, y esto rompe la creación de clientes y ventas en
la app real (confirmado con pruebas empíricas aisladas, no solo en tests). Se
diseñó un fix acotado, se autorizó, y se envió el prompt exacto al agente
(está al final de este documento) justo antes de cerrar la sesión anterior —
por lo que probablemente ya tengas la respuesta del agente con el resultado.

Pégame esa respuesta completa y literal (diff aplicado a db_helper.dart,
resultado de flutter analyze, y resultado de crear_factura_integration_test.dart)
para que la revise con el mismo rigor de siempre antes de autorizar cualquier
commit. Si el fix funcionó, seguimos con el resto del cierre de Fase 2 (sección
3 de este documento): revisar generator_test.dart, decidir qué hacer con
analysis_output.txt, y comitear el bloque XML y el fix de triggers como DOS
commits separados, cada uno con autorización explícita.

Mismo rigor de siempre: evidencia literal, nunca aceptar trazas de comandos sin
resultados, señalar cualquier contexto no verificable.
```
