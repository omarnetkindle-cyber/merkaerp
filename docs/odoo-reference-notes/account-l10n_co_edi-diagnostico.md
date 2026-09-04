# Diagnóstico: account + l10n_co_edi

## Código existente detectado en MerkaERP
- Módulo backend en `backend/src/modules/account`.
- Modelo `Invoice` en `backend/src/modules/account/models/Invoice.js` con operaciones CRUD básicas, validación, publicación y cancelación.
- Modelo `InvoiceLine` en `backend/src/modules/account/models/Invoice.js` con creación, consulta y actualización de líneas.
- Rutas REST en `backend/src/modules/account/routes/invoices.js` para crear/leer/actualizar facturas y líneas, y cambiar estados (`validate`, `post`, `cancel`).
- Migración en `backend/src/database/migrations/001_phase1_core.sql` con tablas `account_invoices`, `account_invoice_lines`, además de `account_accounts` y `account_journals` básicas.
- Integración de rutas en `backend/src/routes/odooApi.js` bajo `/api/odoo/invoices`.

## Para qué caso de uso comercial/privado fue construido
- Facturación básica de clientes/proveedores con tipos simples (`out_invoice`, `in_invoice`, `out_refund`, `in_refund`).
- Control de estado de factura (`draft`, `posted`, `paid`, `cancelled`).
- Registro de líneas de factura con producto, cuenta, cantidad, precio y subtotal.
- Soporte CRUD simple y consulta por socio y referencia.

## Qué le falta comparado con el módulo equivalente de Odoo
- No existe un motor completo de contabilidad: no hay asientos contables, conciliación, ni flujo de diarios/journals más allá de la tabla básica.
- No existen entidades de documento electrónico ni procesos de envío/recepción DIAN.
- No hay integración con plan de cuentas real ni validación de cuentas según tipo de factura.
- Falta manejo de impuestos y bases para tasas, así como cálculos fiscales y retenciones.
- No hay conceptos de partner tributario completo ni de comprobantes de pago con estructura fiscal colombiana.
- No hay soporte de orden de pago, conciliación bancaria ni registro de pagos asociados.

## Qué le falta para sector público
- No hay soporte de facturación electrónica DIAN con CUFE, resolución, ambiente, tipo de documento de venta público, ni estados de aceptación/rechazo.
- No hay campos para contratos públicos, procesos de contratación o referencias SECOP/Ley 80.
- No existe soporte de RIPS, glosas, códigos de servicio médico o facturación por prestación de servicios de salud pública.
- No hay validaciones específicas para entidades públicas: régimen tributario especial, clasificación de socios como entidades estatales, ni requerimientos de transparencia.
- No se contempla la conciliación presupuestal ni el encuadramiento de gastos en partidas presupuestales.

## Evaluación
- ¿Ya existía algo equivalente en MerkaERP? sí
- Decisión: extender lo existente

## Resumen breve
El sistema actual ya tiene la base de facturación y facturas, pero está muy enfocado en flujos comerciales privados básicos. Para el módulo `account + l10n_co_edi` hay que ampliar la contabilidad a un mapa de cuentas real, soportar DIAN y documentos electrónicos, y agregar validaciones/public sector extras sin romper el flujo comercial existente.
