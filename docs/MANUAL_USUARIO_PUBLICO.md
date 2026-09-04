# Manual operativo · MerkaERP Público 1.2

## 1. Primera puesta en marcha
1. Active una licencia MerkaERP Público. La familia queda fijada por licencia; la entidad no puede cambiar a Comercial desde la interfaz.
2. Complete el onboarding institucional: identidad, tipo de entidad, dependencias, módulos públicos y continuidad.
3. Configure usuarios y roles por dependencia y principio de mínimo privilegio.
4. Parametrice los instrumentos, políticas y configuraciones adoptadas por la entidad antes de ejecutar automatismos asociados.
5. Si existe un sistema anterior, ejecute la migración y conciliación antes del Go‑Live.

## 2. Migración institucional
El asistente admite CSV/TSV/TXT/PSV, XLSX, JSON y SQLite. Puede migrar terceros, plan de cuentas público, apropiación vigente y ejecución acumulada de apertura, y saldos contables públicos balanceados.

Para migraciones a mitad de vigencia, MerkaERP conserva la cadena lógica **Pagado ≤ Obligado ≤ RP ≤ CDP ≤ Apropiación vigente**. No inventa documentos históricos que no existan en el sistema fuente: los soportes y movimientos históricos se preservan en Archivo Legado y/o SGDEA.

Las carpetas documentales heredadas pueden incorporarse a un expediente SGDEA restringido. Se conserva ruta relativa, tamaño, SHA‑256 y vínculo de trazabilidad.

## 3. Presupuesto y tesorería
Configure vigencia, estructura presupuestal, fuentes y rubros antes de registrar ejecución. Mantenga la trazabilidad entre disponibilidad, compromiso, obligación y pago. Use las validaciones del sistema como barrera de integridad, no como sustituto de los actos y soportes institucionales.

## 4. Contabilidad pública
Configure el catálogo y la política contable aplicable a la entidad. Los saldos de apertura migrados se aceptan únicamente si el asiento cuadra. Las integraciones y reportes externos deben permanecer pendientes hasta confirmación del canal institucional configurado.

## 5. Contratación y supervisión
Use el expediente como eje de trazabilidad: planeación, disponibilidad, registro, contrato, garantías, actas, informes, supervisión, cuentas, obligaciones, pagos, modificaciones y liquidación. Relacione cada documento con el proceso que lo originó.

## 6. SGDEA y archivo
El módulo permite radicación de entrada/salida/interna, asignación, términos, actuaciones, expedientes, versiones, anexos, integridad, ubicación física, préstamos, transferencias, disposición y auditoría.

La entidad configura sus propios PGD, TRD/TVD, CCD, PINAR, SIC, políticas de retención, actos de adopción, calendarios, responsables y demás instrumentos. MerkaERP no impone una retención ficticia ni ejecuta disposición automática si no existe política institucional configurada.

Los documentos reservados, clasificados o con datos personales se protegen también en la capa de servicio. Las actuaciones de disposición y firma requieren usuario autorizado; la IA no puede alterar ni eliminar originales de manera autónoma.

## 7. Interoperabilidad
SECOP II, CHIP/CGN, SIIF, PILA, BPIN/MGA, transparencia, firma/sello, correo y otros canales se configuran con credenciales de la entidad desde **Integraciones institucionales**. Exportar o preparar un archivo no equivale a transmitirlo: MerkaERP solo cambia estados de envío cuando existe confirmación real del canal configurado.

## 8. Continuidad
Los respaldos integrales incluyen SQLite y el repositorio SGDEA. Cada archivo se verifica mediante SHA‑256. Antes de restaurar se comprueba integridad y se genera un respaldo de rollback. Use periódicamente el simulacro de restauración no destructivo.

## 9. Soporte y auditoría
El paquete de soporte está sanitizado: incluye diagnóstico técnico y logs redactados, sin bases, expedientes, secretos ni datos completos del negocio. Mantenga la bitácora y las evidencias Go‑Live como parte de la trazabilidad técnica de la instalación.

## 10. Go‑Live público
Complete al menos: release/analyzer/tests, usuarios/permisos, backup, restore drill, conciliación de migración, cadena presupuestal, contabilidad pública, SGDEA, instrumentos archivísticos configurados e integración institucional necesaria. Exporte el reporte Go‑Live JSON y su SHA‑256.
