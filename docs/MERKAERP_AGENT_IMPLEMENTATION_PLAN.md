# MerkaERP Agent — plan y estado de implementación

Fecha de corte: 2026-08-31

## Contrato de referencia

La integración sigue el contrato v2 ubicado en `merkaerp_agent_contract` del
proyecto Merka Control Center. La aplicación mantiene `ControlCenterAgent` como
fachada pública para no romper la inicialización existente.

## Fase 1 — núcleo seguro (completada)

- Identidad local UUID v4 persistente y preferencia por el `installation_id`
  firmado de la licencia.
- Bootstrap, publicación de capacidades, polling cada 45 segundos y heartbeat
  cada 5 minutos, sin ejecuciones solapadas.
- Allowlist exacto de las 25 acciones del contrato v2. Una acción desconocida
  se rechaza y nunca se transforma en otro comando.
- Verificación HMAC-SHA256 sobre JSON canónico, validación de instalación,
  expiración y nonce.
- Idempotencia durable por `command_id` y nonce. El resultado se persiste y los
  reintentos no vuelven a ejecutar la acción.
- ACK estructurado y durable, con reintento cuando vuelve la conexión.
- Colas SQLite oficiales para estado, comandos procesados, ACK, telemetría,
  errores y descargas; migración de esquema v113.
- Heartbeat con versión, capacidades, plataforma, arquitectura, host, memoria,
  disco, esquema, migraciones, licencia y último respaldo.
- Acciones habilitadas en esta fase: bloquear/activar instalación, mensaje de
  administrador y solicitud de acceso remoto con consentimiento. Las acciones
  de fases posteriores fallan de forma explícita y no simulan éxito.

## Validación de la Fase 1

- 24/24 pruebas específicas de Agent, endpoints, licencia y comandos aprobadas.
- Análisis estático dirigido a los archivos del Agent: 0 problemas.
- Contrato backend: self-check, fingerprint RS256, 25 acciones y rutas API
  requeridas aprobados.
- Suite global: 462 aprobadas, 1 omitida y 4 fallos heredados ajenos al Agent
  (dos fixtures HRM sin `fecha_contratacion`, una tabla de rentas
  departamentales ausente en el smoke test y `DISTINCTyear` en la auditoría de
  consultas).
- Análisis global: conserva los mismos 21 avisos preexistentes del baseline; la
  Fase 1 no agregó avisos.

## Builds de integración del corte 3C

- Windows x64 Release: compilado y empaquetado como
  `build/artifacts/MerkaERP-1.3.0+8-agent-3.5.0-windows-x64.zip` (47.802.093
  bytes, SHA-256
  `d314cfc7d94013e94db5c215968360f1718d1b64e48c495cc35b0dacf7cb73b4`).
  El paquete contiene todo el directorio Release requerido por la aplicación.
  El ejecutable todavía no tiene firma Authenticode, por lo que este artefacto
  no se considera un instalador de publicación final.
- Android Debug APK: compilado, verificado con `apksigner` y empaquetado como
  `build/artifacts/MerkaERP-1.3.0+8-agent-3.5.0-android-debug.apk` (234.888.016
  bytes, SHA-256
  `6310ba9593a63bba32ab090b2d1493abe42fcccd941373d2b2f8838868eb9219`).
  Usa APK Signature Scheme v2 y el certificado Android Debug; sirve para
  integración y pruebas, no para distribución.
- Android Release APK: la compilación permanece correctamente bloqueada hasta
  proporcionar `MERKA_RELEASE_STORE_FILE`, `MERKA_RELEASE_KEY_ALIAS`,
  `MERKA_RELEASE_STORE_PASSWORD` y `MERKA_RELEASE_KEY_PASSWORD`. No se agregó
  ninguna sustitución insegura por la firma debug.

## Builds de integración del corte 5B

- Windows x64 Release: compilado y empaquetado como
  `build/artifacts/MerkaERP-1.3.0+8-agent-5.0.0-windows-x64.zip` (47.828.069
  bytes, SHA-256
  `1a17dd7bfd1575f5c85b3631b6c30a37b3579374b6e6a0c97606e79d33ed9d51`).
  El ejecutable `build/windows/x64/runner/Release/MerkaERP.exe` conserva SHA-256
  `1bbff0b88f0419a5903035256d7d0ea9d82591b7a4dc232772eb369b1453ee25`.
  Authenticode permanece `NotSigned`, por lo que el ZIP es artefacto de
  integración, no instalador final de publicación.
- Android Debug APK: compilado, copiado y verificado con `apksigner` como
  `build/artifacts/MerkaERP-1.3.0+8-agent-5.0.0-android-debug.apk`
  (234.908.967 bytes, SHA-256
  `02df0a1ae349e280a69e9fca744095310d168a4fbc28ab7d9a54d3405bfb0485`).
  Firma válida con APK Signature Scheme v2 y certificado Android Debug
  SHA-256 `4dd026fd393be4287d24f01c0e233b498d91cb68f7db77ee92f3a333d19d1608`.
- Android Release APK: no se generó porque no están presentes
  `MERKA_RELEASE_STORE_FILE`, `MERKA_RELEASE_KEY_ALIAS`,
  `MERKA_RELEASE_STORE_PASSWORD` ni `MERKA_RELEASE_KEY_PASSWORD`. Se mantiene el
  bloqueo correcto: no se reemplaza por firma debug.

## Builds locales limpios del corte 5E

- Corrección de flujo: la primera apertura ya no crea una licencia trial local
  desde el Agent. Si no existe licencia firmada válida, `StartupFlow` abre
  primero `LicensingPage`; sólo después de activar, el wrapper recarga y muestra
  el onboarding correspondiente a `license.productFamily`. La activación online
  de la pantalla delega en `LicenciaService.activarDesdeControlCenter`, que
  valida el JWT RS256, hardware fingerprint, instalación y `pf` firmado. Se
  eliminó la construcción manual de licencia desde metadata paralela de la
  respuesta.
- Limpieza previa: se eliminaron las bases locales usadas para las pruebas en
  `Documents` (`merka_erp_public_fresco.db` y
  `merka_erp_commercial_fresco.db`, con journals si existían). Los nombres de
  build `public` y `commercial` son sólo perfiles de base de datos para poder
  probar dos activaciones en el mismo PC; no fijan la familia del producto. El
  instalador real de publicación seguirá siendo único y la familia dependerá
  exclusivamente de la licencia firmada.
- Windows x64 Release perfil de prueba `public`: compilado con
  `--dart-define=MERKAERP_DATA_PROFILE=public` y copiado a
  `build/clean_releases/MerkaERP-public-license-windows-x64`. Usará la base
  independiente `merka_erp_public_fresco.db`. `sqlite3.dll` presente.
  `MerkaERP.exe` SHA-256
  `3352e5d885cc26fecd3c88f86fcb6f3bf2f9f4e36ba5eb7ff7881eb46450b26d`;
  `data/app.so` fecha 2026-08-31 22:11:26, SHA-256
  `0ec0ead763d9047ca3ade594ada5834bb43d010ab281ea23f9063bdbd870b706`.
- Windows x64 Release perfil de prueba `commercial`: compilado con
  `--dart-define=MERKAERP_DATA_PROFILE=commercial` y copiado a
  `build/clean_releases/MerkaERP-commercial-license-windows-x64`. Usará la base
  independiente `merka_erp_commercial_fresco.db`. `sqlite3.dll` presente.
  `MerkaERP.exe` SHA-256
  `3352e5d885cc26fecd3c88f86fcb6f3bf2f9f4e36ba5eb7ff7881eb46450b26d`;
  `data/app.so` fecha 2026-08-31 22:14:48, SHA-256
  `c1c7af735e21e2ab655d81544a31148c29bed76395cfab81523bd51710e2a39d`.

## Fases siguientes

1. Fase 2A (completada): `actualizar_licencia` y `actualizar_modulos` consumen
   exclusivamente el `license_token` RS256. Se fijó y comprobó el fingerprint
   SPKI del publicador, se vincularon instalación/hardware/familia, se impidió
   el rollback a un token anterior y se habilitó la persistencia de suspensión
   o expiración auténticas, incluyendo licencias perpetuas. Validación del
   corte: 8/8 pruebas nuevas, 32/32 acumuladas y análisis dirigido sin
   problemas.
2. Fase 2B (completada): validación online y reconciliación del estado
   operativo al iniciar y al recuperar conectividad. El servidor funciona como
   señal operativa; módulos, vigencia y estado sólo cambian mediante el token
   RS256 firmado. Se implementó gracia offline limitada a siete días y nunca
   superior a la expiración firmada, bloqueo por denegación online o gracia
   vencida, detección de cambios que requieren un token firmado nuevo y
   persistencia transaccional del estado. El Agent quedó en versión 2.2.0.
   Validación del corte: 7/7 pruebas nuevas, 39/39 acumuladas y análisis
   dirigido sin problemas.
3. Fase 3A (completada): `run_diagnostics`, `collect_diagnostics` y
   `verificar_base_datos` ejecutan exclusivamente un catálogo local de checks
   de lectura. El resultado estructurado cubre integridad SQLite, esquema y
   migraciones, colas del Agent, sincronización, licencia, respaldos,
   almacenamiento y runtime. Los parámetros SQL/shell y checks desconocidos
   se rechazan, y la salida elimina claves, tokens, JWT, correos y rutas de
   usuario sin incluir filas empresariales, documentos ni la base de datos. El
   Agent quedó en versión 3.0.0. Validación del corte: 7/7 pruebas nuevas,
   46/46 acumuladas y análisis dirigido sin problemas.
4. Fase 3B (completada): `enviar_log` genera exclusivamente JSON sanitizado,
   acotado por periodo, número de entradas y tamaño, y lo carga como artefacto
   asociado a un `request_id` válido. Se rechazan parámetros de archivos, SQL
   o shell y el truncamiento conserva un documento JSON íntegro. Los errores
   críticos se sanitizan, persisten en una cola durable y sólo se eliminan
   después de la confirmación del backend; los fallos offline se reintentan.
   La telemetría enviada no incluye nombre ni identificación tributaria de la
   empresa. El Agent quedó en versión 3.1.0. Validación del corte: 7/7 pruebas
   nuevas, 53/53 acumuladas y análisis estático dirigido sin problemas.
5. Fase 3C-1 (completada): `aplicar_configuracion` y
   `aplicar_feature_flags` quedan habilitados con allowlists locales. La
   configuración administrada sólo acepta `currency`, `vat_enabled`,
   `withholding_enabled` y `default_tax`; las feature flags se limitan a las
   claves conocidas por `FeatureRegistry` y `FeatureFlagService`, con opción de
   aplicar el último `bootstrap_v2` persistido. Se rechazan claves libres,
   parámetros SQL/shell/rutas y flags desconocidas, y el ACK conserva códigos
   estables sin exponer detalles sensibles. El Agent quedó en versión 3.2.0.
   Validación del corte: 6/6 pruebas nuevas, 59/59 acumuladas y análisis
   estático dirigido sin problemas.
6. Fase 3C-2 (completada): `entrar_mantenimiento` y `salir_mantenimiento`
   activan/desactivan el modo visible de mantenimiento y el bloqueo operativo
   local `operacion_bloqueada`, que ya es consultado por ventas, compras y caja
   antes de nuevas transacciones. `forzar_sincronizacion` sólo dispara el motor
   local autenticado e idempotente, sin aceptar tablas, SQL ni payloads remotos.
   `reconstruir_indices`, `limpiar_cache` y `ejecutar_reparacion` quedaron
   ligados a un catálogo cerrado de reparaciones seguras: `reindex_database`,
   `optimize_database` y `clear_cache`. Los mensajes se sanitizan antes de
   persistirlos y se corrigió la reconstrucción de claves en
   `AgentDataSanitizer` para emitir `token=<redacted>` en lugar del literal
   interno del reemplazo. El Agent quedó en versión 3.5.0. Validación del corte:
   12 pruebas nuevas dentro de fase 3C, 18/18 pruebas de fase 3C, 71/71
   acumuladas y análisis estático dirigido sin problemas.
7. Fase 4A-4C (completada): `forzar_respaldo` crea respaldos integrales
   mediante el servicio local, los verifica, calcula SHA-256 y devuelve sólo
   una referencia local (`backup_ref`), tamaño, versión de base y métricas del
   manifiesto; nunca expone rutas absolutas. `restaurar_respaldo` acepta sólo
   `backup_ref` y checksum SHA-256, busca el archivo en el catálogo local de
   respaldos, rechaza rutas o nombres inseguros, valida el checksum real,
   ejecuta verificación integral, exige simulacro de restauración correcto,
   crea un respaldo previo `cc_pre_restore` y recién entonces invoca la
   restauración local. Los fallos por parámetros quedan como no recuperables;
   los de ejecución, verificación o simulacro quedan como recuperables para
   reintento/operación manual. `collect_diagnostics` conserva el diagnóstico
   estructurado en ACK y, cuando recibe `request_id`, sube además un artefacto
   `diagnostic` JSON sanitizado a `/api/v1/agent/artifacts`, limitado a 2 MiB,
   sin secretos ni datos empresariales. El Agent quedó en versión 4.2.0.
   Validación del corte: 9/9 pruebas de fase 4, 81/81 acumuladas y análisis
   estático dirigido sin problemas.
8. Fase 5A (completada): `forzar_actualizacion` quedó enlazado al
   `UpdateService` seguro existente mediante `AgentUpdateService`. El comando
   remoto sólo acepta `target_version`/`version`, `canal`/`channel` y
   `request_id`; no acepta rutas, instaladores ni scripts remotos. Antes de
   aplicar exige metadata local de actualización firmada: URL HTTPS o localhost
   de desarrollo, SHA-256 hexadecimal, tamaño razonable y `manifest_token`
   RS256 presente. La descarga vuelve a pasar por el `UpdateService`, que valida
   manifiesto de publicador, HTTPS y SHA-256; la aplicación queda delegada al
   updater local transaccional, con ACK estructurado sin rutas absolutas. El
   Agent quedó en versión 5.0.0. Validación del corte: 5/5 pruebas de fase 5A,
   86/86 acumuladas y análisis estático dirigido sin problemas.
9. Fase 5B (contención segura completada): `rollback_actualizacion` y
   `aplicar_hotfix` ya no responden con pendiente genérico. Ambos pasan por
   `AgentUpdateService`, rechazan parámetros libres, scripts, rutas o
   identificadores inseguros, y devuelven ACK fallido controlado con códigos
   estables (`UPDATE_ROLLBACK_ENGINE_UNAVAILABLE` /
   `UPDATE_HOTFIX_ENGINE_UNAVAILABLE`) cuando la solicitud es formalmente
   válida pero no existe aún motor transaccional local. No se anuncian en
   capacidades, no ejecutan instaladores, no descargan hotfixes y no simulan
   éxito. Validación del corte: 9/9 pruebas de fase 5, 90/90 acumuladas y
   análisis estático dirigido sin problemas.
10. Fase 5C-1 (completada): `rollback_actualizacion` restaura de forma segura
   el snapshot pre-update local cuando existe un catálogo verificable. El
   `UpdateService` registra en `app_config` el snapshot creado antes de lanzar
   el instalador firmado, incluyendo versión origen, versión destino,
   `backup_ref` y SHA-256 del respaldo integral. El Agent valida
   `target_version`, `backup_ref` y `checksum`, busca únicamente respaldos del
   catálogo local, recalcula SHA-256, ejecuta verificación integral, exige
   simulacro de restauración correcto y recién entonces invoca la restauración
   local. Si no hay snapshot, no coincide la versión o falla checksum/drill,
   el comando falla con ACK estructurado y recuperable. El resultado declara
   explícitamente `data_snapshot_restored=true` y
   `binary_rollback_applied=false`; el rollback binario de ejecutable sigue
   pendiente hasta contar con instalador firmado de versión destino y
   supervisor/updater transaccional. El Agent quedó en versión 5.3.0.
   Validación del corte: 11/11 pruebas de fase 5, 100/100 acumuladas y análisis
   estático dirigido sin problemas.
11. Fase 6A (completada): `reiniciar_sesiones` quedó movido a un servicio
   local seguro (`AgentSessionService`) en lugar de ejecutar lógica cruda desde
   el procesador de comandos. El comando sólo acepta `reason` y `request_id`,
   rechaza parámetros libres o cadenas con forma SQL/shell, cierra únicamente
   sesiones de caja abiertas (`caja_sesiones.estado = abierta`), deja intactas
   las sesiones ya cerradas, tolera instalaciones sin tabla de caja devolviendo
   `closed_sessions=0`, registra auditoría y responde con ACK estructurado
   `MERKAERP_AGENT_SESSIONS_1`. La capacidad `reiniciar_sesiones` ya se anuncia
   porque cuenta con implementación y pruebas. El Agent quedó en versión
   5.1.0. Validación del corte: 4/4 pruebas nuevas, 94/94 acumuladas y análisis
   estático dirigido sin problemas.
12. Fase 6B (completada): `reiniciar` quedó implementado como reinicio
   controlado de proceso mediante `AgentRestartService`. El comando sólo acepta
   `reason`, `delay_seconds` y `request_id`; rechaza parámetros libres, cadenas
   con forma SQL/shell y delays fuera de 2 a 60 segundos. Antes de relanzar
   persiste la intención en `app_config`, registra auditoría, devuelve ACK
   durable `MERKAERP_AGENT_RESTART_1` sin exponer rutas locales y agenda el
   relanzamiento diferido del ejecutable actual con cierre del proceso. En
   pruebas el scheduler se inyecta para validar el flujo sin cerrar el runner.
   La capacidad `reiniciar` ya se anuncia porque cuenta con implementación y
   pruebas. El Agent quedó en versión 5.2.0. Validación del corte: 4/4 pruebas
   nuevas, 98/98 acumuladas y análisis estático dirigido sin problemas.
13. Fase 5C-2 (hotfix firmado completado): `aplicar_hotfix` consume
   exclusivamente un `manifest_token` de publicador validado para la
   instalación local. El manifiesto firmado debe declarar `hotfix_id`,
   `target_version`, checksum opcional y una lista acotada de operaciones
   seguras: reparación del catálogo local, configuración administrada o feature
   flags conocidas. Antes de aplicar crea respaldo integral pre-hotfix, lo
   verifica y calcula SHA-256; si alguna operación falla intenta restaurar ese
   snapshot y devuelve ACK fallido controlado. El ACK exitoso conserva
   `hotfix_id`, `backup_ref`, hash del snapshot y operaciones aplicadas, sin
   exponer rutas locales ni ejecutar scripts/instaladores remotos. El Agent
   quedó en versión 5.4.0. Validación del corte: 13/13 pruebas de fase 5,
   102/102 acumuladas y análisis estático dirigido sin problemas.
14. Fase 5D (rollback binario completado): `rollback_actualizacion` puede
   combinar restauración de snapshot de datos con rollback binario agendado.
   Cuando recibe `manifest_token`, valida un manifiesto de publicador
   `merkaerp-rollback` ligado a la instalación, exige `target_version`,
   `from_version`, `installer_ref` y SHA-256, localiza el instalador sólo por
   referencia segura en el catálogo local, recalcula el hash y rechaza cualquier
   ruta/script remoto. Después de verificar y restaurar el snapshot de datos,
   `AgentBinaryRollbackService` escribe un plan local
   `MERKAERP_BINARY_ROLLBACK_PLAN_1`, persiste `cc_pending_binary_rollback`,
   registra auditoría y lanza el instalador firmado como proceso externo
   separado del proceso activo. El ACK declara
   `binary_rollback_scheduled=true`, sin exponer rutas locales ni afirmar que el
   binario ya fue reemplazado antes del helper. La capacidad
   `rollback_actualizacion` ya se anuncia. El Agent quedó en versión 5.5.0.
   Validación del corte: 14/14 pruebas de fase 5, 103/103 acumuladas y análisis
   estático dirigido sin problemas.
15. Cierre pendiente fuera de código: prueba end-to-end contra Control Center
   real y builds firmados de publicación. Windows local ya está compilado en dos
   perfiles limpios; Android Release requiere las llaves
   `MERKA_RELEASE_STORE_FILE`, `MERKA_RELEASE_KEY_ALIAS`,
   `MERKA_RELEASE_STORE_PASSWORD` y `MERKA_RELEASE_KEY_PASSWORD`.
