import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';

import '../../app_session.dart';
import '../../db_helper.dart';
import '../../sector_publico/security/roles_permisos_service.dart';
import 'evidence_capsule.dart';

const _publicMoneyConversions = <Map<String, dynamic>>[
  {
    'storage': 'SQLite INTEGER',
    'unit': 'minor_units',
    'scale': 2,
    'currency': 'COP',
    'conversion': 'minor_units / 100 only for human display',
  },
];

/// Reusable request understood by UI cards and other result surfaces.
class EvidenceRequest {
  const EvidenceRequest({
    required this.domain,
    required this.recordType,
    required this.recordId,
  });

  final String domain;
  final String recordType;
  final String recordId;
}

/// Builds exact, local evidence for high-value records.
class EvidenceCapsuleService {
  EvidenceCapsuleService({
    DatabaseExecutor? executor,
    DateTime Function()? clock,
  }) : _executor = executor,
       _clock = clock ?? DateTime.now;

  final DatabaseExecutor? _executor;
  final DateTime Function() _clock;

  Future<DatabaseExecutor> _database() async {
    return _executor ?? await DatabaseHelper.instance.database;
  }

  Future<EvidenceCapsule> generate(EvidenceRequest request) async {
    final db = await _database();
    switch (request.recordType) {
      case 'asiento_contable_comercial':
        return _generateCommercialAccounting(db, request);
      case 'asiento_contable_publico':
        return _generatePublicAccounting(db, request);
      case 'nomina_liquidacion_comercial':
        return _generateCommercialPayroll(db, request);
      case 'liquidacion_nomina_publica':
        return _generatePublicPayroll(db, request);
      case 'apropiacion':
      case 'cdp':
      case 'rp':
        return _generateBudget(db, request);
      default:
        throw ArgumentError(
          'Tipo de evidencia no soportado: ${request.recordType}',
        );
    }
  }

  Future<String?> exportJson(EvidenceRequest request) async {
    final capsule = await generate(request);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Exportar cápsula de evidencia',
      fileName:
          'evidencia_${request.domain}_${request.recordType}_${request.recordId}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null || path.trim().isEmpty) return null;
    await File(path).writeAsString(capsule.toJson());
    return path;
  }

  Future<EvidenceCapsule> _generateCommercialAccounting(
    DatabaseExecutor db,
    EvidenceRequest request,
  ) async {
    final header = await _requiredRow(
      db,
      'asientos_contables',
      request.recordId,
    );
    final lines = await db.query(
      'asiento_lineas',
      where: 'asiento_id = ?',
      whereArgs: [request.recordId],
      orderBy: 'id',
    );
    final debit = _sum(lines, 'debito');
    final credit = _sum(lines, 'credito');
    return _createCapsule(
      db: db,
      request: request,
      sourceRecords: [
        _source('asientos_contables', header),
        ...lines.map((row) => _source('asiento_lineas', row)),
      ],
      calculations: [
        {
          'formula': 'SUM(asiento_lineas.debito) = SUM(asiento_lineas.credito)',
          'debit_minor_units': debit,
          'credit_minor_units': credit,
          'difference_minor_units': debit - credit,
          'sql_guard': 'v76 partida doble SQLite',
        },
      ],
      result: {
        'status': header['estado'],
        'balanced': debit == credit,
        'debit_minor_units': debit,
        'credit_minor_units': credit,
      },
      requiredPermissions: const ['crearAsientoContable'],
      auditReferences: [request.recordId],
    );
  }

  Future<EvidenceCapsule> _generatePublicAccounting(
    DatabaseExecutor db,
    EvidenceRequest request,
  ) async {
    final header = await _requiredRow(
      db,
      'asientos_contables_sp',
      request.recordId,
    );
    final lines = await db.query(
      'detalles_asientos',
      where: 'asiento_id = ?',
      whereArgs: [request.recordId],
      orderBy: 'id',
    );
    final debit = _sum(lines, 'debito');
    final credit = _sum(lines, 'credito');
    return _createCapsule(
      db: db,
      request: request,
      sourceRecords: [
        _source('asientos_contables_sp', header),
        ...lines.map((row) => _source('detalles_asientos', row)),
      ],
      calculations: [
        {
          'formula':
              'SUM(detalles_asientos.debito) = SUM(detalles_asientos.credito)',
          'debit_minor_units': debit,
          'credit_minor_units': credit,
          'difference_minor_units': debit - credit,
          'sql_guard': 'v76 partida doble SQLite',
        },
      ],
      result: {
        'status': header['estado'],
        'balanced': debit == credit,
        'debit_minor_units': debit,
        'credit_minor_units': credit,
        'entity_id': header['entidad_id'],
      },
      requiredPermissions: const ['crearAsientoContable'],
      monetaryConversions: _publicMoneyConversions,
      entityId: header['entidad_id']?.toString(),
      auditReferences: [request.recordId],
    );
  }

  Future<EvidenceCapsule> _generateCommercialPayroll(
    DatabaseExecutor db,
    EvidenceRequest request,
  ) async {
    final row = await _requiredRow(
      db,
      'nomina_liquidaciones',
      request.recordId,
    );
    final hrm = await _approvedHrmLeaves(
      db,
      employeeId: _asInt(row['empleado_id']),
      companyId: _asInt(row['company_id']),
      period: row['periodo']?.toString(),
    );
    return _createCapsule(
      db: db,
      request: request,
      sourceRecords: [
        _source('nomina_liquidaciones', row),
        ...hrm.map((leave) => _source('hrm_leaves', leave)),
      ],
      calculations: [
        {
          'formula': 'novedades_hrm y ausencias aprobadas del periodo',
          'novedades_hrm': _decode(row['novedades_hrm']),
          'approved_leave_days': _sum(hrm, 'length_days'),
        },
      ],
      result: {
        'estado': row['estado'],
        'neto_pagar_minor_units': row['neto_pagar'],
        'total_devengado_minor_units': row['total_devengado'],
        'approved_leave_days': _sum(hrm, 'length_days'),
      },
      requiredPermissions: const ['liquidarNomina'],
      auditReferences: [request.recordId],
    );
  }

  Future<EvidenceCapsule> _generatePublicPayroll(
    DatabaseExecutor db,
    EvidenceRequest request,
  ) async {
    final row = await _requiredRow(
      db,
      'liquidaciones_nomina',
      request.recordId,
    );
    final employee = await _requiredRow(
      db,
      'empleados_sp',
      row['empleado_id']?.toString() ?? '',
    );
    final hrmId = _asInt(employee['hrm_employee_id']);
    final hrm = hrmId == null
        ? const <Map<String, dynamic>>[]
        : await _approvedHrmLeaves(
            db,
            employeeId: hrmId,
            companyId: null,
            period: row['periodo']?.toString(),
          );
    return _createCapsule(
      db: db,
      request: request,
      sourceRecords: [
        _source('liquidaciones_nomina', row),
        _source('empleados_sp', employee),
        ...hrm.map((leave) => _source('hrm_leaves', leave)),
      ],
      calculations: [
        {
          'formula': 'ausencias HRM por empleados_sp.hrm_employee_id',
          'hrm_employee_id': hrmId,
          'approved_leave_days': _sum(hrm, 'length_days'),
        },
      ],
      result: {
        'estado': row['estado'],
        'neto_pagar_minor_units': row['neto_pagar'],
        'approved_leave_days': _sum(hrm, 'length_days'),
        'hrm_data_available': hrmId != null,
      },
      requiredPermissions: const ['liquidarNomina'],
      monetaryConversions: _publicMoneyConversions,
      entityId: row['entidad_id']?.toString(),
      auditReferences: [request.recordId],
    );
  }

  Future<EvidenceCapsule> _generateBudget(
    DatabaseExecutor db,
    EvidenceRequest request,
  ) async {
    Map<String, dynamic>? appropriation;
    Map<String, dynamic>? cdp;
    Map<String, dynamic>? rp;
    switch (request.recordType) {
      case 'apropiacion':
        appropriation = await _requiredRow(
          db,
          'apropiaciones',
          request.recordId,
        );
      case 'cdp':
        cdp = await _requiredRow(db, 'cdps', request.recordId);
        appropriation = await _requiredRow(
          db,
          'apropiaciones',
          cdp['apropiacion_id']?.toString() ?? '',
        );
      case 'rp':
        rp = await _requiredRow(db, 'rps', request.recordId);
        cdp = await _requiredRow(db, 'cdps', rp['cdp_id']?.toString() ?? '');
        appropriation = await _requiredRow(
          db,
          'apropiaciones',
          cdp['apropiacion_id']?.toString() ?? '',
        );
    }
    final appropriationRow = appropriation;
    if (appropriationRow == null) {
      throw StateError('La cadena presupuestal no tiene apropiacion.');
    }
    final sources = <EvidenceSourceRecord>[
      _source('apropiaciones', appropriationRow),
      if (cdp != null) _source('cdps', cdp),
      if (rp != null) _source('rps', rp),
    ];
    final cdpValue = _asInt(cdp?['valor_cdp']) ?? 0;
    final rpValue = _asInt(rp?['valor_rp']) ?? 0;
    return _createCapsule(
      db: db,
      request: request,
      sourceRecords: sources,
      calculations: [
        {
          'formula':
              'apropiacion -> CDP -> RP; cada eslabon referencia al anterior',
          'apropiacion_minor_units': appropriationRow['valor_apropiado'],
          'cdp_minor_units': cdpValue,
          'rp_minor_units': rpValue,
          'cdp_within_appropriation':
              cdpValue <= (_asInt(appropriationRow['valor_apropiado']) ?? 0),
          'rp_within_cdp': rpValue <= cdpValue,
        },
      ],
      result: {
        'chain_complete':
            (request.recordType == 'apropiacion' || cdp != null) &&
            (request.recordType != 'rp' || rp != null),
        'appropriation_id': appropriationRow['id'],
        'cdp_id': cdp?['id'],
        'rp_id': rp?['id'],
        'saldo_disponible_minor_units': appropriationRow['saldo_disponible'],
      },
      requiredPermissions: const ['consultarTodo'],
      monetaryConversions: _publicMoneyConversions,
      entityId: appropriationRow['entidad_id']?.toString(),
      auditReferences: [
        appropriationRow['id'],
        if (cdp != null) cdp['id'],
        if (rp != null) rp['id'],
      ],
    );
  }

  Future<EvidenceCapsule> _createCapsule({
    required DatabaseExecutor db,
    required EvidenceRequest request,
    required List<EvidenceSourceRecord> sourceRecords,
    required List<Map<String, dynamic>> calculations,
    required Map<String, dynamic> result,
    required List<String> requiredPermissions,
    required List<String> auditReferences,
    List<Map<String, dynamic>> monetaryConversions = const [
      {
        'storage': 'SQLite INTEGER',
        'unit': 'minor_units',
        'scale': 'resolved Currency.decimalPlaces',
        'currency': 'resolved company currency',
        'conversion': 'MoneyValue.toSql(); major units only for human display',
      },
    ],
    String? entityId,
  }) async {
    final audit = await _auditRows(
      db,
      references: auditReferences,
      entityId: entityId,
    );
    final actor = _actorSnapshot(requiredPermissions);
    return EvidenceCapsule.create(
      generatedAt: _clock(),
      domain: request.domain,
      recordType: request.recordType,
      recordId: request.recordId,
      sourceRecords: sourceRecords,
      calculations: calculations,
      monetaryConversions: monetaryConversions,
      actor: actor,
      schemaVersion: DatabaseHelper.schemaVersion,
      auditRecords: audit,
      result: result,
    );
  }

  Future<Map<String, dynamic>> _requiredRow(
    DatabaseExecutor db,
    String table,
    String id,
  ) async {
    if (id.trim().isEmpty) {
      throw StateError('Falta el identificador de $table.');
    }
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('No existe $table con id $id.');
    return Map<String, dynamic>.from(rows.single);
  }

  Future<List<Map<String, dynamic>>> _approvedHrmLeaves(
    DatabaseExecutor db, {
    required int? employeeId,
    required int? companyId,
    required String? period,
  }) async {
    if (employeeId == null || period == null || period.length < 7) return [];
    final month = DateTime.tryParse('${period.substring(0, 7)}-01');
    if (month == null) return [];
    final next = DateTime(month.year, month.month + 1, 1);
    final args = <dynamic>[
      employeeId,
      month.toIso8601String(),
      next.toIso8601String(),
    ];
    final companyClause = companyId == null ? '' : ' AND l.company_id = ?';
    if (companyId != null) args.add(companyId);
    return db.rawQuery('''
      SELECT l.*, t.code AS leave_code, t.name AS leave_name,
             t.requires_entitlement
      FROM hrm_leaves l
      JOIN hrm_leave_types t ON t.id = l.leave_type_id
      WHERE l.employee_id = ? AND l.status = 'aprobado'
        AND l.date >= ? AND l.date < ?$companyClause
      ORDER BY l.date, l.id
    ''', args);
  }

  Future<List<Map<String, dynamic>>> _auditRows(
    DatabaseExecutor db, {
    required List<String> references,
    String? entityId,
  }) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['auditoria_registros'],
    );
    if (tables.isEmpty || references.isEmpty) return [];
    final placeholders = List.filled(references.length, '?').join(', ');
    final args = <dynamic>[...references];
    var where = 'referencia_id IN ($placeholders)';
    if (entityId != null) {
      where += ' AND entidad_id = ?';
      args.add(entityId);
    }
    return db.rawQuery(
      'SELECT * FROM auditoria_registros WHERE $where ORDER BY fecha_hora, id',
      args,
    );
  }

  EvidenceSourceRecord _source(String table, Map<String, dynamic> row) {
    return EvidenceSourceRecord(
      table: table,
      id: row['id']?.toString() ?? '',
      values: Map<String, dynamic>.from(row),
    );
  }

  Map<String, dynamic> _actorSnapshot(List<String> requiredPermissions) {
    return {
      'user_id': AppSession.usuarioId,
      'user_name': AppSession.nombre,
      'role': AppSession.rol,
      'permissions': requiredPermissions.map((name) {
        final matches = Permiso.values.where(
          (permission) => permission.name == name,
        );
        final permission = matches.isEmpty ? null : matches.first;
        return {
          'permission': name,
          'granted_at_generation': permission == null
              ? null
              : AppSession.puedeEjecutarPermiso(permission),
        };
      }).toList(),
    };
  }

  int _sum(List<Map<String, dynamic>> rows, String key) {
    return rows.fold<int>(0, (total, row) => total + (_asInt(row[key]) ?? 0));
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  dynamic _decode(Object? value) {
    if (value is! String || value.trim().isEmpty) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
}
