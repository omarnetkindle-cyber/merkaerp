# Migración desde otros sistemas a MerkaERP

## Objetivo

El asistente de migración permite iniciar MerkaERP con información procedente de otro ERP, programa contable, POS o sistema institucional sin tratar el histórico anterior como si hubiera sido generado originalmente por MerkaERP.

El principio es:

- **datos vigentes normalizables** → módulos operativos de MerkaERP;
- **saldos de apertura** → registros de apertura auditados;
- **histórico legado** → Archivo Legado consultable con trazabilidad;
- **carpetas documentales heredadas** → expediente SGDEA restringido, con copia controlada, ruta relativa y SHA-256 por archivo;
- **fuente original** → identificada por SHA-256;
- **credenciales detectables** → redactadas del archivo histórico interno;
- **antes de importar** → respaldo integral automático;
- **después de importar** → conciliación y rollback controlado disponibles.

## Formatos admitidos

- CSV
- TSV
- TXT delimitado
- PSV (`|`)
- XLSX
- JSON
- SQLite (`.db`, `.sqlite`, `.sqlite3`) en modo solo lectura

El lector soporta comillas, saltos de línea dentro de campos, BOM UTF-8 y exportaciones Latin-1. Las fuentes demasiado grandes se detienen y deben dividirse en lotes para evitar agotar memoria.

## Comercial

Destinos operativos incluidos:

- clientes;
- proveedores;
- productos, costos, precios y existencia inicial;
- cuentas por cobrar iniciales;
- cuentas por pagar iniciales;
- asiento contable de apertura balanceado.

Las ventas/compras históricas anteriores no se recrean automáticamente como operaciones nuevas porque hacerlo podría duplicar inventario, impuestos, cartera, caja o contabilidad. Se conservan en Archivo Legado y los saldos vigentes se trasladan mediante aperturas.

## Sector Público

Destinos operativos incluidos:

- terceros;
- Catálogo/plan de cuentas CGN por entidad;
- apropiaciones presupuestales;
- snapshot de ejecución acumulada por rubro;
- saldos contables públicos de apertura.

La ejecución presupuestal de apertura valida:

`Pagado ≤ Obligado ≤ RP ≤ CDP ≤ Apropiación vigente`.

MerkaERP **no inventa** CDP, RP, obligaciones o pagos históricos que no fueron creados dentro del sistema. La ejecución acumulada permite continuar operando con saldos vigentes y los soportes/documentos históricos permanecen en Archivo Legado o pueden incorporarse al SGDEA.

El asiento público de apertura:

- exige una sola vigencia por importación;
- exige igualdad entre débitos y créditos;
- crea/relaciona cuentas CGN válidas;
- actualiza `saldos_cuentas`;
- se niega a mezclar la apertura con cuentas que ya tengan saldo operativo en esa vigencia.

## Flujo recomendado

1. Crear la organización desde el onboarding.
2. Crear un respaldo integral inicial.
3. Exportar el sistema anterior.
4. Seleccionar la fuente en **Administración → Migración de datos**.
5. Preservar todas las hojas/tablas en Archivo Legado cuando sea necesario.
6. Si existen carpetas de soportes, usar **Migrar carpeta documental al SGDEA**; MerkaERP no sigue enlaces simbólicos, crea respaldo previo y conserva la jerarquía relativa en el título.
7. Elegir el destino operativo.
8. Revisar el mapeo automático de columnas.
9. Corregir únicamente los campos que el asistente no pueda identificar.
10. Revisar la vista previa y observaciones.
11. Importar.
12. Repetir por cada conjunto de datos necesario.
13. Ejecutar **Conciliar todas**.
14. Comparar totales contra reportes de cierre del sistema anterior.
15. Exportar los reportes de migración como evidencia.
16. Cerrar el control `Migración conciliada` del Go-Live.

## Duplicados

- **Omitir:** conserva el registro existente en MerkaERP.
- **Fusionar:** actualiza únicamente los campos permitidos y registra el valor anterior y posterior para rollback.

No se debe usar fusión sobre datos que ya hayan tenido operación posterior si el asistente lo bloquea.

## Rollback

Cada cambio generado por la migración se registra en `data_migration_changes`. Para actualizaciones, el rollback comprueba primero que el registro no haya cambiado después de la migración. Si cambió, se detiene antes de sobrescribir trabajo posterior.

El rollback no borra el historial de auditoría ni la evidencia de que la migración existió. En migraciones documentales elimina también las copias físicas creadas por ese trabajo, siempre a partir de la traza de migración; el respaldo previo se conserva.

## Sistemas no soportados directamente

Cuando un sistema legado usa un formato propietario, el cliente puede:

1. exportar a uno de los formatos admitidos; o
2. conservar su exportación en Archivo Legado y desarrollar posteriormente un adaptador específico.

Un adaptador específico debe implementar el mismo contrato: fuente de solo lectura, mapeo, vista previa, backup, transacción, trazabilidad, conciliación y rollback. Nunca debe escribir en la base del sistema anterior.
