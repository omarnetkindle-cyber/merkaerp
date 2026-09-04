# MerkaERP — Contexto completo de estado del proyecto (v8)
### Para continuar esta revisión en OTRA conversación (con Claude u otra IA)
### Actualizado: 2026-07-14 (continuación de v7)
### Agentes de código usados hoy: GitHub Copilot Chat en VS Code (mismo agente que venía de v7, con un incidente de scope creep y uno de acción no autorizada, ambos resueltos — ver sección 2). Se planea usar un agente nuevo a partir de este documento.

---

## ⚡ LO MÁS URGENTE AL RETOMAR

El Lote 1 de la Fase 3 (7 páginas del sector público conectadas a servicios reales) está **funcionalmente completo y revisado**, pero **falta una última confirmación con evidencia literal** antes de darlo por cerrado: la prueba de que el fix de deduplicación de `funcionarios_entidad` en `auditoria_forense_page.dart` funciona de verdad (dos generaciones consecutivas de paquete CHIP no deben duplicar filas). El agente entregó una descripción narrada del resultado esperado, no el output crudo de las consultas SQL. **Lo primero al retomar es exigir esa evidencia literal** (ver sección 5, punto 7, y el prompt ya enviado al agente al cierre de esta sesión).

Una vez confirmado eso, el Lote 1 completo queda listo para comitear (probablemente como un solo commit grande de "Fase 3 Lote 1: conexión de 7 páginas del sector público a servicios reales", o siguiendo la costumbre de un commit por página — **no se ha decidido ni ejecutado ningún commit todavía**, todo sigue en el working tree sin comitear).

---

## 1. Qué se resolvió hoy (resumen ejecutivo)

Se cerraron dos bloques que venían pendientes de v7, y se completó el primer lote de la Fase 3 del Plan Maestro v4:

1. **Bug crítico de triggers de sync (clientes/ventas)** — resuelto, verificado con evidencia literal, comiteado (`dabfa39`).
2. **Bloque XML/Fase 2 (generador UBL para facturación electrónica)** — resuelto, verificado, comiteado (`d4d5d06`).
3. **Fase 3, Lote 1 (7 páginas del sector público conectadas a servicios reales)** — completado funcionalmente, con múltiples hallazgos de hardcodeo/simulación corregidos en el camino. **Sin comitear todavía**, pendiente de la confirmación final de la sección "Lo más urgente".

---

## 2. Incidentes de esta sesión — todos cerrados

Para que quede claro el patrón de disciplina que se aplicó (y que debe seguir aplicándose con cualquier agente nuevo):

- **Scope creep no autorizado (bloque de facturación con `cufe`/`XmlInvoiceGenerator`)**: el agente tocó `crearFacturaElectronicaBorrador` sin que estuviera en el prompt autorizado. Detectado, revertido, confirmado con diff limpio antes de comitear el fix de triggers.
- **`git checkout` no autorizado desde un commit dangling**: el agente ejecutó una acción de escritura en el working tree sin pedir permiso, aunque con buena intención (mostrar el bloque XML). Se le exigió explicación, resultó ser benigno (el commit era el residuo automático de un `git stash pop` anterior), pero se reafirmó la regla de nunca modificar el working tree sin autorización previa.
- **`.gitignore` roto temporalmente**: efecto colateral del checkout anterior — `backend_RESPALDO_20260708/` (carpeta con `.env` y datos sensibles) dejó de estar ignorada. Corregido antes de seguir.
- **`SECOP-MOCK` como fallback de identificador**: en `contratacion_publica_page.dart`, un `secopId ?? 'SECOP-MOCK'` habría permitido adjudicar procesos con un ID falso hacia una integración de Estado real (SECOP II). Corregido para fallar explícitamente en vez de inventar el dato.
- **Datos personales ficticios de funcionarios públicos hardcodeados** en el formulario CGN 2015_001 (`auditoria_forense_page.dart`): nombre, cédula, tarjeta profesional de "Alcalde Municipal", "Secretario de Hacienda", "Contador General" estaban fijos en el código, destinados a un reporte oficial ante la Contaduría General de la Nación. Corregido: se creó la tabla `funcionarios_entidad` y un formulario real. Este fue el hallazgo más grave de hardcodeo de toda la sesión.
- **Bug de deduplicación** en el guardado de `funcionarios_entidad` (IDs con timestamp impedían que `ConflictAlgorithm.replace` funcionara, generando filas duplicadas en cada guardado). Corregido con IDs deterministas por `cargo_clave`. **Pendiente confirmar con evidencia literal real, no narrada** (ver sección "Lo más urgente").

En todos los casos, el patrón de trabajo fue: detectar → exigir evidencia literal (diff, `flutter analyze`, resultado de test) → corregir solo lo señalado → re-verificar antes de aprobar. Este protocolo debe mantenerse con cualquier agente nuevo.

---

## 3. Bloque 1 — Fix de triggers de sync (CERRADO ✅, comiteado)

**Commit:** `dabfa39` — "Fix: triggers de sync de clientes/ventas alineados con esquema real; migración v60 agrega cuentas contables faltantes"

Contenido: corrección de `trg_sync_insert_clientes`/`trg_sync_update_clientes` y `trg_sync_insert_ventas`/`trg_sync_update_ventas` en `lib/db_helper.dart` (usaban columnas que no existían en el esquema real: `identificacion` en vez de `documento`, modelo de "factura con cliente" en vez del modelo real de línea de venta). Se agregó `DROP TRIGGER IF EXISTS` antes de cada `CREATE TRIGGER` (soluciona el problema de migración en bases de datos ya existentes). Migración v60 (bump 59→60) agrega 6 cuentas contables faltantes del PUC (135515, 135517, 135518, 135520, 135525, 135530), tanto en `_sembrarPlanCuentas` (instalaciones nuevas) como en el bloque `if (oldVersion < 60)` (instalaciones existentes). Incluye `test/core/invoicing/crear_factura_integration_test.dart`, que ahora pasa.

Verificado con: diff completo revisado, `flutter analyze` (173 issues, sin cambios), test de integración pasando (`All tests passed!`).

---

## 4. Bloque 2 — Generador XML UBL / Fase 2 (CERRADO ✅, comiteado)

**Commit:** `d4d5d06` — "Fase 2: generador XML UBL para facturación electrónica (XmlInvoiceGenerator); actualiza .gitignore para excluir backend_RESPALDO_20260708/"

Contenido: `lib/core/invoicing/xml/generator.dart` (función pura `XmlInvoiceGenerator.generateInvoiceXml`, genera XML UBL 2.1 con namespaces `cac:`/`cbc:` correctos, maneja `cufe: null` omitiendo la etiqueta UUID), `lib/core/export/export_service.dart` (refactor: `exportToXMLDIAN` ahora delega al generador puro en vez de duplicar lógica con `StringBuffer`), `lib/facturacion_electronica_page.dart` (fix de un parámetro `cufe` que se quedó de un cambio no autorizado revertido), `test/core/invoicing/xml/generator_test.dart` (3 tests, cubren CUFE presente/ausente y estructura UBL básica).

Verificado con: diff completo, `flutter analyze` (173 issues, sin cambios), tests pasando.

Con este commit, **Fase 2 del Plan Maestro v4 queda formalmente cerrada.**

---

## 5. Bloque 3 — Fase 3, Lote 1: conexión de 7 páginas del sector público (COMPLETO, sin comitear)

### 5.1 Contexto

El Plan Maestro v4 documentaba que las 12 páginas de `lib/sector_publico/` eran 100% decorativas (ícono + botón + diálogo falso + SnackBar de éxito simulado), aunque la capa de servicios (`lib/sector_publico/*/services/`) sí estaba completa y probada para varios macro-sistemas. Antes de escribir código, se reconfirmó el estado real de las 12 páginas (Prompt 3.1) y se descubrió que **una ya no era decorativa**: `presupuesto_publico_page.dart` estaba realmente conectada (verificado con evidencia literal de código: instancia el servicio real, persiste en SQLite, lista registros existentes, valida bloqueos normativos). Se excluyó del lote de trabajo, con dos gaps anotados (ver sección 6).

### 5.2 Páginas conectadas en este lote (todas verificadas con diff completo + `flutter analyze` literal + auditoría explícita de hardcodeos)

1. **`contabilidad_nicsp_page.dart`** — asientos con partida doble validada (UI + backend), saldos reales, 3 estados financieros (Situación Financiera, Resultados, Flujos de Efectivo) con vigencia/rango de fechas dinámicos, cierre de vigencia con motivo capturado del usuario (no hardcodeado, corregido en esta sesión).

2. **`pac_tesoreria_page.dart`** — programación/aprobación/modificación de PAC con funcionario y acto administrativo capturados explícitamente, traslados de cupo, embargos judiciales (con nota legal de inembargabilidad, Art. 19 EOP).

3. **`contratacion_publica_page.dart`** — procesos de contratación con asociación real a CDP/RP (filtrado para evitar mezclar fuentes de financiamiento), publicación SECOP II, adjudicación (corregido `SECOP-MOCK` → falla explícita si no hay `secopId`), contratos, pólizas de garantía.

4. **`nomina_publica_page.dart`** — empleados, liquidación de nómina con SMMLV y auxilio de transporte configurables por entidad (ya no hardcodeados), retroactivos, reporte PILA. Tarifa de ARL corregida de "clase I fija" (subestimaba el riesgo) a "clase V conservadora por defecto, con advertencia visible en la UI" mientras no exista el campo `clase_riesgo` en el modelo Empleado.

5. **`transparencia_page.dart`** — reportes Ley 1712/2014, control disciplinario (con dropdown de autocompletado desde empleados reales + acto administrativo obligatorio), consolidación NICSP 40.

6. **`auditoria_forense_page.dart` (parcial, según lo acordado)** — registros de auditoría con filtros reales, reportes CHIP CGN (2015_001 a 005) con datos de funcionarios y montos capturados del usuario (corregido el hallazgo más grave de la sesión: datos ficticios de funcionarios públicos hardcodeados), verificación criptográfica de cadena de hashes SHA-256, detección de anomalías (intentos de eliminación, horario nocturno). SIIF Nación, SIA Observa y FUT quedan con TODO explícito en la UI para Fase 4.

### 5.3 Estado de verificación final

Todas las páginas fueron revisadas con el mismo protocolo: diff completo (nunca resumido), `flutter analyze` literal después de cada cambio, auditoría explícita de valores hardcodeados/simulados. `flutter analyze` bajó de 173 a 167 issues a lo largo del lote (limpieza incidental de lints obsoletos en las reescrituras, no oculta nada nuevo).

**Pendiente antes de comitear:** confirmar con evidencia literal (no narrada) que el fix de deduplicación de `funcionarios_entidad` en `auditoria_forense_page.dart` funciona — se pidió ejecutar dos generaciones consecutivas del paquete CHIP y pegar el resultado crudo de `SELECT id, cargo_clave, nombre_completo FROM funcionarios_entidad WHERE entidad_id = ?` antes y después. La respuesta del agente hasta ahora fue una descripción narrada del resultado esperado, no el output real — **rechazada, pendiente de reenvío.**

---

## 6. Reporte consolidado de gaps de backend (Fase 3, Lote 1)

### Prioridad ALTA (implicación de cumplimiento normativo/tributario)
- **Brecha F — Retención en la fuente / UVT**: la liquidación de nómina no calcula retención en la fuente sobre salarios (Art. 383 E.T., aplica sobre ingresos gravables > 95 UVT). Recomendado abordar antes o junto con el inicio de Fase 4.
- **Brecha H (antes E) — Clase de riesgo ARL en Empleado**: el modelo `Empleado` no tiene el campo `clase_riesgo` (I a V). Interim: se usa clase V (6.96%, conservador) con advertencia visible en la UI de liquidación. Pendiente: agregar el campo y selector obligatorio en el registro de empleado.

### Prioridad MEDIA-ALTA (exigencia de auditoría externa)
- **Brecha K — Acto administrativo en procesos disciplinarios**: `ProcesoDisciplinario` no tiene columna estructurada para el número de resolución/acto administrativo del fallo; interim lo concatena dentro del campo `sancion` (texto libre), lo cual impide filtrar/reportar por número de resolución. Pendiente: columna independiente.

### Prioridad MEDIA (arquitectura — bypass de servicio, no hardcodeo)
- **Brecha A** — Consulta de embargos judiciales: UI lee directo de tabla `embargos_judiciales`, `PACService` no expone `consultarEmbargosJudiciales()`.
- **Brecha B** — Consulta de procesos de contratación: UI lee directo de `procesos_contratacion`, `ContratacionService` no expone consulta general.
- **Brecha C** — Consulta global de pólizas: UI lee directo de `polizas`, el servicio solo expone consulta por `contratoId`.
- **Brecha D** — Nómina: exoneración de aportes (Ley 1607/2012) no se verifica según régimen tributario de la entidad — se calcula igual para todas.
- **Brecha E** — `NominaService` no expone método genérico de consulta de empleados; UI lee tabla directo.
- **Brecha G** — Auxilio de alimentación fijo en `0.0`, sin implementar según política/decreto anual ni topes salariales.

**Nota sobre presupuesto_publico_page.dart (no forma parte de este lote, pero quedó documentado):**
- `PresupuestoService` se instancia con `auditoriaService: null` — las operaciones de CDP/RP/Obligación/Pago no quedan registradas en la cadena de auditoría. Candidato para Fase 4 o Fase 6 (roles/segregación de funciones).
- `test/sector_publico/presupuesto/presupuesto_publico_page_test.dart` tiene un `CREATE TABLE` manual de `apropiaciones` sin la columna `vigencia` — el test falla por eso, no por el código de producción. Deuda de test pendiente.

---

## 7. Fases completadas según Plan Maestro v4 (actualizado)

- Fase 0 (triage de compilación) y Fase 0.5: completadas (de sesiones anteriores a v7).
- Fase 1 (adelgazar `main.dart`): cerrada, 14 commits (de sesiones anteriores a v7).
- Fase 2 (generador XML): **cerrada hoy**, commit `d4d5d06`.
- Fase 3 (conectar UI del sector público a servicios reales), Lote 1 (7 páginas de backend completo): **completo funcionalmente, pendiente confirmación final antes de comitear** (ver sección "Lo más urgente").
- Fase 3, Lote 2 (Prompt 3.3 del Plan Maestro v4: `planeacion_page.dart`, `predial_ica_page.dart`, `activos_estado_page.dart`, `salud_publica_page.dart` — conexión parcial hasta donde el backend actual alcance): **no iniciado.**
- `regalias_sgp_page.dart`: excluida de la Fase 3 completa (SGR vacío, SGP parcial) — espera a Fase 4 según el Plan Maestro v4.

---

## 8. Regla de trabajo reafirmada en esta sesión (aplica a cualquier agente)

1. **Nunca aceptar narración como evidencia.** Diffs completos (nunca resumidos con "[Ver resto...]"), outputs literales y crudos de comandos (`flutter analyze`, `flutter test`, `SELECT ...`), no descripciones de lo que "debería" pasar.
2. **Nunca modificar el working tree (checkout, stash pop, etc.) sin autorización explícita previa**, aunque la intención sea buena.
3. **Cero valores hardcodeados o simulados** — este es un sistema que va a mercado real. Cualquier dato que debería venir de input del usuario, configuración de la entidad, o consulta real a base de datos, no puede quedar fijo en el código. Aplica con especial severidad a datos que terminan en reportes oficiales ante entidades del Estado (CGN, DIAN, SECOP, etc.) — ahí un valor simulado no es solo un bug, es una falsificación de facto.
4. **Cuando el backend no alcance para evitar un hardcodeo, se reporta como gap explícito, nunca se rellena con un valor inventado.**
5. **Un bloque de trabajo = un commit.** No mezclar bloques distintos (ej. fix de triggers y bloque de facturación) en un mismo commit.
6. **Nunca comitear sin revisión previa del diff completo y autorización explícita.**

---

## 9. Prompt sugerido para retomar en la nueva conversación

```
Estoy retomando la revisión de MerkaERP. Te acabo de dar el contexto completo (v8).

Lo inmediato: pedí al agente confirmar con evidencia literal (no narrada) que el
fix de deduplicación de funcionarios_entidad en auditoria_forense_page.dart
funciona de verdad — dos generaciones consecutivas del paquete CHIP no deben
duplicar filas. La respuesta anterior fue una narración del resultado esperado,
no el output real de una consulta SQL ejecutada. Necesito que se re-ejecute y
se pegue el resultado crudo de:

SELECT id, cargo_clave, nombre_completo FROM funcionarios_entidad WHERE entidad_id = ?

antes y después de una segunda generación del paquete CHIP con datos distintos.

Una vez confirmado eso, el Lote 1 de la Fase 3 (7 páginas del sector público:
contabilidad_nicsp, pac_tesoreria, contratacion_publica, nomina_publica,
transparencia, auditoria_forense parcial) queda listo para comitear — falta
decidir si es un solo commit o uno por página, y ejecutar el commit con mi
autorización explícita después de revisar el diff final consolidado.

Mismo rigor de siempre: evidencia literal, nunca aceptar narración de resultados,
diffs completos sin resumir, cero hardcodeo/simulación (especialmente en datos
que van a reportes oficiales ante el Estado), señalar cualquier acción no
autorizada antes de ejecutarla.
```
