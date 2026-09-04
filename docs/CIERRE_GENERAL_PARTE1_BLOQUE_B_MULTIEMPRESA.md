# Bloque B - Multiempresa, transferencias y consolidacion

Fecha: 2026-08-13

## Hallazgo

`CompanyTransferService` y `FinancialConsolidationService` existian, pero no estaban conectados al ciclo real de esquema ni a una UI operativa. Ademas:

- `completeTransfer` permitia completar transferencias sin estado `approved`.
- La ejecucion no era atomica.
- Las transferencias de fondos no generaban asientos contables.
- La consolidacion sumaba saldos sin eliminacion intercompania.
- El servicio intentaba insertar una columna `referencia` inexistente en `movimientos_caja`.
- CxC/CxP se consultaban con nombres de columnas incorrectos para el esquema real.

## Decision conservadora

La eliminacion intercompania queda explicita y auditable en `intercompany_eliminations`. No se infiere por coincidencia de monto/fecha, porque eso puede eliminar operaciones reales no relacionadas. Cada eliminacion registra empresas, metrica, monto, referencia, aprobador y fecha.

## Implementacion

- Migracion v98: crea/ensancha `company_transfers` e `intercompany_eliminations`.
- `CompanyTransferService.completeTransfer()` ahora:
  - exige estado `approved`;
  - ejecuta todo dentro de una transaccion;
  - genera movimientos de caja sin columnas inexistentes;
  - genera asientos contables balanceados en `asientos_contables`/`asiento_lineas`;
  - registra eliminacion intercompania para transferencias de fondos.
- `FinancialConsolidationService`:
  - resta eliminaciones aprobadas para `sales_expenses` y `receivable_payable`;
  - usa columnas reales (`saldo` en CxC/CxP);
  - tolera tablas opcionales ausentes devolviendo cero.
- `EmpresasPage`:
  - expone una UI minima para crear transferencia de fondos, aprobar/completar y consultar consolidado.

## Evidencia ejecutada

```text
flutter test test\multi_company_transfer_consolidation_test.dart --reporter expanded
Resultado: 2 tests passed.
```

```text
dart analyze lib\core\multi_company\transfer_service.dart lib\core\multi_company\financial_consolidation.dart lib\empresas_page.dart test\multi_company_transfer_consolidation_test.dart
Resultado: No issues found.
```
