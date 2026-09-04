import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/app/app_version.dart';
import '../db_helper.dart';
import '../licensing/domain/product_family.dart';
import '../services/licencia_service.dart';
import 'agent_contract.dart';
import 'agent_data_sanitizer.dart';

final class AgentDiagnosticRequestException implements Exception {
  const AgentDiagnosticRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Diagnósticos remotos estrictamente de lectura y con un catálogo cerrado.
///
/// Los parámetros sólo seleccionan checks conocidos. Nunca se interpretan
/// consultas SQL, comandos de sistema, rutas ni nombres de tabla remotos.
final class AgentDiagnosticsService {
  AgentDiagnosticsService({
    Future<Database> Function()? databaseProvider,
    Future<LicenciaInfo?> Function()? licenseProvider,
    Future<LicenseOperationalState?> Function()? operationalStateProvider,
    Future<List<File>> Function()? backupProvider,
    DateTime Function()? clock,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _licenseProvider =
           licenseProvider ??
           (() => LicenciaService.instance.obtenerLicencia()),
       _operationalStateProvider =
           operationalStateProvider ??
           (() => LicenciaService.instance.obtenerEstadoOperativo()),
       _backupProvider = backupProvider ?? _productionBackups,
       _clock = clock ?? DateTime.now;

  static final AgentDiagnosticsService instance = AgentDiagnosticsService();

  static const Set<String> supportedChecks = {
    'database',
    'migrations',
    'agent_queues',
    'sync',
    'license',
    'backup',
    'storage',
    'runtime',
  };

  static const Set<String> _essentialTables = {
    'app_config',
    'empresas',
    'agent_state',
    'processed_command_ids',
    'pending_ack',
    'pending_telemetry',
    'pending_errors',
    'download_jobs',
  };

  final Future<Database> Function() _databaseProvider;
  final Future<LicenciaInfo?> Function() _licenseProvider;
  final Future<LicenseOperationalState?> Function() _operationalStateProvider;
  final Future<List<File>> Function() _backupProvider;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> runDiagnostics(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'checks', 'request_id'});
    final checks = _parseChecks(params['checks']);
    return _execute(checks, mode: 'requested');
  }

  Future<Map<String, dynamic>> collectDiagnostics(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'checks', 'request_id'});
    final checks = _parseChecks(params['checks']);
    return _execute(checks, mode: 'sanitized_collection');
  }

  Future<Map<String, dynamic>> verifyDatabase(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'request_id'});
    return _execute(const ['database'], mode: 'database_verification');
  }

  List<String> _parseChecks(dynamic raw) {
    if (raw == null) return supportedChecks.toList(growable: false);
    if (raw is! List || raw.isEmpty) {
      throw const AgentDiagnosticRequestException(
        'INVALID_DIAGNOSTIC_CHECKS',
        'checks debe ser una lista no vacía de diagnósticos permitidos',
      );
    }
    final requested = raw.map((value) => value.toString()).toSet();
    final unsupported = requested.difference(supportedChecks);
    if (unsupported.isNotEmpty) {
      throw AgentDiagnosticRequestException(
        'UNSUPPORTED_DIAGNOSTIC_CHECK',
        'Diagnóstico no permitido: ${unsupported.first}',
      );
    }
    return requested.toList(growable: false);
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentDiagnosticRequestException(
        'UNSUPPORTED_DIAGNOSTIC_PARAMETER',
        'Parámetro de diagnóstico no permitido: ${unsupported.first}',
      );
    }
  }

  Future<Map<String, dynamic>> _execute(
    List<String> requested, {
    required String mode,
  }) async {
    final checks = <Map<String, dynamic>>[];
    for (final id in requested) {
      checks.add(await _safeCheck(id));
    }
    final statuses = checks.map((check) => check['status']).toSet();
    final overall = statuses.contains('ERROR')
        ? 'ERROR'
        : statuses.contains('WARNING')
        ? 'WARNING'
        : 'OK';
    return {
      'format': 'MERKAERP_AGENT_DIAGNOSTICS_1',
      'mode': mode,
      'generated_at': _clock().toUtc().toIso8601String(),
      'overall_status': overall,
      'checks': checks,
      'privacy': const {
        'sanitized': true,
        'business_rows_included': false,
        'documents_included': false,
        'credentials_included': false,
        'database_file_included': false,
      },
    };
  }

  Future<Map<String, dynamic>> _safeCheck(String id) async {
    try {
      return switch (id) {
        'database' => await _databaseCheck(),
        'migrations' => await _migrationCheck(),
        'agent_queues' => await _agentQueuesCheck(),
        'sync' => await _syncCheck(),
        'license' => await _licenseCheck(),
        'backup' => await _backupCheck(),
        'storage' => await _storageCheck(),
        'runtime' => _runtimeCheck(),
        _ => throw StateError('Check local no registrado'),
      };
    } catch (error) {
      return _check(id, 'ERROR', 'No fue posible completar el diagnóstico', {
        'error_code': 'DIAGNOSTIC_CHECK_FAILED',
        'error': AgentDataSanitizer.sanitizeText(error.toString()),
      });
    }
  }

  Future<Map<String, dynamic>> _databaseCheck() async {
    final db = await _databaseProvider();
    final quickRows = await db.rawQuery('PRAGMA quick_check(20)');
    final quickValues = quickRows
        .expand((row) => row.values)
        .map((value) => value?.toString() ?? '')
        .take(20)
        .toList(growable: false);
    final quickOk =
        quickValues.isNotEmpty &&
        quickValues.every((value) => value.toLowerCase() == 'ok');
    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tables = tableRows
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    final missing = _essentialTables.difference(tables).toList()..sort();
    final objectCounts = await db.rawQuery('''
      SELECT type, COUNT(*) AS total
      FROM sqlite_master
      WHERE type IN ('table', 'index', 'trigger', 'view')
      GROUP BY type
    ''');
    final counts = <String, int>{};
    for (final row in objectCounts) {
      counts[row['type']?.toString() ?? 'unknown'] =
          (row['total'] as num?)?.toInt() ?? 0;
    }
    final hasError = !quickOk || foreignKeys.isNotEmpty || missing.isNotEmpty;
    return _check(
      'database',
      hasError ? 'ERROR' : 'OK',
      hasError
          ? 'La base de datos requiere revisión'
          : 'Integridad SQLite verificada',
      {
        'engine': 'sqlite',
        'quick_check': quickOk ? 'ok' : 'failed',
        'quick_check_details': quickOk ? const <String>[] : quickValues,
        'foreign_key_violations': foreignKeys.length,
        'missing_essential_tables': missing,
        'objects': counts,
      },
    );
  }

  Future<Map<String, dynamic>> _migrationCheck() async {
    final db = await _databaseProvider();
    final current =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
    final expected = DatabaseHelper.schemaVersion;
    final pending = current < expected ? expected - current : 0;
    final status = current == expected
        ? 'OK'
        : current < expected
        ? 'WARNING'
        : 'ERROR';
    return _check(
      'migrations',
      status,
      status == 'OK'
          ? 'Esquema actualizado'
          : 'La versión del esquema no coincide con la aplicación',
      {
        'current_schema_version': current,
        'expected_schema_version': expected,
        'pending_migrations': pending,
      },
    );
  }

  Future<Map<String, dynamic>> _agentQueuesCheck() async {
    final db = await _databaseProvider();
    final counts = <String, int>{};
    for (final table in const [
      'pending_ack',
      'pending_telemetry',
      'pending_errors',
      'download_jobs',
    ]) {
      counts[table] = await _safeTableCount(db, table);
    }
    final warning = counts.values.any((value) => value > 100);
    return _check(
      'agent_queues',
      warning ? 'WARNING' : 'OK',
      warning ? 'Hay colas técnicas acumuladas' : 'Colas del Agent disponibles',
      counts,
    );
  }

  Future<Map<String, dynamic>> _syncCheck() async {
    final db = await _databaseProvider();
    if (!await _tableExists(db, 'sync_outbox')) {
      return _check(
        'sync',
        'WARNING',
        'Motor de sincronización no configurado',
        const {'configured': false, 'pending': 0, 'failed': 0},
      );
    }
    final pendingRows = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed
      FROM sync_outbox
    ''');
    final row = pendingRows.first;
    final pending = (row['pending'] as num?)?.toInt() ?? 0;
    final failed = (row['failed'] as num?)?.toInt() ?? 0;
    return _check(
      'sync',
      failed > 0 ? 'WARNING' : 'OK',
      failed > 0
          ? 'La sincronización tiene elementos fallidos'
          : 'Cola de sincronización disponible',
      {'configured': true, 'pending': pending, 'failed': failed},
    );
  }

  Future<Map<String, dynamic>> _licenseCheck() async {
    final license = await _licenseProvider();
    final operational = await _operationalStateProvider();
    if (license == null) {
      return _check(
        'license',
        'ERROR',
        'No hay licencia local configurada',
        const {'configured': false},
      );
    }
    final now = _clock().toUtc();
    final expired =
        license.tipoLicencia != TipoLicencia.perpetua &&
        now.isAfter(license.fechaExpiracion.toUtc());
    final locallyActive =
        license.estado == EstadoLicencia.activa ||
        license.estado == EstadoLicencia.trial;
    final blocked =
        !locallyActive ||
        expired ||
        operational == LicenseOperationalState.onlineDenied ||
        operational == LicenseOperationalState.invalidLocalToken ||
        operational == LicenseOperationalState.graceExpired;
    return _check(
      'license',
      blocked ? 'ERROR' : 'OK',
      blocked
          ? 'La licencia no permite operación normal'
          : 'Licencia operativa',
      {
        'configured': true,
        'status': license.estado.name,
        'type': license.tipoLicencia.name,
        'product_family': license.productFamily.storageValue,
        'expires_at': license.fechaExpiracion.toUtc().toIso8601String(),
        'operational_state': operational?.name ?? 'not_checked',
      },
    );
  }

  Future<Map<String, dynamic>> _backupCheck() async {
    final backups = await _backupProvider();
    DateTime? latest;
    if (backups.isNotEmpty) latest = (await backups.first.stat()).modified;
    final stale = latest == null || _clock().difference(latest).inHours > 48;
    return _check(
      'backup',
      stale ? 'WARNING' : 'OK',
      latest == null
          ? 'No se encontraron respaldos'
          : stale
          ? 'El respaldo más reciente supera 48 horas'
          : 'Existe un respaldo reciente',
      {
        'count': backups.length,
        'last_backup_at': latest?.toUtc().toIso8601String(),
        'max_age_hours': 48,
      },
    );
  }

  Future<Map<String, dynamic>> _storageCheck() async {
    final db = await _databaseProvider();
    final rows = await db.rawQuery('PRAGMA database_list');
    final main = rows.where((row) => row['name'] == 'main').firstOrNull;
    final rawPath = main?['file']?.toString() ?? '';
    if (rawPath.isEmpty) {
      return _check(
        'storage',
        'WARNING',
        'Tamaño de almacenamiento no disponible',
        const {'database_size_bytes': null},
      );
    }
    final file = File(rawPath);
    final bytes = await file.length();
    return _check('storage', 'OK', 'Almacenamiento local accesible', {
      'database_size_bytes': bytes,
    });
  }

  Map<String, dynamic> _runtimeCheck() {
    final architecture =
        Platform.environment['PROCESSOR_ARCHITEW6432'] ??
        Platform.environment['PROCESSOR_ARCHITECTURE'] ??
        'unknown';
    return _check('runtime', 'OK', 'Runtime identificado', {
      'app_version': AppVersion.version,
      'app_build_number': AppVersion.build,
      'agent_version': MerkaAgentContract.agentVersion,
      'os': Platform.operatingSystem,
      'architecture': architecture,
    });
  }

  Future<int> _safeTableCount(Database db, String table) async {
    if (!await _tableExists(db, table)) return -1;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM "$table"');
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  Map<String, dynamic> _check(
    String id,
    String status,
    String summary,
    Map<String, dynamic> details,
  ) {
    return {
      'id': id,
      'status': status,
      'summary': AgentDataSanitizer.sanitizeText(summary),
      'details': AgentDataSanitizer.sanitize(details),
    };
  }

  static Future<List<File>> _productionBackups() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'respaldos'));
    if (!await directory.exists()) return const [];
    final files = await directory
        .list(followLinks: false)
        .where((entry) => entry is File && entry.path.endsWith('.mkbackup'))
        .cast<File>()
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }
}
