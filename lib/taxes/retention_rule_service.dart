import 'package:sqflite/sqflite.dart';

import '../core/currency/currency.dart';
import '../core/currency/money_value.dart';
import 'retention_policy.dart';

class RetentionRule {
  const RetentionRule({
    this.id,
    required this.companyId,
    required this.code,
    required this.name,
    required this.ratePercent,
    required this.minimumBase,
    required this.appliesSales,
    required this.appliesPurchases,
    required this.active,
  });

  final int? id;
  final int companyId;
  final String code;
  final String name;
  final double ratePercent;
  final MoneyValue minimumBase;
  final bool appliesSales;
  final bool appliesPurchases;
  final bool active;

  MoneyValue calculate(MoneyValue base) {
    if (!active || base < minimumBase) {
      return MoneyValue(minorUnits: 0, currency: base.currency);
    }
    return base.percent(ratePercent.toString());
  }

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'company_id': companyId,
    'codigo': code,
    'nombre': name,
    'tasa': ratePercent,
    'base_minima': minimumBase.toSql(),
    'cuenta_contable': '2365',
    'aplica_ventas': appliesSales ? 1 : 0,
    'aplica_compras': appliesPurchases ? 1 : 0,
    'activo': active ? 1 : 0,
    'updated_at': DateTime.now().toIso8601String(),
  };

  static RetentionRule fromRow(
    Map<String, Object?> row, {
    required Currency currency,
  }) {
    return RetentionRule(
      id: (row['id'] as num?)?.toInt(),
      companyId: (row['company_id'] as num?)?.toInt() ?? 0,
      code: row['codigo']?.toString() ?? '',
      name: row['nombre']?.toString() ?? '',
      ratePercent: (row['tasa'] as num?)?.toDouble() ?? 0,
      minimumBase: MoneyValue.fromSql(
        row['base_minima'],
        currency: currency,
        nullableAsZero: true,
      ),
      appliesSales: (row['aplica_ventas'] as num?)?.toInt() == 1,
      appliesPurchases: (row['aplica_compras'] as num?)?.toInt() == 1,
      active: (row['activo'] as num?)?.toInt() != 0,
    );
  }
}

/// Editable company rules for Colombian withholding at source.
///
/// Sources for the default seed:
/// - Decreto 572/2025, DIAN: service minimum base becomes 2 UVT and other
///   income minimum base becomes 10 UVT.
/// - DIAN concepts 10721/2025 and 12329/2025: real-estate leases use 3.5%
///   and the 10 UVT threshold.
/// - DIAN concept 5224/2026: cleaning/security services 2%, movable leases 4%.
/// - DUR 1625/2016 article 1.2.4.2.5 / DIAN compilation: general financial
///   yields use 7%.
class RetentionRuleService {
  const RetentionRuleService();

  static List<RetentionRule> defaultRules({
    required int companyId,
    required Currency currency,
  }) {
    final uvt = RetentionPolicy.currentUvt(currency: currency);
    MoneyValue base(int uvtCount) => uvt * uvtCount;
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    RetentionRule rule(
      String code,
      String name,
      double rate,
      MoneyValue minimumBase,
    ) {
      return RetentionRule(
        companyId: companyId,
        code: code,
        name: name,
        ratePercent: rate,
        minimumBase: minimumBase,
        appliesSales: true,
        appliesPurchases: true,
        active: true,
      );
    }

    return [
      rule('RTFTE_COMPRAS_25', 'Compras generales declarante', 2.5, base(10)),
      rule(
        'RTFTE_COMPRAS_NO_DECLARANTE',
        'Compras generales no declarante',
        3.5,
        base(10),
      ),
      rule(
        'RTFTE_OTROS_DECLARANTE',
        'Otros ingresos declarante',
        2.5,
        base(10),
      ),
      rule(
        'RTFTE_OTROS_NO_DECLARANTE',
        'Otros ingresos no declarante',
        3.5,
        base(10),
      ),
      rule('RTFTE_SERVICIOS_DECLARANTE', 'Servicios declarante', 4, base(2)),
      rule(
        'RTFTE_SERVICIOS_NO_DECLARANTE',
        'Servicios no declarante',
        6,
        base(2),
      ),
      rule('RTFTE_HONORARIOS_DECLARANTE', 'Honorarios declarante', 10, zero),
      rule(
        'RTFTE_HONORARIOS_NO_DECLARANTE',
        'Honorarios no declarante',
        11,
        zero,
      ),
      rule(
        'RTFTE_ARRENDAMIENTOS_INMUEBLES',
        'Arrendamiento de bienes inmuebles',
        3.5,
        base(10),
      ),
      rule(
        'RTFTE_ARRENDAMIENTOS_MUEBLES',
        'Arrendamiento de bienes muebles',
        4,
        base(2),
      ),
      rule(
        'RTFTE_RENDIMIENTOS_FINANCIEROS',
        'Rendimientos financieros generales',
        7,
        zero,
      ),
      rule('RTFTE_ASEO_VIGILANCIA', 'Aseo y vigilancia', 2, base(2)),
    ];
  }

  Future<void> seedDefaults({
    required DatabaseExecutor db,
    required int companyId,
    required Currency currency,
  }) async {
    for (final rule in defaultRules(companyId: companyId, currency: currency)) {
      await db.insert(
        'reglas_retenciones_empresa',
        rule.toRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<List<RetentionRule>> listRules({
    required DatabaseExecutor db,
    required int companyId,
    required Currency currency,
  }) async {
    final rows = await db.query(
      'reglas_retenciones_empresa',
      where: 'company_id = ? AND codigo LIKE ?',
      whereArgs: [companyId, 'RTFTE_%'],
      orderBy: 'codigo ASC',
    );
    return rows
        .map((row) => RetentionRule.fromRow(row, currency: currency))
        .toList();
  }

  Future<void> updateRule({
    required DatabaseExecutor db,
    required RetentionRule rule,
  }) async {
    await db.update(
      'reglas_retenciones_empresa',
      rule.toRow()..remove('id'),
      where: 'id = ? AND company_id = ?',
      whereArgs: [rule.id, rule.companyId],
    );
  }

  Future<RetentionRule?> findApplicable({
    required DatabaseExecutor db,
    required int companyId,
    required Currency currency,
    required String concept,
    required bool isDeclarante,
    required bool saleFlow,
  }) async {
    await seedDefaults(db: db, companyId: companyId, currency: currency);
    final codes = codesFor(concept: concept, isDeclarante: isDeclarante);
    final placeholders = List.filled(codes.length, '?').join(',');
    final rows = await db.query(
      'reglas_retenciones_empresa',
      where:
          'company_id = ? AND activo = 1 AND ${saleFlow ? 'aplica_ventas' : 'aplica_compras'} = 1 '
          'AND codigo IN ($placeholders)',
      whereArgs: [companyId, ...codes],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RetentionRule.fromRow(rows.single, currency: currency);
  }

  static List<String> codesFor({
    required String concept,
    required bool isDeclarante,
  }) {
    final normalized = concept
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
    final suffix = isDeclarante ? 'DECLARANTE' : 'NO_DECLARANTE';
    if (normalized.contains('serv')) {
      return ['RTFTE_SERVICIOS_$suffix'];
    }
    if (normalized.contains('honor') || normalized.contains('comision')) {
      return ['RTFTE_HONORARIOS_$suffix'];
    }
    if (normalized.contains('arrend')) {
      if (normalized.contains('mueble') && !normalized.contains('inmueble')) {
        return ['RTFTE_ARRENDAMIENTOS_MUEBLES'];
      }
      return ['RTFTE_ARRENDAMIENTOS_INMUEBLES'];
    }
    if (normalized.contains('rend') || normalized.contains('financ')) {
      return ['RTFTE_RENDIMIENTOS_FINANCIEROS'];
    }
    if (normalized.contains('aseo') || normalized.contains('vigilancia')) {
      return ['RTFTE_ASEO_VIGILANCIA'];
    }
    if (normalized.contains('compra')) {
      return isDeclarante
          ? ['RTFTE_COMPRAS_25']
          : ['RTFTE_COMPRAS_NO_DECLARANTE'];
    }
    return ['RTFTE_OTROS_$suffix', 'RTFTE_COMPRAS_25'];
  }
}
