# MerkaERP — Bitácora de Sesión de Trabajo (Continuidad)
### Actualizado al cierre del último prompt enviado (auditoría/hardening comercial, pendiente confirmación de commit)

---

## Cómo usar este documento

Este documento reemplaza y extiende `MerkaERP_Transcripcion_Sesion_2026-07-2X_Fase3-4.md`. Está pensado para pegarse al inicio de una conversación nueva (con Claude u otro asistente) para retomar exactamente donde quedamos, sin perder el contexto de decisiones, hallazgos de seguridad y estado real de commits.

**Metodología de trabajo establecida:** dos agentes en paralelo — un agente de IA ejecuta prompts directamente sobre el repo de MerkaERP (Flutter/Dart + SQLite), y este asistente (Claude) diseña los prompts, audita las respuestas del agente con exigencia de evidencia de código, detecta huecos de seguridad/lógica antes de aceptar un "listo" del agente, y decide junto con el usuario cuándo hacer commit. `flutter analyze`/`flutter test` están **suspendidos** temporalmente por consumo de tokens en la Fase 3; todo se documenta en `CHANGELOG_TECNICO.md` para una corrida final en bloque al cierre del plan.

**Regla de oro:** el agente reporta con optimismo por defecto ("100% Real", "0 hallazgos"). Cada vez que hemos exigido evidencia línea por línea en vez de aceptar el resumen, han aparecido bugs reales (ver tabla de hallazgos abajo). No aceptar cierres de fase sin pedir esa evidencia.

---

## Estado de commits (repositorio local, sin push a GitHub)

| Commit (hash corto) | Contenido | Estado |
|---|---|---|
| `ca81e21` | Fase 3 Lote 1 (último commit histórico antes de esta sesión) | Confirmado, preexistente |
| `66436e9` | Fases 4 (Prompts 4.1-4.4) + 5 (auditoría UI + renombrado `fut`) + 6 (RBAC/segregación de funciones) consolidadas en un solo commit | Confirmado, 60 archivos, +8543/-835 |
| `ced0245` | Fase 7 (Selector de modo Comercial/Público + fix crítico `entidadId='default'` + `AppSession.usuarioId` estricto) | Confirmado, 8 archivos, +648/-94 |
| *(pendiente)* | Hardening comercial (aislamiento tributario `company_id` + fail-closed `AppSession.rol` + rol reservado `sistema`) | **Prompt de commit ya enviado al agente, hash aún no confirmado** — este es el primer paso a retomar |

**Nunca se ha hecho `git push`.** Todo vive en el disco local del agente. Se sugirió evaluar un push antes de entrar de lleno a la Fase 8 (la de mayor riesgo del plan), pero no se ha decidido ni ejecutado.

---

## Resumen por fase

### Fase 4 — Cierre de brechas de backend (Prompts 4.1 a 4.4)
Completada e incluida en el commit `66436e9`.
- **4.1** SIIF Nación y SIA Observa.
- **4.2** FUT territorial DNP real + renombrado preventivo `fut.dart`/`fut_service.dart` → `fondo_unidad_tesoreria` (para no confundir con el FUT normativo DNP). *(La tabla física SQLite quedó con el alias legado `fut` hasta que se cerró explícitamente en la Fase 5, ver abajo.)*
- **4.3** SGR completo: OCAD, bienios presupuestales, reporte SPGR, vinculado al Banco de Proyectos MGA. Verificado: FKs `proyectos_mga`/`entidades_territoriales` válidas, filtro `entidad_id` correcto en el dropdown de MGA.
- **4.4** Brechas menores: actas de responsabilidad (activos), exportación ICA/Predial, reporte SICODIS, facturación EPS-ADRES (salud). Verificado: FK `actas_responsabilidad.funcionario_id → empleados_sp(id)` válida (tabla nómina).

### Fase 5 — Verificación final de UI + refactor
Completada e incluida en el commit `66436e9`.
- Auditoría de las 12 páginas de `lib/sector_publico/`: confirmadas 100% conectadas (formulario real, servicio, persistencia, listas, bloqueo normativo).
- Barrido completo de las 16 FKs introducidas en Fase 4: todas válidas contra tabla/columna real.
- **Decisión y cierre del alias legado `fut`:** se confirmó que no había datos de producción que proteger (todo desarrollo/testing) → se renombró la tabla física SQLite `fut` → `fondo_unidad_tesoreria`, con índices coherentes y regeneración de schema (sin `ALTER TABLE` porque no había datos reales que migrar).
- Grep final: 0 residuos de imports/nombres viejos.

### Fase 6 — RBAC y segregación de funciones (requisito legal)
Completada e incluida en el commit `66436e9`.
- **Auditoría inicial (Prompt 6.1)** encontró: `RolSectorPublico` (10 roles normativos, con matriz de permisos y negaciones ya diseñada en `roles_permisos_service.dart`) vs. `RolUsuario` (4 roles, obsoleto, en `mfa_service.dart`) — **dos fuentes de verdad duplicadas**. También encontró que ningún servicio validaba roles todavía (cualquier usuario autenticado podía hacer cualquier cosa), y que no existía vínculo entre `usuarios.id` (login comercial, INTEGER) y `funcionarios_entidad` (sector público, TEXT/UUID).
- **Implementación (Prompt 6.2):**
  - Unificado `RolUsuario` → `RolSectorPublico` (10 roles).
  - Agregada columna `funcionarios_entidad.usuario_id` con índices.
  - `RolesPermisosService.obtenerRolUsuarioEnEntidad`: **fail-closed real** — retorna `null` si no hay match único (0 o >1 resultados), nunca un rol por defecto con permisos (se corrigió una primera versión del agente que sí tenía ese fallback peligroso, `orElse: () => ordenadorGasto`).
  - Conectado en presupuesto (CDP/RP/obligación/pago), PAC/tesorería, contabilidad (asientos/reversas), rentas (predial/ICA), auditoría forense (CHIP, SIA Observa, FUT territorial, SIIF) — con verificación explícita de que los 4 servicios de auditoría **no tienen métodos de escritura en tablas operativas**, solo en sus propias tablas de reportes (por eso `jefeControlInterno` sí puede generar sus reportes sin violar el perfil de solo lectura).
  - Tests cubriendo: tesorero no aprueba su propio pago, contador no ejecuta pagos, control interno no escribe en módulos operativos, usuario sin rol vinculado queda bloqueado.

### Fase 7 — Selector de modo Comercial/Público
Completada e incluida en el commit `ced0245`.
- `SelectorModoScreen` con Navigator 1.0, auto-skip si `tipo_entidad` ya está determinado.
- Reconfiguración manual restringida por rol: `alcaldeRepresentanteLegal` + `secretarioHacienda` (justificado normativamente: Ley 136/1994, Ley 617/2000, Decreto 111/1996 EOP) en sector público, `administrador` en comercial.
- **Defensa en profundidad:** botón oculto preventivamente en UI (`FutureBuilder` + `tieneAutoridadReconfiguracion`) + bloqueo fail-closed en el servicio como respaldo (no reemplazo).
- **Bug crítico encontrado y corregido:** `entidadId: 'default'` hardcodeado en `public_sector_config.dart` (la fábrica que instancia las 10 páginas del sector público) — **sí llegaba hasta las cláusulas `WHERE entidad_id = ?`** en presupuesto, contabilidad y rentas, confirmado con evidencia de código. Corregido usando `AppSession.entidadId` real.
- **Segundo bug relacionado:** `AppSession.usuarioId` tenía una cadena de fallback ambigua (`id ?? usuario ?? nombre`) y retornaba `'1'` por defecto sin sesión — corregido a `String?` estricto: `null` = sin sesión = acceso denegado en todos los consumidores.
- Auditoría de datos: **0 registros contaminados** con `entidad_id='default'` en las 17 bases de datos locales inspeccionadas (los tests usaban entidades explícitas tipo `'ENT-001'`, nunca pasaban por el código de UI afectado).

### Auditoría y hardening comercial (rama de trabajo en paralelo a Fase 8, no forma parte del Plan Maestro original)
El usuario preguntó si nos estábamos enfocando solo en sector público (el Plan Maestro v4 nació de una auditoría que encontró la UI de sector público 100% decorativa; el comercial se asumía funcional por ser la base preexistente del producto, sin el mismo hallazgo). Se decidió auditar el lado comercial antes de seguir con Fase 8, aprovechando que la Fase 8 iba a tocar `lib/core/multi_company/` (código comercial) de todas formas.
- **Primera pasada (23 módulos comerciales)**: reportada como "100% Real" en todos — se exigió evidencia línea por línea antes de aceptarlo, dado el patrón de la conversación.
- **Hallazgos reales al pedir evidencia exhaustiva:**
  1. **7 consultas SQL de resumen tributario** (`obtenerReporteFiscal`, `obtenerBorradorICA`, `_calcularValorRealPresupuesto` en `db_helper.dart`) filtraban solo por fecha, **sin `company_id`** — mezclaban cifras de ventas/compras/IVA/retenciones entre empresas distintas en la misma instalación. Riesgo real: declaraciones tributarias (IVA F.300, Retefuente F.350, ReteICA) contaminadas entre empresas. **Corregido.**
  2. **Fail-open sin sesión**: `AppSession.rol` retornaba `'consulta'` por defecto sin usuario autenticado, y el rol `'consulta'` tenía permiso `view`/`export` en todos los módulos (`moduleId: '*'`) — cualquiera podía consultar/exportar datos sin login. **Corregido**: `AppSession.rol` retorna `null` sin sesión; `PermissionService.can` deniega explícitamente con rol `null`/vacío.
  3. **Puerta trasera potencial en el fix**: al introducir un rol `'sistema'` (comodín, todas las acciones, para procesos batch/sync) se detectó que no había ninguna validación que impidiera asignar ese rol a un usuario humano real vía formulario o BD directa. **Corregido con defensa en 3 capas**: `AppSession.rol` ignora `'sistema'` si viene de una sesión humana autenticada (retorna `null`), `guardarUsuario`/`actualizarUsuario` lanzan `ArgumentError` si se intenta asignar `'sistema'`, y el formulario de usuarios no lo lista como opción.
  4. Se confirmó explícitamente que ningún otro fallback de rol con permisos existe en el resto del código (grep exhaustivo), y que los procesos de sync (`sync_service.dart`, `hybrid_sync_service.dart`) operan a nivel de BD directo sin pasar por `AppSession`, por lo que no se rompieron con el fail-closed.
- Tests en `test/commercial_security_test.dart` cubriendo los 5 escenarios.
- **Pendiente:** confirmar hash del commit de este hardening (prompt ya enviado, respuesta no recibida todavía).

### Fase 8 — Multi-usuario, sync y consolidación multi-entidad (NICSP 40) — EN CURSO, máximo riesgo del plan
Solo se completó el **Prompt 8.1 (auditoría)**, sin escribir código todavía — así lo exige el propio Plan Maestro ("no empezarla hasta que las fases 0-7 estén sólidas").

**Hallazgos de la auditoría 8.1:**
- **Sync/multi-usuario** (`lib/sync/`, `lib/services/sync_service.dart`, `hybrid_sync_service.dart`): arquitectura híbrida offline-first — `SyncService` usa HTTP por lotes contra un backend en Render (`merkaerp-control-center-backend`), con colas locales (`sync_outbox`, `sync_inbox`, `sync_conflicts`); `HybridSyncService` sincroniza SQLite↔PostgreSQL directo; `SqliteSyncRepository` implementa event-sourcing con relojes vectoriales e idempotencia. **Bug/brecha encontrada:** el `login()` de `sync_service.dart` tiene la validación de credenciales del servidor **comentada** (`return true; // Temporalmente retorna true sin login`), y el mecanismo de sync usa `company_id`/`branch_id` (INTEGER, comercial) completamente desconectado de `entidad_id` (TEXT, sector público) y de `AppSession.entidadId`/`usuarioId` que quedaron firmes en la Fase 7.
- **Consolidación multi-entidad**: `lib/core/multi_company/` (`FinancialConsolidationService`, `CompanyTransferService`) es **puramente multi-sucursal comercial** — suma algebraica simple (`SUM(...)` filtrado por `company_id`), sin eliminación de operaciones recíprocas ni homologación de plan de cuentas (CGC/NICSP). **Buena noticia:** `entidades_territoriales` (`schema_multi_tenant.dart`) **ya tiene la columna `gobernacion_id`** con FK a sí misma para modelar jerarquía padre-hijo — pero está 100% virgen, ningún servicio la usa todavía.

**Decisión pendiente (no tomada aún):** el alcance exacto del Prompt 8.2, que debe cubrir como mínimo:
1. Corregir o decidir qué hacer con el `login()` comentado de `sync_service.dart` antes de construir nada encima.
2. Diseñar cómo el motor de sync va a transportar `entidad_id`/`AppSession.usuarioId` (hoy no lo hace).
3. Construir el servicio de consolidación jerárquica NICSP 40 aprovechando `gobernacion_id` (vista de solo lectura de la entidad padre sobre sus hijas, eliminación de operaciones recíprocas, validación de plan de cuentas homologado) — reutilizando o no `lib/core/multi_company/` según se decida.

---

## Trabajo futuro acordado (fuera del Plan Maestro original, decidido en esta sesión)

El usuario aportó un documento nuevo (`MerkaERP_Modulos_CRM_HRM_MRP_v1.md`) con especificación clean-room de 3 módulos nuevos (CRM inspirado en SuiteCRM, HRM en OrangeHRM, MRP en ERPNext), con prompts ya redactados (Prompt 0 arranque + Prompt 1 CRM + Prompt 2 HRM + Prompt 3 MRP + Prompt 4 cierre), pensados para complementar/reusar módulos existentes (`stock`, `sale`, `contacts`), no reconstruir desde cero.

**Decisión tomada:** implementar esto **después de cerrar la Fase 8 completa**, no antes ni en paralelo. Razones:
- HRM propone `hrm_employee`, que puede chocar conceptualmente con `empleados_sp` (nómina sector público) igual que pasó con `fut` — mejor decidir esa relación una vez que la Fase 8 defina la forma final de la jerarquía multi-entidad.
- MRP depende de `stock`, que puede cambiar de forma con la consolidación multi-entidad de la Fase 8.
- La Fase 8 es la de mayor riesgo del plan; no conviene meter módulos nuevos en medio.

**Meta explícita del usuario:** al terminar todo esto (Plan Maestro completo + CRM/HRM/MRP), el sistema debe quedar "listo para el mercado" — funcional tanto en comercial como en sector público. Esto fue lo que disparó la decisión de auditar también el lado comercial (ver arriba), no solo el público.

---

## Próximos pasos inmediatos al retomar

1. Confirmar el hash del commit de hardening comercial (prompt ya enviado, pendiente respuesta del agente).
2. Decidir con el usuario el alcance final del Prompt 8.2 (consolidación NICSP 40 + qué hacer con el login comentado de sync + cómo conectar entidad_id/usuarioId al motor de sync).
3. Ejecutar Fase 8 completa con el mismo nivel de exigencia de evidencia que se ha mantenido toda la sesión.
4. Evaluar si conviene un `git push` antes o después de la Fase 8.
5. Al cerrar Fase 8: retomar el documento de CRM/HRM/MRP como "Fase 9" del plan.
6. Al cerrar todo: correr `flutter analyze`/`flutter test` en bloque (suspendidos desde la Fase 3) y limpiar lo acumulado en `CHANGELOG_TECNICO.md`.
