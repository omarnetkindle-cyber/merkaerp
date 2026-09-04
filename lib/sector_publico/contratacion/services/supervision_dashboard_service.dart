import 'package:sqflite/sqflite.dart';

class ContractSupervisionSummary {
  const ContractSupervisionSummary({required this.data});
  final Map<String, Object?> data;

  String get id => data['id']?.toString() ?? '';
  String get number => data['numero_contrato']?.toString() ?? 'Sin número';
  String get object => data['objeto_contrato']?.toString() ?? '';
  String get contractor => data['contratista_nombre']?.toString() ?? '';
  String get supervisor => data['supervisor_nombre']?.toString() ?? 'Sin asignar';
  String get status => data['estado']?.toString() ?? '';
  double get physicalProgress => (data['porcentaje_ejecucion'] as num?)?.toDouble() ?? 0;
  int get contractValue => (data['valor_contrato'] as num?)?.toInt() ?? 0;
  int get rpValue => (data['valor_rp_total'] as num?)?.toInt() ?? 0;
  int get obligated => (data['valor_obligado_total'] as num?)?.toInt() ?? 0;
  int get paid => (data['valor_pagado_total'] as num?)?.toInt() ?? 0;
  int get openAlerts => (data['alertas_abiertas'] as num?)?.toInt() ?? 0;
  String? get lastReport => data['ultimo_informe']?.toString();
  String? get endDate => data['fecha_fin_ejecucion']?.toString();
  String? get nextPolicyExpiry => data['proxima_poliza']?.toString();

  double get financialProgress => contractValue <= 0 ? 0 : (paid / contractValue * 100).clamp(0, 999).toDouble();
}

class SupervisionDashboardService {
  const SupervisionDashboardService(this.db);
  final Database db;

  Future<List<ContractSupervisionSummary>> contracts({
    required String entityId,
    required String userId,
    required bool canSeeAll,
  }) async {
    final filter = canSeeAll
        ? 'c.entidad_id = ?'
        : 'c.entidad_id = ? AND (c.supervisor_id = ? OR c.interventor_id = ?)';
    final args = canSeeAll ? <Object?>[entityId] : <Object?>[entityId, userId, userId];
    final rows = await db.rawQuery('''
      SELECT c.*,
        COALESCE((SELECT SUM(r.valor_rp) FROM rps r WHERE r.contrato_id = c.id), 0) AS valor_rp_total,
        COALESCE((SELECT SUM(o.valor_obligacion) FROM obligaciones o WHERE o.contrato_id = c.id), 0) AS valor_obligado_total,
        COALESCE((SELECT SUM(p.valor_pago)
          FROM pagos p JOIN obligaciones o2 ON o2.id = p.obligacion_id
          WHERE o2.contrato_id = c.id AND LOWER(p.estado) IN ('pagado','ejecutado','aprobado')), 0) AS valor_pagado_total,
        (SELECT MAX(i.fecha_informe) FROM informes_supervision i WHERE i.contrato_id = c.id) AS ultimo_informe,
        (SELECT COUNT(*) FROM alertas_incumplimiento a
          WHERE a.contrato_id = c.id AND LOWER(a.estado) NOT IN ('resuelto','cerrado')) AS alertas_abiertas,
        (SELECT MIN(pz.fecha_fin_vigencia) FROM polizas pz
          WHERE pz.contrato_id = c.id AND LOWER(pz.estado) NOT IN ('cancelada','vencida')) AS proxima_poliza
      FROM contratos c
      WHERE $filter
      ORDER BY c.fecha_fin_ejecucion ASC, c.numero_contrato ASC
    ''', args);
    return rows.map((e) => ContractSupervisionSummary(data: e)).toList();
  }

  Future<Map<String, Object?>> traceability(String contractId) async {
    Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) => db.rawQuery(sql, args);
    final contract = await q('SELECT * FROM contratos WHERE id = ? LIMIT 1', [contractId]);
    if (contract.isEmpty) throw StateError('Contrato no encontrado.');
    final c = contract.first;
    final processId = c['proceso_id']?.toString();
    final cdpId = c['cdp_id']?.toString();
    final rps = await q('SELECT * FROM rps WHERE contrato_id = ? ORDER BY fecha_expedicion', [contractId]);
    final obligations = await q('SELECT * FROM obligaciones WHERE contrato_id = ? ORDER BY fecha_reconocimiento', [contractId]);
    final payments = await q('''SELECT p.*, o.contrato_id FROM pagos p
      JOIN obligaciones o ON o.id = p.obligacion_id WHERE o.contrato_id = ? ORDER BY p.fecha_programacion''', [contractId]);
    final companyRows = await q('SELECT company_id FROM entidades_territoriales WHERE id = ? LIMIT 1', [c['entidad_id']]);
    final companyId = companyRows.isEmpty ? null : companyRows.first['company_id'];
    List<Map<String, Object?>> documents = const [];
    if (companyId != null) {
      documents = await q('''SELECT l.*, e.code AS expediente_code, e.title AS expediente_title,
        d.title AS document_title, r.number AS radicado_number
        FROM gd_entity_links l
        LEFT JOIN gd_expedientes e ON e.id = l.expediente_id AND e.company_id = l.company_id
        LEFT JOIN gd_documents d ON d.id = l.document_id AND d.company_id = l.company_id
        LEFT JOIN gd_radicados r ON r.id = l.radicado_id AND r.company_id = l.company_id
        WHERE l.company_id = ? AND l.entity_id = ? AND l.entity_type IN ('contrato','contrato_publico')
        ORDER BY l.created_at DESC''', [companyId, contractId]);
    }
    return {
      'contract': c,
      'process': processId == null ? const <Map<String, Object?>>[] : await q('SELECT * FROM procesos_contratacion WHERE id = ?', [processId]),
      'cdp': cdpId == null ? const <Map<String, Object?>>[] : await q('SELECT * FROM cdps WHERE id = ?', [cdpId]),
      'rps': rps,
      'obligations': obligations,
      'payments': payments,
      'policies': await q('SELECT * FROM polizas WHERE contrato_id = ? ORDER BY fecha_fin_vigencia', [contractId]),
      'reports': await q('SELECT * FROM informes_supervision WHERE contrato_id = ? ORDER BY fecha_informe DESC', [contractId]),
      'alerts': await q('SELECT * FROM alertas_incumplimiento WHERE contrato_id = ? ORDER BY fecha_deteccion DESC', [contractId]),
      'liquidations': await q('SELECT * FROM actas_liquidacion WHERE contrato_id = ? ORDER BY fecha_liquidacion DESC', [contractId]),
      'documents': documents,
    };
  }
}
