# Auditoria de completitud CRM - 2026-08-09

## Comparacion con la especificacion

| Entidad | Requisito/campo | Estado | Evidencia |
|---|---|---|---|
| CrmAccount | nombre, industria, ingreso anual, empleados, web | Parcial | `clientes` conserva nombre y datos comerciales; industria, ingreso anual, empleados y web no estan modelados como campos dedicados. |
| CrmAccount | parent_id, assigned_user_id, jerarquia | Implementado | `clientes.parent_id` y `clientes.assigned_user_id`; el servicio valida cuenta padre. |
| CrmContact | identidad, cuenta, fecha de nacimiento, correo, telefonos | Implementado | `crm_contacts` y `CrmContact`. |
| CrmContact | reports_to_id, lead_source, opportunity_role, assigned_user_id | Implementado | FK de jerarquia y campos persistidos. |
| CrmLead | cuenta/contacto, fuente, estado, monto, conversion y responsable | Implementado | `crm_leads`, `CrmLeadService.convert` atomico. |
| CrmOpportunity | nombre, cuenta, etapa, probabilidad, monto, siguiente paso, cierre, tipo y fuente | Implementado | `crm_opportunities` y maquina de etapas con probabilidad automatica. |
| CrmOpportunity | campaign_id | Parcial | El campo aparece en la especificacion, pero no existe tabla/flujo de campanas ni columna persistida en la implementacion actual. |
| CrmOpportunity | productos, cantidades y precio unitario | Implementado como extension | `crm_opportunity_items` referencia `productos`; no estaba en el DDL original, pero es necesario para el puente Quote/Sale y para demanda CRM->MRP. |
| CRM | Lead -> Account + Contact + Opportunity | Implementado | Transaccion en `crm_lead_service.dart`. |
| CRM | Closed Won -> sale | Implementado | Enlace validado por `CrmOpportunityService.linkClosedWonToSale`. |
| CRM | Kanban por etapa | Implementado | `crm_pipeline_page.dart`, drag-and-drop y filtro por vendedor. |
| CRM | ficha de cuenta e historial | Implementado | `crm_account_page.dart`, contactos, oportunidades e interacciones. |

## Alcance adicional evaluado

- Campanas: el campo `campaign_id` no existe en el esquema actual y la
  especificacion solo lo enumera como campo de oportunidad; no hay entidad ni
  flujo de campanas. Se deja parcial, recomendado como backlog posterior.
- Territorios de venta: no aparecen en la especificacion CRM revisada ni en el
  modelo actual. No se implementan sin una decision de producto.
- Forecasting: la probabilidad por etapa permite valor ponderado, pero no hay
  periodos, cuotas o versionado de pronosticos. Se deja parcial.
- Reportes de conversion del embudo: el Kanban existe, pero no hay reporte
  historico de conversion por etapa. Se deja parcial; requiere conservar
  transiciones y periodos, no solo una consulta adicional.

## Decision CRM -> MRP

La demanda del simulador se calcula con las lineas reales de oportunidad:

`demanda_ponderada_producto = suma(cantidad_linea * probabilidad_oportunidad / 100)`

El incremento del escenario escala esa demanda, no el ingreso como proxy. Si
existe BOM y operaciones para el producto, tambien se calcula la carga estimada
en horas con datos MRP; si no existe BOM, se conserva la demanda en unidades y
se emite una advertencia explicita.
