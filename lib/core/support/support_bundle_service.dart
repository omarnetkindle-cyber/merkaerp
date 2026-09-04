import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app/app_version.dart';
import '../../core/backup/full_backup_service.dart';
import '../../core/database/data_health_service.dart';
import '../../core/logging/logging_service.dart';
import '../../data_migration/application/data_migration_service.dart';
import '../../db_helper.dart';
import '../../services/licencia_service.dart';
import '../../licensing/domain/product_family.dart';

class SupportBundleResult {
  const SupportBundleResult({
    required this.file,
    required this.sha256,
    required this.generatedAt,
  });

  final File file;
  final String sha256;
  final DateTime generatedAt;
}

/// Genera un paquete de diagnóstico apto para soporte sin extraer datos
/// comerciales, documentos ni secretos de integraciones.
class SupportBundleService {
  SupportBundleService._();
  static final SupportBundleService instance = SupportBundleService._();

  static final RegExp _sensitiveKey = RegExp(
    r'(password|passwd|secret|token|authorization|cookie|api[_-]?key|client[_-]?secret|private[_-]?key|pin|credential|certificate|certificado|firma|hmac)',
    caseSensitive: false,
  );

  Future<Map<String, Object?>> snapshot() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final license = await LicenciaService.instance.obtenerLicencia();
    final generatedAt = DateTime.now().toUtc();

    Map<String, Object?> health;
    try {
      health = (await DataHealthService().audit()).toMap();
    } catch (error) {
      health = {'available': false, 'error': _sanitizeText(error.toString())};
    }

    final quickCheck = await _quickCheck(db);
    final migration = await _migrationSummary();
    final backups = await _backupSummary();
    final documents = await _documentRepositorySummary();
    final logs = LoggingService.instance
        .getRecentLogs(count: 100)
        .map((entry) => <String, Object?>{
              'level': entry.levelString,
              'module': entry.module == null ? null : _sanitizeText(entry.module!),
              'timestamp': entry.timestamp.toUtc().toIso8601String(),
              'message': _sanitizeText(entry.message),
              'stack_trace': entry.stackTrace == null ? null : _sanitizeText(entry.stackTrace!),
            })
        .toList();

    return <String, Object?>{
      'format': 'MERKAERP_SUPPORT_1',
      'generated_at': generatedAt.toIso8601String(),
      'app': {
        'version': AppVersion.display,
        'schema_version': DatabaseHelper.schemaVersion,
        'release_mode': const bool.fromEnvironment('dart.vm.product'),
        'platform': Platform.operatingSystem,
        'platform_version': _sanitizeText(Platform.operatingSystemVersion),
      },
      'license': {
        'product_family': license?.productFamily.storageValue ?? 'unknown',
        'configured': license != null,
      },
      'scope': {
        'company_id': companyId,
      },
      'database': {
        'quick_check': quickCheck,
        'user_version': Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')),
      },
      'data_health': health,
      'backups': backups,
      'document_repository': documents,
      'migrations': migration,
      'logs': logs,
      'privacy': {
        'business_rows_included': false,
        'documents_included': false,
        'credentials_included': false,
        'note': 'El paquete contiene metadatos técnicos y logs sanitizados, no bases de datos ni archivos de negocio.',
      },
    };
  }

  Future<SupportBundleResult> exportBundle() async {
    final generatedAt = DateTime.now().toUtc();
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'soporte'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = generatedAt.toIso8601String().replaceAll(':', '').replaceAll('.', '');
    final file = File(p.join(dir.path, 'merkaerp_support_$stamp.json'));
    final payload = const JsonEncoder.withIndent('  ').convert(await snapshot());
    await file.writeAsString(payload, flush: true);
    final digest = (await crypto.sha256.bind(file.openRead()).first).toString();
    await File('${file.path}.sha256').writeAsString('$digest  ${p.basename(file.path)}\n', flush: true);
    return SupportBundleResult(file: file, sha256: digest, generatedAt: generatedAt);
  }

  Future<Map<String, Object?>> _quickCheck(Database db) async {
    try {
      final rows = await db.rawQuery('PRAGMA quick_check');
      final values = rows.expand((row) => row.values).map((value) => value?.toString() ?? '').toList();
      final ok = values.isNotEmpty && values.every((value) => value.toLowerCase() == 'ok');
      return {'ok': ok, 'result': values.take(20).toList()};
    } catch (error) {
      return {'ok': false, 'error': _sanitizeText(error.toString())};
    }
  }

  Future<Map<String, Object?>> _migrationSummary() async {
    try {
      final jobs = await DataMigrationService.instance.history();
      return {
        'jobs': jobs.length,
        'recent': jobs.take(20).map((job) => {
          'id': job.id,
          'source': p.basename(job.sourceName),
          'family': job.productFamily,
          'status': job.status,
          'started_at': job.startedAt.toIso8601String(),
          'completed_at': job.completedAt?.toIso8601String(),
          'rolled_back_at': job.rolledBackAt?.toIso8601String(),
          'summary': _redactMap(job.summary),
        }).toList(),
      };
    } catch (error) {
      return {'available': false, 'error': _sanitizeText(error.toString())};
    }
  }

  Future<Map<String, Object?>> _backupSummary() async {
    try {
      final backups = await FullBackupService.instance.listBackups();
      final recent = <Map<String, Object?>>[];
      for (final file in backups.take(10)) {
        final stat = await file.stat();
        recent.add({
          'file': p.basename(file.path),
          'bytes': stat.size,
          'modified_at': stat.modified.toUtc().toIso8601String(),
        });
      }
      return {'count': backups.length, 'recent': recent};
    } catch (error) {
      return {'available': false, 'error': _sanitizeText(error.toString())};
    }
  }

  Future<Map<String, Object?>> _documentRepositorySummary() async {
    try {
      final root = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(root.path, 'gestion_documental'));
      if (!await dir.exists()) return {'files': 0, 'bytes': 0};
      var files = 0;
      var bytes = 0;
      await for (final entry in dir.list(recursive: true, followLinks: false)) {
        if (entry is File) {
          files++;
          bytes += await entry.length();
        }
      }
      return {'files': files, 'bytes': bytes};
    } catch (error) {
      return {'available': false, 'error': _sanitizeText(error.toString())};
    }
  }

  Map<String, Object?> _redactMap(Map<String, Object?> input) {
    final output = <String, Object?>{};
    for (final entry in input.entries) {
      if (_sensitiveKey.hasMatch(entry.key)) {
        output[entry.key] = '<redacted>';
        continue;
      }
      output[entry.key] = _redactValue(entry.value);
    }
    return output;
  }

  Object? _redactValue(Object? value) {
    if (value is Map) {
      return _redactMap(Map<String, Object?>.from(value));
    }
    if (value is Iterable) return value.map(_redactValue).toList();
    if (value is String) return _sanitizeText(value);
    return value;
  }

  String _sanitizeText(String value) {
    var result = value;
    result = result.replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/]+=*', caseSensitive: false), 'Bearer <redacted>');
    result = result.replaceAll(RegExp(r'(password|secret|token|api[_-]?key|client[_-]?secret|pin)\s*[:=]\s*[^\s,;]+', caseSensitive: false), r'$1=<redacted>');
    result = result.replaceAll(RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false), '<email>');
    result = result.replaceAll(RegExp(r'C:\\Users\\[^\\/\s]+', caseSensitive: false), r'C:\Users\<user>');
    result = result.replaceAll(RegExp(r'/home/[^/\s]+'), '/home/<user>');
    result = result.replaceAll(RegExp(r'([?&](?:access_token|token|api_key|apikey|key|secret)=)[^&\s]+', caseSensitive: false), r'$1<redacted>');
    return result.length > 4000 ? '${result.substring(0, 4000)}…' : result;
  }
}
