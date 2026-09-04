import '../../db_helper.dart';

class AuditRiskFinding {
  const AuditRiskFinding({
    required this.title,
    required this.detail,
    required this.severity,
    required this.date,
    required this.user,
    required this.source,
    this.entityId,
  });

  final String title;
  final String detail;
  final String severity; // high | medium | low
  final DateTime date;
  final String user;
  final String source;
  final int? entityId;

  int get score => severity == 'high' ? 3 : severity == 'medium' ? 2 : 1;
}

class AuditRiskSummary {
  const AuditRiskSummary({required this.findings, required this.generatedAt});
  final List<AuditRiskFinding> findings;
  final DateTime generatedAt;

  int get high => findings.where((e) => e.severity == 'high').length;
  int get medium => findings.where((e) => e.severity == 'medium').length;
  int get low => findings.where((e) => e.severity == 'low').length;
}

/// Detector explicable de operaciones de riesgo.
///
/// No declara fraude ni reemplaza una auditoría profesional. Prioriza eventos
/// que merecen revisión humana y conserva siempre el vínculo con la evidencia.
class AuditRiskService {
  AuditRiskService._();
  static final AuditRiskService instance = AuditRiskService._();

  Future<AuditRiskSummary> analyze({int days = 30}) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final since = DateTime.now().subtract(Duration(days: days));
    final events = await db.query(
      'auditoria_eventos',
      where: 'company_id = ? AND fecha >= ?',
      whereArgs: [companyId, since.toUtc().toIso8601String()],
      orderBy: 'fecha DESC',
      limit: 5000,
    );
    final findings = <AuditRiskFinding>[];
    final sensitiveByUserDay = <String, int>{};

    for (final row in events) {
      final action = row['accion']?.toString().toUpperCase() ?? '';
      final entity = row['entidad']?.toString() ?? 'general';
      final detail = row['detalle']?.toString() ?? '';
      final user = row['usuario']?.toString() ?? 'local';
      final date = DateTime.tryParse(row['fecha']?.toString() ?? '')?.toLocal();
      if (date == null) continue;
      final text = '$action $entity $detail'.toUpperCase();
      String? severity;
      String? title;

      if (_containsAny(text, const [
        'REAPERTURA', 'ELIMIN', 'ANUL', 'REVERS', 'PERMISO', 'ROL_',
        'CAMBIO_PRECIO', 'AJUSTE_INVENTARIO', 'STOCK_NEGATIVO',
      ])) {
        severity = 'high';
        title = 'Operación sensible: ${_friendly(action)}';
      } else if (_containsAny(text, const [
        'DESCUENTO', 'MODIFIC', 'UPDATE', 'CIERRE_CAJA', 'CAMBIO', 'DEVOLUC',
      ])) {
        severity = 'medium';
        title = 'Cambio que conviene revisar: ${_friendly(action)}';
      }

      if (severity != null) {
        findings.add(AuditRiskFinding(
          title: title!,
          detail: '$entity · ${detail.isEmpty ? 'Sin detalle adicional' : detail}',
          severity: severity,
          date: date,
          user: user,
          source: 'auditoria_eventos',
          entityId: (row['entidad_id'] as num?)?.toInt(),
        ));
        final key = '$user|${date.year}-${date.month}-${date.day}';
        sensitiveByUserDay[key] = (sensitiveByUserDay[key] ?? 0) + 1;
      }

      if (date.hour < 5 || date.hour >= 23) {
        findings.add(AuditRiskFinding(
          title: 'Operación en horario atípico',
          detail: '${_friendly(action)} en $entity a las ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}.',
          severity: 'medium',
          date: date,
          user: user,
          source: 'auditoria_eventos',
          entityId: (row['entidad_id'] as num?)?.toInt(),
        ));
      }
    }

    for (final entry in sensitiveByUserDay.entries) {
      if (entry.value < 8) continue;
      final parts = entry.key.split('|');
      findings.add(AuditRiskFinding(
        title: 'Concentración inusual de operaciones sensibles',
        detail: '${entry.value} eventos sensibles del mismo usuario en un día. Revisar el detalle antes de concluir cualquier irregularidad.',
        severity: 'high',
        date: DateTime.now(),
        user: parts.first,
        source: 'patrón de auditoría',
      ));
    }

    final closures = await db.rawQuery('''
      SELECT id, fecha, diferencia, observacion
      FROM cierres_caja
      WHERE company_id = ? AND ABS(COALESCE(diferencia, 0)) > 0
      ORDER BY fecha DESC LIMIT 100
    ''', [companyId]);
    for (final row in closures) {
      final date = DateTime.tryParse(row['fecha']?.toString() ?? '')?.toLocal() ?? DateTime.now();
      findings.add(AuditRiskFinding(
        title: 'Cierre de caja con diferencia',
        detail: 'El cierre #${row['id']} presenta diferencia registrada. ${row['observacion'] ?? ''}',
        severity: 'high',
        date: date,
        user: 'ver cierre/auditoría',
        source: 'cierres_caja',
        entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    final negativeStock = await db.query(
      'productos',
      columns: ['id', 'nombre', 'stock'],
      where: 'company_id = ? AND stock < 0',
      whereArgs: [companyId],
      limit: 100,
    );
    for (final row in negativeStock) {
      findings.add(AuditRiskFinding(
        title: 'Inventario negativo',
        detail: '${row['nombre']} registra stock ${row['stock']}. Revisar Kardex, anulaciones y ajustes.',
        severity: 'high',
        date: DateTime.now(),
        user: 'sistema',
        source: 'productos',
        entityId: (row['id'] as num?)?.toInt(),
      ));
    }

    findings.sort((a, b) {
      final severity = b.score.compareTo(a.score);
      return severity != 0 ? severity : b.date.compareTo(a.date);
    });
    return AuditRiskSummary(findings: findings, generatedAt: DateTime.now());
  }

  bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);

  String _friendly(String action) => action
      .toLowerCase()
      .replaceAll('_', ' ')
      .trim();
}
