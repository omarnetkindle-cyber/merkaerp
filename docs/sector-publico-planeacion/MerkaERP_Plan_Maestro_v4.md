# MerkaERP — Plan Maestro de Restauración v4
### Actualizado con el plan de producto v1.1 del sector público: roles/segregación de funciones y consolidación multi-entidad (NICSP 40)

---

## Qué cambió respecto a v3

Se integró el documento `MerkaERP_SectorPublico_Plan_v1_1.md` (visión completa de producto/negocio, 11 macro-sistemas con base normativa detallada, más una sección de "Requisitos Arquitectónicos y de Habilitación" y "Validación de Mercado y Modelo Comercial").

De ahí se incorporan al plan técnico dos piezas que no estaban cubiertas en v3:

- **Fase 6 (nueva): Roles y segregación de funciones.** Requisito legal, no opcional — un tesorero no puede aprobar su propio pago, un contador no puede expedir su propio CDP. Ninguna fase anterior tocaba permisos; se agrega después de que el backend y la UI del sector público estén completos y verificados (Fase 5), porque no tiene sentido definir quién puede tocar un botón que todavía no existe.
- **Fase 8 (antes Fase 7, ampliada): Multi-usuario, sync y consolidación multi-entidad (NICSP 40).** Si MerkaERP se vende a una gobernación, esta necesita ver el consolidado de municipios/hospitales/entidades descentralizadas que le reportan — con eliminación de operaciones recíprocas y plan de cuentas homologado. Es la misma naturaleza arquitectónica (multi-tenant) que la fase de multi-usuario que ya teníamos, así que se fusionan en una sola fase con dos prompts secuenciales.

Lo que **no** se incorpora como fase de código (no son tareas para un agente de IA, son compromisos de negocio/certificación): certificación ISO 27001, migración de datos históricos por cliente, y el proceso de licitación pública. Quedan anotados al final del documento para que no se pierdan de vista, sin prompts asociados.

La estimación de esfuerzo del documento de producto (76-90 semanas, 120-150 persona-semana) asume construir los 11 macro-sistemas desde cero; las auditorías reales del repo muestran que buena parte ya existe, así que esa cifra no se usa como referencia — el plan técnico sigue basándose en lo que las auditorías de código confirman, no en estimaciones de un documento de producto que no miró el repo.

---

## Qué cambió en v3 respecto a v2 (histórico)

Dos hallazgos nuevos, ambos de auditorías reales hechas por agentes de IA trabajando directo sobre el repo:

1. **Fase 0 más precisa**: apareció un archivo crítico no listado en v2 (`api_auth_middleware.dart`, 10 errores, rompe toda la capa de auth de la API) y dos fixes triviales de una línea que también estaban sin listar. Se reordena la fase por gravedad real.

2. **Hallazgo crítico — la UI del sector público es 100% decorativa.** Una auditoría página por página de las 12 páginas de `lib/sector_publico/` confirmó que **ninguna** tiene formularios reales, llama a un servicio, persiste en base de datos, muestra listas de registros, o valida bloqueos normativos. Todas siguen el mismo patrón: ícono + botón "crear" + diálogo decorativo + `SnackBar` de éxito falso.

   Esto es compatible con la auditoría de v2 que decía que los macro-sistemas 2 (Financiero), 4 (Contratación), 5 (Nómina) y 11 (Transparencia) tenían "lógica real, no cáscara" — esa auditoría miraba la capa de **servicios** (`lib/sector_publico/*/services/`), que sí existe y es real. El problema es que **la UI nunca se conectó a esos servicios**. Es decir: hay motor, pero ninguna página tiene el cableado hacia él.

   **Consecuencia para el plan:** no tiene sentido seguir completando backend (Fase 3 de v2: SGR, SICODIS, actas, etc.) antes de conectar lo que YA está completo. Por eso esta versión inserta una fase nueva — **conectar la UI a servicios reales** — antes de cerrar más brechas de backend, y la vuelve a retomar después para las páginas cuyo backend se termine de completar.

**Regla de oro sin cambios:** después de cada fase, correr `flutter analyze` y `flutter test`, commit solo si no se agregaron errores nuevos. No avanzar con el build roto. No commitear sin revisión previa del diff.

---

## Fase 0 — Triage de Compilación

**Objetivo:** dejar el proyecto compilable antes de tocar organización o UI. Reordenada por gravedad real (antes se agrupaba por causa raíz; ahora se ataca primero lo que bloquea más).

**Orden de ataque:**

| Orden | Archivo | Errores | Por qué va aquí |
|---|---|---|---|
| 1 | `lib/core/api/api_auth_middleware.dart` | 10 | 🔴 Crítico y aislado — bloquea toda la capa de auth de la API. Firma de `shelf` desalineada (`Handler` / `FutureOr<Response> Function(Handler)`) y llamadas a `unauthorized()`/`forbidden()` con argumentos que ya no aplican. |
| 2 | `lib/core/api/endpoints/inventory_api.dart` | 7 | 🔴 Llave sin cerrar en línea 256 — puede esconder errores no vistos por el analizador. Además llama a métodos inexistentes (`_updateProduct`, `_deleteProduct`, `_getLowStockProducts`). |
| 3 | `lib/core/multi_company/financial_consolidation.dart` | 7 | 🔴 Llave sin cerrar en línea 69, mismo riesgo que el anterior. |
| 4 | `lib/db_helper.dart` (fix de raíz) | — | 🟠 Un método devuelve `Object?` donde se espera `List<Map<String,Object?>>`. Arreglarlo aquí resuelve de golpe ~21 errores en 4 archivos consumidores (`dashboard_analytics.dart`, `financial_consolidation.dart`, `transfer_service.dart`, y posibles otros). |
| 5 | `lib/core/export/export_service.dart` | 16 | 🟡 API vieja de `excel: ^4.0.6` (ahora usa `CellValue`), falta import de `share_plus`. |
| 6 | `lib/core/invoicing/e_invoice_config.dart` | 16 | 🟡 Mapas `const` con valores no constantes (8 bloques). |
| 7 | `lib/core/security/timestamp_service.dart` | 5 | 🟡 API vieja de `pointycastle: ^3.7.3` (`RSAKeyGeneratorParameters`, `toUnsigned`, `BigInt.toBytes`). |
| 8 | `lib/core/security/database_encryption_service.dart` | 1 | 🟢 Función `async` con tipo de retorno que no es `Future`. Fix de una línea. |
| 9 | `lib/core/predictive/predictive_analytics.dart` | 1 | 🟢 Variable `dailyConsumed` usada pero nunca declarada — revisar la lógica antes de decidir el fix, no es solo sintaxis. |

### Prompt para el agente de IA (Fase 0)

```
Estoy arreglando errores de compilación en un proyecto Flutter/Dart llamado MerkaERP.
No reorganices ni muevas archivos en esta fase — solo arregla errores de compilación.
Este log de errores puede estar desactualizado (viene de una auditoría previa) — antes de
empezar, corre flutter analyze y confirma si esto sigue vigente.

Ataca los archivos en este orden exacto, uno a la vez, corriendo flutter analyze después
de cada uno antes de seguir con el siguiente:

1. lib/core/api/api_auth_middleware.dart (10 errores)
   Las funciones (requireAuth, requireRole, requireAnyRole, rateLimit, cors, logging)
   devuelven un tipo que no coincide con lo que espera el paquete shelf instalado
   (revisa la versión real en pubspec.lock). Revisa también las llamadas a
   unauthorized()/forbidden() — probablemente cambiaron de argumento posicional a
   nombrado (ej. jsonBody) en la versión instalada. Verifica todos los call sites antes
   de cambiar firmas.

2. lib/core/api/endpoints/inventory_api.dart:256 y
   lib/core/multi_company/financial_consolidation.dart:69
   Ambos tienen "Expected to find '}'". Lee el archivo completo primero para entender
   qué bloque quedó mal cerrado — no agregues una llave a ciegas, puede haber lógica
   cortada a medias. inventory_api.dart también llama a métodos que no existen
   (_updateProduct, _deleteProduct, _getLowStockProducts) — decide si hay que
   implementarlos o si la llamada está mal y debe apuntar a otro método existente.

3. lib/db_helper.dart — antes de tocar los archivos con "Object? no asignable a
   List<Map<String,Object?>>", revisa la firma real del método afectado aquí y decide
   si el fix correcto es corregir el tipo de retorno en la fuente (probablemente resuelve
   muchos de golpe) o hacer cast en cada consumo. Prefiere el fix de raíz si no rompe a
   otros consumidores — verifica TODOS los call sites primero.

4. lib/core/export/export_service.dart — adapta a la API real de excel 4.x instalada
   (revisa pubspec.lock, no adivines nombres de clases). Agrega el import de share_plus
   si falta.

5. lib/core/invoicing/e_invoice_config.dart — los 8 mapas const con valores no
   constantes: decide caso por caso si extraer el valor fuera del const o quitar el
   const del mapa completo.

6. lib/core/security/timestamp_service.dart — adapta a la API real de pointycastle
   3.7.3 instalada.

7. lib/core/security/database_encryption_service.dart — función async con tipo de
   retorno incorrecto, fix de una línea.

8. lib/core/predictive/predictive_analytics.dart — variable dailyConsumed usada pero
   no declarada. Antes de declararla a ciegas, revisa la lógica de la función completa
   para entender qué valor debería tener realmente.

Al final, corre flutter analyze completo y flutter test, y repórtame cuántos errores
quedan (debe ser 0, o si queda alguno, explícame por qué no se pudo resolver).

No hagas commit todavía — déjame revisar el diff primero.
```

---

## Fase 1 — Auditoría y adelgazamiento de `main.dart`

**Objetivo:** `main.dart` tiene 1657 líneas mezclando arranque de la app, secciones de menú, selección de modo y widgets. Sacar todo lo que no sea `main()` y configuración de `MaterialApp`.

**Contexto real:** `lib/core/` ya existe y está maduro — esta fase NO crea esa carpeta, la usa.

### Prompt para el agente de IA (Fase 1)

```
Trabajas sobre MerkaERP, un proyecto Flutter. La Fase 0 (compilación limpia) ya está
completa — confírmalo corriendo flutter analyze antes de empezar; si hay errores, detente
y avísame.

lib/core/ ya existe con subcarpetas maduras (invoicing, export, security, multi_company,
dashboard, company, branch, etc.) — NO crees una estructura nueva, usa la existente.

Objetivo: reducir lib/main.dart a la función main() y la configuración de MaterialApp/tema,
sacando todo lo demás a ubicaciones apropiadas.

Pasos:
1. Lee lib/main.dart completo y haz un inventario de qué hace cada bloque de código.
2. Para cada bloque que no sea arranque/tema, identifica la carpeta de lib/core/ o el
   módulo (lib/sector_publico/, lib/sales/, etc.) donde debería vivir.
3. Presta atención especial a _obtenerTipoEntidad() y _buildCentroTrabajo() (línea ~1443,
   donde baseSections = _seccionesSectorPublico()) — es el selector de modo
   Comercial/Público existente. NO lo elimines ni lo rompas; en esta fase solo muévelo de
   archivo, se formaliza en la Fase 6.
4. Mueve el código por bloques pequeños, corriendo flutter analyze después de cada
   movimiento — no muevas todo de una vez.
5. Verifica que todos los imports se actualicen correctamente.
6. Al final, main.dart debe quedar por debajo de 150 líneas. Corre flutter analyze y
   flutter test completos.
7. No hagas commit todavía — déjame revisar el diff primero.
```

---

## Fase 2 — Consolidación del motor DIAN

**Objetivo:** Unificar la lógica de facturación electrónica DIAN, hoy dispersa en 14 archivos, dentro de `lib/core/invoicing/` (que ya existe).

**Archivos con lógica DIAN identificados:**
```
lib/facturacion_electronica_page.dart      (UI)
lib/core/invoicing/e_invoice_config.dart
lib/core/export/export_service.dart
lib/core/api/api_contract.dart
lib/core/features/feature_flag.dart
lib/db_helper.dart
lib/contabilidad_page.dart
lib/licensing_page.dart
lib/seed_operations.dart
lib/exportar_excel.dart
lib/declaraciones_tributarias_page.dart
lib/manual_page.dart
lib/services/merka_intelligence_service.dart
lib/ui/sales_mode_panel.dart
```

### Prompt para el agente de IA (Fase 2)

```
Trabajas sobre MerkaERP, un proyecto Flutter. Las Fases 0 y 1 ya están completas —
confírmalo con flutter analyze antes de empezar.

Objetivo: consolidar toda la lógica de facturación electrónica DIAN (generación de XML,
firma digital, validaciones fiscales, config del proveedor tecnológico) dentro de
lib/core/invoicing/, que ya existe.

Estos son los archivos con lógica DIAN identificados (verifica tú también si hay otros,
buscando "dian", "cufe", "resolucion_facturacion", "factura_electronica" en todo lib/):
- lib/facturacion_electronica_page.dart
- lib/core/invoicing/e_invoice_config.dart
- lib/core/export/export_service.dart
- lib/core/api/api_contract.dart
- lib/core/features/feature_flag.dart
- lib/db_helper.dart
- lib/contabilidad_page.dart
- lib/licensing_page.dart
- lib/seed_operations.dart
- lib/exportar_excel.dart
- lib/declaraciones_tributarias_page.dart
- lib/manual_page.dart
- lib/services/merka_intelligence_service.dart
- lib/ui/sales_mode_panel.dart

Pasos:
1. Para cada archivo, identifica QUÉ PARTE es lógica DIAN (probablemente no es el
   archivo completo).
2. Diseña la estructura final dentro de lib/core/invoicing/: separa por responsabilidad
   (generación de XML, firma digital, validación, configuración del proveedor, cliente
   HTTP hacia el web service DIAN) — no un solo archivo gigante.
3. Mueve la lógica identificada a esa estructura, dejando en los archivos originales solo
   imports hacia la nueva ubicación (no dupliques código).
4. IMPORTANTE: no cambies comportamiento, solo ubicación. Si encuentras lógica duplicada
   entre dos archivos (ej. dos formas de generar el mismo XML), NO la fusiones sola —
   señálamela en tu reporte final.
5. Corre flutter analyze después de cada archivo movido, no al final.
6. Al final, dame un resumen: qué archivos quedaron, su responsabilidad, y cualquier
   duplicación no resuelta.
7. No hagas commit todavía — déjame revisar el diff primero.
```

---

## Fase 3 — Conectar la UI del sector público a los servicios reales (NUEVA, máxima prioridad después de Fase 0-2)

**Objetivo:** Las 12 páginas de `lib/sector_publico/` son decorativas — ninguna tiene formulario real, llama a servicio, persiste en BD, lista registros, ni valida bloqueos normativos. Antes de completar más backend (SGR, SICODIS, etc.), hay que conectar lo que YA está terminado en la capa de servicios.

**Por qué esta fase va antes de cerrar brechas de backend:** los macro-sistemas 2 (Financiero), 4 (Contratación), 5 (Nómina) y 11 (Transparencia) tienen servicios completos y probados — pero inservibles porque ninguna página los invoca. Conectar estos primero da valor real de inmediato, sin esperar a que el resto del backend esté listo.

**Las 12 páginas y su backend real:**

| Página | Backend (servicios) | Se puede conectar ya |
|---|---|---|
| `presupuesto_publico_page.dart` | Completo (Macro-sistema 2) | ✅ Sí |
| `contabilidad_nicsp_page.dart` | Completo (Macro-sistema 2) | ✅ Sí |
| `pac_tesoreria_page.dart` | Completo (Macro-sistema 2) | ✅ Sí |
| `contratacion_publica_page.dart` | Completo (Macro-sistema 4) | ✅ Sí |
| `nomina_publica_page.dart` | Completo (Macro-sistema 5) | ✅ Sí |
| `transparencia_page.dart` | Completo (Macro-sistema 11) | ✅ Sí |
| `auditoria_forense_page.dart` | Completo (Macro-sistema 7, parcial) | ✅ Sí |
| `planeacion_page.dart` | Falta 1.3 (trazabilidad Plan-Presupuesto) | 🟡 Parcial — conecta lo que sí existe (PDT, Banco MGA) |
| `predial_ica_page.dart` | Calcula pero no exporta declaración | 🟡 Parcial — conecta cálculo, exportación va en Fase 5 |
| `activos_estado_page.dart` | Falta 6.3 (actas de responsabilidad) | 🟡 Parcial — resto va en Fase 5 |
| `salud_publica_page.dart` | Falta 8.2 (facturación EPS-ADRES) | 🟡 Parcial — resto va en Fase 5 |
| `regalias_sgp_page.dart` | SGR vacío (0/3), SGP parcial | ❌ No — espera a Fase 4 |

### Prompt 3.1 — Confirmar el alcance real antes de tocar código

```
Trabajas sobre MerkaERP, proyecto Flutter. Las Fases 0-2 ya están completas.

Antes de escribir código, necesito que confirmes un hallazgo de una auditoría previa:
las 12 páginas de lib/sector_publico/ (presupuesto_publico_page.dart,
contabilidad_nicsp_page.dart, auditoria_forense_page.dart, predial_ica_page.dart,
contratacion_publica_page.dart, nomina_publica_page.dart, planeacion_page.dart,
activos_estado_page.dart, salud_publica_page.dart, regalias_sgp_page.dart,
transparencia_page.dart, pac_tesoreria_page.dart) supuestamente no tienen formularios
reales, no llaman a ningún servicio, no persisten en base de datos, no listan registros
existentes, y no validan bloqueos normativos — solo un botón que muestra un SnackBar de
"creado exitosamente" sin hacer nada real.

Revisa cada una de las 12 y confírmame, página por página: ¿sigue siendo así hoy?
¿Hay alguna que ya tenga algo real que la auditoría pasó por alto? Repórtame la tabla
actualizada antes de que sigamos. No escribas código todavía.
```

### Prompt 3.2 — Conectar las 7 páginas con backend completo (lote 1, alto valor inmediato)

```
Trabajas sobre MerkaERP, proyecto Flutter, dentro de lib/sector_publico/. La Fase 0-2
están completas y confirmaste el alcance real en el paso anterior.

Objetivo: conectar estas 7 páginas a sus servicios reales, que ya existen y están
completos: presupuesto_publico_page.dart, contabilidad_nicsp_page.dart,
pac_tesoreria_page.dart, contratacion_publica_page.dart, nomina_publica_page.dart,
transparencia_page.dart, auditoria_forense_page.dart.

Para cada página, en este orden, una a la vez (corre flutter analyze después de cada
una antes de seguir con la siguiente):

1. Identifica el servicio real correspondiente en lib/sector_publico/<módulo>/services/
   y sus modelos en lib/sector_publico/<módulo>/models/. Léelos para entender qué
   operaciones exponen (crear, listar, validar, etc.).
2. Reemplaza el diálogo decorativo por un formulario real: usa TextFormField,
   DropdownButtonFormField, y los campos que el modelo real requiera — no inventes
   campos que el modelo no tiene.
3. Conecta el botón de guardar al método real del servicio (no un Navigator.pop +
   SnackBar falso). Maneja errores del servicio y muéstralos al usuario.
4. Agrega un ListView/FutureBuilder que consulte y muestre los registros reales ya
   guardados en base de datos — no solo el formulario de creación.
5. Si el servicio expone validación de bloqueos normativos (ej. cierres presupuestales,
   periodos cerrados), la página debe respetarlos: deshabilitar o advertir antes de
   permitir la acción, no solo dejar que el guardado falle silenciosamente.
6. Tests en test/sector_publico/ para la página, siguiendo el patrón existente si hay
   tests de widgets en el proyecto; si no existe ese patrón, dímelo antes de inventar uno.

Al final de las 7 páginas, corre flutter analyze y flutter test completos y dame un
resumen de qué quedó conectado y qué encontraste que no cuadraba (ej. un servicio que
esperabas completo y no lo estaba).

No hagas commit todavía — déjame revisar el diff primero.
```

### Prompt 3.3 — Conectar lo parcial: planeación, predial/ICA, activos, salud (lote 2, hasta donde el backend alcance hoy)

```
Trabajas sobre MerkaERP, proyecto Flutter, dentro de lib/sector_publico/. El lote 1
(Prompt 3.2) ya está conectado y probado.

Objetivo: conectar estas 4 páginas hasta donde su backend actual lo permita — sin
inventar la parte que falta, esa se hace en la Fase 4:

1. planeacion_page.dart — conecta PDT y Banco de Proyectos MGA (ambos completos, con
   llamadas HTTP reales a DNP). NO conectes el "motor de trazabilidad Plan-Presupuesto"
   porque no existe todavía (macro-sistema 1.3) — dejá un TODO claro en el código y en
   tu reporte final marcando exactamente qué falta.

2. predial_ica_page.dart — conecta el cálculo de liquidación (ica_service.dart,
   predial_service.dart ya lo hacen). NO conectes un botón de "exportar declaración"
   todavía porque ese método no existe en el servicio — la exportación se agrega en la
   Fase 4 y se conecta después.

3. activos_estado_page.dart — conecta clasificación de bienes y depreciación NICSP17
   (ambos completos). NO conectes actas de responsabilidad — no existe el modelo/servicio
   todavía, se crea en Fase 4.

4. salud_publica_page.dart — conecta RIPS (rips_service.dart, ya genera el archivo
   plano real) y glosas (glosas_service.dart). NO conectes facturación/contratación
   EPS-ADRES — no existe el servicio todavía, se crea en Fase 4.

Mismo estándar que en el lote 1: formularios reales, persistencia real, listas reales,
validación de bloqueos normativos donde el servicio lo exponga. Corre flutter analyze
después de cada página.

Al final, dame un resumen explícito de qué quedó conectado en cada página y qué botón/
funcionalidad quedó pendiente (con el TODO correspondiente) para cuando cerremos las
brechas de backend en la Fase 4.

No hagas commit todavía — déjame revisar el diff primero.
```

---

## Fase 4 — Cerrar brechas de backend del sector público

**Objetivo:** `lib/sector_publico/` está aislado arquitectónicamente y ahora parcialmente conectado a su UI (Fase 3) — esta fase completa lo que falta en la capa de servicios, brecha por brecha.

**Estado por macro-sistema:**

| # | Macro-sistema | Estado |
|---|---|---|
| 1 | Planeación y Proyectos | Falta 1.3 Motor de trazabilidad Plan-Presupuesto-Resultado |
| 3 | Rentas y Tributos | Predial e ICA calculan pero no exportan declaración |
| 6 | Almacén y Activos | Falta 6.3 Actas de responsabilidad |
| 7 | Trazabilidad y Rendición | Faltan SIIF Nación, SIA Observa, FUT real (Formulario Único Territorial — ojo, existe `fut_service.dart` que es "Fondo de Unidad de Tesorería", concepto distinto), informe al Concejo |
| 8 | Salud Pública | Falta 8.2 Facturación/contratación EPS-ADRES |
| 9 | SGR (Regalías) | Vacío: falta OCAD, bienalidades, reporte SPGR — el más débil, 0/3 |
| 10 | SGP (Participaciones) | Falta reporte SICODIS |

Ejecutar **una brecha a la vez**, no todas de golpe.

### Prompt 4.1 — SIIF Nación y SIA Observa

```
Trabajas sobre MerkaERP, proyecto Flutter, dentro de lib/sector_publico/. Las fases
previas (0-3) ya están completas y el proyecto compila limpio.

Voy a darte contexto de un módulo hermano YA IMPLEMENTADO que debes usar como patrón:
lib/sector_publico/auditoria/services/chip_reporter_service.dart y su modelo
lib/sector_publico/auditoria/models/reporte_chip.dart. Ese servicio genera formularios
CGN2015_001 a 005, los guarda en BD vía sqflite, valida cuadres contables, y exporta a
formato plano. Léelo primero para entender el patrón de este proyecto antes de escribir
nada nuevo.

Objetivo: crear dos servicios nuevos siguiendo ese mismo patrón (misma estructura de
carpetas: database/, models/, services/, pages/):

1. SIIF Nación (lib/sector_publico/siif/):
   - Investiga la estructura real de reporte que exige el Ministerio de Hacienda para
     entidades territoriales que reportan a SIIF Nación (presupuesto, tesorería, pagos).
     Si no tienes certeza de la estructura exacta del archivo plano, dilo explícitamente
     en el código con un comentario, no inventes campos.
   - Debe leer datos desde los módulos ya existentes lib/sector_publico/presupuesto/ y
     lib/sector_publico/contabilidad/ (no dupliques esos datos, referencia los modelos
     existentes: Apropiacion, CDP, RP, Obligacion, Pago).
   - Periodicidad mensual.

2. SIA Observa (lib/sector_publico/auditoria/services/sia_observa_service.dart, junto
   al chip_reporter_service.dart existente):
   - Genera el archivo plano .txt anual para el Plan de Mejoramiento de la Contraloría.
   - Debe leer datos desde contratación, presupuesto, y nómina, igual que hace CHIP.

Para ambos: incluye auditoría (usa AuditoriaService como hace CHIP), validación de
cuadres antes de exportar, y tests básicos en test/sector_publico/.

Después de crear cada servicio, conecta el botón correspondiente en
auditoria_forense_page.dart (ya está conectada desde la Fase 3, solo agrega la nueva
opción de reporte).

No hagas commit todavía — déjame revisar el diff primero.
```

### Prompt 4.2 — FUT real (Formulario Único Territorial) y renombrar el FUT existente

```
Trabajas sobre MerkaERP, proyecto Flutter, dentro de lib/sector_publico/.

IMPORTANTE — colisión de nombres: ya existe lib/sector_publico/activos/models/fut.dart
y lib/sector_publico/activos/services/fut_service.dart, pero ese "FUT" significa
"Fondo de Unidad de Tesorería" (manejo de recursos de terceros) — concepto DISTINTO al
que necesito ahora, "Formulario Único Territorial" del DNP/Ministerio de Hacienda
(reporte trimestral de ingresos, gastos, deuda y regalías vía Excel + plataforma Chip).

Pasos:
1. Renombra el FUT existente para evitar la confusión: fut.dart ->
   fondo_unidad_tesoreria.dart, fut_service.dart -> fondo_unidad_tesoreria_service.dart,
   clase FUT -> FondoUnidadTesoreria (actualiza todas las referencias en el proyecto,
   verifica con flutter analyze que no quede nada roto).
2. Crea el FUT real (Formulario Único Territorial) en
   lib/sector_publico/auditoria/services/fut_territorial_service.dart, siguiendo el
   patrón de chip_reporter_service.dart. Debe consolidar datos de ingresos, gastos,
   deuda pública y regalías, y exportar tanto a Excel como al formato de la plataforma
   Chip.
3. Conecta el nuevo reporte en auditoria_forense_page.dart (ya conectada desde Fase 3).
4. Tests en test/sector_publico/.

No hagas commit todavía — déjame revisar el diff primero.
```

### Prompt 4.3 — SGR completo: OCAD, bienalidades, reporte SPGR (el macro-sistema más débil, 0/3)

```
Trabajas sobre MerkaERP, proyecto Flutter, dentro de lib/sector_publico/regalias/.

Ya existe regalias_service.dart (estimación, recepción, consulta de regalías) y
sgp_service.dart (Sistema General de Participaciones — OJO, es un sistema distinto a
SGR, no lo confundas ni lo mezcles). Léelos primero para entender el patrón y los
modelos existentes (Regalia, en regalias/models/regalia.dart).

Objetivo: completar el macro-sistema de SGR (Sistema General de Regalías):

1. OCAD (Órganos Colegiados de Administración y Decisión):
   - Modelo para sesiones OCAD, proyectos presentados, votos/decisiones, actas.
   - Servicio para registrar sesiones y sus resultados (proyecto aprobado/rechazado,
     monto asignado).
   - Debe conectarse con el Banco de Proyectos MGA existente en
     lib/sector_publico/planeacion/ (un proyecto de regalías normalmente nace ahí).

2. Bienalidades:
   - El SGR opera en periodos bianuales. Extiende el modelo de Regalia o crea un modelo
     BienioSGR que agrupe la ejecución presupuestal del SGR por bienio, con estados
     (vigente, cerrado).

3. Reporte SPGR (Sistema de Presupuesto y Giro de Regalías):
   - Servicio de exportación siguiendo el patrón de chip_reporter_service.dart, que
     consolide OCAD + bienalidades + ejecución en el formato que exige el SPGR. Si no
     tienes certeza de la estructura exacta, dilo en un comentario, no inventes campos.

4. Conecta todo esto en regalias_sgp_page.dart (esta página quedó marcada como "no
   conectable todavía" en la Fase 3 — ahora sí tiene backend real para conectar; sigue
   el mismo estándar de esa fase: formulario real, persistencia real, lista real,
   validación de bloqueos normativos).

Tests en test/sector_publico/ siguiendo el patrón existente.

No hagas commit todavía — déjame revisar el diff primero.
```

### Prompt 4.4 — Brechas menores (actas de responsabilidad, declaraciones ICA/Predial, SICODIS, EPS/ADRES)

```
Trabajas sobre MerkaERP, proyecto Flutter, dentro de lib/sector_publico/.

Necesito cerrar 4 brechas menores, cada una pequeña. Hazlas una por una, corriendo
flutter analyze después de cada una:

1. Actas de responsabilidad (lib/sector_publico/activos/):
   Ya existe activos_service.dart y activo_estado.dart. Agrega un modelo y servicio para
   actas de responsabilidad — el documento que asigna un bien del Estado a un funcionario
   bajo su custodia, con historial de traspasos. Conecta esto en activos_estado_page.dart
   (quedó pendiente desde la Fase 3).

2. Exportación de declaraciones ICA/Predial (lib/sector_publico/rentas/):
   ica_service.dart y predial_service.dart ya calculan la liquidación pero no generan
   el documento de declaración final. Agrega el método de exportación a ambos servicios,
   siguiendo el patrón de exportarAPlano() de chip_reporter_service.dart. Conecta el
   botón correspondiente en predial_ica_page.dart (quedó pendiente desde la Fase 3).

3. Reporte SICODIS (lib/sector_publico/regalias/, junto a sgp_service.dart):
   sgp_service.dart ya asigna participaciones (SGP) pero no genera el reporte de
   certificación de destinación que exige SICODIS. Agrega ese servicio de exportación
   y conéctalo donde corresponda en la UI de SGP/regalías.

4. Facturación/contratación EPS-ADRES (lib/sector_publico/salud/):
   Ya existe rips_service.dart y glosas_service.dart, pero falta el servicio
   intermedio: registrar contratos con EPS/ADRES y generar las facturas de prestación
   de servicios que después se concilian vía glosas. Sigue el patrón de los servicios
   de salud existentes. Conecta esto en salud_publica_page.dart (quedó pendiente desde
   la Fase 3).

Tests en test/sector_publico/ para cada uno.

No hagas commit todavía — déjame revisar el diff primero.
```

---

## Fase 5 — Verificación final de la UI del sector público

**Objetivo:** con todo el backend completo (Fase 4), confirmar que las 12 páginas quedaron 100% conectadas — cero botones decorativos, cero TODOs pendientes de la Fase 3.

### Prompt para el agente de IA (Fase 5)

```
Trabajas sobre MerkaERP, proyecto Flutter. Las Fases 0-4 ya están completas.

Repite la auditoría de la Fase 3 (Prompt 3.1) sobre las 12 páginas de
lib/sector_publico/, pero esta vez debe dar 12/12 con formulario real, servicio real,
persistencia real, lista real, y validación de bloqueos normativos donde aplique.

Presta especial atención a los TODOs que quedaron marcados en la Fase 3 (planeación
1.3, exportación de declaración predial/ICA, actas de responsabilidad, facturación
EPS-ADRES, SGR) — confirma que cada uno se resolvió y el botón/flujo correspondiente
ya está conectado, no solo que el servicio existe.

Dame la tabla final, página por página, con el mismo formato de la auditoría original.
Si encuentras algo que sigue decorativo, dímelo explícitamente antes de darlo por
cerrado.

No hagas commit todavía — déjame revisar el diff primero.
```

---

## Fase 6 — Roles y segregación de funciones (NUEVA)

**Objetivo:** en el sector público los permisos no son configuración por conveniencia, son ley. El sistema debe impedir, como regla dura, que un mismo usuario ejecute dos roles que la norma exige mantener separados.

**Segregaciones clave identificadas en el plan de producto (no exhaustivo — el agente debe confirmar contra el código real):**

| Rol | No puede hacer |
|---|---|
| Alcalde / Representante legal | Autoliquidarse pagos |
| Secretario de Hacienda | Expedir CDP ni RP directamente |
| Tesorero | Expedir CDP/RP de su propio pago |
| Contador | Aprobar ni ejecutar pagos |
| Jefe de Rentas/Tesorería de Ingresos | Administrar el gasto, solo el ingreso |
| Jefe de Control Interno | Modificar registros — solo lectura + módulo de auditoría forense |

### Prompt 6.1 — Auditar qué existe hoy en materia de permisos

```
Trabajas sobre MerkaERP, proyecto Flutter. Las Fases 0-5 ya están completas.

Antes de escribir nada, audita qué existe hoy en materia de roles y permisos:
- Busca en todo lib/ referencias a roles, permisos, RBAC, o similar (revisa
  especialmente lib/core/security/ y lib/licensing/).
- Confirma si hay algún modelo de Usuario con rol asignado, y si las páginas o
  servicios ya validan ese rol antes de ejecutar una acción, o si por ahora cualquier
  usuario autenticado puede hacer cualquier cosa.

Repórtame el estado real antes de que decidamos el alcance exacto de esta fase — si ya
existe una base de roles genérica (aunque sea del lado comercial), la reusamos en vez
de construir una paralela.
```

### Prompt 6.2 — Implementar segregación de funciones del sector público

```
Trabajas sobre MerkaERP, proyecto Flutter, dentro de lib/sector_publico/ y
lib/core/security/ (según lo que confirmaste en el paso anterior).

Objetivo: implementar la segregación de funciones exigida por ley para el sector
público, como regla dura del sistema, no como configuración opcional:

- Alcalde/representante legal: no puede autoliquidarse pagos.
- Secretario de Hacienda: no puede expedir CDP ni RP directamente.
- Tesorero: no puede expedir CDP/RP de su propio pago, solo ejecuta el pago ya
  aprobado.
- Contador: no puede aprobar ni ejecutar pagos, solo registra y ajusta asientos
  contables.
- Jefe de Rentas/Tesorería de Ingresos: solo administra el ingreso (predial, ICA,
  cobro coactivo), no el gasto.
- Jefe de Control Interno: acceso de solo lectura a todo el sistema + módulo de
  auditoría forense; no puede modificar ningún registro.

Pasos:
1. Si ya existe un modelo de roles (confirmado en el paso anterior), extiéndelo con
   estos roles del sector público. Si no existe nada, diséñalo desde
   lib/core/security/ siguiendo el patrón de arquitectura ya usado en ese módulo.
2. La validación de segregación debe vivir en la capa de servicio (no solo ocultar el
   botón en la UI) — un usuario no debe poder ejecutar la acción prohibida ni
   llamando al servicio directamente.
3. Conecta esto en las páginas ya funcionales de la Fase 3/5 (presupuesto, tesorería,
   contabilidad, rentas, auditoría forense) — cada acción sensible debe validar el rol
   del usuario actual antes de ejecutarse.
4. Tests en test/sector_publico/ que confirmen explícitamente que un tesorero NO puede
   aprobar su propio pago, y que un contador NO puede ejecutar pagos (al menos estos
   dos casos, más los que consideres críticos).
5. Corre flutter analyze y flutter test al final.

No hagas commit todavía — déjame revisar el diff primero.
```

---

## Fase 7 — Formalizar el selector de modo Comercial/Público

**Objetivo:** El selector ya existe como un `if` embebido (según dónde haya quedado tras la Fase 1). Convertirlo en pantalla y flujo de navegación propios.

### Prompt para el agente de IA (Fase 6)

```
Trabajas sobre MerkaERP, proyecto Flutter. Las fases 0-6 ya están completas.

Ya existe un selector de modo básico: la función _obtenerTipoEntidad() determina si la
entidad es 'publica' o 'privada', y según eso se elige entre _seccionesSectorPublico()
o las secciones comerciales. Encuentra dónde quedó ese código después de la Fase 1.

Objetivo: formalizar esto en una arquitectura de navegación explícita:

1. Crea una pantalla dedicada SelectorModoScreen (ubícala en lib/core/ en la carpeta que
   consideres apropiada) que muestre las dos opciones (Comercial / Sector Público) de
   forma clara, para los casos donde el tipo de entidad no esté ya determinado.
2. Si el tipo de entidad YA está determinado (la mayoría de los casos), el selector no
   debe interrumpir el flujo — debe usarse la lógica existente de _obtenerTipoEntidad()
   para saltárselo automáticamente. El selector manual es solo para reconfiguración o
   primer uso.
3. Revisa si ya existe enrutamiento con go_router o Navigator 2.0 (busca en
   pubspec.yaml y en el código) antes de decidir cómo implementar la navegación — si el
   proyecto usa Navigator 1.0 tradicional, no introduzcas un paquete de routing nuevo
   sin preguntarme primero.
4. Asegúrate de que las opciones de un modo estén completamente ocultas cuando se está
   en el otro modo (revisa que no queden rutas o botones accesibles cruzados).

Corre flutter analyze y flutter test al final. No hagas commit todavía — déjame revisar
el diff primero.
```

---

## Fase 8 — Multi-usuario, sincronización en la nube y consolidación multi-entidad (NICSP 40)

**Objetivo:** Fase de mayor riesgo y alcance de todo el plan — no empezarla hasta que las fases 0-7 estén sólidas y probadas. Cubre dos problemas relacionados pero distintos: (a) que varios usuarios trabajen simultáneamente con auth centralizada y sync en la nube, y (b) que una entidad "padre" (gobernación) vea el consolidado de sus entidades "hijas" (municipios, hospitales, descentralizadas) — requisito de la NICSP 40 si se vende a gobernaciones.

**Contexto real:** el proyecto ya tiene `lib/licensing/`, `lib/sync/` (con `application/` y `data/`), y `lib/services/hybrid_sync_service.dart`, `lib/services/sync_service.dart` — hay una base de sincronización parcial que hay que auditar antes de asumir que se construye desde cero. También existe `lib/core/multi_company/` (visto en la Fase 0 por el bug de `financial_consolidation.dart`) — hay que confirmar si ese módulo ya resuelve parte de la consolidación multi-entidad o si es solo multi-sucursal comercial.

### Prompt 8.1 — Auditar la base real de sync y multi-entidad

```
Trabajas sobre MerkaERP, proyecto Flutter. Las fases 0-7 ya están completas y probadas.

Antes de escribir código nuevo, audita lo que ya existe:
- lib/sync/ (application/, data/)
- lib/services/hybrid_sync_service.dart
- lib/services/sync_service.dart
- lib/licensing/
- lib/core/company/company_context.dart
- lib/core/branch/branch_context.dart
- lib/core/multi_company/ (incluye financial_consolidation.dart, transfer_service.dart,
  ya arreglados en la Fase 0 — revisa qué tan cerca están de un modelo de consolidación
  jerárquica entidad-padre/entidad-hija, o si son puramente multi-sucursal comercial)

Repórtame primero, en dos bloques separados:
1. Sync/multi-usuario: ¿qué tan cerca está esto de un modelo multi-tenant real con
   autenticación centralizada y sync en tiempo real? ¿Es sync offline-first punto a
   punto, o ya contempla un backend central?
2. Consolidación multi-entidad: ¿lib/core/multi_company/ modela jerarquía entre
   entidades (una gobernación con municipios que le reportan), o es multi-sucursal de
   una sola empresa comercial? ¿Hay algo de eliminación de operaciones recíprocas o
   plan de cuentas homologado?

No escribas código todavía — dame el reporte y decidimos juntos el alcance real de
esta fase antes de construir nada.
```

### Prompt 8.2 — Consolidación multi-entidad (NICSP 40), solo si aplica al alcance decidido

```
Trabajas sobre MerkaERP, proyecto Flutter. Ya definimos el alcance real de la Fase 8
con base en tu auditoría anterior.

Objetivo: modelo multi-tenant jerárquico para el sector público, donde una entidad
"padre" (ej. gobernación) tiene una vista consolidada de solo lectura de sus entidades
"hijas" (municipios, hospitales, entidades descentralizadas), según NICSP 40:

1. Modelo multi-tenant jerárquico: cada entidad hija opera su propia instancia de
   datos; la entidad padre tiene una vista consolidada de solo lectura, no acceso de
   escritura a los datos de sus hijas.
2. Eliminación de operaciones recíprocas: si detectas transferencias registradas entre
   dos entidades del mismo grupo (ej. gobernación → hospital), esas deben eliminarse
   del consolidado para no duplicar el gasto/ingreso.
3. Plan de cuentas homologado: valida que todas las entidades a consolidar usen el
   mismo Catálogo General de Cuentas (CGC) de la CGN antes de sumar — si una entidad
   usa un plan distinto, el sistema debe advertir, no sumar cifras no homologables.
4. Reusa lib/core/multi_company/ si tu auditoría confirmó que ya tiene la base
   estructural correcta; si es puramente multi-sucursal comercial, dime explícitamente
   qué tanto se puede extender vs. qué necesita un módulo nuevo antes de construirlo.

Tests en test/sector_publico/ o test/core/multi_company/ según dónde termine viviendo
el código.

No hagas commit todavía — déjame revisar el diff primero.
```

---

## Cómo usar este documento

1. Ejecuta las fases **en orden**, una a la vez. No saltes la Fase 0.
2. Copia el prompt de la fase al agente de IA que uses, en una conversación nueva y limpia para esa fase.
3. Después de que el agente termine, corre tú mismo `flutter analyze` y `flutter test` para confirmar antes de aceptar los cambios.
4. Haz commit al final de cada fase/sub-prompt, no a mitad de una. Así, si algo sale mal, puedes volver al punto exacto donde la fase empezó.
5. Las Fases 3, 4, 6 y 8 están divididas en sub-prompts — trátalos como fases independientes, con su propio commit cada uno.
6. Tráeme lo que el agente te devuelva en cada paso (reportes, diffs, resultados de `flutter analyze`/`flutter test`) para que yo supervise antes de que hagas commit.

## Fuera del plan de desarrollo — compromisos de negocio/certificación, no tareas de código

Estos puntos del plan de producto v1.1 son reales y hay que atenderlos en algún momento, pero no son tareas para un agente de IA sobre el repo — son trabajo de certificación, consultoría de implementación por cliente, y estrategia comercial:

- **Certificación ISO 27001 y lineamientos MinTIC (Gobierno Digital, MSPI, interoperabilidad X-Road):** proceso de certificación externo con auditor acreditado, no una tarea de desarrollo. Sí conviene, cuando se llegue ahí, pedirle a un agente que audite si la arquitectura actual (cifrado, logs, control de acceso) ya cumple los controles típicos de un SGSI — pero la certificación en sí es un trámite, no código.
- **Migración de datos históricos:** es específica de cada entidad cliente (viene de otro ERP público como SEVEN/Softexpert/Limay, o de Excel) — no se construye en abstracto ahora, se ejecuta cuando exista un cliente real con datos concretos que migrar.
- **Proceso de licitación pública (Ley 80/1993, pliegos de condiciones):** estrategia comercial y jurídica de venta, no desarrollo de producto.

## Nota sobre el backend Node.js/Odoo

El backend rescatado (`merkaerp-control-center-backend`, rama `rescate-odoo-local`) **no forma parte de este plan** — MerkaERP se mejora de forma nativa en Dart, usando el conocimiento de cómo Odoo resuelve problemas de negocio como referencia conceptual, sin integrar código Node.js paralelo. Queda archivado como material de consulta.

Para referencia futura si se decide desarchivarlo: la auditoría encontró que el código es real y sustancial (64 archivos, ~7773 líneas, cero errores de sintaxis), bloqueado por dos bugs puntuales — el manejador 404 se registraba antes que las rutas de Odoo en `server.js` (anulaba el 100% del módulo), y `xmldom: ^0.7.7` en `package.json` es una versión inventada que nunca existió en npm (la real más cercana es 0.6.0).
