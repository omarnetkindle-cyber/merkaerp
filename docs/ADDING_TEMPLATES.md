# Agregar Una Nueva Plantilla

Las plantillas viven en `assets/templates` y se cargan desde
`CompanyTemplateService`.

Cada JSON debe incluir:

- `id`
- `name`
- `description`
- `features`
- `settings`
- `base_catalog`

Ejemplo:

```json
{
  "id": "consultoria",
  "name": "Consultoria",
  "description": "Servicios profesionales con clientes y cartera.",
  "features": {
    "services_enabled": true,
    "crm_enabled": true,
    "pos_enabled": true,
    "inventory_enabled": false
  },
  "settings": {
    "default_tax": "19",
    "invoice_prefix": "CS"
  },
  "base_catalog": []
}
```

Despues agrega el archivo a `templateAssets` en
`lib/features/company_template_service.dart`.
