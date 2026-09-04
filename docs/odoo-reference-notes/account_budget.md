# Módulo: account_budget
## Origen en Odoo
- Módulo Odoo de referencia: account_budget
- Versión revisada: Odoo 19.0
## Propósito funcional
Proveer soporte de presupuesto público: definición de presupuestos por ejercicio, partidas presupuestales, apropiaciones, compromisos y ejecución presupuestal. Integrarse con compras y contabilidad para validar disponibilidad presupuestal y garantizar trazabilidad para entidades públicas.
## Modelos de datos (nombres propios de MerkaERP, no los de Odoo)
| Entidad | Campos clave | Relaciones |
| --- | --- | --- |
| `Budget` | `company_id`, `fiscal_year`, `name`, `state` (`draft`, `approved`, `closed`) | `BudgetLine`, `Company` |
| `BudgetLine` | `budget_id`, `code`, `name`, `initial_amount`, `appropriated_amount`, `committed_amount`, `executed_amount`, `available_amount` | `Budget`, `Account` |
| `BudgetCommitment` | `budget_line_id`, `origin_type`, `origin_id`, `amount`, `state` (`pending`, `confirmed`, `cancelled`) | `BudgetLine`, polymorphic link a `PurchaseOrder`/`Contract` |
| `BudgetAllocation` | `budget_line_id`, `date`, `amount`, `source`, `reference` | `BudgetLine` |
## Flujo de estados
- `Budget`: `draft` → `approved` → `closed`
- `BudgetLine` mantiene cantidades actualizadas en base a asignaciones y compromisos.
- `BudgetCommitment`: `pending` → `confirmed` → `cancelled`.
## Reglas de negocio críticas
- No permitir confirmar un compromiso que exceda el `available_amount` de la `BudgetLine`.
- Al confirmar compromiso, incrementar `committed_amount` y reducir `available_amount` en consecuencia.
- Al registrar ejecución (pago/registro contable), incrementar `executed_amount` y reducir `committed_amount` según corresponda.
- Soportar rollbacks: al cancelar un compromiso, liberar la apropiación.
- Validaciones de integridad: sumas y balances por `Budget`.
## Adaptaciones para sector público colombiano
- Normativa aplicable:
  - Ley 80/1150 (contratación pública), SGP, SGR, Ley 1712 (transparencia)
- Diferencias respecto al comportamiento estándar de Odoo:
  - Validaciones estrictas de apropiaciones y límites por partida presupuestal.
  - Campos para referencias de contrato/SECOP y trazabilidad de aprobaciones.
  - Reportes y exportaciones para auditoría.
## Diagnóstico del código existente
- ¿Ya existía algo equivalente en MerkaERP? (parcial: frontend solamente)
- Decisión: crear desde cero el backend `account_budget` y conectar con frontend existente
## Estado de implementación
- [x] Diagnóstico completo
- [x] Especificación completa
- [ ] Modelos de datos actualizados o creados
- [ ] Lógica de negocio implementada (extendida o nueva)
- [ ] Compatibilidad comercial/privada verificada (no se rompió nada existente)
- [ ] Pruebas
- [ ] Documentado
