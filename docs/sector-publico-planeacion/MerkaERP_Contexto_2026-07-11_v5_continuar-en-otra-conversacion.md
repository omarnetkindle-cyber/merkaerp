# MerkaERP — Contexto completo de estado del proyecto (v5)
### Para continuar esta revisión en OTRA conversación (con Claude u otra IA)
### Actualizado: 2026-07-11
### Agentes de código usados hasta ahora: Cascade (Cognition, SWE-1.6) — DESCARTADO. Antigravity (Google) — funcionó bien, se quedó sin tokens, investigación pendiente. GitHub Copilot Chat en VS Code (modelo Gemini vía Copilot) — en uso actual.

---

## 🔴 INCIDENTE NUEVO DE ESTA SESIÓN: commit accidental por clic en VS Code, con violación de una regla dura del proyecto

**Qué pasó:** el usuario, sin intención, hizo clic en el botón azul "Confirmación" (= "Commit" en español) del panel de Source Control de VS Code, con 78 cambios pendientes visibles. Esto ejecutó un `git commit --amend` que **absorbió el bloque del generador XML (sin comitear y sin verificación completa) dentro del commit anterior** `873cb2e` ("DianTransmissionClient + NoOp"), convirtiéndolo en un nuevo commit `44d4e30` con 12 archivos y 539 líneas en vez de los 5 archivos/230 líneas originales.

**Esto violó dos reglas del proyecto simultáneamente:**
- "Un bloque de trabajo = un commit" — se fusionaron dos bloques distintos (DianTransmissionClient+NoOp, ya cerrado, y el generador XML, todavía bloqueado por el bug de sync sin resolver) en un solo commit.
- "No se comitea sin autorización explícita" — el bloque XML nunca fue autorizado para comitear.

**Hallazgo más grave, colateral del mismo accidente:** `backend_RESPALDO_20260708/` — la carpeta que la regla del proyecto dice explícitamente que **debe permanecer siempre fuera de git** — apareció trackeada dentro del commit accidental (`backend_RESPALDO_20260708 | 1 +` en el diffstat, con marca `m` minúscula de submódulo/gitlink en `git status`). Es la primera vez en todo el proyecto que se viola esta regla concreta.

**Estado al momento de detectarlo:** nada de esto se había empujado a `origin/main` (`ahead 19`, sin push) — margen completo para corregir en local sin ningún riesgo para el remoto.

**Plan acordado y en ejecución:** `git reset --soft 873cb2e` para deshacer el amend, devolviendo el bloque XML a su estado de "cambios sin comitear" previo al accidente, y sacar `backend_RESPALDO_20260708` del índice de git (`git rm --cached`) si el reset no lo revierte solo. **Esto se le pidió al agente actual (GitHub Copilot/Gemini) pero la respuesta con el resultado todavía no ha llegado al momento de escribir este documento — confirmar el resultado literal antes de asumir que quedó resuelto.**

**Además, sin resolver todavía:** aparecieron cambios locales sin comitear en `lib/sector_publico/contratacion/services/secop_service.dart` y `lib/sector_publico/nomina/services/pila_service.dart` que no corresponden a ningún bloque de trabajo documentado en ninguna sesión anterior. Se pidió el diff literal completo pero la respuesta tampoco ha llegado. **Investigar su origen antes de decidir si se quedan, se descartan, o son indicio de otro accidente similar.**

**Lección para cualquier sesión futura, con cualquier agente:** antes de retomar trabajo, siempre correr `git log --oneline -5`, `git reflog -10` y `git status --branch --short` al principio de la sesión para detectar cualquier commit accidental o divergencia de HEAD respecto a lo documentado — no asumir que el HEAD documentado en el contexto sigue siendo el HEAD real, especialmente si hubo uso de la interfaz gráfica de Git (Source Control panel de VS Code) entre sesiones.

---

## Cambio de agente: historial de confiabilidad

- **Cascade (Cognition, SWE-1.6): DESCARTADO.** Ver v3 — diff fabricado/alucinado + referencia a un "reinicio de Windows" inexistente.
- **Antigravity (Google): funcionó muy bien**, evidencia literal consistente, halló y corrigió un error de Cascade (columna `cliente_id` sí existe), encontró la falla silenciosa de inicialización por su cuenta. Se quedó sin tokens a mitad de la investigación del backend Odoo/Render — no descartado, solo interrumpido.
- **GitHub Copilot Chat en VS Code (Gemini vía Copilot): en uso actual.** Sin incidentes de confiabilidad propios todavía — el commit accidental fue causado por el usuario (clic en la UI de VS Code), no por el agente. El agente sí respondió con buena evidencia forense (reflog, diffstat, comparación de commits) cuando se le pidió reconstruir qué pasó.

**Lección de esta sesión, aplicable a cualquier agente:** cuando una respuesta llega como solo la *traza de comandos ejecutados* sin los resultados/outputs pegados, no se puede tratar como evidencia — hay que pedir la ejecución de nuevo con outputs literales completos (pasó con Antigravity al quedarse sin tokens).

---

## Cómo funciona el flujo de trabajo (léelo primero, es la regla más importante)

El usuario supervisa a un agente de IA que ejecuta código directamente sobre el repo `C:\Users\PC\Desktop\Caja_simple` (proyecto MerkaERP, ERP Flutter/Dart con extensión sector público colombiano NICSP/Ley 80 y facturación electrónica DIAN). Quien lea este documento actúa como **revisor externo**: el usuario pega la respuesta cruda del agente, el revisor la revisa con ojo crítico (pide evidencia literal, detecta contradicciones, caza bugs, pide diffs completos) y devuelve al usuario el siguiente prompt exacto para pegarle al agente. El usuario **no decide técnicamente** — solo transmite mensajes entre el revisor y el agente. El revisor decide el rumbo del trabajo.

**Reglas de proceso estrictas, mantenidas durante todo el proyecto:**
- Antes de mover/tocar cualquier función: grep de seguridad (`context|state\.|this\.|setState|AppSession|Navigator`) para confirmar si depende de instancia o es pura.
- Después de cada cambio: `flutter analyze` completo con desglose por severidad (errors/warnings/infos).
- Se exige ver diffs/contenidos completos pegados literalmente. Una traza de comandos sin sus outputs no es evidencia.
- Un bloque de trabajo = un commit. No se acumulan varios cambios sin revisar en un solo commit. **(Violado una vez por accidente de UI, ver incidente arriba — en corrección.)**
- No se hace commit sin autorización explícita. **(Violado una vez por accidente de UI, ver incidente arriba — en corrección.)**
- `backend_RESPALDO_20260708/` es una carpeta sin trackear que debe permanecer siempre fuera de git. **(Violado una vez por el mismo accidente — en corrección activa.)**
- Nunca simular éxito falso de cara al usuario real de la app. No aplica a fixtures/datos de prueba dentro de `test/`.
- No se agregan dependencias nuevas (pubspec.yaml) sin aprobación explícita.
- No se avanza sobre pseudo-código o supuestos no verificados.
- Si el agente hace referencia a contexto no verificable, debe señalarse de inmediato.
- **Restricción de negocio no negociable:** nada que haga referencia a Odoo (código, dependencias, nombres, arquitectura heredada) puede llegar a la versión que se saque al mercado.
- **La app todavía no se ha distribuido a usuarios reales** — reduce la urgencia de hotfix de emergencia para bugs encontrados, pero no reduce la exigencia de calidad. Hay margen para rediseñar bien antes del primer release.
- **Nueva regla explícita tras este incidente:** al inicio de cada sesión, antes de cualquier otra cosa, correr `git log --oneline -5`, `git reflog -10`, y `git status --branch --short` para confirmar que el HEAD real coincide con el HEAD documentado. Cualquier divergencia se investiga antes de continuar con cualquier tarea.

---

## Estado del repo (a confirmar al retomar — ver incidente arriba)

- **Antes del incidente:** HEAD documentado = `873cb2e`, bloque XML sin comitear.
- **Tras el amend accidental:** HEAD pasó a `44d4e30`, con el bloque XML fusionado dentro (violación de reglas, ver arriba).
- **Plan en ejecución (resultado aún no confirmado con evidencia al cierre de esta sesión):** `git reset --soft 873cb2e` para volver al estado correcto, más `git rm --cached backend_RESPALDO_20260708` si hace falta.
- **Acción obligatoria al retomar:** confirmar con `git log --oneline -3` y `git status --short` que el reset se ejecutó y quedó como se esperaba, antes de asumir cualquier otra cosa sobre el estado del repo.
- El branch local `main` estaba `ahead 19` de `origin/main`, sin push — confirmar que sigue así.
- Proceso real de habilitación DIAN iniciado por el usuario pero campos nuevos explícitamente pausados hasta después del Plan Maestro completo.
- Operación real en Colombia es vía **proveedor tecnológico autorizado (PTA)**, no conexión directa a la DIAN.

---

## Fases completadas

- **Fase 0** (triage de compilación) y **Fase 0.5** (ajuste de tests): completadas.
- **Fase 1** (adelgazar `main.dart` de 1657 a 316 líneas): cerrada, 14 commits (`a91685c` a `f71445c` según el log completo visto en esta sesión).

---

## Fase 2 — Consolidación del motor DIAN (en curso, sigue pausada)

### Ya cerrado y comiteado (commit `873cb2e`, tras deshacer el amend)

1. **CUFE unificado** (`f71445c`).
2. **`DianTransmissionClient` + `NoOp`** (`873cb2e`) — 5 archivos: `dian_transmission_client.dart`, `dian_transmission_client_noop.dart`, `dian_transmission_client_registry.dart`, `facturacion_electronica_page.dart` (parcial), `dian_transmission_client_noop_test.dart`.

### Bloque generador XML consolidado — vuelve a estado "sin comitear" tras el reset

Contenido confirmado (visto en el diff del commit accidental antes de deshacerlo, así que el código en sí ya fue verificado que existe y es coherente con lo documentado en v2/v3):
- `lib/core/invoicing/xml/generator.dart` (nuevo, 102 líneas)
- Cambios en `lib/db_helper.dart` (mapeo supplier/líneas, ~63 líneas)
- Cambios en `lib/core/export/export_service.dart` (wrapper delegante, -73/+pocas líneas netas)
- Cambios en `lib/facturacion_electronica_page.dart` (pasar CUFE calculado)
- `test/core/invoicing/crear_factura_integration_test.dart` (nuevo, 92 líneas) — confirmado que NO hay duplicado en `test/core/invoicing/db/` (ese archivo no existe, se descartó esa sospecha)
- `test/core/invoicing/xml/generator_test.dart` (nuevo, 45 líneas) — **no documentado en sesiones anteriores, revisar su contenido cuando se retome**
- `test_init.dart` en la raíz del repo (16 líneas) — parece script de scratch/prueba del agente, candidato a borrar, pendiente de confirmar

**Todo el bloqueo técnico documentado en v3/v4 sigue vigente sin cambios:**
- Bug de triggers de sync (`clientes`, `ventas`) — confirmado como bug de producción real con evidencia de script aislado (ver v4 para el detalle completo, sin cambios esta sesión).
- Sospecha sin confirmar de que el backend de sync en Render es el backend Odoo archivado — **investigación sigue incompleta, no se avanzó en esta sesión** (esta sesión se dedicó a poner al día al agente nuevo y luego a resolver el incidente del commit accidental).
- Bloqueo de entorno Windows (`sqlite3.dll`) en `flutter test` — sigue sin resolver, confirmado que se repite también con este agente (Copilot/Gemini), no es exclusivo de un agente en particular. Recomendado seguir con el enfoque de Antigravity (scripts Dart aislados con base de datos sandbox) para evitarlo mientras no se resuelva de raíz.

### Qué falta para cerrar todo esto (orden de prioridad actualizado)

1. **Confirmar que el `git reset --soft 873cb2e` se ejecutó correctamente** y que `backend_RESPALDO_20260708` volvió a estar fuera de git — con evidencia literal, no asumir.
2. **Investigar el origen de los cambios sin explicación en `secop_service.dart` y `pila_service.dart`** — diff literal pendiente de recibir.
3. **Retomar la investigación del backend Odoo/Render** (los 8 puntos de verificación documentados en v4, sección "Investigación en curso") — sigue siendo la prioridad de fondo antes de decidir el fix del bug de sync.
4. Decidir el fix del bug de triggers de sync según lo que arroje el punto 3.
5. Confirmar que `crear_factura_integration_test.dart` pasa sus aserciones.
6. Resolver o esquivar el bloqueo de `sqlite3.dll` en Windows para poder correr la suite completa.
7. Revisar el contenido de `test/core/invoicing/xml/generator_test.dart` (no visto en detalle todavía en ningún documento de contexto).
8. Decidir si `test_init.dart` en la raíz se borra.
9. Solo entonces: recomitear el bloque XML como su propio commit limpio, con mensaje propio, y autorización explícita.

---

## Bug de triggers de sync desincronizados — resumen (sin cambios desde v4)

Confirmado como bug de producción real (no solo de tests) con evidencia de script aislado. Afecta `clientes` (7 campos fantasma) y `ventas` (6 campos fantasma, corrigiendo que `cliente_id` sí existe). Backend remoto en Render activo y respondiendo. App aún no distribuida a usuarios reales. Ver v4 para el detalle técnico completo (`_mapRemoteToLocal`, `_crearTablasYTriggersDeSincronizacion` sin try-catch, `SyncAwareDatabaseHelper` huérfano, etc.) — nada de esto cambió en esta sesión.

---

## 🚩 Sospecha sin confirmar — backend de sync podría ser el backend Odoo archivado (sin cambios desde v4, sigue pendiente)

Ver v4 para el detalle completo. Los 8 puntos de investigación (headers HTTP, rutas del backend, contenido de `SYNC_CONFIG.md`, `render.yaml`, `server.js`, rutas de `backend/src/routes/`, `git branch -a`, `git log` de los archivos de sync) siguen sin evidencia literal confirmada. **No se tocó en esta sesión** — retomar en cuanto se resuelva el incidente del commit accidental.

---

## Pendiente para una fase posterior (explícitamente pausado por decisión del usuario)

Ampliar el modelo de configuración DIAN con campos reales del proceso de habilitación. No tocar hasta que el usuario lo pida explícitamente.

---

## Fases siguientes del Plan Maestro (no iniciadas)

Después de Fase 2 (y de resolver el incidente de commit + el hallazgo de sync/Odoo): Fases 3-8 del `MerkaERP_Plan_Maestro_v4.md`.

---

## Fuera de alcance del plan de desarrollo

Certificación ISO 27001, migración de datos históricos por cliente, proceso de licitación pública. Backend Node.js/Odoo rescatado (rama `rescate-odoo-local`) — bajo sospecha activa de estar corriendo en vivo y conectado a la app. Regla de negocio: cero referencias a Odoo en la versión de mercado.

---

## Prompt sugerido para retomar en la nueva conversación

```
Estoy retomando la revisión de MerkaERP. En la sesión anterior ocurrió un incidente:
un clic accidental en el botón "Confirmación" del panel de Source Control de VS Code
enmendó (git commit --amend) un commit, fusionando dos bloques de trabajo que debían
ir separados y colando la carpeta backend_RESPALDO_20260708 (que debe estar siempre
fuera de git) como trackeada. Se acordó un plan de corrección (git reset --soft
873cb2e + git rm --cached si hace falta) pero el resultado final todavía no se había
confirmado con evidencia literal al cerrar esa sesión.

Te acabo de dar el contexto completo (v5). Lo primero que necesito, antes de cualquier
otra cosa: confirma con git log --oneline -5, git reflog -10, y git status --branch
--short el estado REAL actual del repo, y compáralo contra lo que este documento dice
que debería ser. Si hay divergencia, repórtala en detalle antes de que sigamos.

Después de eso, la prioridad de fondo sigue siendo la investigación pendiente del
backend de sync en Render (posible conexión al backend Odoo archivado, ver sección
correspondiente del documento) — eso decide cómo se arregla el bug confirmado de
triggers de sincronización.

Mismo rigor de siempre: evidencia literal, nunca aceptar trazas de comandos sin
resultados, señalar cualquier contexto no verificable.
```
