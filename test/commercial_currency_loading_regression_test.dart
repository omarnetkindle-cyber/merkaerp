import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/compras_page.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/ventas_page.dart';

void main() {
  testWidgets(
    'Ventas muestra carga mientras la moneda aún no está resuelta',
    (tester) async {
      DatabaseHelper.disableAutoLoadsForTests = true;
      addTearDown(() => DatabaseHelper.disableAutoLoadsForTests = false);

      await tester.pumpWidget(const MaterialApp(home: VentasPage()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'Compras muestra carga mientras la moneda aún no está resuelta',
    (tester) async {
      DatabaseHelper.disableAutoLoadsForTests = true;
      addTearDown(() => DatabaseHelper.disableAutoLoadsForTests = false);

      await tester.pumpWidget(const MaterialApp(home: ComprasPage()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  test('MoneyValue conserva el fail-closed sin moneda resuelta', () {
    expect(
      () => MoneyValue(minorUnits: 0, currency: null),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'A resolved currency is required for MoneyValue',
        ),
      ),
    );
  });
}
