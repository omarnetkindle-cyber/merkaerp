import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../db_helper.dart';

final class AgentBinaryRollbackService {
  AgentBinaryRollbackService._();

  static final AgentBinaryRollbackService instance =
      AgentBinaryRollbackService._();

  static const String pendingRollbackConfigKey = 'cc_pending_binary_rollback';

  Future<List<File>> listRollbackInstallers() async {
    final dir = await _updatesDirectory();
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && _isSafeInstallerRef(p.basename(entity.path))) {
        files.add(entity);
      }
    }
    return files;
  }

  Future<Map<String, dynamic>> scheduleRollback(
    Map<String, dynamic> plan,
  ) async {
    if (!Platform.isWindows) {
      throw StateError(
        'El rollback binario automático está disponible únicamente en Windows.',
      );
    }

    final installerPath = plan['installer_path']?.toString();
    if (installerPath == null || installerPath.trim().isEmpty) {
      throw StateError('Rollback binario sin instalador local verificado.');
    }
    final installer = File(installerPath);
    final installerRef = p.basename(installer.path);
    if (!_isSafeInstallerRef(installerRef) || !await installer.exists()) {
      throw StateError('Instalador local de rollback no disponible.');
    }

    final expectedChecksum = plan['installer_sha256']?.toString().toLowerCase();
    final actualChecksum = await sha256.bind(installer.openRead()).first;
    if (expectedChecksum == null ||
        expectedChecksum != actualChecksum.toString().toLowerCase()) {
      throw StateError('El instalador de rollback cambió desde su validación.');
    }

    final updates = await _updatesDirectory();
    if (!await updates.exists()) {
      await updates.create(recursive: true);
    }
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final planRef =
        'rollback_plan_${createdAt.replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}.json';
    final planFile = File(p.join(updates.path, planRef));
    final payload = {
      'format': 'MERKAERP_BINARY_ROLLBACK_PLAN_1',
      'target_version': plan['target_version'],
      'from_version': plan['from_version'],
      'installer_ref': installerRef,
      'installer_sha256': expectedChecksum,
      'data_backup_ref': plan['data_backup_ref'],
      'data_backup_sha256': plan['data_backup_sha256'],
      'created_at': createdAt,
      'state': 'pending',
    };
    await planFile.writeAsString(jsonEncode(payload), flush: true);

    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': pendingRollbackConfigKey,
      'valor': jsonEncode({...payload, 'plan_ref': planRef}),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_ROLLBACK_BINARIO_PROGRAMADO',
      entidad: 'control_center',
      detalle:
          'target=${plan["target_version"]}; from=${plan["from_version"]}; installer=$installerRef; plan=$planRef',
    );

    await Process.start(
      installer.path,
      ['/MERKAERP_ROLLBACK=1', '/MERKAERP_PLAN=${planFile.path}'],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    return {
      'format': 'MERKAERP_BINARY_ROLLBACK_SCHEDULED_1',
      'target_version': plan['target_version'],
      'from_version': plan['from_version'],
      'installer_ref': installerRef,
      'installer_sha256': expectedChecksum,
      'plan_ref': planRef,
      'scheduled': true,
      'local_path_disclosed': false,
    };
  }

  Future<Directory> _updatesDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(p.join(root.path, 'merkaerp', 'updates'));
  }

  bool _isSafeInstallerRef(String value) {
    return p.basename(value) == value &&
        value.length <= 160 &&
        RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_.+-]*[.](exe|msix)$',
          caseSensitive: false,
        ).hasMatch(value);
  }
}
