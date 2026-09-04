# Módulo: account + l10n_co_edi
## Origen en Odoo
- Módulo Odoo de referencia: account, l10n_co_edi
- Versión revisada: Odoo 19.0
## Propósito funcional
Gestionar la contabilidad general y la facturación electrónica de MerkaERP como capa unificada. El módulo debe permitir registrar facturas de clientes y proveedores, generar asientos contables, mantener un plan de cuentas/journales, y extender el flujo de facturación para cumplir con la facturación electrónica DIAN y requisitos de entidades públicas.
## Modelos de datos (nombres propios de MerkaERP, no los de Odoo)
| Entidad | Campos clave | Relaciones |
| --- | --- | --- |
| `AccountInvoice` | `partner_id`, `company_id`, `invoice_date`, `due_date`, `state`, `invoice_type`, `reference`, `total_amount`, `currency_id`, `edi_status`, `edi_document_id`, `public_sector_document_type`, `contract_reference` | `Partner`, `Company`, `AccountInvoiceLine`, `ElectronicInvoiceDocument` |
| `AccountInvoiceLine` | `invoice_id`, `product_id`, `account_id`, `quantity`, `price_unit`, `subtotal`, `tax_ids`, `service_rip_code`, `glosa_reference` | `AccountInvoice`, `Product`, `Account` |
| `AccountAccount` | `name`, `code`, `account_type`, `active` | `Company` |
| `AccountJournal` | `name`, `code`, `type`, `company_id`, `active` | `Company` |
| `ElectronicInvoiceDocument` | `invoice_id`, `dian_uuid`, `cufe`, `resolution_number`, `environment`, `document_type`, `status`, `xml_payload`, `json_payload`, `response_message` | `AccountInvoice` |
## Flujo de estados
- `draft` → `validated` → `posted` → `paid`
- `draft` → `cancelled`
- Para facturación electrónica DIAN: `draft` → `edi_prepared` → `edi_sent` → `edi_accepted` / `edi_rejected`
- En sector público, después de `edi_accepted` puede añadirse `budget_verified`/`glosa_pending` según el caso de salud o contrataciones públicas.
## Reglas de negocio críticas
- Validar campos requeridos por tipo de factura y por tipo de socio (`customer`, `supplier`, `public_entity`).
- Garantizar referencia única y estado consistente ante `validate`, `post` y `cancel`.
- Calcular totales en base a líneas de factura y mantener `total_amount` sincronizado.
- En facturación electrónica, generar los datos obligatorios DIAN y conservar `cufe`/`dian_uuid` en el documento asociado.
- No permitir publicación (`post`) de facturas públicas sin los campos de contratación/partida presupuestal requeridos cuando aplique.
- Permitir conservar flujos comerciales privados existentes sin exigir campos de sector público adicionales para clientes/proveedores privados.
- `AccountJournal` y `AccountAccount` deben ser usados para clasificar asientos, aunque el registro de asientos completos puede implementarse en un siguiente paso.
## Adaptaciones para sector público colombiano
- Normativa aplicable:
  - DIAN facturación electrónica y resolución de facturación.
  - Ley 1712 de transparencia.
  - Ley 80/1150 de contratación pública y SECOP.
  - RIPS y glosas para facturación en salud pública.
- Diferencias respecto al comportamiento estándar de Odoo:
  - La validación de documento electrónico debe seguir la estructura y estados de DIAN, no solo el flujo genérico de Odoo.
  - Para entidades públicas se requieren campos de contratación y presupuesto que no son obligatorios en el módulo comercial estándar.
  - Debe existir una separación clara entre facturas comerciales privadas y facturas públicas, con extensiones condicionales, no módulos paralelos.
  - Debe priorizarse la normatividad colombiana en campos de identidad tributaria, tipo de contribuyente y documentos electrónicos, aun cuando Odoo permita valores más genéricos.
## Diagnóstico del código existente
- ¿Ya existía algo equivalente en MerkaERP? (sí)
- Decisión: extender lo existente
## Estado de implementación
- [x] Diagnóstico completo
- [x] Especificación completa
- [x] Modelos de datos actualizados o creados
- [x] Lógica de negocio implementada (extendida o nueva)
- [x] Compatibilidad comercial/privada verificada (no se rompió nada existente)
- [x] Pruebas
- [ ] Documentado
