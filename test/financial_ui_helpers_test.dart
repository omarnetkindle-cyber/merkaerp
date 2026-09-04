import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/financial/financial_ui_helpers.dart';

void main() {
  group('FinancialUiHelpers', () {
    test('formatea montos en COP de forma legible', () {
      expect(FinancialUiHelpers.formatCurrency(1250000), '\$1.250.000');
      expect(FinancialUiHelpers.formatCurrency(0), '\$0');
    });

    test('normaliza estados para pantallas contables', () {
      expect(FinancialUiHelpers.accountStatusLabel('pendiente'), 'Pendiente');
      expect(FinancialUiHelpers.accountStatusLabel('PARCIAL'), 'Parcial');
      expect(FinancialUiHelpers.accountStatusLabel(''), 'Sin estado');
    });
  });
}
