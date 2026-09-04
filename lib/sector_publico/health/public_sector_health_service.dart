import '../../app_session.dart';
import '../../db_helper.dart';

/// Diagnóstico institucional de solo lectura para MerkaERP Público.
///
/// No reemplaza auditorías fiscales, contables ni archivísticas. Su objetivo es
/// detectar inconsistencias operativas evidentes antes de que se conviertan en
/// incidentes: cadena presupuestal rota, asientos descuadrados, pagos sin
/// contabilización, expedientes vencidos o garantías próximas a vencer.
class PublicSectorHealthService {
  PublicSectorHealthService._();

  static final PublicSectorHealthService instance = PublicSectorHealthService._();

  Future<PublicSectorHealthReport> audit() async {
    final db = await DatabaseHelper.instance.database;
    final entityId = AppSession.entidadId;
    final entityRows = await db.query(
      'entidades_territoriales',
      columns: ['company_id'],
      where: 'id = ?',
      whereArgs: [entityId],
      limit: 1,
    );
    final companyId = entityRows.isEmpty
        ? await DatabaseHelper.instance.obtenerEmpresaActivaId(db)
        : (entityRows.first['company_id'] as num?)?.toInt() ??
            await DatabaseHelper.instance.obtenerEmpresaActivaId(db);

    final checks = <PublicSectorHealthCheck>[];
    await _capture(checks, () => _budgetChain(db, entityId));
    await _capture(checks, () => _budgetReferences(db, entityId));
    await _capture(checks, () => _accountingBalance(db, entityId));
    await _capture(checks, () => _budgetAccountingBridge(db, entityId));
    await _capture(checks, () => _treasuryPac(db, entityId));
    await _capture(checks, () => _contractualRisk(db, entityId));
    await _capture(checks, () => _obligationSupport(db, entityId));
    await _capture(checks, () => _documentManagement(db, companyId));

    return PublicSectorHealthReport(
      entityId: entityId,
      generatedAt: DateTime.now(),
      checks: checks,
    );
  }

  Future<void> _capture(
    List<PublicSectorHealthCheck> target,
    Future<PublicSectorHealthCheck> Function() operation,
  ) async {
    try {
      target.add(await operation());
    } catch (error) {
      target.add(
        PublicSectorHealthCheck(
          key: 'diagnostic_unavailable_${target.length}',
          title: 'Control institucional no disponible',
          status: PublicSectorHealthStatus.warning,
          count: 1,
          detail: 'No fue posible ejecutar uno de los controles: $error',
          recommendation:
              'Actualice el esquema y vuelva a ejecutar el diagnóstico. El fallo de un control no invalida los demás.',
        ),
      );
    }
  }

  Future<PublicSectorHealthCheck> _budgetChain(dynamic db, String entityId) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS n
      FROM apropiaciones
      WHERE entidad_id = ? AND activo = 1 AND (
        valor_inicial < 0 OR valor_apropiado < 0 OR valor_cdp < 0 OR
        valor_rp < 0 OR valor_obligado < 0 OR valor_pagado < 0 OR
        valor_cdp > valor_apropiado OR valor_rp > valor_cdp OR
        valor_obligado > valor_rp OR valor_pagado > valor_obligado OR
        saldo_disponible < 0
      )
    ''', [entityId]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'budget_chain',
      title: 'Cadena presupuestal',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.blocking,
      count: count,
      detail: count == 0
          ? 'Apropiación ≥ CDP ≥ RP ≥ obligación ≥ pago, sin saldos negativos en las apropiaciones activas.'
          : '$count apropiaciones presentan valores que rompen la cadena presupuestal o dejan saldo negativo.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'Revise inmediatamente apropiaciones, CDP, RP, obligaciones y pagos antes de continuar ejecución.',
    );
  }

  Future<PublicSectorHealthCheck> _budgetReferences(dynamic db, String entityId) async {
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM cdps c LEFT JOIN apropiaciones a ON a.id = c.apropiacion_id
          WHERE c.entidad_id = ? AND a.id IS NULL) +
        (SELECT COUNT(*) FROM rps r LEFT JOIN cdps c ON c.id = r.cdp_id
          WHERE r.entidad_id = ? AND c.id IS NULL) +
        (SELECT COUNT(*) FROM obligaciones o LEFT JOIN rps r ON r.id = o.rp_id
          WHERE o.entidad_id = ? AND r.id IS NULL) +
        (SELECT COUNT(*) FROM pagos p LEFT JOIN obligaciones o ON o.id = p.obligacion_id
          WHERE p.entidad_id = ? AND o.id IS NULL) AS n
    ''', [entityId, entityId, entityId, entityId]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'budget_references',
      title: 'Integridad CDP / RP / obligación / pago',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.blocking,
      count: count,
      detail: count == 0
          ? 'No se detectaron documentos presupuestales huérfanos.'
          : '$count documentos tienen una referencia anterior inexistente.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'No elimine registros manualmente. Revise la trazabilidad y restaure/migre el documento de origen correspondiente.',
    );
  }

  Future<PublicSectorHealthCheck> _accountingBalance(dynamic db, String entityId) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM asientos_contables_sp a
      WHERE a.entidad_id = ? AND a.estado <> 'borrador' AND (
        a.total_debito <> a.total_credito OR
        a.total_debito <> COALESCE((SELECT SUM(d.debito) FROM detalles_asientos d WHERE d.asiento_id = a.id), 0) OR
        a.total_credito <> COALESCE((SELECT SUM(d.credito) FROM detalles_asientos d WHERE d.asiento_id = a.id), 0)
      )
    ''', [entityId]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'accounting_balance',
      title: 'Contabilidad NICSP balanceada',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.blocking,
      count: count,
      detail: count == 0
          ? 'Los asientos cerrados conservan partida doble y coinciden con sus líneas.'
          : '$count asientos cerrados presentan diferencia entre débitos, créditos o totales de cabecera.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'Ejecute revisión contable antes de emitir estados financieros o reportes oficiales.',
    );
  }

  Future<PublicSectorHealthCheck> _budgetAccountingBridge(dynamic db, String entityId) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS n
      FROM pagos p
      LEFT JOIN asientos_contables_sp a
        ON a.entidad_id = p.entidad_id
       AND a.tipo_documento_origen = 'PAGO'
       AND a.referencia_origen = p.id
      WHERE p.entidad_id = ? AND p.estado = 'pagado' AND a.id IS NULL
    ''', [entityId]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'budget_accounting_bridge',
      title: 'Presupuesto ↔ contabilidad',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.warning,
      count: count,
      detail: count == 0
          ? 'Los pagos ejecutados tienen asiento contable de origen identificable.'
          : '$count pagos marcados como pagados no tienen asiento contable PAGO asociado.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'Regularice la contabilización de los pagos antes de conciliar ejecución presupuestal y contabilidad.',
    );
  }

  Future<PublicSectorHealthCheck> _treasuryPac(dynamic db, String entityId) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM pac
      WHERE entidad_id = ? AND (
        valor_programado < 0 OR valor_ejecutado < 0 OR
        valor_ejecutado > valor_programado OR saldo_disponible < 0
      )
    ''', [entityId]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'treasury_pac',
      title: 'Tesorería / PAC',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.blocking,
      count: count,
      detail: count == 0
          ? 'No se detectó ejecución PAC superior al cupo programado ni saldos negativos.'
          : '$count registros PAC exceden el cupo o presentan valores/saldos negativos.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'Revise programación y ejecución de caja antes de aprobar nuevos pagos.',
    );
  }

  Future<PublicSectorHealthCheck> _contractualRisk(dynamic db, String entityId) async {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 30)).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM contratos
          WHERE entidad_id = ? AND estado NOT IN ('liquidado','cerrado','terminado','anulado')
          AND fecha_fin_ejecucion >= ? AND fecha_fin_ejecucion <= ?) +
        (SELECT COUNT(*) FROM polizas
          WHERE entidad_id = ? AND estado NOT IN ('cancelada','vencida','anulada')
          AND fecha_fin_vigencia >= ? AND fecha_fin_vigencia <= ?) +
        (SELECT COUNT(*) FROM alertas_incumplimiento
          WHERE entidad_id = ? AND estado NOT IN ('cerrada','resuelta','anulada')) AS n
    ''', [
      entityId, now.toIso8601String(), limit,
      entityId, now.toIso8601String(), limit,
      entityId,
    ]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'contractual_risk',
      title: 'Contratación y supervisión',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.warning,
      count: count,
      detail: count == 0
          ? 'No hay vencimientos a 30 días ni alertas de supervisión abiertas en los controles disponibles.'
          : '$count señales requieren atención: contratos/pólizas próximos a vencer o alertas de supervisión abiertas.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'Abra Contratación → Supervisión y priorice vencimientos, garantías y medidas correctivas.',
    );
  }

  Future<PublicSectorHealthCheck> _obligationSupport(dynamic db, String entityId) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS n FROM obligaciones
      WHERE entidad_id = ? AND estado NOT IN ('anulada','cancelada') AND (
        (factura_numero IS NULL OR TRIM(factura_numero) = '') AND
        (acta_recibo_numero IS NULL OR TRIM(acta_recibo_numero) = '')
      )
    ''', [entityId]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'obligation_support',
      title: 'Soportes de obligaciones',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.warning,
      count: count,
      detail: count == 0
          ? 'Las obligaciones activas tienen factura o acta de recibo registrada.'
          : '$count obligaciones activas no tienen factura ni acta de recibo registrada.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'Complete los soportes antes de aprobar/programar pagos. Vincule además los originales al expediente SGDEA.',
    );
  }

  Future<PublicSectorHealthCheck> _documentManagement(dynamic db, int companyId) async {
    final now = DateTime.now().toIso8601String();
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM gd_radicados
          WHERE company_id = ? AND due_at IS NOT NULL AND due_at < ?
          AND status NOT IN ('closed','archived','cancelled','cerrado','archivado','anulado')) +
        (SELECT COUNT(*) FROM gd_instruments
          WHERE company_id = ? AND status IN ('pending','draft','pendiente','borrador')) AS n
    ''', [companyId, now, companyId]);
    final count = _count(rows);
    return PublicSectorHealthCheck(
      key: 'document_management',
      title: 'Gestión documental / SGDEA',
      status: count == 0 ? PublicSectorHealthStatus.ok : PublicSectorHealthStatus.warning,
      count: count,
      detail: count == 0
          ? 'No hay radicados vencidos ni instrumentos archivísticos pendientes en los controles disponibles.'
          : '$count elementos requieren atención entre radicados vencidos e instrumentos pendientes/borrador.',
      recommendation: count == 0
          ? 'Sin acción requerida.'
          : 'Revise Gestión Documental, responsables, términos e instrumentos institucionales antes del cierre del período.',
    );
  }

  int _count(List<Map<String, Object?>> rows) =>
      rows.isEmpty ? 0 : (rows.first['n'] as num?)?.toInt() ?? 0;
}

enum PublicSectorHealthStatus { ok, warning, blocking }

class PublicSectorHealthCheck {
  const PublicSectorHealthCheck({
    required this.key,
    required this.title,
    required this.status,
    required this.count,
    required this.detail,
    required this.recommendation,
  });

  final String key;
  final String title;
  final PublicSectorHealthStatus status;
  final int count;
  final String detail;
  final String recommendation;
}

class PublicSectorHealthReport {
  const PublicSectorHealthReport({
    required this.entityId,
    required this.generatedAt,
    required this.checks,
  });

  final String entityId;
  final DateTime generatedAt;
  final List<PublicSectorHealthCheck> checks;

  int get blocking =>
      checks.where((item) => item.status == PublicSectorHealthStatus.blocking).length;
  int get warnings =>
      checks.where((item) => item.status == PublicSectorHealthStatus.warning).length;
  bool get ok => blocking == 0 && warnings == 0;
}
