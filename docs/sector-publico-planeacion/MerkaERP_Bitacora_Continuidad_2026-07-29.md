# MerkaERP — Bitácora de Continuidad
### Consolidado al cierre de la sesión del 2026-07-29. Cambio de agente ejecutor: de GitHub Copilot / Kiro a Codex 5.6 "Terra" (esfuerzo alto).

---

## Cómo usar este documento

Pegar al inicio de una conversación nueva con Codex. Este documento reemplaza y extiende todas las bitácoras anteriores (`MerkaERP_Bitacora_Diagnostico_Compilacion_2026-07-22.md`, `MerkaERP_Bitacora_Sesion_2026-07-22_Fase8_Cierre.md`, `MerkaERP_Bitacora_Sesion_2026-07-22_Fase4-8.md`), que siguen siendo válidas como historial pero ya no reflejan el estado actual.

**Metodología de trabajo establecida (sin cambios, aplícala desde el primer prompt):** Claude (el asistente de chat) diseña los prompts, audita las respuestas del agente ejecutor con exigencia de evidencia línea por línea, no acepta resúmenes optimistas sin verificar, y decide junto con el usuario (Omar) cuándo hacer commit. **El usuario no programa** — Claude decide el enfoque técnico y explica en términos claros. Omar aprueba/decide sobre las opciones que Claude le presenta.

**Regla de oro (reconfirmada muchísimas veces esta sesión):** el agente ejecutor reporta con optimismo por defecto. Cada vez que se exigió evidencia línea por línea en vez de aceptar un "listo"/"0 errores"/"ALL CLEAR" sin verificar, aparecieron bugs reales. Ejemplos concretos de esta sesión: un `flutter analyze` que resultó estar leyendo caché de un proceso viejo (mostraba los mismos 8 errores que ya se habían corregido), un commit con +54.045 inserciones que casi se acepta sin investigar (resultó ser ruido de EOL, pero solo se supo verificando), y un script de reemplazo automático que corrompió `workspace_widgets.dart` a 8.716 issues sin que el agente lo notara hasta que se le pidió explícitamente comparar conteos de líneas antes/después.

**Nunca aceptar "ALL CLEAR" o "0 errores" sin ver la salida cruda del comando, leída de un archivo, no del eco de una terminal.** Esta sesión tuvo problemas recurrentes de terminal PowerShell devolviendo salida corrupta/repetida — el patrón que funcionó fue escribir la salida a un `.txt` y leerlo con la herramienta de lectura de archivos, nunca confiar en el eco directo.

---

## ⚠️ Bloqueador activo al cierre de esta sesión — resolver primero

**Kiro (el agente anterior) dejó de poder ejecutar operaciones de escritura/destructivas** (`git add`, `git commit`, `fs_write`, `Remove-Item`, incluso `flutter analyze > archivo.txt`) a pesar de estar configurado en modo "Autopilot". Las operaciones de solo lectura (`git status`, `execute_pwsh` con comandos no destructivos) sí funcionaban. El patrón sugiere una capa de aprobación separada del modo general, específica para comandos de escritura/git/borrado — no se resolvió durante la sesión.

**Si Codex tiene el mismo problema:** el flujo de respaldo que funcionó fue que Omar ejecute los comandos exactos en su propia terminal de PowerShell (Codex/Claude los prepara, Omar los pega y ejecuta, reporta el resultado). No es ideal pero es confiable.

**Último comando pendiente de confirmar cuando se resuelva el bloqueo:**
```powershell
cd C:\Users\PC\Desktop\Caja_simple
flutter analyze > analyze_output.txt 2>&1
```
Esto se lanzó justo antes de cerrar la sesión, para confirmar el conteo de `flutter analyze` después de borrar 23 archivos de código muerto. **El resultado de este comando es el primer paso al retomar.**

---

## Qué es MerkaERP (para quien no tenga el contexto de negocio)

ERP en Flutter/Dart + SQLite (offline-first), originalmente comercial (ventas/POS, inventario, contabilidad, nómina, banca), al que se le agregó un módulo completo de **Sector Público** para alcaldías, gobernaciones y hospitales públicos colombianos (ESE), con cumplimiento normativo real (NICSP, presupuesto público, Ley 80, segregación de funciones, auditoría). El objetivo de negocio explícito de Omar es dejar el sistema **"listo para el mercado"**.

Existe un documento de referencia mucho más ambicioso (`PROMPT_MAESTRO_MerkaERP_SectorPublico.md` + `MerkaERP_SectorPublico_Plan_v1_1.md`, ambos subidos por Omar) que describe un roadmap formal de **12 fases (Fase 0 a Fase 11)**, cada una de 6-8 semanas, con alcance mucho mayor (SECOP II real, PILA, RIPS, módulo disciplinario, motor de intereses moratorios exacto, ISO 27001). **Decisión pendiente, nunca cerrada:** si ese plan reemplaza el trabajo incremental que se ha venido haciendo o si es una referencia aparte. Los "Fase 4" que aparecen en el código actual (banners de "pendiente para Fase 4") son de la numeración informal de las bitácoras anteriores, **no** de este Plan Maestro — son sistemas de numeración distintos, no los confundas.

---

## Arquitectura — resumen para orientarse rápido

- **11 macro-sistemas** del sector público: Planeación/Proyectos, Financiero (Presupuesto/Contabilidad/Tesorería), Rentas y Tributos, Contratación Pública, Nómina Pública, Almacén y Activos, Trazabilidad/Rendición de Cuentas, Salud Pública, SGR (Regalías), SGP (Participaciones), Transparencia.
- **Patrón por capas** en cada módulo: `lib/sector_publico/<área>/{database,models,services,pages}/`.
- **Aislamiento de datos:** comercial usa `company_id` (INTEGER), sector público usa `entidad_id` (TEXT/UUID) vía `entidades_territoriales`. Son mecanismos paralelos — vigilar siempre que no se cuele un valor mágico tipo `'default'` o `1` (ya pasó varias veces en el histórico del proyecto, es EL bug estructural más recurrente).
- **RBAC de sector público:** 10 roles normativos (`RolSectorPublico`) con segregación de funciones dura (tesorero no aprueba su propio pago, contador no expide CDP, etc.), gestionado por `RolesPermisosService`/`obtenerRolUsuarioEnEntidad` — fail-closed real.
- **Selector de modo Comercial/Público:** `SelectorModoScreen`, con auto-skip si el tipo de entidad ya está determinado.

---

## Estado de commits — todo respaldado en GitHub, sin excepción

**Repo:** `https://github.com/omarnetcom-hub/mera-erp.git`, rama `main`. Al cierre de esta sesión: `origin/main` está sincronizado hasta el commit `2a17024` (push confirmado). Los 23 borrados de código muerto de la última ronda **están en el working directory pero NO comiteados todavía** — eso es lo primero que hay que cerrar al retomar.

**Historial relevante de esta sesión (más reciente primero):**
| Commit | Contenido |
|---|---|
| *(sin commitear)* | 23 archivos de código muerto borrados (Grupo A + B) — ver sección "Limpieza de código" |
| `2a17024` | Fix `LateInitializationError` en Contratación + `auditoriaService: null` real en Presupuesto |
| `8e6004a` | Limpieza de ~163MB de artefactos innecesarios del repo (Output/, installers/, .codex/, residuos NexoPyme) |
| `458d2c0` | Toggle manual online/offline en `LicenseActivationPage` (SegmentedButton) |
| `133849b` | Fix definitivo de contraste de botones (foregroundColor:Colors.white) en 15+ archivos, tras varios intentos fallidos con scripts que corrompieron sintaxis |
| `a97a0f0` | Fix `regalias_sgp_page.dart` (segunda vez — hubo una regresión real, ver más abajo) |
| `8e2517e` | Sesión grande: nullability (causa raíz #2), migración `apropiaciones.vigencia`, ReteICA con reglas por empresa, formato moneda/tema/fechas en 12 páginas, guard división por cero, selector de modo público (3 pestañas), RBAC conectado, onboarding conectado al arranque |
| `ced0245`, `d90a951`, `ed3b512`, `990d513`, `42219c9`, `6e99221` | Fases 7 y 8 (histórico, confirmado real vía `git reflog` tras un susto de "trabajo perdido" que resultó ser solo falta de commit, no pérdida real) |
| `66436e9` | Fases 4-6 (histórico) |

**Importante — susto de "trabajo perdido" ya resuelto:** en un punto de esta sesión pareció que semanas de trabajo se habían perdido (`regalias_sgp_page.dart` volvió a tener bugs ya corregidos). Se investigó a fondo con `git reflog`, `git fsck`, comparación de fechas de archivos — **nada se perdió**. Fue un error puntual de una sesión con reinicios de contexto que sobrescribió sin querer un archivo. La lección: **nunca se ha perdido trabajo real en este proyecto**, pero **si llevaba semanas sin hacerse push**, ya se corrigió — ahora se empuja a GitHub después de cada ronda de cambios significativa, no se deja acumular.

---

## Lo que se corrigió esta sesión (para no repetir investigación)

### Compilación (bloqueaba todo, ya resuelto)
- **Causa raíz #1:** 7 archivos de test con import de paquete viejo (`caja_simple` en vez de `merka_erp`) — corregido.
- **Causa raíz #2:** 23 sitios de nullability en `public_sector_config.dart`/`erp_readiness_page.dart` por `AppSession.usuarioId`/`rol` vueltos `String?` (fail-closed intencional) sin propagar a consumidores — corregido con manejo explícito de `null`, sin usar `!` a la ligera.
- **`apropiaciones.vigencia`:** columna faltante en una ruta de creación de esquema. Causa real: BD persistente de test (`merka_erp_test_fresco.db`) nunca se borraba entre corridas, y `CREATE TABLE IF NOT EXISTS` no repara tablas viejas. Se agregó migración defensiva (verifica con `PRAGMA table_info`, solo agrega la columna si la tabla está vacía, nunca inventa datos en filas existentes).
- **ReteICA/Retefuente en ventas:** se aplicaba automáticamente a toda venta sin verificar si la empresa está designada autorretenedora ni si supera base mínima — corregido para depender de `reglas_retenciones_empresa` (por empresa, no por el flag `autorretenedor` del cliente, que es un concepto distinto).
- **`regalias_sgp_page.dart`:** desalineada con sus propios modelos (`TipoRegalia.directa` no existe, `TipoParticipacionSGP` debía ser `TipoParticipacion`, parámetros `numeroRegalia`/`numeroSGP` que el servicio genera internamente). Corregido dos veces (hubo una regresión real, ver arriba) — **confirmar que sigue bien al retomar**, es el archivo más frágil de la sesión.
- **Primera compilación Windows exitosa** lograda tras resolver lo anterior — el bloqueador del build en sí (`MSB8066`) no era de toolchain de Visual Studio, era un `flutter_tester.exe` colgado reteniendo archivos — **si un build falla igual, revisar procesos Dart/Flutter colgados antes que nada más**.

### Visual / UX (ronda grande, con varios incidentes de scripts automáticos)
- Formato de dinero: 118 sitios sin separador de miles → `CurrencyFormatter` centralizado (`lib/core/utils/currency_formatter.dart`).
- Modo oscuro roto en las 12 páginas del sector público (colores hardcodeados) → migrados a `Theme.of(context)`/`AppTheme`.
- Fechas en formato ISO crudo → `DateFormatter` centralizado, locale `es_CO`.
- Guard de división por cero en el Chip de porcentaje de Presupuesto.
- **Botones con texto invisible** (mismo color que el fondo) — bug real y extendido, apareció en 15+ archivos. **Cuidado con este archivo si se vuelve a tocar:** se intentó resolver con scripts de regex/sed automatizados y hubo **corrupción de sintaxis real** en más de una ocasión (una vez llegó a 8.716 issues por un script que confundió `ElevatedButton.styleFrom` con cualquier `.copyWith`/`style:` del archivo). La solución final funcionó con reemplazo de texto exacto, verificado con un detector de patrones Python que comprobaba sintaxis válida antes de aceptar, y comparación de conteo de líneas antes/después para descartar contenido duplicado. **Si hay que tocar más botones, no automatizar con regex masivo — uno por uno con reemplazo exacto.**
- **Reconstrucción del "main"** para que el sector público no comparta pestañas comerciales: la barra superior (`_WorkspaceModeSelector`) mostraba siempre Dashboard/Ventas/Operaciones/Finanzas sin importar el tipo de entidad. Se agregaron 3 pestañas propias para sector público (Ejecución Presupuestal / Cumplimiento y Alertas / Transparencia), con paneles reales conectados a datos de SQLite.
- **RBAC del menú principal:** `AppSession.puedeAbrirModulo()` usaba `PermissionService` (matriz 100% comercial, sin ningún rol/módulo del sector público) — por eso cualquier clic en un módulo público fallaba silenciosamente salvo para rol `administrador`/`sistema`. Se conectó a `RolesPermisosService` para módulos del sector público, dejando intacto el camino comercial.
- **Alias de menú sin distinción real:** PILA/Horas Extra/Nómina Pública, MGA/PDT/Planeación, SECOP II/Interventoría/Contratación apuntaban todos genéricamente a la misma página sin indicar pestaña. Se cablearon las tabs reales que sí existen (NominaPublicaPage tiene tab PILA, ContratacionPublicaPage tiene tab SECOP II); donde NO existe tab real (Horas Extra, Interventoría), **no se inventó nada** — quedó anotado como pendiente. `FUT` (mal enrutado bajo Activos) se corrigió para apuntar a `AuditoriaForensePage`/`FUTTerritorialService`.
- **Onboarding conectado al arranque:** `OnboardingPage` se importaba en `main.dart` pero nunca se invocaba. Flujo corregido: `app start → Onboarding (si !onboarding_completed) → LicenseCheckWrapper → Login → SelectorModo (si no configurado) → MenuPrincipal`.
- **Bugs adicionales encontrados por capturas de pantalla reales** (Omar las subió directo al chat, mejor método que descripciones): `NotInitializedError` crudo mostrado al usuario en Rentas/SECOP II, y un crash real de SQL inválido (`GROUP BY mes 1` en vez de `GROUP BY mes`) en el servicio de PAC — ambos corregidos.
- **`NotInitializedError` — causa raíz real (no solo el mensaje):** en `contratacion_publica_page.dart`, `_contratacionService`/`_secopService` eran `late` sin protección — si `_inicializarServicios()` fallaba antes de la asignación, cualquier interacción posterior lanzaba `LateInitializationError`. Corregido a nullable con null-guards en todos los call-sites.
- **`auditoriaService: null` en Presupuesto:** deuda técnica pura, no un gap de diseño — `AuditoriaService` solo necesitaba `db`, igual que otras páginas. Corregido a instancia real. Confirmado que era el único caso en todo el sector público.

### Licencias / Control Center (investigación profunda, sin gaps reales encontrados)
- Toggle manual online/offline en `LicenseActivationPage` (antes dependía 100% de detección automática de conectividad, sin control manual).
- **Investigación del backend real:** existían dos copias de backend — una vieja/abandonada dentro de `Caja_simple/backend/` (SQLite, rutas separadas) y la real desplegada en Render (`Merka_Control_Center/backend/src/server.js`, monolítico, PostgreSQL real vía `DATABASE_URL`). Se confirmó con pruebas HTTP reales (POST correcto, no GET) que **las 4 rutas clave existen y funcionan**: `/api/v1/licenses/activate`, `/api/v1/auth/login`, `/api/v1/data/push`, `/api/v1/data/pull`.
- Se descartó una hipótesis de "falta un campo `schema` en el JWT" — el código real confirma que el `schema` de PostgreSQL se deriva de `client_id` (que sí está en el token), no requiere campo adicional.
- **Pendiente real, no urgente:** `LicenseValidationService` tiene una clave pública RSA placeholder (`[GENERAR DESDE CONTROL CENTER Y PEGAR AQUÍ]`) — cualquier JWT con estructura correcta pasa la verificación offline hoy. Hay que cerrarlo antes de vender a clientes reales.
- **`SyncService` confirmado código muerto** — sus rutas (`/api/v1/installations/sync/*`) no existen en ningún backend real. `HybridSyncService`/`PostgresService` sí usa las rutas correctas (`/api/v1/data/*`) y es el que está realmente activo.
- **Gap real pendiente:** el backend solo sincroniza tablas comerciales (`ALLOWED_TABLES = ['productos', 'clientes', 'ventas', 'venta_items']`) — ninguna tabla del sector público está en la lista blanca. Arreglar esto requiere tocar el backend real (vive en el proyecto `Merka_Control_Center`, no en `Caja_simple`) y probablemente crear las tablas en el schema de PostgreSQL por cliente.

### Limpieza de disco y código
- **~163 MB liberados dentro del repo** (commiteado): `Output/`, `installers/`, `.codex/`, residuos de NexoPyme (`nexopyme_home.png`, `nexopyme_ui.xml`), documentación generada por IA obsoleta. `backend_RESPALDO_20260708/` también borrado del disco (nunca estuvo en git, confirmado que no tenía nada que `backend/` no tuviera ya).
- **~3.5 GB movidos a papelera temporal fuera del repo** (`C:\Users\PC\Desktop\_PAPELERA_MERKAERP_BORRAR\`) — builds/rars viejos del Desktop, 7 bases de datos SQLite de pruebas antiguas en `Documents\`. **NO se borró definitivamente** — Omar debe confirmar manualmente que todo sigue funcionando (usar la app un rato) antes de vaciar esa papelera y recuperar el espacio de verdad.
- **23 archivos de código muerto borrados** (sin comitear todavía, ver bloqueador de arriba): legacy claro (`shopify_service.dart`, `woocommerce_service.dart`, `portal_service.dart`, `blind_close_screen.dart`, `dynamic_report_screen.dart`, `premium_module_host.dart`, `template_editor_screen.dart`, `saas_admin_page.dart`, `enterprise_operations_service.dart`, `enterprise_accounting_policy.dart`, `cobranza_service.dart`, `sync_service.dart`) y duplicados/reemplazados confirmados muertos por ambos lados (`company_settings.dart`, `company_feature.dart`, `feature_guard.dart`, `export_service.dart`/`exportar_excel.dart`, los dos `mfa_service.dart`, `sector_publico/models/entidad.dart`, `ica_form_page.dart` — este último verificado campo por campo contra `predial_ica_page.dart`, que lo cubre todo y corrige dos `FIXME` que el form viejo tenía hardcodeados —, los dos `crm_service.dart`).
- **`horas_extra_form_page.dart` — NO se borró a propósito.** Es la única implementación real de Horas Extra en el proyecto (6 tipos con recargos legales correctos, cálculo en tiempo real), simplemente nunca se conectó a ninguna pestaña. Va a la lista de Grupo C (integrar, no borrar).

---

## Pendientes explícitos, en orden de prioridad sugerido

1. **Cerrar el commit de los 23 borrados** (bloqueado por el problema de Kiro) — confirmar `flutter analyze` limpio primero, luego commit, luego push.
2. **Grupo C — funcionalidad real construida pero no conectada, decidir integrar vs. documentar como backlog:** `HorasExtraFormPage` (prioridad alta, es funcionalidad legal real), `depreciacion_job_service.dart`, `flujo_efectivo_service.dart`, `provisiones_service.dart` (NICSP), `interventoria_liquidacion_service.dart`, `dnp_service.dart`, `validacion_distribucion_service.dart` (SGR), `auxilio_alimentacion_service.dart`, `regimen_docente_service.dart`, `rentas_departamentales_service.dart`, `portal_transparencia_service.dart`, `configuracion_general_page.dart`/`onboarding_entidad_page.dart`.
3. **3 banners honestos de "pendiente para Fase 4"** (numeración informal de las bitácoras, no del Plan Maestro): motor de trazabilidad Plan-Presupuesto en Planeación, actas de responsabilidad a cuentadantes en Activos, exportación oficial PDF/XML de declaración ICA en Rentas.
4. **Suite de tests rota:** 6 errores de compilación en `test/` (no bloquean la app, sí bloquean CI/CD real), timeout de `pumpAndSettle` en el test de Presupuesto (posible `Timer`/`StreamBuilder` que no se asienta), tablas faltantes en tests de auditoría (`funcionarios_entidad`, `empleados_sp`, `auditoria_registros`), 2 tests de UI con texto no encontrado, 2 skips honestos en contratación (RP sin contrato, publicación SECOP).
5. **`PublicSectorSyncHelper`** — plomería lista, nunca conectada a flujos reales de escritura (CDP/RP/pagos/asientos).
6. **`ALLOWED_TABLES` del backend real** — agregar tablas del sector público requiere tocar el proyecto `Merka_Control_Center` (backend), no `Caja_simple`. Coordinar en qué repo se hace.
7. **Clave RSA placeholder** en verificación de licencia offline — antes de producción real.
8. **Vaciar `_PAPELERA_MERKAERP_BORRAR`** una vez Omar confirme que nada dependía de esos 3.5 GB.
9. **Decisión estratégica sin cerrar:** qué tanto del `PROMPT_MAESTRO`/Plan v1.1 (12 fases) se adopta formalmente de aquí en adelante.
10. Auditar Fases 0-3 del proyecto (lo más viejo, nunca revisado con este nivel de exigencia).

---

## Notas de entorno / gotchas del proyecto (para no perder tiempo redescubriéndolas)

- Windows, PowerShell. La terminal ha mostrado corrupción de eco repetidamente en sesiones largas — preferir escribir salida a archivo `.txt` y leerla con herramienta de archivos.
- `flutter analyze` tarda ~2 minutos en corridas completas — no relanzarlo más de una vez por ronda de cambios, y verificar que sea un proceso fresco (no cacheado) si el resultado no cuadra con lo esperado.
- Si `flutter build windows` falla con error de MSBuild/NuGet (`MSB8066`), revisar primero procesos `dart.exe`/`flutter*`/`flutter_tester.exe` colgados reteniendo archivos antes de sospechar de toolchain de Visual Studio.
- `git commit -m` con mensajes multilínea desde PowerShell puede fallar/corromperse — usar `git commit -F archivo.txt` con el mensaje ya escrito en un archivo.
- Nombres viejos del proyecto que pueden aparecer en residuos: "Caja Simple" (nombre anterior de MerkaERP), "NexoPyme" y "Lucro" (proyectos anteriores de los que Omar reutilizó código base).
