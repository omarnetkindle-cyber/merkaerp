# MerkaERP — Bitácora de Continuidad: Diagnóstico de Compilación
### Actualizado tras primera corrida de `flutter analyze` + `flutter test` (2026-07-22)

---

## Cómo usar este documento

Pegar al inicio de una conversación nueva. Este documento reemplaza y extiende `MerkaERP_Bitacora_Sesion_2026-07-22_Fase8_Cierre.md`, que sigue siendo válido como historial de las Fases 4-8. Este nuevo documento se enfoca específicamente en el estado de compilación/tests, que era el punto ciego más importante señalado al cierre de la Fase 8.

**Cambio de agente ejecutor:** para esta ronda de diagnóstico se usó **GitHub Copilot (plan gratuito)** en vez del agente de Antigravity usado en las Fases 4-8. Es un modelo más limitado — hay que ser más estricto pidiendo evidencia cruda, ya que tiende más a resumir, truncar salidas largas, o no completar todas las partes de un prompt de varios puntos (ya pasó: dos de tres investigaciones pedidas en el último prompt no se respondieron todavía).

**Metodología sin cambios:** Claude diseña los prompts, audita con exigencia de evidencia línea por línea, no acepta resúmenes optimistas sin verificar. El usuario no programa — aprueba/decide sobre las opciones que Claude presenta.

---

## ⚠️ Estado de compilación — YA NO es una incógnita total, pero sigue sin confirmarse limpio

Se corrieron `flutter analyze` y `flutter test` sobre el proyecto completo por primera vez desde que se suspendieron en la Fase 3. Duración total de `flutter test`: **2 horas 1 minuto** — anormalmente largo, posible fricción de entorno en Windows (antivirus, IO), anotado pero no bloqueante ya que sí terminó y dio resultados consistentes.

### Resultado de `flutter analyze`: 372 issues totales
- **166 errores** (bloqueantes para compilar)
- 51 warnings
- 155 infos

### Resultado de `flutter test`: 103 pasaron / 2 omitidos / 28 fallaron

---

## Causa raíz #1 — CONFIRMADA Y RESUELTA (diagnóstico completo, falta aplicar el fix)

**Bug real, no problema de entorno.** `pubspec.yaml` declara el paquete como `name: merka_erp`. Pero **7 archivos de test específicos** tienen hardcodeado el import con el nombre viejo del paquete, `package:caja_simple/...`, en vez de `package:merka_erp/...`. Los otros 47 archivos de test sí usan el nombre correcto. Las rutas de archivo bajo `lib/` existen sin problema — no falta ningún archivo, es puramente el nombre de paquete en el import.

**Archivos afectados (7):**
```
test/commercial_security_test.dart
test/core/selector_modo_test.dart
test/sector_publico/activos/acta_responsabilidad_service_test.dart
test/sector_publico/regalias/sicodis_service_test.dart
test/sector_publico/rentas/exportacion_declaraciones_test.dart
test/sector_publico/salud/facturacion_salud_service_test.dart
test/sector_publico/security/rbac_segregacion_test.dart
```

**Fix:** trivial, mecánico — cambiar `package:caja_simple/` → `package:merka_erp/` en esos 7 archivos. Esto por sí solo debería resolver 134 de los 166 errores de `flutter analyze` (los que están en `test/`) y desbloquear 7 de los 10 archivos de test que hoy no cargan.

---

## Causa raíz #2 — CONFIRMADA, es una consecuencia directa de nuestro propio trabajo de Fase 7/hardening

**32 errores en `lib/`**, todos del mismo tipo: *"The argument type 'String?' can't be assigned to the parameter type 'String'"*.

- `lib/core/workspace/public_sector_config.dart` — **22 sitios**, todos pasando `AppSession.usuarioId` a un parámetro que espera `String` no-nulo.
- `lib/erp_readiness_page.dart` — **1 sitio**, pasando `AppSession.rol` igual.
- `lib/sector_publico/regalias/pages/regalias_sgp_page.dart` — **9 errores**, causa aún sin diagnosticar (podría ser el mismo patrón o algo distinto — pendiente).

**Por qué pasó esto:** en la Fase 7 y en el hardening comercial de esta sesión, se cambió deliberadamente `AppSession.usuarioId` y `AppSession.rol` de `String` a `String?` (fail-closed: `null` = sin sesión = acceso denegado). Fue correcto y bien auditado en su momento — pero **nunca se propagó ese cambio a estos dos archivos que los consumen**, que seguían esperando el tipo viejo no-nulo. Esto bloquea 3 archivos de test adicionales: `login_widget_test.dart`, `module_smoke_test.dart`, `widget_test.dart`.

**Fix:** hay que decidir, para cada uno de los ~23 sitios confirmados, si el consumidor debe:
(a) aceptar `String?` y manejar el caso nulo explícitamente (probablemente lo correcto, dado que estos son puntos de UI que sí pueden ejecutarse sin sesión), o
(b) si el punto de código garantiza que siempre hay sesión activa ahí, usar el operador `!` con una aserción explícita — **con cuidado, esto no debe convertirse en un nuevo fail-open silencioso**.

---

## Bugs reales adicionales encontrados por tests que SÍ compilaron y corrieron (no relacionados con lo anterior)

Estos son hallazgos genuinos de `flutter test`, con evidencia cruda ya en mano — no diagnosticados a fondo todavía:

1. **`presupuesto_publico_page_test.dart` (6 tests fallan)**: error `no such column: vigencia` al crear el índice `idx_apropiaciones_vigencia` sobre la tabla `apropiaciones`. Sospechoso porque `presupuesto_service_test.dart`, que usa la misma tabla, sí pasa — sugiere que hay dos rutas distintas de creación de esquema (`_onCreate` vs. una migración) y una de ellas no tiene la columna `vigencia`. **Pendiente de diagnóstico**, ya se había pedido en un prompt anterior pero el agente no llegó a responderlo (se enfocó en la causa raíz #1).

2. **3 servicios de auditoría fallan por falta de tabla `funcionarios_entidad`** en su configuración de test: `fut_territorial_service_test.dart`, `sia_observa_service_test.dart`, `siif_service_test.dart`. Posiblemente el setup de esos tests no crea todas las tablas necesarias (no necesariamente un bug del código de producción, podría ser un test con `setUpAll` incompleto).

3. **`nomina_service_test.dart` (4 tests fallan)** por falta de tabla `empleados_sp` — mismo patrón que el punto anterior.

4. **`spgr_service_test.dart`** falla por falta de tabla `auditoria_registros` — mismo patrón.

5. **`sales_flow_test.dart`**: discrepancia numérica real, no de esquema — el test esperaba `5000` y obtuvo `4979.3` (diferencia de `20.7`) en *"venta POS descuenta inventario, registra caja y asiento contable"*. **Pendiente de diagnóstico** — no se ha visto el código del test ni de la función que calcula ese valor. Podría ser un tema de impuestos/redondeo, o un bug real de cálculo.

6. **2 tests de UI no encuentran texto esperado en pantalla**: `predial_ica_page_test.dart` (busca *"Exportación oficial de Declaración ICA"*) y `salud_publica_page_test.dart` (busca *"Salud Pública"*). Podría ser un test desactualizado (el texto cambió) o una regresión real de UI.

7. **2 skips honestos, no son bugs nuevos**: `contratacion_service_test.dart` tiene 2 tests marcados como `Skip` con comentarios explícitos de que ciertas validaciones normativas (RP sin contrato, publicación en SECOP) todavía no están implementadas. Documentado ya por el agente en una sesión anterior — transparencia correcta, no requiere acción inmediata salvo decidir cuándo implementar esas validaciones.

---

## Lo que quedó pendiente de responder en el último prompt (el agente no llegó a esto)

Se le pidió al agente investigar 3 cosas; solo resolvió la primera (causa raíz del import roto). Las otras 2 quedan pendientes para la próxima conversación:

1. ~~Investigación de si el problema de "paquete no encontrado" era de entorno o código real~~ → **RESUELTO**, ver Causa raíz #1 arriba.
2. **Diagnóstico de `apropiaciones.vigencia`** (por qué falta la columna en una ruta de creación de esquema) → **pendiente**.
3. **Diagnóstico de la discrepancia `5000` vs `4979.3`** en `sales_flow_test.dart` → **pendiente**.

---

## Aún no hecho — limpieza del proyecto

Se había planeado (y el usuario ya lo pidió explícitamente) una limpieza de artefactos de build (`flutter clean` + carpetas de build por plataforma) y una revisión de bases de datos SQLite locales de desarrollo antes de la primera compilación real. **Esto se pospuso** para hacer primero el diagnóstico de `analyze`/`test`, que ya se completó. Sigue pendiente como siguiente paso natural, junto con el prompt de `flutter build` real — pero *después* de aplicar los fixes de las 2 causas raíz confirmadas, para no limpiar y compilar sobre una base que ya sabemos que tiene errores.

---

## Orden de trabajo recomendado al retomar (en este orden)

1. **Aplicar fix de Causa raíz #1** (7 archivos, cambio mecánico de nombre de paquete en imports de test). Bajo riesgo, alto impacto (resuelve la mayoría de los 166 errores).
2. **Aplicar fix de Causa raíz #2** (`AppSession.usuarioId`/`rol` nullable no propagado a 2-3 archivos consumidores). Requiere decisión de diseño (manejar `null` explícitamente vs. aserción `!`), no solo mecánico — pedirle al agente que primero muestre el contexto de cada sitio antes de decidir.
3. Diagnosticar `lib/sector_publico/regalias/pages/regalias_sgp_page.dart` (9 errores, causa aún desconocida).
4. Volver a correr `flutter analyze` completo para confirmar cuántos de los 372 issues quedaron resueltos, y ver qué queda real.
5. Investigar y corregir los bugs reales de tablas faltantes en tests (`funcionarios_entidad`, `empleados_sp`, `auditoria_registros`) y la columna `apropiaciones.vigencia`.
6. Investigar la discrepancia numérica de `sales_flow_test.dart`.
7. Revisar los 2 tests de UI con texto no encontrado (decidir si son tests desactualizados o regresiones reales).
8. Volver a correr `flutter test` completo para confirmar el estado final.
9. **Solo después de todo lo anterior**: limpieza del proyecto (`flutter clean`, revisión de BDs locales) + `flutter build` real.
10. Retomar los pendientes de Fase 8 documentados en `MerkaERP_Bitacora_Sesion_2026-07-22_Fase8_Cierre.md` (cableado de `PublicSectorSyncHelper`, decisión de `HybridSyncService`, etc.).
11. Solo después de todo: arrancar Fase 9 (CRM/HRM/MRP).

---

## Recordatorios de metodología (sin cambios)

- **Regla de oro:** el agente reporta con optimismo por defecto. Exigir evidencia cruda línea por línea antes de aceptar cualquier "listo" o "no queda ninguna pendiente". Ya pasó varias veces esta sesión que el agente omitió partes de un prompt de varios puntos (como en esta misma ronda) — verificar siempre que TODAS las partes de un prompt fueron respondidas antes de continuar.
- Si el agente reporta rutas a archivos temporales del sistema en vez de pegar contenido, pedir el contenido real en el chat — esos archivos no son accesibles para Claude y pueden borrarse.
- Vigilar conteos que no cuadren entre sí (ya ha pasado varias veces) — siempre pedir el desglose exacto si algo no suma.
- Nunca se ha hecho `git push`. Sigue pendiente decidir cuándo.
- El usuario no programa — Claude decide el enfoque técnico y explica en términos claros.
