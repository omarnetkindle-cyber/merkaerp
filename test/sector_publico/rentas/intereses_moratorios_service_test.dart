/// Pruebas unitarias del camino normativo duro - Fase 4: Rentas (Intereses Moratorios)
/// Validaciones marcadas como "✅ Implementada (Dura)"
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math';
import 'package:merka_erp/sector_publico/rentas/services/intereses_moratorios_service.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

void main() {
  late InteresesMoratoriosService interesesService;

  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'SOCRATA_APP_TOKEN=token\nSOCRATA_AUTH_HEADER=header',
    );
  });

  setUp(() {
    interesesService = InteresesMoratoriosService();
  });

  group('Validaciones Normativas Duras - Fase 4', () {
    test('convierte la tasa EA de mora a tasa diaria equivalente', () {
      final intereses = interesesService.calcularInteresesMora(
        capital: publicMoneyFromMajor('1000000'),
        diasMora: 30,
      );

      // 28.79% EA de usura - 2 puntos = 26.79% EA;
      // ((1 + 0.2679)^(1/365) - 1) * 1,000,000 * 30.
      expect(publicMoneyForDisplay(intereses), closeTo(19515.55, 0.01));
    });

    test('Cálculo de intereses de mora según fórmula I = K × T × t', () {
      final capital = publicMoneyFromMajor('1000000');
      final diasMora = 30;

      final intereses = interesesService.calcularInteresesMora(
        capital: capital,
        diasMora: diasMora,
      );

      final tasaMoraDiaria =
          pow(1 + (interesesService.tasaInteresMoratorio / 100), 1 / 365) - 1;
      final esperado =
          publicMoneyForDisplay(capital) * tasaMoraDiaria * diasMora;

      expect(publicMoneyForDisplay(intereses), closeTo(esperado, 0.01));
    });

    test(
      'Debe calcular intereses de mora con fecha de vencimiento específica',
      () {
        final capital = publicMoneyFromMajor('1000000');
        final fechaVencimiento = DateTime(2024, 1, 1);
        final fechaCalculo = DateTime(2024, 1, 31);

        final intereses = interesesService.calcularInteresesMoraConFecha(
          capital: capital,
          fechaVencimiento: fechaVencimiento,
          fechaCalculo: fechaCalculo,
        );

        final diasMora = fechaCalculo.difference(fechaVencimiento).inDays;
        final tasaMoraDiaria =
            pow(1 + (interesesService.tasaInteresMoratorio / 100), 1 / 365) - 1;
        final esperado =
            publicMoneyForDisplay(capital) * tasaMoraDiaria * diasMora;

        expect(publicMoneyForDisplay(intereses), closeTo(esperado, 0.01));
      },
    );
  });
}
