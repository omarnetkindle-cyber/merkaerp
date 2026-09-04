import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';

final Currency testCop = Currency(
  code: 'COP',
  name: 'Peso colombiano de prueba',
  symbol: r'$',
  decimalPlaces: 2,
);

MoneyValue testMoney(String majorUnits) =>
    MoneyValue.fromMajorUnits(majorUnits, currency: testCop);

MoneyValue get zeroTestMoney => MoneyValue(minorUnits: 0, currency: testCop);
