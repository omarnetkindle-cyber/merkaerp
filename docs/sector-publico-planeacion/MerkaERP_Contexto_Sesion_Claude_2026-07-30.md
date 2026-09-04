# MerkaERP — Contexto Completo de Sesión (para retomar desde otra cuenta de Claude)
### Generado el 2026-07-30, cierre de una sesión muy larga de trabajo continuo

---

## Cómo usar este documento

Pégalo completo como primer mensaje en la conversación nueva. Está escrito para que Claude (el asistente de chat, rol de supervisor/diseñador de prompts) retome exactamente donde quedó — no es para pegarle al agente ejecutor de código (para eso existe un documento aparte, `MerkaERP_Bitacora_Continuidad_2026-07-29.md`, generado horas antes en esta misma sesión y ya entregado al agente ejecutor).

---

## Quién es Omar y cómo trabajamos

Omar es desarrollador/asesor independiente construyendo y extendiendo **MerkaERP** (antes "Caja Simple"), un ERP Flutter/Dart + SQLite. Empezó como ERP comercial (ventas/POS, inventario, contabilidad, nómina) y se está expandiendo con un módulo completo de **Sector Público** para alcaldías, gobernaciones y hospitales públicos colombianos, con cumplimiento normativo real (NICSP, presupuesto público, Ley 80, segregación de funciones, auditoría). Meta explícita: dejar el sistema **"listo para el mercado"**.

**Omar no programa.** El flujo de trabajo establecido, sin excepción:
1. Omar pega el resultado de lo que hizo un agente ejecutor de IA (GitHub Copilot, Kiro, o Codex — ha ido cambiando de herramienta durante la sesión).
2. Claude audita esa respuesta con exigencia de evidencia línea por línea — **nunca acepta un "listo"/"0 errores"/"ALL CLEAR" sin ver la salida cruda**, idealmente leída de un archivo, nunca del eco de una terminal (ha habido corrupción de terminal repetidamente).
3. Claude diseña el siguiente prompt, bien delimitado, con pasos de investigación separados de pasos de implementación cuando el tema es delicado (seguridad, dinero, datos).
4. Omar pega ese prompt al agente ejecutor y trae la respuesta de vuelta.

**Regla de oro, reconfirmada decenas de veces esta sesión:** el agente ejecutor reporta con optimismo por defecto. Cada vez que se exigió evidencia en vez de aceptar un resumen, aparecieron bugs reales. Ejemplos memorables de esta sesión: un `flutter analyze` que resultó estar leyendo caché de un proceso viejo; un commit con +54.045 inserciones que resultó ser solo ruido de fin de línea (pero había que verificarlo, no asumirlo); un script de reemplazo automático que corrompió un archivo a 8.716 issues sin que el agente lo notara hasta que se le pidió comparar conteos de líneas; y, ya al final, una corrección que se creía cerrada desde el principio de la sesión (`package:caja_simple` → `package:merka_erp`) que había desaparecido silenciosamente sin que nadie lo notara hasta la última corrida completa de `flutter analyze`.

---

## Estado técnico actual — todo funcionando y respaldado

**Repo:** `https://github.com/omarnetcom-hub/mera-erp.git`, rama `main`, sincronizado hasta `a72f45d` (push confirmado, verificado).

**`flutter analyze`: 184 issues, 0 errores.** `flutter build windows` compila limpio y genera el ejecutable. La app corre de punta a punta: onboarding → activación de licencia (online y offline, ambas confirmadas funcionales) → login → selector de modo → menú principal con las pestañas correctas según sea comercial o sector público.

**Arquitectura, para orientarse rápido:**
- 11 macro-sistemas del sector público (Planeación, Financiero/Presupuesto/Contabilidad/Tesorería, Rentas, Contratación, Nómina, Activos, Trazabilidad/Auditoría, Salud, SGR/Regalías, SGP/Participaciones, Transparencia).
- Patrón por capas en cada módulo: `lib/sector_publico/<área>/{database,models,services,pages}/`.
- Aislamiento de datos: comercial usa `company_id` (INTEGER), sector público usa `entidad_id` (TEXT/UUID). Vigilar siempre que no se cuele un valor mágico tipo `'default'` o `1` — es el bug estructural más recurrente del histórico del proyecto.
- RBAC de sector público: 10 roles normativos (`RolSectorPublico`), segregación de funciones dura, gestionado por `RolesPermisosService`.

---

## Lo que se resolvió en esta sesión (cronológico, resumen)

1. **Diagnóstico y primera compilación exitosa** de Windows — resueltos: import de paquete viejo en 7 tests, 23 sitios de nullability, columna faltante `apropiaciones.vigencia` (con migración defensiva que nunca inventa datos), ReteICA aplicándose sin verificar regla de empresa autorretenedora, y `regalias_sgp_page.dart` desalineada con sus propios modelos.
2. **Auditoría visual completa a partir de capturas de pantalla reales** que Omar subió (mucho más efectivo que descripciones de texto): formato de dinero sin separador de miles en 118 sitios, modo oscuro roto por colores hardcodeados en las 12 páginas del sector público, fechas en formato ISO crudo, un bug de división por cero, y **el hallazgo más grande**: la barra superior del menú principal mostraba siempre pestañas comerciales (Ventas/Operaciones/Finanzas) sin importar el tipo de entidad, y el sistema de permisos del menú (`PermissionService`) no conocía ningún rol ni módulo del sector público — por lo que casi ningún módulo público se podía abrir con un clic.
3. **Reconstrucción del "main"** para sector público: 3 pestañas propias (Ejecución Presupuestal / Cumplimiento y Alertas / Transparencia), RBAC del menú conectado a `RolesPermisosService`, alias de menú (PILA, MGA/PDT, SECOP II) cableados a sus tabs reales donde existían, `FUT` reenrutado correctamente.
4. **Ronda de botones con texto invisible** — bug real y extendido (mismo color de texto y de fondo), apareció en 15+ archivos. **Tuvo varios incidentes serios de corrupción de sintaxis** por scripts de regex/sed automatizados mal diseñados (uno llegó a inflar el analyze a 8.716 issues). Se resolvió finalmente con reemplazo de texto exacto y verificación de sintaxis + conteo de líneas antes/después. **Lección aprendida y ya registrada: nunca más automatizar reemplazos masivos con regex sobre múltiples archivos Dart — uno por uno, con reemplazo exacto.**
5. **Onboarding conectado al flujo de arranque** (existía en el código pero nunca se invocaba) y **toggle manual online/offline en la activación de licencia** (antes dependía 100% de detección automática de conectividad).
6. **Investigación profunda del backend de licencias/Control Center** — se descubrió que había dos copias de backend (una vieja abandonada dentro del repo de la app, otra real desplegada en Render con PostgreSQL de verdad). Se confirmó con pruebas HTTP reales que el sistema de licencias (online, offline, y sync con Postgres) está bien diseñado y funcional de punta a punta. Pendiente real, no urgente: clave RSA placeholder en la verificación offline (hay que reemplazarla antes de producción con clientes reales), y que el backend solo sincroniza tablas comerciales (`ALLOWED_TABLES`), ninguna del sector público todavía.
7. **Dos bugs de causa raíz cerrados** (no solo el síntoma): `LateInitializationError` en Contratación (servicios `late` sin protección) y `auditoriaService: null` en Presupuesto (el flujo más sensible del sector público operaba sin registro de auditoría).
8. **Limpieza de disco**: ~163MB liberados dentro del repo (instaladores viejos, residuos de NexoPyme, logs de sesiones de IA anteriores), ~3.5GB movidos a una papelera temporal fuera del repo (`_PAPELERA_MERKAERP_BORRAR`, todavía sin vaciar — Omar debe confirmar que todo sigue funcionando antes de borrarla en serio).
9. **Limpieza de código muerto** — la ronda más larga y con más idas y vueltas: 21 archivos legacy/duplicados eliminados definitivamente, 2 restaurados al confirmar que sí tenían consumidores reales (`exportar_excel.dart`, `sync_service.dart` — este último queda con una nota de rediseño pendiente, ver abajo), y una investigación honesta que confirmó que una política contable NIIF descartada no hacía falta (el flujo comercial activo ya cubre lo esencial de esa validación).
10. **Regresión inesperada detectada y corregida** ya casi al final: el fix original de `package:caja_simple` → `package:merka_erp` en 7 archivos de test (el primerísimo bug de toda la sesión) había desaparecido en algún punto sin que nadie lo notara — se recuperó y volvió a corregir, junto con 3 errores adicionales de tests desalineados con las firmas reales de sus servicios (`setDatabaseForTesting` → `setTestDatabase`, parámetros obsoletos en `exportacion_declaraciones_test.dart`).
11. **Cambio de agente ejecutor a mitad de sesión**: Kiro (el IDE que se venía usando) empezó a rechazar sistemáticamente cualquier operación de escritura/destructiva (`git add`, `git commit`, `fs_write`, `Remove-Item`) a pesar de estar en modo "Autopilot" — nunca se resolvió la causa, el flujo de respaldo fue que Omar ejecutara los comandos exactos a mano en su propia terminal. Se cambió a **Codex 5.6 "Terra" (esfuerzo alto)**, que sí puede escribir archivos pero tuvo sus propios problemas de timeout con comandos largos (`flutter analyze` cortándose a los 4-6 minutos) — se resolvió con el mismo patrón de fondo: Omar corriendo el comando él mismo en su terminal cuando el agente no podía esperar el resultado.

---

## Pendientes explícitos, en el orden que veníamos siguiendo

1. **EN CURSO AHORA MISMO — Grupo C:** funcionalidad real construida pero nunca conectada a la UI. Se acaba de mandar un prompt a Codex para: (a) integrar `HorasExtraFormPage` (prioridad — es la única implementación real de Horas Extra que existe, con 6 tipos y recargos legales correctos, simplemente nunca se conectó a ninguna pestaña), y (b) evaluar rápidamente el resto de la lista para decidir cuáles se integran ya y cuáles quedan documentadas como backlog: `depreciacion_job_service.dart`, `flujo_efectivo_service.dart`, `provisiones_service.dart` (NICSP), `interventoria_liquidacion_service.dart`, `dnp_service.dart`, `validacion_distribucion_service.dart` (SGR), `auxilio_alimentacion_service.dart`, `regimen_docente_service.dart`, `rentas_departamentales_service.dart`, `portal_transparencia_service.dart`, `configuracion_general_page.dart`/`onboarding_entidad_page.dart`. **Todavía no ha llegado la respuesta de esta ronda — es lo primero que hay que revisar al retomar.**
2. Los 3 banners honestos de "pendiente para Fase 4" (numeración informal de las bitácoras, no confundir con el Plan Maestro de 12 fases): motor de trazabilidad Plan-Presupuesto en Planeación, actas de responsabilidad a cuentadantes en Activos, exportación oficial PDF/XML de declaración ICA en Rentas.
3. Suite de tests todavía con huecos más allá de lo ya arreglado: timeout de `pumpAndSettle` en el test de Presupuesto, tablas faltantes en tests de auditoría, 2 tests de UI con texto no encontrado, 2 skips honestos en contratación.
4. `PublicSectorSyncHelper` — plomería lista, nunca conectada a flujos reales de escritura.
5. `ALLOWED_TABLES` del backend real — agregar tablas del sector público requiere tocar el proyecto `Merka_Control_Center` (backend), no el repo de la app. Coordinar en qué repo se hace.
6. Clave RSA placeholder en verificación de licencia offline — antes de producción real.
7. `sync_service.dart` — quedó restaurado (tiene consumidores reales: el login remoto es best-effort desde `main.dart`/`login_page.dart`), pero sus métodos de push/pull apuntan a rutas que no existen en ningún backend. Pendiente de decisión: ¿simplificar el archivo dejando solo el login y borrando el código muerto de sync, o migrar `login_page.dart` para no depender de él en absoluto?
8. Vaciar `_PAPELERA_MERKAERP_BORRAR` (3.5GB) una vez Omar confirme que nada dependía de esos archivos.
9. Decisión estratégica sin cerrar: qué tanto del `PROMPT_MAESTRO_MerkaERP_SectorPublico.md` / `MerkaERP_SectorPublico_Plan_v1_1.md` (roadmap formal de 12 fases, mucho más ambicioso que el trabajo incremental hecho hasta ahora) se adopta de aquí en adelante.
10. Auditar Fases 0-3 del proyecto (lo más viejo, nunca revisado con este nivel de exigencia).

---

## Notas de entorno — para no perder tiempo redescubriéndolas

- Windows, PowerShell (a veces `cmd`, funciona igual para Flutter). La terminal ha mostrado corrupción de eco repetidamente en sesiones largas — preferir escribir salida a archivo `.txt` y leerla con herramienta de lectura de archivos, nunca confiar en el eco directo.
- `flutter analyze` puede tardar varios minutos (se ha visto hasta 6-8 min en corridas después de cambios grandes) — si el agente ejecutor tiene un timeout de comando corto, pedirle a Omar que lo corra él mismo en su terminal y espere a que vuelva el prompt (`PS C:\...>`) antes de decir que terminó.
- Si `flutter build windows` falla con error de MSBuild/NuGet, revisar primero procesos `dart.exe`/`flutter*`/`flutter_tester.exe` colgados reteniendo archivos antes de sospechar de toolchain de Visual Studio.
- `git commit -m` con mensajes multilínea desde PowerShell puede fallar/corromperse — usar `git commit -F archivo.txt` con el mensaje ya escrito en un archivo de texto.
- **Nunca automatizar reemplazos masivos de texto en archivos Dart con regex/sed sobre múltiples archivos a la vez** — ya causó corrupción real más de una vez esta sesión. Reemplazo de texto exacto, uno por uno.
- Nombres viejos del proyecto que pueden aparecer en residuos de código o archivos: "Caja Simple" (nombre anterior de MerkaERP), "NexoPyme" y "Lucro" (proyectos anteriores de los que Omar reutilizó código base) — Omar no recuerda detalles de esos proyectos, no preguntarle por nombres específicos de ahí.
- Existe un documento paralelo, `MerkaERP_Bitacora_Continuidad_2026-07-29.md`, generado horas antes que este mismo dentro de esta sesión — está pensado para dárselo al agente ejecutor (Codex), no a Claude. Tiene más detalle técnico línea por línea de cada fix. Si hace falta ese nivel de detalle, pídeselo a Omar, seguramente lo tiene guardado.
