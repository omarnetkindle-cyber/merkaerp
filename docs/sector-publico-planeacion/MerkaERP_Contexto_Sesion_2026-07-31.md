> ⚠️ SNAPSHOT HISTÓRICO al 2026-07-31 20:46. NO es el estado más
> reciente del proyecto — para el log completo y actualizado, ver
> SESION_AUTONOMA_2026-07-31_TARDE.md en esta misma carpeta.

# MerkaERP — Contexto de Sesión (para retomar desde otra cuenta/chat de Claude)
### Generado el 2026-07-31, cierre de una sesión larga de trabajo continuo

---

## Cómo usar este documento

Pégalo completo como primer mensaje en la conversación nueva. Está escrito para
que Claude (rol de supervisor/auditor/diseñador de prompts) retome exactamente
donde quedó. No es para pegarle al agente ejecutor de código — para eso existe
`docs/sector-publico-planeacion/SESION_AUTONOMA_2026-07-31_TARDE.md` y el resto
de bitácoras ya archivadas en esa carpeta del repo.

---

## Quién es Omar y cómo trabajamos

Omar es desarrollador/asesor independiente en Colombia, construyendo y
extendiendo **MerkaERP** (repo `mera-erp`, antes "Caja Simple"), un ERP
Flutter/Dart + SQLite. Empezó como ERP comercial (ventas/POS, inventario,
contabilidad, nómina) y se está expandiendo con un módulo completo de
**Sector Público** para alcaldías, gobernaciones y hospitales públicos
colombianos, con cumplimiento normativo real. Meta explícita: dejar el
sistema **"listo para el mercado"**.

**Omar no programa.** El flujo de trabajo, sin excepción:
1. Claude diseña un prompt bien delimitado para el agente ejecutor de IA
   (actualmente **Codex**, esfuerzo "Terra" — antes se usó GitHub Copilot y
   Kiro; Kiro se abandonó porque empezó a rechazar operaciones de escritura
   pese a estar en modo Autopilot).
2. Omar pega ese prompt al agente ejecutor y trae la respuesta de vuelta a
   Claude.
3. Claude audita esa respuesta con exigencia de evidencia línea por línea —
   **nunca acepta un "listo"/"0 errores"/"pasan las pruebas" sin ver la
   salida cruda** pegada literalmente en el mensaje. Un commit hash o un
   resumen en prosa no son evidencia por sí solos; siempre se exige también
   `git log origin/main -N` y `git status` reales para confirmar el push.
4. Claude diseña el siguiente prompt.

**Regla de oro de toda la sesión:** el agente ejecutor reporta con optimismo
por defecto. Cada vez que se exigió evidencia en vez de aceptar un resumen,
aparecieron bugs reales — el más grave de esta sesión fue descubrir que el
flujo de pago presupuestal no validaba cupo PAC, no actualizaba obligación/RP/
apropiación en cascada, y no generaba el asiento contable NICSP (ver más abajo).

Cuando Codex mismo se equivocó y dijo "terminé" sin haber terminado todas las
subtareas de una sesión autónoma, se le señaló, corrigió sin excusas y dio el
estado real — ese nivel de honestidad ya es la norma esperada y se sigue
exigiendo igual.

**Sesiones autónomas:** quedó establecido un protocolo para cuando Omar no
puede supervisar en vivo (p. ej. mientras trabaja fuera varias horas): Codex
recibe reglas explícitas de decisión conservadora ante ambigüedad, deja de
ejecutar y marca "requiere decisión humana" ante credenciales/red real/datos
irreversibles, hace un commit+push por subtarea, y lleva todo en un log único
(`SESION_AUTONOMA_2026-07-31_TARDE.md`) con sección "Cierre de la subtarea X"
obligatoria en cada una. Ha funcionado bien — incluida la vez que se detuvo
él solo ante URLs hardcodeadas (que resultaron ser endpoints públicos, no
secretos, pero la reacción de detenerse a preguntar fue la correcta).

---

## Estado técnico actual

**Repo:** `https://github.com/omarnetcom-hub/mera-erp.git`, rama `main`.
Último commit confirmado en esta sesión: `286f0dd` (más los de SECOP/M6/M7 de
la ronda más reciente — confirmar con `git log origin/main -5` al retomar).

**`flutter analyze`: 184 issues, 0 errores** (línea base estable, verificada
docenas de veces esta sesión, nunca cambió con ningún fix).
**`flutter build windows`** compila limpio en cada ronda.

**Documentación consolidada:** `docs/sector-publico-planeacion/` contiene 19
documentos relevantes (planes, bitácoras históricas, prompts maestros) — se
excluyeron 4 archivos ajenos que aparecieron mezclados en la carpeta de
Descargas de Omar (documentos societarios/personales de otro asunto, nunca
llegaron a commit). El documento normativo de referencia es
`MerkaERP_SectorPublico_Plan_v1.1.md` (y su versión `.docx` idéntica) — los
11 macro-sistemas con reglas comprobables. `MerkaERP_Plan_Maestro_v4.md` es
el roadmap técnico de restauración basado en auditorías reales del código
(no en la estimación de esfuerzo del plan de producto).

**Herramienta clave: `docs/sector-publico-planeacion/MATRIZ_TRAZABILIDAD.md`**
— documento vivo que mapea `requisito del plan v1.1 → código → test →
evidencia → estado` para los 11 macro-sistemas. Se corrigió dos veces por
citar tests que en realidad no cubrían el requisito descrito (evidencia falsa
sin querer) — es la principal defensa contra volver a perder de vista qué
está realmente probado vs. solo inspeccionado. **Siempre pedir la sección
completa de la matriz al auditar cualquier avance, no solo el resumen
numérico** — ya se detectaron varias veces conteos correctos con evidencia
mal citada por debajo.

---

## Lo que se resolvió en esta sesión (cronológico, resumen)

### 1. Configuración de la Entidad conectada
`ConfiguracionGeneralPage` (huérfana, sin consumidor) se conectó al menú de
sector público con `Permiso.configurarEntidad` dedicado.

### 2. Segregación de funciones de Secretaría de Hacienda corregida
`secretarioHacienda` tenía concentrados `expedirCDP`, `expedirRP`,
`aprobarPago`, `gestionarUsuarios`, `asignarRoles` — violación normativa
(plan v1.1: "no expide CDP ni RP directamente") y de segregación de
funciones. Se creó el rol `RolSectorPublico.jefePresupuesto` (nombre elegido
por Codex citando Decreto 568/1996, arts. 19-20) para recibir `expedirCDP`/
`expedirRP`. `gestionarUsuarios`/`asignarRoles` se retiraron sin reasignar
(no se validaban en ningún servicio/página; queda pendiente de diseño quién
administra usuarios en contexto público — no resuelto todavía).

### 3. Auditoría blindada a nivel de SQLite (la corrección más crítica)
`auditoria_registros` era append-only solo por convención de servicio Dart,
sin garantía real en la base de datos. Se agregaron triggers `BEFORE DELETE`
(bloquea siempre) y `BEFORE UPDATE` (solo permite `archivado: 0→1` sin tocar
ninguna otra columna en la misma operación; cualquier otra alteración se
bloquea con `RAISE(ABORT)`). Esto cumple la Regla 1 no negociable del
`PROMPT_MAESTRO` ("nada se borra"). 3 tests de integración lo verifican.

### 4. Selector de entidad — conflicto de esquema resuelto
Existían dos taxonomías incompatibles de "tipo de entidad": el onboarding
activo (`tipo_entidad`/`subtipo_entidad_publica` string libre) vs.
`SelectorEntidadService` (enum `TipoEntidad`, huérfano, sin consumidor).
`configuracion_entidad` tenía `UNIQUE(entidad_id)` (sin historial) y
`SelectorEntidadService` insertaba sin los campos obligatorios `parametro`/
`valor`. Se resolvió: `TipoEntidad` extendido con `hospitalEse`/`otroEnte`
como taxonomía canónica pública, `configuracion_entidad` reconstruida con
`vigente`/`fecha_fin` (historial real, sin perder datos existentes), tabla
nueva `modulos_por_tipo_entidad` (matriz de módulos migrada desde el
hardcodeo original), y migración del onboarding legado (`company_id=2`,
municipio) hacia el nuevo esquema. Nómina (que lee/escribe
`configuracion_entidad` bajo `parametro='configuracion_legal'`) se confirmó
intacta tras el cambio — era el consumidor más delicado.

### 5. Flujo de pago presupuestal integrado con PAC y NICSP (hallazgo más grave)
`ejecutarPago` podía marcar cualquier pago como `pagado` sin exigir estado
`aprobado` previo, sin validar cupo PAC, sin actualizar obligación/RP/
apropiación en cascada, y sin generar el asiento contable NICSP. Esto abría
la puerta real a sobregiro presupuestal o doble pago. Se corrigió con
migración v67 (`mes_pac` persistido en `pagos`), transacción atómica
(patrón `DatabaseExecutor` opcional en los servicios, sin romper consumidores
existentes que siguen usando `Database` directo), y test de integración de
punta a punta (flujo feliz + 5 bloqueos). `MATRIZ_TRAZABILIDAD.md` M2 subió
de 0 a 2 Completos (flujo de pago + catálogo CGC) con esto.

### 6. Sesión autónoma de 4 horas — M2/M6/M7
Con Omar fuera del computador, Codex trabajó con el protocolo de decisión
conservadora:
- **Cierre de vigencia:** confirmó que el cálculo actual no cubre reservas
  presupuestales reales ni cuentas por pagar de recibidos sin obligación, ni
  existe vigencias futuras — documentó la brecha sin fabricar una prueba que
  aparentara cubrirla. Propuso diseño (tabla `recepciones_satisfaccion` para
  recibidos sin obligación; tablas de autorización plurianual para vigencias
  futuras) sin implementar — pendiente de decisión normativa humana.
- **NICSP 2 (flujo de efectivo):** conectado a pestaña/UI real con selector
  de periodo, RBAC aplicado, test de integración con montos conocidos.
- **Catálogo CGC:** confirmado completo para las cuentas clave de las 8
  clases exigidas por el plan; no se agregó nada sin fuente CGN verificada.
- **NICSP 1 (estados financieros):** encontró bug real — los generadores
  suman saldos con signo acreedor sin invertir, y no integran el resultado
  del periodo al patrimonio, por lo que un estado derivado no cuadra
  (Activo ≠ Pasivo + Patrimonio). Documentado como brecha, no enmascarado.
- **CHIP:** los formularios (CGN2015_001-005, CGN2016C01) reciben DTOs
  manuales por UI, no datos reales del sistema contable/presupuestal —
  hoy no se pueden certificar aunque el código "funcione".
- **Activos/FUT:** test integral del job de depreciación agregado; FUT
  recibió entrada de menú dedicada reutilizando el permiso ya existente
  (`auditoria_forense`/`exportarDatos`+`consultarAuditoria`), sin inventar
  RBAC nuevo.

### 7. SECOP II — investigación y diseño (sin implementar)
Confirmado: falta la 6ª modalidad de contratación (Acuerdos Marco CCE),
`crearContrato` no verifica que el RP citado exista/corresponda al proceso,
`legalizarContrato` no valida pólizas. `SECOPService` sí intenta red real
(Dio) con URLs hardcodeadas — **no son secretos** (endpoints públicos +
`<CONFIGURAR_EN_CENTRO_DE_INTEGRACIONES>` placeholder sin valor real), pero están mal ubicadas
arquitectónicamente. Diseño propuesto y aprobado (no implementado):
interfaz `SecopIntegrationClient` inyectable siguiendo el patrón ya probado
de `dian_transmission_client.dart`, con `NoOpSecopIntegrationClient` como
default seguro, `SecopIntegrationConfig` por entidad/entorno, secretos nunca
en SQLite/Dart/repo. Se puede certificar sin red real: generación y
validación de payloads. Radio de cambio estimado: 10-14 archivos.

---

## Estado real de la matriz (macro-sistemas tocados esta sesión)

- **M2 (Financiero):** 2 Completos / 8 Parciales / 0 Pendientes
- **M6 (Activos):** 0 Completos / 4 Parciales / 0 Pendientes
- **M7 (Auditoría/Seguridad):** 1 Completo / 4 Parciales / 0 Pendientes
- **M4 (Contratación):** no actualizado formalmente en la matriz todavía con
  los hallazgos de la investigación SECOP — pendiente de hacerlo en la
  próxima ronda.
- **M1, M3, M5, M8, M9, M10, M11:** sin tocar desde la auditoría inicial de
  Codex (mayoría Parcial, algunos Pendiente — ver la matriz completa para
  el detalle fila por fila).

---

## Pendientes explícitos, priorizados

1. **SECOP II:** implementar las 3 validaciones locales primero (RP real
   ligado al proceso, contrato existente/firmado antes del RP, pólizas
   vigentes antes de legalizar) — esto no depende de ningún cliente externo
   y cierra una brecha de integridad real. Después, si se decide, construir
   la interfaz inyectable diseñada (sin cliente remoto real, que si depende
   de credenciales de cada entidad cliente).
2. **NICSP 1:** corregir el signo acreedor y la integración del resultado
   del periodo al patrimonio en los generadores de estados financieros.
3. **CHIP:** conectar los generadores a datos reales del sistema contable/
   presupuestal en vez de DTOs manuales.
4. **Reservas presupuestales / cuentas por pagar / vigencias futuras:**
   diseño ya propuesto (tabla `recepciones_satisfaccion` + tablas de
   autorización plurianual). Requiere decisión de Omar sobre la autoridad
   normativa de vigencias futuras (Confis, concejo municipal según tipo de
   entidad) antes de implementar — esto es la única pieza que no se resuelve
   solo con más código/investigación.
5. **`gestionarUsuarios`/`asignarRoles`:** sin titular en el RBAC público
   desde que se retiraron de `secretarioHacienda`. Diseño pendiente: ¿rol
   público nuevo, o se extiende el `administrador` comercial existente?
6. Resto de macro-sistemas sin auditar a fondo con evidencia ejecutada:
   Planeación/PDT (trazabilidad plan-presupuesto-resultado), Rentas
   (cobro coactivo, importación IGAC), Nómina (6 regímenes salariales
   completos, archivo PILA), Salud (RIPS, interoperabilidad ADRES/EPS),
   SGR/SGP (bloqueos duros entre componentes), Transparencia (NICSP 40 no
   elimina operaciones recíprocas — contradice el requisito del plan v1.1).
7. **`_PAPELERA_MERKAERP_BORRAR`** (3.5GB fuera del repo, de una limpieza de
   disco anterior a esta sesión) — pendiente de que Omar confirme que nada
   dependía de esos archivos antes de vaciarla.
8. **`ALLOWED_TABLES`** del backend `Merka_Control_Center` — solo sincroniza
   4 tablas comerciales, ninguna de sector público. Cambio en otro repo.
9. **Clave RSA placeholder** en verificación de licencia offline — antes de
   producción con clientes reales.

---

## Notas de entorno

- Windows, PowerShell. La terminal ha mostrado corrupción de eco en sesiones
  largas — preferir escribir salida a archivo `.txt` y pegarla completa, no
  confiar en el eco directo. `flutter : ... RemoteException` en la salida
  cruda de PowerShell tras `flutter analyze *> archivo.txt` es ruido de
  redirección (PowerShell trata la línea de resumen como error no
  terminante), no un fallo real — el conteo real de issues sigue siendo
  válido, solo hay que leerlo con cuidado.
- `flutter analyze` puede tardar varios minutos en corridas grandes.
- `git commit -F archivo.txt` en vez de `-m` multilínea desde PowerShell
  (evita corrupción del mensaje).
- **Nunca automatizar reemplazos masivos de texto con regex/sed sobre
  múltiples archivos Dart a la vez** — causó corrupción real más de una vez
  en el historial del proyecto (antes de esta sesión). Reemplazo exacto,
  uno por uno.
- Nombres viejos del proyecto que pueden aparecer en residuos de código:
  "Caja Simple", "NexoPyme", "Lucro" — Omar no recuerda detalles de esos
  proyectos anteriores, no preguntarle por nombres específicos de ahí.
- Omar puede subir los `.zip` completos de los repos (`Caja_simple` /
  `Merka_Control_Center`) para inspección directa de código en vez de
  depender solo de lo que reporta el agente ejecutor — se ha usado varias
  veces esta sesión para verificar hallazgos de forma independiente.
- Preferencia de formato explícita de Omar: los prompts para el agente
  ejecutor van siempre en bloque de código (para copiar con un clic), nunca
  como texto plano en el cuerpo de la respuesta.
