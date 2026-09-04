# Fase 3A: inventario comercial de dinero

Fecha: 2026-08-02  
Base: manifiesto v75 del commit `004db33`.

## Conteo verificado

- Esquema total: 125 tablas y 355 columnas monetarias.
- Sector publico: 51 tablas y 158 columnas.
- Comercial: **74 tablas y 197 columnas**.
- Busqueda amplia: 99 archivos Dart fuera de `lib/sector_publico/` mencionan
  al menos una tabla comercial. Incluye navegacion, catalogos, textos y flags.
- Alcance directo depurado: **79 archivos** con calculo, modelo, persistencia o
  presentacion de importes. Los demas se auditan, pero no se modifican si solo
  contienen metadatos o navegacion.

## Orden de conversion por riesgo

### 1. Ventas/POS y documentos de venta

1. `lib/sales/application/create_sale_use_case.dart`
2. `lib/accounting/application/accounting_engine.dart`
3. `lib/commerce/application/payment_policy.dart`
4. `lib/sales/domain/sales_document.dart`
5. `lib/sales/domain/sale.dart`
6. `lib/sales/domain/order.dart`
7. `lib/sales/domain/order_line.dart`
8. `lib/sales/domain/quote.dart`
9. `lib/sales/data/sale_repository.dart`
10. `lib/sales/data/sales_document_repository.dart`
11. `lib/sales/application/order_service.dart`
12. `lib/sales/application/quote_service.dart`
13. `lib/sales/application/sales_command_handlers.dart`
14. `lib/sales/application/sales_projections.dart`
15. `lib/sales/application/sales_query_handlers.dart`
16. `lib/ventas_page.dart`
17. `lib/ui/sales_mode_panel.dart`
18. `lib/services/api_router.dart`
19. `lib/public_api_server.dart`
20. `lib/documento_pdf_service.dart`
21. `lib/facturacion_electronica_page.dart`

La verificacion de ReteICA se hace en este bloque. La fuente debe seguir siendo
`reglas_retenciones_empresa` filtrada por empresa, activa y aplicable a ventas;
sin regla activa el valor es cero.

### 2. Caja, cartera, bancos y compras

1. `lib/caja_page.dart`
2. `lib/cierres_caja_page.dart`
3. `lib/extracto_caja_page.dart`
4. `lib/transferencias_page.dart`
5. `lib/cuentas_por_cobrar_page.dart`
6. `lib/cuentas_por_pagar_page.dart`
7. `lib/bancos_page.dart`
8. `lib/conciliacion_bancaria_page.dart`
9. `lib/extractos_bancarios_page.dart`
10. `lib/compras_page.dart`
11. `lib/detalle_compra_page.dart`
12. `lib/purchases/application/create_purchase_use_case.dart`
13. `lib/purchases/application/purchase_command_handlers.dart`
14. `lib/purchases/application/purchase_projections.dart`
15. `lib/purchases/application/purchase_query_handlers.dart`
16. `lib/purchases/data/purchase_document_repository.dart`
17. `lib/purchases/data/purchase_repository.dart`
18. `lib/purchases/domain/purchase.dart`
19. `lib/purchases/domain/purchase_document.dart`

`payment_policy.dart` pertenece a ventas y caja, pero se cuenta una sola vez.

### 3. Nomina comercial y reportes fiscales

1. `lib/db_helper.dart`
2. `lib/nomina_page.dart`
3. `lib/reportes_fiscales_page.dart`
4. `lib/declaraciones_tributarias_page.dart`

Este bloque incluye la regresion obligatoria de cesantias: provision anual del
12 % sobre el saldo/base aplicable, no un 1 % mensual presentado como anual;
tambien cubre IBC, `neto_pagar`, Formulario 300 y Formulario 350.

### 4. Contabilidad e inventario

1. `lib/accounting/application/ledger_engine.dart`
2. `lib/accounting/data/accounting_report_repository.dart`
3. `lib/accounting/data/journal_entry_repository.dart`
4. `lib/accounting/domain/journal_entry.dart`
5. `lib/accounting/domain/trial_balance.dart`
6. `lib/comprobantes_page.dart`
7. `lib/contabilidad_page.dart`
8. `lib/inventory/application/inventory_control_service.dart`
9. `lib/inventory/data/stock_ledger_repository.dart`
10. `lib/inventory/domain/inventory_lot.dart`
11. `lib/inventory/domain/inventory_summary.dart`
12. `lib/inventory/domain/price_history.dart`
13. `lib/inventory/domain/product.dart`
14. `lib/inventory/domain/stock_ledger.dart`
15. `lib/inventario_page.dart`

### 5. Reportes, proyecciones e integraciones

1. `lib/core/analytics/dashboard_analytics.dart`
2. `lib/core/multi_company/financial_consolidation.dart`
3. `lib/core/payments/payment_service.dart`
4. `lib/core/predictive/predictive_analytics.dart`
5. `lib/cqrs/application/dashboard_projection.dart`
6. `lib/cqrs/domain/read_models.dart`
7. `lib/enterprise/application/final_enterprise_command_handlers.dart`
8. `lib/enterprise/application/final_enterprise_projections.dart`
9. `lib/enterprise/application/final_enterprise_query_handlers.dart`
10. `lib/enterprise/domain/final_enterprise_contexts.dart`
11. `lib/exportar_excel.dart`
12. `lib/reportes_page.dart`
13. `lib/services/enterprise_feature_service.dart`
14. `lib/services/merka_intelligence_service.dart`
15. `lib/services/nequi_service.dart`
16. `lib/services/pse_service.dart`
17. `lib/services/recetas_service.dart`
18. `lib/ui/finance_mode_panel.dart`
19. `lib/ui/operations_mode_panel.dart`
20. `lib/seed_operations.dart`

## Contrato de borde requerido

Las tablas comerciales heredadas no siempre guardan moneda por fila. Antes de
deserializar un importe se resuelve la moneda en este orden: moneda explicita de
la fila, moneda base de la empresa y, si ninguna existe, error. Los modelos
sincronos reciben la `Currency` ya resuelta; no consultan SQLite ni usan COP por
defecto. SQLite entrega/recibe `minorUnits` como `INTEGER`; UI y documentos
entregan texto decimal a `MoneyValue.fromMajorUnits` y presentan
`toMajorUnitsString()`/`format()`.

## Manifiesto comercial (74 tablas / 197 columnas)

| Tabla | Columnas monetarias |
|---|---|
| abonos_cxc | monto |
| abonos_cxp | monto |
| accounting_journal_lines | credit, debit, local_credit, local_debit |
| activos_fijos | costo, depreciacion_acumulada, valor_libros, valor_residual |
| ap_payment_schedules | amount |
| ap_supplier_ledger | amount, open_amount |
| ar_ledger_entries | amount, open_amount |
| ar_payment_promises | amount |
| asiento_lineas | credito, debito |
| bancos | saldo_inicial |
| bank_statement_lines | amount |
| caja_sesiones | diferencia, monto_contado, monto_inicial, total_egresos, total_ingresos, total_ventas |
| cierres_caja | diferencia, efectivo_contado, saldo_sistema |
| comisiones_liquidadas | base, comision |
| commission_rules | max_amount, min_amount |
| commissions | commission_amount, sale_amount |
| compras | credito, efectivo, impuesto_total, retefuente, reteica, reteiva, subtotal, total, transferencia |
| compras_detalle | costo_unitario, subtotal |
| comprobantes_contables | total |
| conciliaciones_bancarias | diferencia, saldo_extracto, saldo_libros |
| cotizacion_detalle | precio_unitario, subtotal |
| cotizaciones | impuesto, subtotal, total |
| crm_opportunities | value |
| cuentas_por_cobrar | saldo, total |
| cuentas_por_pagar | saldo, total |
| customer_credit_profiles | balance, credit_limit |
| devoluciones_compras | total |
| devoluciones_compras_detalle | costo_unitario, subtotal |
| devoluciones_ventas | total |
| devoluciones_ventas_detalle | precio_unitario, subtotal |
| documentos_compra_flujo | total |
| documentos_compra_flujo_lineas | costo_unitario, total |
| documentos_venta_flujo | total |
| documentos_venta_flujo_lineas | precio_unitario, total |
| empleados | salario_base |
| enterprise_fixed_assets | accumulated_depreciation, book_value, cost, fiscal_depreciation, monthly_depreciation |
| enterprise_tax_calculations | retention, tax, taxable_base, total |
| extractos_bancarios | valor |
| fixed_asset_events | amount |
| historial_precios | precio_anterior, precio_nuevo |
| inventory_lots | unit_cost |
| kardex_inventario | costo_total, costo_unitario |
| lotes | costo |
| movimientos_caja | monto |
| movimientos_inventario | costo_anterior, costo_nuevo |
| nomina_liquidaciones | aportes_empleador, arl, cesantias, fsp, intereses_cesantias, neto_pagar, parafiscal_caja, parafiscal_icbf, parafiscal_sena, pension_empleado, pension_empleador, prima_servicios, retefuente, salario_base, salud_empleado, salud_empleador, total_deducciones, total_devengado, vacaciones |
| order_lines | discount_amount, subtotal, tax_amount, total, unit_cost, unit_price |
| payment_transactions | amount |
| payroll_novelties | tarifa, valor |
| payroll_parameters | smmlv, transportation_allowance, uvt |
| pedido_detalle | precio_unitario, subtotal |
| pedidos | impuesto, subtotal, total |
| presupuesto_lineas | monto_presupuestado |
| presupuestos | diferencia, valor_presupuestado, valor_real |
| price_history | new_price, old_price |
| productos | costo, precio |
| purchase_analytics_read_model | retention, spend, tax |
| purchase_document_lines | retention_total, subtotal, tax_total, total, unit_cost |
| purchase_documents | budget_available, retention_total, subtotal, tax_total, total |
| quote_lines | discount_amount, subtotal, tax_amount, total, unit_cost, unit_price |
| reglas_retenciones_empresa | base_minima |
| sales_analytics_read_model | revenue, tax |
| sales_document_lines | discount, subtotal, tax_total, total, unit_price |
| sales_documents | discount_total, subtotal, tax_total, total |
| sales_orders | discount_amount, subtotal, tax_amount, total |
| sales_quotes | discount_amount, subtotal, tax_amount, total |
| stock_bodega | costo |
| supplier_balances | balance |
| traslados_bodega | costo_at_movement |
| treasury_bank_accounts | balance |
| treasury_bank_movements | amount |
| treasury_transfers | amount |
| ventas | costo_unitario, credito, efectivo, impuesto_total, precio_unitario, retefuente, reteica, reteiva, subtotal, total, transferencia |
| ventas_detalle | precio_unitario, subtotal |

## Regla para dependencias cruzadas

Si una firma compartida llega a sector publico aun no convertido, se conserva
la frontera por adaptador tipado que reciba/entregue `MoneyValue`; no se permite
un `dynamic`, `num`, cast a `double` ni division manual como puente temporal. La
dependencia se registra en el log y se deja para 3B si su implementacion vive
exclusivamente bajo `lib/sector_publico/`.

## Estado histórico al cierre de la entrega parcial

La compilacion incremental descubrio seis bordes comerciales que la busqueda
inicial por tablas no habia clasificado como consumidores directos:

- `lib/core/api/api_dispatcher.dart`
- `lib/core/invoicing/cufe.dart`
- `lib/estados_financieros_page.dart`
- `lib/financial_dashboard.dart`
- `lib/presupuestos_page.dart`
- `lib/core/currency/money_currency_resolver.dart` (nuevo borde de moneda)

Se convirtieron semanticamente 27 de los 79 consumidores del inventario, mas
estos seis bordes de soporte. Quedan **52 consumidores inventariados** para una
continuacion de Fase 3A. `order_service.dart`, `quote_service.dart`,
`commission_service.dart`, `warranty_service.dart` y `order.dart` recibieron
formateo mecanico durante la compilacion; esos cambios se revirtieron antes del
commit. No se cuentan como convertidos y sus modelos monetarios siguen pendientes.

## Cierre de Fase 3A - tramo final de 35 consumidores

El inventario fue reconciliado contra el alcance directo de 79 consumidores:
44 ya estaban convertidos antes de este tramo y los 35 siguientes quedaron
convertidos en esta entrega.

### Pedidos y cotizaciones

- `lib/sales/domain/order.dart`
- `lib/sales/domain/order_line.dart`
- `lib/sales/domain/quote.dart`
- `lib/sales/application/order_service.dart`
- `lib/sales/application/quote_service.dart`

### Otros documentos, API y pantallas comerciales

- `lib/services/api_router.dart`
- `lib/public_api_server.dart`
- `lib/documento_pdf_service.dart`
- `lib/detalle_compra_page.dart`
- `lib/comprobantes_page.dart`
- `lib/contabilidad_page.dart`

### Inventario heredado

- `lib/inventory/application/inventory_control_service.dart`
- `lib/inventory/domain/inventory_lot.dart`
- `lib/inventory/domain/inventory_summary.dart`
- `lib/inventory/domain/price_history.dart`
- `lib/inventory/domain/product.dart`
- `lib/inventario_page.dart`

### Reportes, proyecciones e integraciones

- `lib/core/analytics/dashboard_analytics.dart`
- `lib/core/multi_company/financial_consolidation.dart`
- `lib/core/payments/payment_service.dart`
- `lib/core/predictive/predictive_analytics.dart`
- `lib/cqrs/application/dashboard_projection.dart`
- `lib/cqrs/domain/read_models.dart`
- `lib/enterprise/application/final_enterprise_command_handlers.dart`
- `lib/enterprise/application/final_enterprise_projections.dart`
- `lib/enterprise/application/final_enterprise_query_handlers.dart`
- `lib/enterprise/domain/final_enterprise_contexts.dart`
- `lib/services/enterprise_feature_service.dart`
- `lib/services/merka_intelligence_service.dart`
- `lib/services/nequi_service.dart`
- `lib/services/pse_service.dart`
- `lib/services/recetas_service.dart`
- `lib/ui/finance_mode_panel.dart`
- `lib/ui/operations_mode_panel.dart`
- `lib/seed_operations.dart`

### Evidencia dirigida

- `flutter test test/module_smoke_test.dart test/merka_intelligence_service_test.dart test/final_enterprise_contexts_test.dart test/architectural_consolidation_test.dart test/api_dispatcher_test.dart test/orders_quotes_money_test.dart test/inventory_legacy_money_test.dart --reporter expanded`: `00:20 +22: All tests passed!`
- `flutter test test/phase3a_remaining_money_test.dart --reporter expanded`: `00:00 +2: All tests passed!`
- `dart format --output=none --set-exit-if-changed` sobre los archivos convertidos: verificación ejecutada después de formatear; sin cambios pendientes en la última pasada.

### Suite completa

Comando:

```text
flutter test --reporter silent --file-reporter json:phase3a_audit_suite_final.json --concurrency=4
```

Resultado: `217` tests no ocultos (`200` success, `17` errors, `3` skipped).
Los 17 errores son los mismos fallos ajenos a 3A de la línea base: `login_widget_test.dart`, `acta_responsabilidad_service_test.dart`, `fut_territorial_service_test.dart`, `sia_observa_service_test.dart`, `configuracion_general_service_test.dart`, `onboarding_legado_migracion_test.dart`, `presupuesto_pago_integracion_test.dart` (2), `sicodis_service_test.dart`, `exportacion_declaraciones_test.dart`, `facturacion_salud_service_test.dart`, `predial_ica_page_test.dart`, `presupuesto_publico_page_test.dart`, `salud_publica_page_test.dart`, `siif_service_test.dart` y `widget_test.dart` (2). No apareció una falla nueva en los consumidores comerciales convertidos.

### Cierre formal

**Fase 3A: 79/79 consumidores comerciales convertidos - COMPLETA.**
La validación de partida doble directamente a nivel SQL sigue pendiente como
trabajo separado de esquema/transacción; no se presenta como resuelta por esta
fase. El entorno no permitió cerrar la verificación global, por lo que Omar
debe ejecutar manualmente `flutter analyze` y `flutter build windows`.
