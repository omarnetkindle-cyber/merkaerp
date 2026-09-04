import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';

void main() {
  final cop = Currency(
    code: 'COP',
    name: 'Colombian Peso',
    symbol: r'$',
    decimalPlaces: 2,
  );

  group('MoneyValue', () {
    test('suma cien valores decimales sin deriva binaria', () {
      final unit = MoneyValue.fromMajorUnits('99.99', currency: cop);
      var total = MoneyValue.fromMajorUnits('0.00', currency: cop);

      for (var i = 0; i < 100; i++) {
        total += unit;
      }

      expect(total.minorUnits, 999900);
      expect(total.toMajorUnitsString(), '9999.00');

      final remaining =
          MoneyValue.fromMajorUnits('10000.00', currency: cop) - total;
      expect(remaining.minorUnits, 100);
      expect(remaining.toMajorUnitsString(), '1.00');
    });

    test('compara importes solo dentro de la misma moneda y escala', () {
      final lower = MoneyValue.fromMajorUnits('10.01', currency: cop);
      final higher = MoneyValue.fromMajorUnits('10.02', currency: cop);

      expect(lower < higher, isTrue);
      expect(higher > lower, isTrue);
      expect(lower.compareTo(lower), 0);

      final usd = Currency(
        code: 'USD',
        name: 'US Dollar',
        symbol: r'$',
        decimalPlaces: 2,
      );
      expect(
        () =>
            lower.compareTo(MoneyValue.fromMajorUnits('10.01', currency: usd)),
        throwsStateError,
      );
    });

    test('convierte texto a unidades menores y vuelve sin perdida', () {
      const input = '-123456789.07';
      final value = MoneyValue.fromMajorUnits(input, currency: cop);

      expect(value.minorUnits, -12345678907);
      expect(value.toMajorUnitsString(), input);
      expect(value.format(), r'$-123456789.07');
    });

    test('multiplica y divide con redondeo racional exacto', () {
      final value = MoneyValue.fromMajorUnits('10.01', currency: cop);

      expect((value * 3).toMajorUnitsString(), '30.03');
      expect((value / 2).toMajorUnitsString(), '5.01');
      expect(
        value
            .multiplyRatio(numerator: 25, denominator: 100)
            .toMajorUnitsString(),
        '2.50',
      );
    });

    test('falla cerrado sin moneda resuelta', () {
      expect(
        () => MoneyValue.fromMajorUnits('10.00', currency: null),
        throwsStateError,
      );
      expect(
        () => MoneyValue(minorUnits: 1000, currency: null),
        throwsStateError,
      );
    });

    test('rechaza precision mayor a la escala de la moneda', () {
      expect(
        () => MoneyValue.fromMajorUnits('1.001', currency: cop),
        throwsFormatException,
      );
    });

    test('serializa unidades menores SQLite sin conversion implicita', () {
      final value = MoneyValue.fromSql(12345, currency: cop);

      expect(value.toSql(), 12345);
      expect(value.toMajorUnitsString(), '123.45');
      expect(() => MoneyValue.fromSql(123.45, currency: cop), throwsStateError);
    });

    test('aplica factores decimales y porcentajes de forma exacta', () {
      final base = MoneyValue.fromMajorUnits('10000.00', currency: cop);

      expect(base.multiplyDecimal('99.99').minorUnits, 99990000);
      expect(base.percent('12').toMajorUnitsString(), '1200.00');
    });
  });
}
