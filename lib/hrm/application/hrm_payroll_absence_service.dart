import 'package:sqflite/sqflite.dart';

import '../../core/currency/money_value.dart';
import 'hrm_leave_service.dart';

/// Resultado comun para los motores de nomina comercial y publica.
class HrmPayrollAbsenceSummary {
  const HrmPayrollAbsenceSummary({required this.daysByCode});

  final Map<String, double> daysByCode;

  static const automaticallyHandled = {
    'vacaciones',
    'permiso_remunerado',
    'permiso_no_remunerado',
    'incapacidad_eps',
    'incapacidad_arl',
    'licencia_maternidad',
    'licencia_paternidad',
  };

  static const manualReviewCodes = {'luto'};

  double daysFor(String code) => daysByCode[code] ?? 0;

  double get unpaidDays => daysFor('permiso_no_remunerado');

  double get commonSickLeaveDays => daysFor('incapacidad_eps');

  double get workRiskLeaveDays => daysFor('incapacidad_arl');

  double get maternityDays => daysFor('licencia_maternidad');

  double get paternityDays => daysFor('licencia_paternidad');

  double get unprocessedDays =>
      manualReviewCodes.fold(0, (total, code) => total + daysFor(code));

  bool get hasManualReview => unprocessedDays > 0;

  String? get warning {
    if (!hasManualReview) return null;
    final details = manualReviewCodes
        .where((code) => daysFor(code) > 0)
        .map(
          (code) =>
              '${_formatDays(daysFor(code))} d\u00edas de ${_label(code)}',
        )
        .join(', ');
    return 'Advertencia HRM: hay $details sin procesar autom\u00e1ticamente en '
        'este periodo \u2014 requiere revisi\u00f3n manual.';
  }

  Map<String, dynamic> toMap() => {
    'dias_por_tipo': daysByCode,
    'dias_vacaciones': daysFor('vacaciones'),
    'dias_permiso_remunerado': daysFor('permiso_remunerado'),
    'dias_no_remunerados': unpaidDays,
    'dias_incapacidad_eps': commonSickLeaveDays,
    'dias_incapacidad_arl': workRiskLeaveDays,
    'dias_maternidad': maternityDays,
    'dias_paternidad': paternityDays,
    'dias_sin_procesar': unprocessedDays,
    'advertencia': warning,
  };

  /// Calcula el efecto salarial y el pagador de ausencias HRM.
  ///
  /// Fuentes:
  /// - Decreto 2943/2013, modificatorio del Decreto 1406/1999: los dos
  ///   primeros dias de incapacidad general estan a cargo del empleador.
  /// - Regla general citada por Funcion Publica para enfermedad no profesional:
  ///   desde el tercer dia y hasta 90 dias, 2/3 del salario.
  /// - Ley 776/2002: incapacidad temporal por riesgo laboral, subsidio a cargo
  ///   de la ARL.
  /// - Ley 1822/2017 y Ley 2114/2021: licencias de maternidad y paternidad
  ///   remuneradas, a cargo del sistema de seguridad social en salud/EPS.
  HrmPayrollAbsenceImpact payrollImpact({
    required MoneyValue monthlySalary,
    int periodDays = 30,
  }) {
    final zero = MoneyValue(minorUnits: 0, currency: monthlySalary.currency);
    MoneyValue amountForDays(
      double days, {
      int numerator = 1,
      int denominator = 1,
    }) {
      if (days <= 0) return zero;
      return monthlySalary.multiplyRatio(
        numerator: (days * 1000).round() * numerator,
        denominator: periodDays * 1000 * denominator,
      );
    }

    final commonDays = commonSickLeaveDays.clamp(0, periodDays).toDouble();
    final employerCommonDays = commonDays > 0
        ? commonDays.clamp(0, 2).toDouble()
        : 0.0;
    final epsCommonDays = (commonDays - employerCommonDays)
        .clamp(0, periodDays)
        .toDouble();
    final arlDays = workRiskLeaveDays.clamp(0, periodDays).toDouble();
    final matDays = maternityDays.clamp(0, periodDays).toDouble();
    final patDays = paternityDays.clamp(0, periodDays).toDouble();
    final unpaid = unpaidDays.clamp(0, periodDays).toDouble();
    final thirdPartyDays = epsCommonDays + arlDays + matDays + patDays;
    final employerPaidDays = (periodDays - unpaid - thirdPartyDays)
        .clamp(0, periodDays)
        .toDouble();
    final transportEligibleDays =
        (periodDays - unpaid - commonDays - arlDays - matDays - patDays)
            .clamp(0, periodDays)
            .toDouble();

    final employerAmount = amountForDays(employerPaidDays);
    final epsCommonAmount = amountForDays(
      epsCommonDays,
      numerator: 2,
      denominator: 3,
    );
    final arlAmount = amountForDays(arlDays);
    final maternityAmount = amountForDays(matDays);
    final paternityAmount = amountForDays(patDays);

    return HrmPayrollAbsenceImpact(
      employerPaidDays: employerPaidDays,
      transportEligibleDays: transportEligibleDays,
      employerPaidAmount: employerAmount,
      epsRecognizedAmount: epsCommonAmount + maternityAmount + paternityAmount,
      arlRecognizedAmount: arlAmount,
      detail: {
        'empleador': {
          'dias': employerPaidDays,
          'valor': employerAmount.toWireMap(),
        },
        'eps': {
          'incapacidad_general_dias': epsCommonDays,
          'incapacidad_general_valor': epsCommonAmount.toWireMap(),
          'maternidad_dias': matDays,
          'maternidad_valor': maternityAmount.toWireMap(),
          'paternidad_dias': patDays,
          'paternidad_valor': paternityAmount.toWireMap(),
        },
        'arl': {'dias': arlDays, 'valor': arlAmount.toWireMap()},
        'sin_pago': {'dias': unpaid, 'codigo': 'permiso_no_remunerado'},
      },
    );
  }

  static String _label(String code) {
    const labels = {
      'incapacidad_eps': 'incapacidad EPS',
      'incapacidad_arl': 'incapacidad ARL',
      'licencia_maternidad': 'licencia de maternidad',
      'licencia_paternidad': 'licencia de paternidad',
      'luto': 'licencia por luto',
    };
    return labels[code] ?? code;
  }

  static String _formatDays(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}

class HrmPayrollAbsenceImpact {
  const HrmPayrollAbsenceImpact({
    required this.employerPaidDays,
    required this.transportEligibleDays,
    required this.employerPaidAmount,
    required this.epsRecognizedAmount,
    required this.arlRecognizedAmount,
    required this.detail,
  });

  final double employerPaidDays;
  final double transportEligibleDays;
  final MoneyValue employerPaidAmount;
  final MoneyValue epsRecognizedAmount;
  final MoneyValue arlRecognizedAmount;
  final Map<String, dynamic> detail;

  MoneyValue get thirdPartyRecognizedAmount =>
      epsRecognizedAmount + arlRecognizedAmount;

  MoneyValue get totalIncome => employerPaidAmount + thirdPartyRecognizedAmount;

  bool get hasThirdPartyPayer => thirdPartyRecognizedAmount.minorUnits > 0;

  Map<String, dynamic> toMap() => {
    ...detail,
    'dias_pagados_empleador': employerPaidDays,
    'dias_auxilio_transporte': transportEligibleDays,
    'valor_empleador': employerPaidAmount.toWireMap(),
    'valor_eps': epsRecognizedAmount.toWireMap(),
    'valor_arl': arlRecognizedAmount.toWireMap(),
    'valor_total_ingreso': totalIncome.toWireMap(),
  };
}

class HrmPayrollAbsenceService {
  const HrmPayrollAbsenceService._();

  static Future<HrmPayrollAbsenceSummary> forPeriod({
    required DatabaseExecutor db,
    required int companyId,
    required DateTime from,
    required DateTime to,
    required int employeeId,
  }) async {
    final rows = await HrmLeaveService().approvedForPeriod(
      from: from,
      to: to,
      employeeId: employeeId,
      executor: db,
      companyId: companyId,
    );
    return summarize(rows);
  }

  static HrmPayrollAbsenceSummary summarize(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final daysByCode = <String, double>{};
    for (final row in rows) {
      final code = row['leave_code']?.toString();
      if (code == null || code.isEmpty) continue;
      final days = (row['length_days'] as num?)?.toDouble() ?? 0;
      daysByCode[code] = (daysByCode[code] ?? 0) + days;
    }
    return HrmPayrollAbsenceSummary(daysByCode: daysByCode);
  }

  static Future<int?> companyIdForHrmEmployee({
    required DatabaseExecutor db,
    required int employeeId,
  }) async {
    final rows = await db.query(
      'empleados',
      columns: ['company_id'],
      where: 'id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.single['company_id'] as num?)?.toInt();
  }

  static Future<HrmPayrollAbsenceSummary> forPublicEmployee({
    required DatabaseExecutor db,
    required String? hrmEmployeeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final parsedId = int.tryParse(hrmEmployeeId ?? '');
    if (parsedId == null) return const HrmPayrollAbsenceSummary(daysByCode: {});
    final companyId = await companyIdForHrmEmployee(
      db: db,
      employeeId: parsedId,
    );
    if (companyId == null) {
      return const HrmPayrollAbsenceSummary(daysByCode: {});
    }
    return forPeriod(
      db: db,
      companyId: companyId,
      from: from,
      to: to,
      employeeId: parsedId,
    );
  }
}
