# UI-7: Cápsula de Evidencia

## Diseño

La cápsula es un JSON canónico, local y verificable. Su raíz contiene:

| Campo | Contenido |
| --- | --- |
| `capsule_version` | Versión del formato de la cápsula, actualmente `1`. |
| `generated_at` | Instante UTC de generación. Participa en el hash. |
| `domain`, `record_type`, `record_id` | Identidad del resultado explicado. |
| `source_records` | Filas completas de SQLite involucradas, con tabla, ID y valores exactos. |
| `calculations` | Fórmula, operandos, diferencias y validaciones aplicadas. |
| `monetary_conversions` | Convención de almacenamiento (`INTEGER`, unidad menor, escala y moneda). |
| `actor` | Usuario, nombre, rol y snapshot de permisos evaluados al generar. |
| `schema_version` | Versión activa expuesta por `DatabaseHelper`. |
| `audit_records` | Registros de `auditoria_registros` vinculados por `referencia_id`, incluyendo `hash_anterior` y `hash_actual`. |
| `result` | Resultado final exacto de la decisión o cálculo. |
| `integrity_sha256` | SHA-256 del JSON canónico anterior a este campo. |

Las listas de fuentes y auditoría se ordenan por una clave estable. Las claves
de cada objeto también se ordenan para que dos cápsulas generadas con el mismo
registro, datos y instante sean byte a byte iguales. `EvidenceCapsule.verifyIntegrity()`
recalcula el digest sin consultar red ni confiar en la UI.

## Exportación y entrada de UI

Se eligió JSON como formato principal porque conserva enteros monetarios,
fórmulas, filas fuente y hashes sin pérdida de precisión y permite verificación
automática offline. PDF puede agregarse después como una representación humana,
pero no sustituye este artefacto técnico.

`ExpandableRecordCard` acepta un `EvidenceRequest` y un callback de exportación.
Eso convierte la acción en una capacidad compartida de UI-3: una pantalla solo
declara el dominio, tipo e ID, y no duplica la lógica de captura ni de hash.
La página de presupuesto público ya lo expone en apropiaciones, CDP y RP.

## Casos implementados

### Asiento contable

Tipos `asiento_contable_comercial` y `asiento_contable_publico` capturan el
encabezado y sus líneas. La cápsula conserva la suma exacta de débito y crédito,
la diferencia, el estado y la regla SQL de partida doble v76 que valida el
cierre del asiento.

### Liquidación de nómina

Tipos `nomina_liquidacion_comercial` y `liquidacion_nomina_publica` capturan la
liquidación, el vínculo del empleado público (`hrm_employee_id` cuando existe)
y las ausencias HRM aprobadas del periodo. También conservan `novedades_hrm`
si está almacenado en la liquidación y expresan los importes como unidad menor.

### Cadena presupuestal

Los tipos `apropiacion`, `cdp` y `rp` resuelven la cadena hasta la apropiación
raíz. Capturan las filas exactas y documentan las comprobaciones
`CDP <= apropiación` y `RP <= CDP`, además de los saldos almacenados y auditoría
relacionada.

## Extensión

Para agregar un caso nuevo se incorpora un `recordType` al despacho de
`EvidenceCapsuleService`, se agregan consultas de fuente explícitas y un test
con datos exactos. No se debe inferir una relación por monto/fecha ni reemplazar
una fila fuente por un resumen. Una tarjeta nueva puede reutilizar
`EvidenceRequest` sin conocer el algoritmo SHA-256.

## Evidencia de esta entrega

- `test/core/evidence/evidence_capsule_service_test.dart`: asiento comercial,
  nómina con ausencia HRM y cadena apropiación-CDP-RP; verifica valores exactos,
  auditoría, fórmulas y hash estable.
- `test/ui/evidence_capsule_card_test.dart`: verifica que una tarjeta UI-3
  expone y ejecuta la acción reutilizable de exportación.
- `dart analyze` sobre el alcance nuevo: `No issues found!`.
- `flutter analyze`: `241 issues`, todos heredados de nivel info/warning y
  `0 errores`.
- `flutter test --reporter compact`: `277` pasados, `3` omitidos, `0 fallos`.
- `flutter build windows`: exitoso; generó
  `build\\windows\\x64\\runner\\Release\\MerkaERP.exe`.
