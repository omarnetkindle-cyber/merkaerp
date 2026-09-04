# MerkaERP — Contexto completo de estado del proyecto (v4)
### Para continuar esta revisión en OTRA conversación (con Claude u otra IA)
### Actualizado: 2026-07-11
### Agentes de código usados hasta ahora: Cascade (Cognition, SWE-1.6) — DESCARTADO. Antigravity (Google, "Gemini 3.5 Flash" autorreportado) — se acabaron los tokens a mitad de la investigación en curso, no descartado, pausado.

---

## ⚠️ Cambio de agente: Cascade descartado, Antigravity funcionando bien pero sin tokens

Ver v3 para el detalle completo de por qué se descartó Cascade (diff fabricado + referencia a "reinicio de Windows" inexistente).

**Antigravity funcionó notablemente bien en esta sesión**: evidencia literal consistente, scripts aislados para probar hipótesis sin depender de `flutter test` roto, corrección espontánea de errores del agente anterior (ver hallazgo de `cliente_id` abajo), y hallazgos propios no pedidos (falla silenciosa en el arranque). Sin incidentes de confabulación de contexto como los de Cascade. **No está descartado — se quedó sin tokens/créditos a mitad de la última tarea.** Si se retoma con Antigravity, no hay que volver a levantar sospecha de confiabilidad desde cero; sí seguir exigiendo evidencia literal como práctica estándar con cualquier agente.

**Lección de esta sesión, aplicable a cualquier agente:** cuando una respuesta llega como solo la *traza de comandos ejecutados* sin los resultados/outputs pegados (como pasó al final de esta sesión por quedarse sin tokens), **no se puede tratar como evidencia** — es una lista de qué se intentó, no de qué se encontró. Hay que volver a pedir la ejecución con los outputs literales completos.

---

## Cómo funciona el flujo de trabajo (léelo primero, es la regla más importante)

El usuario supervisa a un agente de IA que ejecuta código directamente sobre el repo `C:\Users\PC\Desktop\Caja_simple` (proyecto MerkaERP, ERP Flutter/Dart con extensión sector público colombiano NICSP/Ley 80 y facturación electrónica DIAN). Quien lea este documento actúa como **revisor externo**: el usuario pega la respuesta cruda del agente, el revisor la revisa con ojo crítico (pide evidencia literal, detecta contradicciones, caza bugs, pide diffs completos) y devuelve al usuario el siguiente prompt exacto para pegarle al agente. El usuario **no decide técnicamente** — solo transmite mensajes entre el revisor y el agente. El revisor decide el rumbo del trabajo.

**Reglas de proceso estrictas, mantenidas durante todo el proyecto:**
- Antes de mover/tocar cualquier función: grep de seguridad (`context|state\.|this\.|setState|AppSession|Navigator`) para confirmar si depende de instancia o es pura.
- Después de cada cambio: `flutter analyze` completo con desglose por severidad (errors/warnings/infos), no solo el total.
- Se exige ver diffs/contenidos completos pegados literalmente — "ya lo mostré arriba" no se acepta. Nada de resúmenes narrativos sin el texto literal detrás. **Una traza de comandos sin sus outputs no es evidencia — no avanzar sobre eso.**
- Un bloque de trabajo = un commit. No se acumulan varios cambios sin revisar en un solo commit.
- No se hace commit sin autorización explícita. El agente siempre pausa antes de comitear.
- `backend_RESPALDO_20260708/` es una carpeta sin trackear que debe permanecer siempre fuera de git.
- Nunca simular éxito falso de cara al usuario real de la app. Esto **no** aplica a fixtures/datos de prueba dentro de `test/`.
- No se agregan dependencias nuevas (pubspec.yaml) sin aprobación explícita.
- No se avanza sobre pseudo-código o supuestos no verificados — se pide evidencia literal antes de implementar.
- Si el agente hace referencia a contexto no verificable, debe señalarse de inmediato y pedir aclaración.
- **Restricción de negocio explícita del usuario:** nada que haga referencia a Odoo (código, dependencias, nombres, arquitectura heredada) puede llegar a la versión que se saque al mercado. Es una línea dura, no una preferencia.
- **Nota de estado del producto:** confirmado por el usuario que la app **todavía no se ha distribuido a usuarios reales**. Esto reduce la urgencia de "hotfix a producción viva" para bugs encontrados, pero no reduce la exigencia de calidad — hay más libertad de rediseñar el esquema/arquitectura correctamente antes del primer release, en vez de parchear mínimamente para no romper datos existentes (no existen datos de usuarios reales que proteger todavía).

---

## Estado del repo

- Baseline estable de `flutter analyze`: **173 issues (0 errores, 52 warnings, 121 infos)** — reconfirmado con evidencia literal y aritmética cruzada.
- HEAD actual: commit `873cb2e` (branch `main`, upstream `origin/main`, +19/-0 sin push) — sin cambios, el bloque XML sigue sin comitear.
- Proceso real de habilitación DIAN iniciado por el usuario pero campos nuevos explícitamente pausados hasta después del Plan Maestro completo.
- Operación real en Colombia es vía **proveedor tecnológico autorizado (PTA)**, no conexión directa a la DIAN. Honesto sobre no estar conectado todavía.

---

## Fases completadas

- **Fase 0** (triage de compilación) y **Fase 0.5** (ajuste de tests): completadas.
- **Fase 1** (adelgazar `main.dart` de 1657 a 316 líneas): cerrada, 6 commits.

---

## Fase 2 — Consolidación del motor DIAN (en curso, PAUSADA por un hallazgo más urgente)

### Ya cerrado y comiteado

1. **CUFE unificado** (`f71445c`).
2. **`DianTransmissionClient` + `NoOp`** (`873cb2e`).

(Detalle completo sin cambios desde v3 — ver ahí si hace falta.)

### Bloque generador XML consolidado — SIGUE SIN COMITEAR, trabajo pausado

Sin cambios de código desde v3. `flutter analyze` reconfirmado en 0/52/121 (coincide baseline). El bloqueo real ya no es solo técnico de este bloque — se descubrió algo más grave que hay que resolver primero (ver abajo). No retomar el cierre de este bloque hasta resolver el hallazgo de sync/Odoo.

---

## 🔴 HALLAZGO PRINCIPAL DE ESTA SESIÓN — bug de sync confirmado como crítico, y sospecha grave sin confirmar sobre su origen

### 1. Bug de esquema en triggers de sync — CONFIRMADO como bug de producción real (con script aislado, evidencia literal completa)

Los triggers `trg_sync_insert_clientes`, `trg_sync_update_clientes`, `trg_sync_insert_ventas`, `trg_sync_update_ventas` en `lib/db_helper.dart` (dentro de `_crearTablasYTriggersDeSincronizacion()`) referencian columnas que **no existen** en las tablas reales `clientes` y `ventas` (confirmado con `PRAGMA table_info`, no con el `CREATE TABLE` estático del código fuente, que está desactualizado por migraciones posteriores).

**Columnas reales actuales de `clientes`:** `id, company_id, nombre, documento, telefono, direccion, email, estado, fecha, gran_contribuyente, autorretenedor, regimen_tributario, declarante, branch_id, warehouse_id, cost_center_id`.

**Columnas reales actuales de `ventas`:** `id, company_id, producto_id, producto, cantidad, precio_unitario, costo_unitario, subtotal, impuesto_pct, impuesto_total, total, fecha, metodo_pago_id, estado, cliente_id, cliente, branch_id, warehouse_id, cost_center_id, efectivo, transferencia, credito, retefuente, reteiva, reteica`.

**Campos que el trigger espera y NO existen como dato en ningún lado de la app local:**
- `clientes`: `identificacion` (existe `documento`, sinónimo), `ciudad`, `tipo_cliente`, `limite_credito`, `saldo_actual`, `activo` (existe `estado`, no es booleano), `updated_at` (existe `fecha`, no es lo mismo).
- `ventas`: `numero_factura`, `iva` (existe `impuesto_total`, sinónimo parcial), `observaciones`, `updated_at`. — **Corrección sobre v3/reporte de Cascade: `cliente_id` SÍ existe en la tabla real** (Cascade se equivocó al leer el `CREATE TABLE` estático en vez del esquema vivo con migraciones aplicadas).

**Prueba con script aislado (evidencia literal completa, sin `flutter test`):** INSERT directo en `clientes` con `is_syncing = 0` (estado normal) produjo:
```
SqfliteFfiException(sqlite_error: 1, SqliteException(1): while executing, no such column: NEW.identificacion, SQL logic error (code 1)
```
Mismo resultado en `ventas` con `no such column: NEW.numero_factura`. **Confirmado: crash real al crear cualquier cliente o registrar cualquier venta**, no solo un artefacto de tests.

**Confirmado también:**
- `is_syncing` tiene `DEFAULT 0` y se inicializa en `0` en cualquier instalación fresca → el bug se dispara desde el primer arranque, sin condición especial.
- `_crearTablasYTriggersDeSincronizacion()` **no tiene try-catch interno** — cuando la carga retroactiva de `clientes` falla, aborta el resto de la función, así que las cargas retroactivas de `ventas` y `venta_items` (que van después en el mismo bloque) **tampoco se ejecutan nunca**. Los triggers sí se crean (van antes en la función), solo la carga retroactiva de datos históricos queda incompleta.
- `SyncAwareDatabaseHelper` está completamente huérfano/sin uso en el proyecto — el sync depende al 100% de que los triggers funcionen.
- El backend remoto SÍ está desplegado y respondiendo: `GET https://merkaerp-control-center-backend.onrender.com/health` → `{"status":"ok","timestamp":"...","version":"2.0"}`. Confirmado que `_checkPostgresAvailability()` resolvería `true` con internet disponible, activando el sync automático — y por tanto el crash — en cualquier instalación con conexión.
- **Confirmado por el usuario: la app aún NO se ha distribuido a usuarios reales.** No hay datos de producción en riesgo hoy. Reduce la urgencia de un hotfix de emergencia, pero el bug debe resolverse antes del primer release — no es opcional ni de baja prioridad.

**`_mapRemoteToLocal()` en `postgres_service.dart` (código literal ya visto) confirma el patrón inverso**: al recibir datos del servidor remoto, esta función ya sabe que campos como `ciudad`, `tipo_cliente`, `limite_credito`, `saldo_actual`, `identificacion`, `numero_factura`, `observaciones` no existen localmente, y los descarta (`local.remove(...)`) antes de escribir en SQLite. Es decir: **el lado "pull" (remoto → local) ya fue adaptado al esquema nuevo. El lado "push" (local → remoto, los triggers) nunca se actualizó.** Esto es evidencia fuerte de que el esquema local fue rediseñado/simplificado en algún momento y el trabajo de actualizar la sincronización quedó a medias — se adaptó la lectura pero no la escritura.

### 2. 🚩 SOSPECHA GRAVE SIN CONFIRMAR — el backend de sync podría ser el backend Odoo archivado, fuera de alcance del plan

El `PostgresService` de la app apunta a `https://merkaerp-control-center-backend.onrender.com`. El `Plan Maestro v4` dice textualmente que el backend rescatado (`merkaerp-control-center-backend`, rama `rescate-odoo-local`, Node.js) **"no forma parte de este plan"** y está archivado como referencia conceptual, no como servicio activo.

**Coincide el nombre exacto.** Los campos que el trigger espera enviar (`ciudad`, `tipo_cliente`, `limite_credito`, `saldo_actual`) encajan con un patrón típico de CRM/ERP genérico (Odoo), no con el dominio específico de facturación electrónica colombiana de MerkaERP. Esto sugiere — sin confirmar todavía — que **el módulo de sync podría estar conectado en vivo al backend archivado que el usuario dijo explícitamente que no debe llegar al mercado ni tener ninguna referencia visible.**

**Aclaración del usuario sobre la intención original:** el backend Odoo se usó para estudiar su lógica de negocio y reimplementarla desde cero dentro de MerkaERP — nunca hubo instrucción de mantenerlo corriendo ni de integrarlo como dependencia viva. El usuario no sabe si el servicio Render actual es ese código o no. **Regla de negocio explícita y no negociable: nada que referencie a Odoo puede estar presente cuando el sistema salga al mercado.**

**Investigación en curso — QUEDÓ INCOMPLETA, sin evidencia literal, solo traza de comandos (Antigravity se quedó sin tokens):**

Se intentaron pero **no se obtuvieron los resultados** de:
1. Headers completos + body de `GET /health` (para ver tecnología del backend: Server, X-Powered-By, etc.)
2. `GET /`, `/web`, `/odoo`, `/api/v1`, `/api/v1/data/pull` en el mismo dominio Render.
3. Contenido de `SYNC_CONFIG.md` (visto por el agente, líneas 1-407, pero no pegado).
4. Contenido de `render.yaml` en el repo (visto pero no pegado).
5. Contenido de `backend/src/server.js` (visto, primeras 120 líneas, pero no pegado).
6. Lista de rutas de `backend/src/routes/*.js` (comando corrido, resultado no pegado).
7. `git branch -a` (para ver si existe la rama `rescate-odoo-local` y su relación con lo desplegado).
8. `git log --all --oneline` de `postgres_service.dart` y `hybrid_sync_service.dart` (para ver cuándo se crearon y con qué mensaje de commit).

**Importante: el agente SÍ vio estos archivos/resultados en su propia sesión (aparecen "Viewed X" en la traza), pero no llegó a transcribir ni resumir nada de su contenido al usuario antes de quedarse sin tokens.** No se puede asumir ningún resultado — hay que repetir la investigación completa desde cero con el agente que se use a continuación.

### Qué falta para resolver este hallazgo (orden de prioridad, reemplaza el orden de v3)

1. **Prioridad máxima absoluta:** repetir la investigación del origen del backend Render (los 8 puntos de arriba) con evidencia literal completa esta vez. Esto decide si el backend es información legítima que hay que arreglar, o el backend Odoo archivado que hay que desconectar por completo.
2. Si se confirma que es (o deriva de) el backend Odoo archivado: decidir con el usuario si se **apaga/desconecta el servicio de Render** y se **elimina o rediseña desde cero** todo el módulo de sync (`lib/services/hybrid_sync_service.dart`, `lib/services/postgres_service.dart`, los triggers), en vez de solo arreglar el mapeo de columnas.
3. Si se confirma que es un backend distinto y legítimo: entonces sí, decidir el fix de columnas (tres opciones ya planteadas: agregar columnas localmente, recortar los triggers, o mixto) — con el usuario, no unilateralmente por el agente, porque es una decisión de qué datos captura el negocio.
4. Confirmar que `crear_factura_integration_test.dart` pasa sus aserciones (bloqueado además por el bloqueo de entorno Windows de `sqlite3.dll`, ver abajo, todavía sin resolver).
5. Confirmar el resultado final completo de la suite de tests.
6. Retomar y cerrar el bloque del generador XML (`Fase 2`), solo después de resolver todo lo anterior.

---

## Bloqueo de entorno Windows — SIGUE SIN RESOLVER, no se tocó en esta sesión

```
PathExistsException: Cannot copy file to 'C:\Users\PC\Desktop\Caja_simple\build\native_assets\windows\sqlite3.dll'
OS Error: No se puede crear un archivo que ya existe, errno = 183
```
Sin evidencia literal confiable todavía (la única descripción viene del agente descartado, incluyendo su referencia fantasma a un "reinicio de Windows"). Antigravity logró evitar este bloqueo por completo trabajando con scripts Dart aislados y una copia sandbox de la base de datos, sin depender de `flutter test`. Se recomienda seguir con ese enfoque (scripts aislados) para cualquier verificación futura, y tratar el arreglo de `flutter test` en Windows como un problema aparte, de menor prioridad mientras el enfoque de scripts aislados siga funcionando.

---

## Pendiente para una fase posterior (explícitamente pausado por decisión del usuario)

Ampliar el modelo de configuración DIAN con campos reales del proceso de habilitación. **No tocar hasta que el usuario lo pida explícitamente.**

---

## Fases siguientes del Plan Maestro (no iniciadas)

Después de Fase 2 (y ahora, después de resolver el hallazgo de sync/Odoo): Fases 3-8 del `MerkaERP_Plan_Maestro_v4.md`.

---

## Fuera de alcance del plan de desarrollo

Certificación ISO 27001, migración de datos históricos por cliente, proceso de licitación pública. **Backend Node.js/Odoo rescatado (rama `rescate-odoo-local`) — antes "archivado como referencia", ahora bajo sospecha activa de estar corriendo en vivo y conectado a la app; ver hallazgo principal arriba. Regla de negocio: cero referencias a Odoo en la versión de mercado.**

---

## Prompt sugerido para retomar en la nueva conversación

```
Estoy retomando la revisión de MerkaERP. En la sesión anterior (con el agente
Antigravity, que se quedó sin tokens a mitad de una investigación) se confirmó un bug
de producción real en los triggers de sincronización de clientes/ventas (columnas
inexistentes referenciadas), pero surgió algo más urgente: sospecha sin confirmar de
que el backend de sync activo en Render (merkaerp-control-center-backend.onrender.com)
es el mismo backend Node.js/Odoo archivado que el Plan Maestro dice que está fuera de
alcance — y el usuario tiene una regla de negocio no negociable de que nada relacionado
a Odoo puede llegar a la versión de mercado.

La investigación para confirmar u descartar esto se intentó pero quedó sin evidencia
real (solo una traza de comandos sin resultados pegados, por falta de tokens del
agente anterior) — hay que repetirla completa desde cero. Te acabo de dar el contexto
completo (v4), con la lista exacta de 8 verificaciones pendientes en la sección
"Investigación en curso". Empieza por ahí.

Sigue el mismo nivel de rigor: evidencia literal siempre, nunca aceptar una traza de
comandos sin resultados como si fuera evidencia, y cualquier referencia a contexto no
verificable se señala de inmediato.
```
