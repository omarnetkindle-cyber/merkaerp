import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/hrm/application/hrm_payroll_absence_service.dart';

void main() {
  group('HrmPayrollAbsenceSummary payrollImpact', () {
    final salary = publicMoneyFromMajor('3000000');

    test('incapacidad EPS paga dos dias empleador y desde dia 3 a 2/3 EPS', () {
      final impact = const HrmPayrollAbsenceSummary(
        daysByCode: {'incapacidad_eps': 5},
      ).payrollImpact(monthlySalary: salary);

      expect(impact.employerPaidDays, 27);
      expect(impact.employerPaidAmount, publicMoneyFromMajor('2700000'));
      expect(impact.epsRecognizedAmount, publicMoneyFromMajor('200000'));
      expect(impact.totalIncome, publicMoneyFromMajor('2900000'));
      expect(impact.transportEligibleDays, 25);
    });

    test('incapacidad ARL reconoce desde el dia 1 a cargo de ARL', () {
      final impact = const HrmPayrollAbsenceSummary(
        daysByCode: {'incapacidad_arl': 4},
      ).payrollImpact(monthlySalary: salary);

      expect(impact.employerPaidDays, 26);
      expect(impact.employerPaidAmount, publicMoneyFromMajor('2600000'));
      expect(impact.arlRecognizedAmount, publicMoneyFromMajor('400000'));
      expect(impact.totalIncome, publicMoneyFromMajor('3000000'));
      expect(impact.transportEligibleDays, 26);
    });

    test('licencia de maternidad queda a cargo de EPS por el periodo', () {
      final impact = const HrmPayrollAbsenceSummary(
        daysByCode: {'licencia_maternidad': 30},
      ).payrollImpact(monthlySalary: salary);

      expect(impact.employerPaidDays, 0);
      expect(impact.epsRecognizedAmount, publicMoneyFromMajor('3000000'));
      expect(impact.totalIncome, publicMoneyFromMajor('3000000'));
      expect(impact.transportEligibleDays, 0);
    });

    test('licencia de paternidad queda a cargo de EPS por dos semanas', () {
      final impact = const HrmPayrollAbsenceSummary(
        daysByCode: {'licencia_paternidad': 14},
      ).payrollImpact(monthlySalary: salary);

      expect(impact.employerPaidDays, 16);
      expect(impact.epsRecognizedAmount, publicMoneyFromMajor('1400000'));
      expect(impact.totalIncome, publicMoneyFromMajor('3000000'));
      expect(impact.transportEligibleDays, 16);
    });

    test('tipos no automatizados siguen generando revision manual', () {
      const summary = HrmPayrollAbsenceSummary(daysByCode: {'luto': 2});

      expect(summary.hasManualReview, isTrue);
      expect(summary.warning, contains('requiere'));
    });
  });
}
