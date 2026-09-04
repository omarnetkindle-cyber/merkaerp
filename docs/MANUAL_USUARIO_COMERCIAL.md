# Manual operativo · MerkaERP Comercial 1.2

## 1. Primera puesta en marcha
1. Active la licencia Comercial. La familia de producto queda fijada por la licencia y no puede cambiarse a Público desde la aplicación.
2. Complete el onboarding: identidad de la empresa, información fiscal, moneda, operación, módulos y política de respaldo.
3. Cree al menos un usuario administrador y luego usuarios operativos con permisos mínimos necesarios.
4. Si la empresa viene de otro software, use **Administración → Migración de datos** antes de iniciar operación ordinaria.
5. Ejecute **Salud y soporte → Checklist Go‑Live / UAT** antes de usar datos reales.

## 2. Migración desde otro sistema
MerkaERP admite CSV/TSV/TXT/PSV, Excel XLSX, JSON y bases SQLite de solo lectura. El asistente propone equivalencias de columnas, muestra vista previa, valida y crea un respaldo integral antes de escribir.

Puede incorporar clientes, proveedores, productos e inventario de apertura, cartera, cuentas por pagar y saldos contables iniciales. El histórico que no deba reconstruirse como operación nativa puede conservarse en **Archivo Legado**. Las carpetas de soportes pueden incorporarse al gestor documental con SHA‑256 y trazabilidad.

La reversión solo afecta cambios creados por la migración. Si un registro fue modificado después o un documento fue reutilizado en otro expediente, MerkaERP detiene el rollback para preservar el trabajo posterior.

## 3. Operación diaria recomendada
- Abra caja/turno antes de vender cuando corresponda.
- Registre compras antes de disponer del inventario recibido.
- Use ventas contado, crédito o pago mixto según el medio real.
- Las pasarelas remotas se registran primero como pendientes; solo se acreditan después de verificación del proveedor.
- Revise cartera y cuentas por pagar periódicamente.
- Cierre caja y documente diferencias.
- Consulte reportes y dashboard al finalizar el período operativo.

## 4. Inventario
Use códigos/SKU y códigos de barras estables. Para artículos que lo requieran gestione lotes, vencimientos, bodegas y movimientos auditados. Evite ajustes manuales como sustituto de compras/ventas: los ajustes deben representar hechos reales y conservar justificación.

## 5. Contabilidad
Configure plan de cuentas, impuestos y parametrización antes de operar. Las aperturas migradas deben estar balanceadas. No reconstruya facturas históricas solo para obtener saldos: use apertura + Archivo Legado para evitar duplicar caja, impuestos o inventario.

## 6. Integraciones
Cada empresa configura sus propias credenciales desde **Integraciones**. Los secretos se administran fuera de la base operativa cuando la plataforma lo permite. Una integración no configurada o no verificada permanece cerrada y no simula éxito.

## 7. Gestión documental empresarial
Use radicación/seguimiento, expedientes, anexos, versiones, archivo, préstamos y trazabilidad para contratos, comunicaciones, soportes y documentos internos. Las capacidades archivísticas exclusivas del Sector Público no aparecen en la licencia Comercial.

## 8. Respaldo y recuperación
Mantenga respaldos automáticos y externos. Antes de una actualización o migración importante cree un respaldo integral. Desde **Salud y soporte** puede verificar respaldos y ejecutar un simulacro de restauración no destructivo.

## 9. Soporte
El Centro de Soporte puede exportar un paquete técnico sanitizado con versión, salud, integridad, esquema y logs redactados. No incluye la base de datos, documentos del negocio ni secretos.

## 10. Go‑Live
No declare una instalación lista hasta completar los controles bloqueantes: release build, analyzer/tests, permisos, backup, restore drill, conciliación de migración cuando aplique, integraciones necesarias y UAT comercial de punta a punta. Exporte la evidencia Go‑Live y conserve su checksum SHA‑256.
