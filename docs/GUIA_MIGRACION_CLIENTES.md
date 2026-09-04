# Guía de migración de clientes hacia MerkaERP

## Objetivo
Trasladar a MerkaERP la información necesaria para continuar operando sin reconstruir hechos históricos de forma artificial ni perder la evidencia del sistema anterior.

## Fuentes admitidas
- CSV, TSV, TXT y PSV.
- Excel XLSX.
- JSON.
- SQLite `.db`, `.sqlite`, `.sqlite3` en modo solo lectura.
- Carpetas de documentos y soportes hacia el SGDEA.

Si el software anterior usa otro motor (por ejemplo SQL Server, MySQL o PostgreSQL), utilice preferentemente su exportación oficial a CSV/XLSX/JSON o genere una extracción controlada. Un conector específico puede desarrollarse para formatos propietarios sin alterar el motor genérico de migración.

## Principio de migración
1. **Maestros operativos:** se normalizan cuando existe equivalencia segura.
2. **Saldos de apertura:** se migran con validaciones contables/presupuestales.
3. **Histórico:** se preserva íntegro como Archivo Legado cuando reconstruirlo produciría duplicidades o falsos eventos.
4. **Soportes:** se incorporan al gestor documental/SGDEA con SHA‑256.
5. **Auditoría:** cada fila conserva origen, mapeo, resultado y destino.

## Flujo recomendado
1. Hacer copia independiente del sistema origen.
2. Exportar maestros, saldos y documentos.
3. Crear la organización en MerkaERP.
4. Abrir **Migración de datos**.
5. Seleccionar fuente y hoja/tabla.
6. Revisar el destino sugerido por familia licenciada.
7. Corregir el mapeo de columnas.
8. Revisar vista previa y errores.
9. Importar. MerkaERP crea backup integral antes de escribir.
10. Preservar hojas/tablas no normalizadas en Archivo Legado.
11. Migrar carpeta documental si existe.
12. Ejecutar conciliación.
13. Validar saldos contra reportes de cierre del sistema anterior.
14. Completar UAT y exportar evidencia Go‑Live.

## Reglas de seguridad
- No importar contraseñas, tokens, API keys, PIN ni claves privadas como datos de negocio; el Archivo Legado redacta campos que parezcan credenciales.
- No alterar la fuente SQLite: se abre solo lectura.
- No usar una migración para reconstruir ventas/compras históricas si eso duplica inventario, caja, impuestos o contabilidad.
- No fusionar saldos de apertura sobre cuentas/rubros que ya tengan operación posterior en MerkaERP.
- La reversión se detiene si un registro fue modificado después de migrar.
- La reversión documental se detiene si un documento heredado fue vinculado posteriormente a otro expediente.

## Corte de migración sugerido
Defina una fecha/hora de corte. Cierre y concilie el sistema anterior; exporte datos; suspenda nuevos registros allí; migre maestros y saldos; compare totales; ejecute UAT; documente la aceptación; a partir del Go‑Live registre los hechos nuevos exclusivamente en MerkaERP.

## Evidencia mínima
Conserve exportaciones fuente, hash de origen, respaldo pre-migración, reporte de cada job, incidencias, conciliación final, totales de control y reporte Go‑Live con checksum.
