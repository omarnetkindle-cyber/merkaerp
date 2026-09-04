# MerkaERP — Bitácora de Sesión de Trabajo (Continuidad)
### Actualizado al cierre de la Fase 8 (2026-07-22)

---

## Cómo usar este documento

Este documento reemplaza y extiende `MerkaERP_Bitacora_Sesion_2026-07-22_Fase4-8.md`. Está pensado para pegarse al inicio de una conversación nueva (con Claude u otro asistente) para retomar exactamente donde quedamos, sin perder el contexto de decisiones, hallazgos de seguridad y estado real de commits.

**Metodología de trabajo establecida:** dos agentes en paralelo — un agente de IA ejecuta prompts directamente sobre el repo de MerkaERP (Flutter/Dart + SQLite), y este asistente (Claude) diseña los prompts, audita las respuestas del agente con exigencia de evidencia de código línea por línea, detecta huecos de seguridad/lógica antes de aceptar un "listo" del agente, y decide junto con el usuario cuándo hacer commit.

**Regla de oro (reconfirmada muchas veces esta sesión):** el agente reporta con optimismo por defecto ("100% Real", "0 hallazgos", "no queda ninguna pendiente"). Cada vez que se ha exigido evidencia línea por línea en vez de aceptar el resumen, han aparecido bugs reales o pasos incompletos. **No aceptar cierres de fase sin pedir esa evidencia — incluso cuando el agente ya fue corregido varias veces, sigue repitiendo el patrón de omitir cosas en los resúmenes.**

**El usuario no programa.** Claude decide el enfoque técnico, diseña los prompts exactos para el agente ejecutor, y explica los hallazgos en términos claros. El usuario aprueba/decide sobre las opciones que Claude le presenta.

---

## ⚠️ Estado de verificación de compilación — SIN CONFIRMAR

**Esto es lo más importante que debe saber quien retome esta sesión:**

Desde la Fase 3 de esta sesión, `flutter analyze` y `flutter test` (a nivel de todo el proyecto) están **suspendidos por completo**, para ahorrar tokens. Se ha trabajado toda la Fase 4 a la 8 editando código, renombrando columnas, cambiando firmas de funciones y creando servicios nuevos **sin confirmar en ningún momento que el proyecto completo compile o pase sus pruebas**.

La única excepción: el test puntual de `test/consolidacion_jerarquica_test.dart` sí se corrió de forma aislada y pasó — pero eso solo prueba que ese archivo específico funciona, no que el proyecto entero compile.

**Por lo tanto: NO se sabe si el proyecto compila hoy.** Es razonable esperar que aparezcan errores de tipo, imports faltantes o referencias rotas dado el volumen de cambios. Esto no es alarmante, es lo esperable — pero es el primer paso obligatorio de la próxima sesión, antes que cualquier otra cosa.

### Primer paso al retomar (en este orden, sin saltarse ninguno):

1. **Limpieza del proyecto** (artefactos de build + revisar bases de datos locales de desarrollo antes de compilar por primera vez).
2. **`flutter analyze`** en el proyecto completo — reportar todo sin filtrar, sin corregir todavía.
3. **`flutter test`** en el proyecto completo — reportar todo sin filtrar, sin corregir todavía.
4. Con esos dos resultados en mano, decidir el orden de corrección.
5. Solo después: intentar `flutter build` real.

---

## Estado de commits (repositorio local, sin push a GitHub)

**Nunca se ha hecho `git push`.** Todo vive en el disco local del agente. Sigue pendiente decidir si conviene hacerlo antes o después de que se confirme que el proyecto compila.

| Commit (hash corto) | Contenido | Estado |
|---|---|---|
| `ca81e21` | Fase 3 Lote 1 (último commit histórico antes de esta sesión) | Confirmado, preexistente, **nunca auditado con este nivel de exigencia** |
| `66436e9` | Fases 4 (Prompts 4.1-4.4) + 5 (auditoría UI + renombrado `fut`) + 6 (RBAC/segregación de funciones) | Confirmado |
| `ced0245` | Fase 7 (Selector de modo Comercial/Público + fix `entidadId='default'` + `AppSession.usuarioId` estricto) | Confirmado |
| `d90a951` | Hardening comercial pt.1: aislamiento tributario (13 consultas) + fail-closed `AppSession.rol` + rol reservado `sistema` | Confirmado |
| `ed3b512` | Hardening comercial pt.2: `obtenerBorradorICA`, extractos bancarios, fail-closed en `obtenerEmpresaActivaId(txn)` | Confirmado |
| `990d513...`* | Fase 8.2a: `SyncService.login()` corregido — ya no retorna `true` sin validar credenciales | Confirmado |
| `42219c9...`* | Fase 8.2b: tenencia polimórfica en motor de sync (`tenantType`/`entidadId`/`usuarioId` en `SyncEnvelope`) | Confirmado |
| `6e99221...`* | Fase 8.2c: `ConsolidacionJerarquicaService` (saldos contables + presupuestal por `gobernacion_id`) | Confirmado |

*Nota: los últimos 3 hashes largos fueron pegados por el agente con 41 caracteres en vez de 40 (un SHA-1 válido siempre tiene 40). Es un patrón repetido de error de transcripción del agente al copiar el hash, no algo que invalide los commits. **Verificar con `git log --format="%H"` limpio al retomar** — pendiente de higiene, no bloqueante.

---

## Resumen por fase

### Fases 0-3 (anteriores a esta sesión)
Preexistentes al commit `ca81e21`. **No fueron auditadas con el nivel de exigencia de esta sesión** — se dieron por buenas por ser la base histórica del proyecto. Podrían contener patrones similares a los bugs encontrados después (fallbacks silenciosos, falta de aislamiento por empresa/entidad, etc.) que nunca se revisaron con evidencia línea por línea.

### Fase 4 — Cierre de brechas de backend (Prompts 4.1 a 4.4)
Completada, commit `66436e9`. SIIF Nación, SIA Observa, FUT territorial DNP (con renombrado `fut` → `fondo_unidad_tesoreria`), SGR/OCAD/bienios, actas de responsabilidad, exportación ICA/Predial, SICODIS, facturación EPS-ADRES. FKs verificadas.

### Fase 5 — Verificación final de UI + refactor
Completada, commit `66436e9`. Auditoría de las 12 páginas de `lib/sector_publico/`: 100% conectadas. Cierre del alias legado `fut` (sin datos de producción que migrar). Grep final: 0 residuos.

### Fase 6 — RBAC y segregación de funciones
Completada, commit `66436e9`. Unificación `RolUsuario` → `RolSectorPublico` (10 roles). Fail-closed real en `obtenerRolUsuarioEnEntidad` (se corrigió un `orElse` peligroso del agente). Tests de segregación de funciones cubiertos.

### Fase 7 — Selector de modo Comercial/Público
Completada, commit `ced0245`. `SelectorModoScreen` con defensa en profundidad (UI + servicio). Bug crítico corregido: `entidadId: 'default'` hardcodeado que sí llegaba a cláusulas `WHERE`. `AppSession.usuarioId` corregido a `String?` estricto. 0 registros contaminados encontrados en 17 BDs locales inspeccionadas.

### Auditoría y hardening comercial (rama en paralelo a Fase 8)
Dos commits (`d90a951`, `ed3b512`). Hallazgos reales al exigir evidencia:
1. 15 consultas SQL tributarias/financieras sin `company_id` (mezclaban cifras entre empresas) — todas corregidas, incluyendo dos que el agente había reportado como cerradas sin estarlo (`obtenerBorradorICA`, subconsulta de `extractos_bancarios`).
2. Fail-open sin sesión (`AppSession.rol` retornaba `'consulta'` con permisos por defecto) — corregido a `null` fail-closed.
3. Rol reservado `'sistema'` (comodín, todos los permisos) protegido en 3 capas — confirmado que no hay ninguna derivación externa posible de ese rol.
4. `obtenerEmpresaActivaId(txn)` tenía un `return 1` silencioso cuando no encontraba empresa — reemplazado por `StateError` fail-closed.

### Fase 8 — Multi-usuario, sync y consolidación multi-entidad (NICSP 40) — **COMPLETA**

**8.1 — Auditoría** (sesión previa): mapeo de `SyncService`, `HybridSyncService`, `SqliteSyncRepository`, `lib/core/multi_company/`. Halló: login de sync comentado (`return true`), sync desconectado de `entidad_id`/`usuarioId`, consolidación comercial existente no aplicable al sector público, `gobernacion_id` virgen sin usar.

**8.2a — Login de sync** (commit `990d513...`): `SyncService.login()` corregido. Antes retornaba `true` incondicionalmente ante cualquier respuesta no-200 o excepción (comentario en el código: *"Temporalmente retorna true sin login"*). Ahora valida token/userId reales en la respuesta, retorna `false` en credenciales inválidas, servidor caído, o respuesta malformada. Confirmado que el único punto que lo invoca (`login_page.dart`) ya tolera el fallo sin romper la sesión local (la autenticación real de la app es local vía SQLite; la nube es sync best-effort).

**8.2b — Tenencia polimórfica en el motor de sync** (commit `42219c9...`):
- `SyncEnvelope` extendido con `tenantType` ('commercial'|'public_sector'), `entidadId` (String?), `usuarioId` (String?) — manteniendo `companyId`/`branchId` intactos por compatibilidad retroactiva.
- `SyncTenantScope` creado como resolvedor centralizado desde `AppSession`. **Se corrigió un bug que el propio agente introdujo**: puso `companyId = 1`/`branchId = 1` como defaults — mismo patrón peligroso de "valor mágico" ya visto en Fase 7 y en `obtenerEmpresaActivaId`. Corregido a parámetros requeridos, con `StateError` fail-closed en `SyncTenantScope.current()` si faltan.
- Conectado en `SalesCommandHandlers` para que los eventos comerciales transporten `usuarioId` real (antes ni siquiera el sync comercial lo hacía).
- Payload HTTP de `SyncService` hacia `installations/sync/push` extendido con los 3 campos nuevos.
- `PublicSectorSyncHelper.enqueuePublicEvent` creado para las tablas del sector público (`cdps`, `rps`, `pagos`, `asientos_contables_sp`, `proyectos_ocad` — confirmado que todas ya tienen columna `entidad_id`) — **pero NO está conectado a ningún flujo real de escritura todavía**. Es plomería lista, sin cablear.
- Confirmado con evidencia que ninguna tabla del sector público pasaba por sync antes de esta fase (sync activo = 100% comercial).

**8.2c — Consolidación jerárquica NICSP 40** (commit `6e99221...`):
- Se descubrió una contradicción en el mapeo inicial del agente (afirmó que todas las entidades comparten el mismo catálogo de cuentas sin haber revisado el campo `plan_cuentas_cgc` que sí existe por entidad) — investigada y **resuelta**: `insertarDatosSemillaCGC` siempre siembra el mismo catálogo estándar CGN al crear cualquier entidad, no hay mecanismo para taxonomías distintas. Sumar sin homologar es seguro.
- Se detectó que `NICSP40Service` existente es un servicio distinto (seguimiento de *transferencias* ejecutadas, no consolidación de *saldos*) — se decidió **no mezclarlos** y crear un servicio nuevo separado para evitar confundir ambos reportes.
- `ConsolidacionJerarquicaService` creado (solo lectura, sin ningún INSERT/UPDATE/DELETE):
  - `obtenerConsolidadoContable()`: suma `saldos_cuentas` por clase de cuenta (1-5) de una gobernación + sus municipios (vía `gobernacion_id`).
  - `obtenerConsolidadoPresupuestal()`: suma `apropiaciones`/`cdps`/`rps`/`pagos` de la misma jerarquía.
  - Fail-closed: `StateError` si la entidad padre no existe o no tiene hijas — nunca un consolidado vacío en silencio.
  - Documentado explícitamente en el docstring de la clase y en la UI que **NO elimina operaciones recíprocas** (transferencias gobernación↔municipio pueden aparecer duplicadas).
- Conectado visiblemente en `TransparenciaPage`: nueva sección rotulada "Consolidado de Saldos Contables (Gobernación + Entidades Adscritas)", separada de la sección existente de NICSP40 (transferencias), con aviso de la limitación visible para el usuario final, no solo en el código.
- 2 tests unitarios escritos y corridos (`flutter test test/consolidacion_jerarquica_test.dart`), ambos pasaron.

---

## Pendiente explícito para la semana de análisis (documentado, no improvisado)

1. **Confirmar que el proyecto compila** — ver sección de arriba, es la prioridad #1 al retomar.
2. **`PublicSectorSyncHelper.enqueuePublicEvent`** no está conectado a ningún flujo real de escritura (CDP/RP/pagos/asientos). Falta cablearlo a los servicios que crean/modifican esos registros.
3. **Backend en Render/PostgreSQL** no tiene endpoints ni tablas espejo para recibir eventos con `tenantType='public_sector'` — trabajo del lado servidor, fuera del alcance del repo Flutter.
4. **Eliminación de operaciones recíprocas** en la consolidación jerárquica — decidido explícitamente fuera de alcance por ahora.
5. **Decisión de arquitectura pendiente**: si `HybridSyncService` (SQLite↔PostgreSQL directo, lista hardcodeada de tablas comerciales) debe extenderse al sector público, o si el sector público debe ir exclusivamente por event-sourcing (`SyncService`/`SqliteSyncRepository`). El agente ya recomendó (con justificación normativa: Ley 1474, trazabilidad de autoría) usar solo event-sourcing — falta decisión final del usuario.
6. **Verificar hashes largos** con formato de 41 caracteres (`git log --format="%H"` limpio).
7. **Auditar Fases 0-3** (preexistentes, nunca revisadas con este nivel de exigencia) si el tiempo lo permite — podrían tener patrones similares a los bugs ya encontrados.
8. **Evaluar `git push`** — nunca se ha hecho, sigue pendiente decidir cuándo.
9. Al cerrar todo lo anterior: limpiar `CHANGELOG_TECNICO.md` acumulado y considerar reactivar `flutter analyze`/`flutter test` de forma permanente (ya no suspendida) dado que fueron la causa de haber acumulado tantos cambios sin verificar.

---

## Trabajo futuro acordado — Fase 9 (CRM/HRM/MRP)

El usuario aportó `MerkaERP_Modulos_CRM_HRM_MRP_v1.md`: especificación clean-room de 3 módulos nuevos (CRM inspirado en SuiteCRM, HRM en OrangeHRM, MRP en ERPNext), con prompts ya redactados (Prompt 0 arranque + Prompt 1 CRM + Prompt 2 HRM + Prompt 3 MRP + Prompt 4 cierre).

**Decisión tomada:** implementar **después de cerrar la Fase 8 y confirmar que el proyecto compila**, no antes ni en paralelo. Razones que siguen vigentes:
- HRM propone `hrm_employee`, que puede chocar conceptualmente con `empleados_sp` (nómina sector público), igual que pasó con `fut` — mejor decidir esa relación con la Fase 8 ya asentada y verificada.
- MRP depende de `stock`, que la consolidación multi-entidad de Fase 8 pudo haber tocado indirectamente.
- No conviene meter módulos nuevos sobre una base que todavía no se ha confirmado que compile.

**Meta explícita del usuario:** al terminar todo (Plan Maestro + CRM/HRM/MRP), el sistema debe quedar "listo para el mercado" — funcional tanto en comercial como en sector público.

---

## Próximos pasos inmediatos al retomar (en orden)

1. Pegar este documento al inicio de la conversación nueva.
2. Limpieza del proyecto (artefactos de build + revisar, sin borrar sin confirmar, bases de datos SQLite locales de desarrollo).
3. `flutter analyze` en el proyecto completo — reportar todo sin filtrar.
4. `flutter test` en el proyecto completo — reportar todo sin filtrar.
5. Con esos resultados, decidir y ejecutar el orden de corrección de errores (si los hay).
6. `flutter build` real para confirmar que compila.
7. Solo después de tener el proyecto compilando limpio: abordar los pendientes de Fase 8 (lista arriba) en el orden sugerido — primero la decisión de arquitectura de `HybridSyncService`, luego el cableado del helper público; el trabajo de backend queda fuera del alcance de este asistente.
8. Evaluar `git push`.
9. Solo después de todo lo anterior: arrancar Fase 9 (CRM/HRM/MRP).
