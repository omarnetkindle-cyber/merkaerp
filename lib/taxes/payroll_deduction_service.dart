import '../core/currency/money_value.dart';

enum PayrollDeductionKind {
  childSupportGarnishment,
  ordinaryGarnishment,
  payrollLoan,
  unionFee,
  employerLoan,
  manualOther,
}

class PayrollDeductionApplication {
  const PayrollDeductionApplication({
    required this.kind,
    required this.requested,
    required this.applied,
    required this.reason,
  });

  final PayrollDeductionKind kind;
  final MoneyValue requested;
  final MoneyValue applied;
  final String reason;

  bool get capped => applied < requested;

  Map<String, Object> toMap() => {
    'tipo': kind.name,
    'solicitado': requested.toWireMap(),
    'aplicado': applied.toWireMap(),
    'limitado': capped,
    'razon': reason,
  };
}

class PayrollDeductionResult {
  const PayrollDeductionResult({
    required this.total,
    required this.items,
    this.warning,
  });

  final MoneyValue total;
  final List<PayrollDeductionApplication> items;
  final String? warning;

  Map<String, Object?> toMap() => {
    'total': total.toWireMap(),
    'items': items.map((item) => item.toMap()).toList(),
    'warning': warning,
  };
}

/// Applies Colombian private-payroll deductions after mandatory legal
/// deductions. The precedence is conservative:
///
/// 1. Judicial food/cooperative garnishments: CST art. 156 allows up to 50%.
/// 2. Ordinary judicial garnishments: CST arts. 154-155 protect SMMLV and
///    allow one fifth of the excess over SMMLV.
/// 3. Libranza/payroll loans: Ley 1527/2012 art. 3 requires the worker to
///    keep at least 50% of net salary after legal deductions.
/// 4. Union dues: CST art. 400, applied after judicial/libranza deductions.
/// 5. Employer loans and manual other deductions: written-authorisation bucket,
///    never pushed below SMMLV by this service.
class PayrollDeductionService {
  const PayrollDeductionService();

  static const Set<String> supportedNoveltyTypes = {
    'embargo_alimentos',
    'embargo_cooperativa',
    'embargo_judicial',
    'libranza',
    'cuota_sindical',
    'prestamo_empresa',
  };

  PayrollDeductionResult apply({
    required List<Map<String, Object?>> noveltyRows,
    required MoneyValue manualOtherDeductions,
    required MoneyValue grossIncome,
    required MoneyValue mandatoryDeductions,
    required MoneyValue smmlv,
    required MoneyValue zero,
  }) {
    final netAfterLaw = grossIncome - mandatoryDeductions;
    var remaining = netAfterLaw;
    final applications = <PayrollDeductionApplication>[];

    final childSupport = _sum(noveltyRows, {
      'embargo_alimentos',
      'embargo_cooperativa',
    }, zero);
    _apply(
      applications,
      kind: PayrollDeductionKind.childSupportGarnishment,
      requested: childSupport,
      limit: _min(
        childSupport,
        netAfterLaw.multiplyRatio(numerator: 1, denominator: 2),
      ),
      reason: 'CST art. 156: hasta 50% por alimentos/cooperativas.',
      remaining: () => remaining,
      updateRemaining: (value) => remaining = value,
    );

    final ordinaryGarnishment = _sum(noveltyRows, {'embargo_judicial'}, zero);
    final ordinaryBase = netAfterLaw > smmlv ? netAfterLaw - smmlv : zero;
    _apply(
      applications,
      kind: PayrollDeductionKind.ordinaryGarnishment,
      requested: ordinaryGarnishment,
      limit: _min(
        ordinaryGarnishment,
        ordinaryBase.multiplyRatio(numerator: 1, denominator: 5),
      ),
      reason: 'CST arts. 154-155: una quinta parte del excedente de SMMLV.',
      remaining: () => remaining,
      updateRemaining: (value) => remaining = value,
    );

    final payrollLoan = _sum(noveltyRows, {'libranza'}, zero);
    final fiftyPercentFloor = netAfterLaw.multiplyRatio(
      numerator: 1,
      denominator: 2,
    );
    _apply(
      applications,
      kind: PayrollDeductionKind.payrollLoan,
      requested: payrollLoan,
      limit: _min(payrollLoan, _positive(remaining - fiftyPercentFloor, zero)),
      reason:
          'Ley 1527/2012 art. 3: conserva al menos 50% del neto despues de ley.',
      remaining: () => remaining,
      updateRemaining: (value) => remaining = value,
    );

    final unionFee = _sum(noveltyRows, {'cuota_sindical'}, zero);
    _apply(
      applications,
      kind: PayrollDeductionKind.unionFee,
      requested: unionFee,
      limit: _min(unionFee, remaining),
      reason: 'CST art. 400: retencion de cuotas sindicales comunicadas.',
      remaining: () => remaining,
      updateRemaining: (value) => remaining = value,
    );

    final employerLoan = _sum(noveltyRows, {'prestamo_empresa'}, zero);
    _apply(
      applications,
      kind: PayrollDeductionKind.employerLoan,
      requested: employerLoan,
      limit: _min(employerLoan, _positive(remaining - smmlv, zero)),
      reason:
          'CST art. 149 y guia MinJusticia: descuento autorizado sin afectar SMMLV.',
      remaining: () => remaining,
      updateRemaining: (value) => remaining = value,
    );

    _apply(
      applications,
      kind: PayrollDeductionKind.manualOther,
      requested: manualOtherDeductions,
      limit: _min(manualOtherDeductions, _positive(remaining - smmlv, zero)),
      reason: 'Deduccion manual autorizada; no se aplica si afecta SMMLV.',
      remaining: () => remaining,
      updateRemaining: (value) => remaining = value,
    );

    final total = applications.fold(zero, (sum, item) => sum + item.applied);
    final capped = applications.where((item) => item.capped).toList();
    final warning = capped.isEmpty
        ? null
        : 'Deducciones laborales limitadas por topes legales: '
              '${capped.map((item) => item.kind.name).join(', ')}';
    return PayrollDeductionResult(
      total: total,
      items: applications
          .where((item) => item.requested.minorUnits > 0)
          .toList(),
      warning: warning,
    );
  }

  static void _apply(
    List<PayrollDeductionApplication> applications, {
    required PayrollDeductionKind kind,
    required MoneyValue requested,
    required MoneyValue limit,
    required String reason,
    required MoneyValue Function() remaining,
    required void Function(MoneyValue value) updateRemaining,
  }) {
    if (requested.minorUnits <= 0) return;
    final cappedByRemaining = _min(limit, remaining());
    final applied = _positive(cappedByRemaining, requested - requested);
    updateRemaining(remaining() - applied);
    applications.add(
      PayrollDeductionApplication(
        kind: kind,
        requested: requested,
        applied: applied,
        reason: reason,
      ),
    );
  }

  static MoneyValue _sum(
    List<Map<String, Object?>> rows,
    Set<String> types,
    MoneyValue zero,
  ) {
    return rows
        .where((row) => types.contains(row['tipo_novedad']?.toString()))
        .map(
          (row) => MoneyValue.fromSql(
            row['valor'],
            currency: zero.currency,
            nullableAsZero: true,
          ),
        )
        .fold(zero, (sum, value) => sum + value);
  }

  static MoneyValue _min(MoneyValue a, MoneyValue b) => a <= b ? a : b;

  static MoneyValue _positive(MoneyValue value, MoneyValue zero) {
    return value.minorUnits <= 0 ? zero : value;
  }
}
