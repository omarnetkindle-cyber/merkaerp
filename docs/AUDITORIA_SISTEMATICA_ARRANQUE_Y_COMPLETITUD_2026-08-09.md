# Auditoria sistematica de arranque y completitud

Fecha: 2026-08-09

## Hallazgos iniciales y correcciones

1. **Arranque.** El wrapper de licencia ejecutaba la comprobacion en cada
   build y consultaba onboarding antes de la licencia; no habia una ruta
   determinista que impidiera saltar a una pantalla publica persistida. Se
   creo lib/core/startup/startup_flow.dart y se dejo el orden
   licencia -> onboarding -> login en lib/main.dart. La funcion se prueba
   en test/core/startup_flow_test.dart.
2. **Contexto de entidad.** La migracion publica ahora crea una entidad
   vinculada al company_id legado sin reasignar silenciosamente ENT-001; si
   falta NIT usa un identificador explicito PENDIENTE-<company_id>. La sesion
   resuelve esa relacion despues del login.
3. **Foreign keys de las capturas.** Los errores ENT-001 de SIIF, flujo de
   efectivo y contratacion provenian de contexto publico inexistente o
   desvinculado. El smoke fresco de v8 ya abre esos modulos sin error; esto
   no certifica aun que cada reporte contenga datos oficiales.
4. **Configuracion.** configuracion_visibilidad recibia consultas con
   parametro/valor/vigente, pero el esquema legacy no los tenia. La
   migracion v92/v93 agrega las columnas de forma idempotente. El test de
   contexto publico y el test de servicio de configuracion pasan.
5. **Company settings.** El selector comercial escribia sin updated_at; ahora
   lo incluye. currency_service.dart tambien usa los nombres reales
   setting_key/setting_value.
6. **Garantias y esquemas legacy.** La tabla legacy warranties podia no tener
   aliases modernos. v94 y WarrantyService.createTables agregan aliases
   nullable sin inventar datos; el smoke encontro y cerro sucesivamente
   updated_at, end_date y product_name/customer_name.
7. **Mojibake.** El script versionado tool/audit_mojibake.dart encontro
   exactamente dos lineas de codigo fuente, las corrigio y en la corrida
   posterior reporto cero.
8. **Esquema/query.** tool/audit_schema_queries.dart compara las referencias
   extraidas de consultas con PRAGMA de la base fresca. Tras las migraciones
   defensivas v94-v96, reporta cero discrepancias obvias.
9. **Idempotencia de migraciones.** La suite completa encontro que una
   migracion podia ejecutarse sobre bases pequenas sin algunas tablas. v94-v96
   ahora comprueban la existencia de cada tabla antes de agregar aliases, y la
   migracion de contexto publico tolera tabla ausente o columna ya agregada.
10. **Fixtures de UI.** Al hacer explicitos los mensajes de brecha, tres tests
    seguian buscando el texto historico de “Fase 4”; sus expectativas fueron
    actualizadas al contrato visible nuevo. El fixture fiscal usaba FFI con
    isolate y dejaba bloqueado su directorio temporal; paso a
    databaseFactoryFfiNoIsolate y su teardown quedo limpio.

## Evidencia ejecutada

| Verificacion | Archivo |
|---|---|
| Smoke permanente de todos los modulos registrados: 1 passed | docs/evidencias/module_smoke_total_2026-08-09_v8.txt |
| Suite completa final: 320 passed, 3 skipped, 0 failures | docs/evidencias/auditoria_suite_completa_2026-08-09_final.txt |
| Regresiones de migracion/banners: 11 passed | docs/evidencias/auditoria_regresiones_esquema_mensajes_2026-08-09_v2.txt |
| Fixture fiscal aislado: 4 passed | docs/evidencias/commercial_tax_block1_2026-08-09.txt |
| Auditoria de consultas: tables=271 references=978 discrepancies=0 | docs/evidencias/auditoria_schema_queries_2026-08-09_final.txt |
| Mojibake antes/despues: 2 lineas encontradas, 0 posteriores | docs/evidencias/auditoria_mojibake_2026-08-09_pre.txt, ..._fix.txt, ..._post.txt |
| Startup, selector, currency, migracion y configuracion | test/core/startup_flow_test.dart, test/core/selector_modo_test.dart, test/core/currency_service_schema_test.dart, test/sector_publico/configuracion/public_context_migration_test.dart, test/sector_publico/configuracion/configuracion_general_service_smoke_test.dart |

## Mensajes de fase

La clasificacion completa vive en
docs/MENSAJES_FASE_AUDITORIA_2026-08-09.md. Se corrigieron cuatro textos
visibles que presentaban brechas como una generica “Fase 4”. No se marco como
completo lo que sigue dependiendo de credenciales, catalogos oficiales o
decisiones de producto.

## Mapa maestro

El inventario por dominio vive en
docs/MERKAERP_COMPLETITUD_GENERAL_2026-08-09.md. La conclusion global es
**sistema operable en numerosos flujos locales, pero no terminado para
certificacion productiva completa**. Las brechas externas, normativas y de
canonizacion legacy deben permanecer visibles.

## Verificaciones globales

Las verificaciones globales finales quedaron asi:

  dart format --output=none --set-exit-if-changed .
  flutter analyze
  flutter test
  flutter build windows

- dart format --output=none --set-exit-if-changed .: codigo 1 por 127
  archivos historicamente no formateados fuera del alcance; se restauraron
  esos cambios mecanicos. Los archivos tocados en esta ronda fueron
  formateados individualmente.
- flutter analyze: 243 issues found, sin errores de compilacion. Salida cruda:
  docs/evidencias/auditoria_flutter_analyze_2026-08-09_final.txt.
- flutter test: 320 pasadas, 3 omitidas, 0 fallos. Salida cruda:
  docs/evidencias/auditoria_suite_completa_2026-08-09_final.txt.
- flutter build windows: genero build/windows/x64/runner/Release/MerkaERP.exe.
  El wrapper PowerShell mostro el aviso de NuGet por stderr, pero la salida
  de Flutter confirma el artefacto construido. Salida cruda:
  docs/evidencias/auditoria_flutter_build_windows_2026-08-09.txt.
