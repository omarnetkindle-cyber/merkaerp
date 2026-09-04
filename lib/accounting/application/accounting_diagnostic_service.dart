import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';

class AccountingDiagnosticIssue {
  const AccountingDiagnosticIssue({
    required this.title,
    required this.detail,
    required this.severity,
    required this.kind,
    this.entityId,
  });
  final String title;
  final String detail;
  final String severity;
  final String kind;
  final int? entityId;
}

class AccountingDiagnosticReport {
  const AccountingDiagnosticReport({required this.issues, required this.generatedAt});
  final List<AccountingDiagnosticIssue> issues;
  final DateTime generatedAt;
  int get critical => issues.where((e) => e.severity == 'critical').length;
  int get warnings => issues.where((e) => e.severity == 'warning').length;
}

class AccountingDiagnosticService {
  AccountingDiagnosticService._();
  static final AccountingDiagnosticService instance = AccountingDiagnosticService._();

  Future<AccountingDiagnosticReport> run() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final currency = await MoneyCurrencyResolver.resolve(db, companyId: companyId);
    final issues = <AccountingDiagnosticIssue>[];

    final unbalanced = await db.rawQuery('''
      SELECT a.id, a.fecha, a.concepto,
             COALESCE(SUM(l.debito),0) debito, COALESCE(SUM(l.credito),0) credito
      FROM asientos_contables a
      LEFT JOIN asiento_lineas l ON l.asiento_id = a.id AND l.company_id = a.company_id
      WHERE a.company_id = ? AND a.estado != 'anulado'
      GROUP BY a.id
      HAVING COALESCE(SUM(l.debito),0) != COALESCE(SUM(l.credito),0)
      ORDER BY a.fecha DESC LIMIT 200
    ''', [companyId]);
    for (final row in unbalanced) {
      final d = MoneyValue.fromSql(row['debito'], currency: currency, nullableAsZero: true);
      final c = MoneyValue.fromSql(row['credito'], currency: currency, nullableAsZero: true);
      issues.add(AccountingDiagnosticIssue(
        title: 'Asiento descuadrado #${row['id']}',
        detail: '${row['concepto']} · Débitos ${d.format()} · Créditos ${c.format()}.',
        severity: 'critical', kind: 'unbalanced_entry', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final orphanLines = await db.rawQuery('''
      SELECT l.id, l.asiento_id, l.cuenta_id FROM asiento_lineas l
      LEFT JOIN cuentas_contables c ON c.id = l.cuenta_id AND c.company_id = l.company_id
      WHERE l.company_id = ? AND c.id IS NULL LIMIT 200
    ''', [companyId]);
    for (final row in orphanLines) {
      issues.add(AccountingDiagnosticIssue(
        title: 'Movimiento con cuenta inexistente',
        detail: 'Línea ${row['id']} del asiento ${row['asiento_id']} apunta a la cuenta ${row['cuenta_id']}.',
        severity: 'critical', kind: 'orphan_account', entityId: (row['asiento_id'] as num?)?.toInt(),
      ));
    }

    final noThirdParty = await db.rawQuery('''
      SELECT l.id, l.asiento_id, c.codigo, c.nombre
      FROM asiento_lineas l INNER JOIN cuentas_contables c ON c.id = l.cuenta_id
      WHERE l.company_id = ? AND (l.tercero IS NULL OR TRIM(l.tercero) = '')
        AND (c.codigo LIKE '13%' OR c.codigo LIKE '22%')
      LIMIT 200
    ''', [companyId]);
    for (final row in noThirdParty) {
      issues.add(AccountingDiagnosticIssue(
        title: 'Movimiento de cartera/proveedor sin tercero',
        detail: 'Asiento ${row['asiento_id']} · ${row['codigo']} ${row['nombre']}.',
        severity: 'warning', kind: 'missing_third_party', entityId: (row['asiento_id'] as num?)?.toInt(),
      ));
    }

    final salesMissing = await db.rawQuery('''
      SELECT v.id, v.fecha, v.total FROM ventas v
      LEFT JOIN asientos_contables a
        ON a.company_id = v.company_id AND a.referencia = ('VENTA-' || v.id)
      WHERE v.company_id = ? AND LOWER(COALESCE(v.estado,'emitida')) != 'anulada' AND a.id IS NULL
      ORDER BY v.fecha DESC LIMIT 200
    ''', [companyId]);
    for (final row in salesMissing) {
      final total = MoneyValue.fromSql(row['total'], currency: currency, nullableAsZero: true);
      issues.add(AccountingDiagnosticIssue(
        title: 'Venta sin asiento contable #${row['id']}',
        detail: 'Venta por ${total.format()} del ${row['fecha']}.',
        severity: 'critical', kind: 'sale_without_posting', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final purchasesMissing = await db.rawQuery('''
      SELECT c.id, c.fecha, c.total FROM compras c
      LEFT JOIN asientos_contables a
        ON a.company_id = c.company_id AND a.referencia = ('COMPRA-' || c.id)
      WHERE c.company_id = ? AND LOWER(COALESCE(c.estado,'pagada')) != 'anulada' AND a.id IS NULL
      ORDER BY c.fecha DESC LIMIT 200
    ''', [companyId]);
    for (final row in purchasesMissing) {
      final total = MoneyValue.fromSql(row['total'], currency: currency, nullableAsZero: true);
      issues.add(AccountingDiagnosticIssue(
        title: 'Compra sin asiento contable #${row['id']}',
        detail: 'Compra por ${total.format()} del ${row['fecha']}.',
        severity: 'critical', kind: 'purchase_without_posting', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final negativeStock = await db.query('productos',
      columns: ['id', 'nombre', 'stock'], where: 'company_id = ? AND stock < 0', whereArgs: [companyId]);
    for (final row in negativeStock) {
      issues.add(AccountingDiagnosticIssue(
        title: 'Inventario negativo que puede afectar costos',
        detail: '${row['nombre']} registra ${row['stock']} unidades. Conciliar Kardex y costo de ventas.',
        severity: 'warning', kind: 'negative_inventory', entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    issues.sort((a, b) {
      final sa = a.severity == 'critical' ? 2 : 1;
      final sb = b.severity == 'critical' ? 2 : 1;
      return sb.compareTo(sa);
    });
    return AccountingDiagnosticReport(issues: issues, generatedAt: DateTime.now());
  }
}
