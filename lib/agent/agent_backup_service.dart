import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/backup/full_backup_service.dart';

final class AgentBackupRequestException implements Exception {
  const AgentBackupRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentBackupExecutionException implements Exception {
  const AgentBackupExecutionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentBackupService {
  AgentBackupService({
    Future<File> Function(String label)? backupCreator,
    Future<FullBackupVerification> Function(File backup)? backupVerifier,
    Future<List<File>> Function()? backupLister,
    Future<FullBackupDrillResult> Function(File backup)? restoreDrill,
    Future<void> Function(File backup)? backupRestorer,
    DateTime Function()? clock,
  }) : _backupCreator =
           backupCreator ??
           ((label) =>
               FullBackupService.instance.createFullBackup(label: label)),
       _backupVerifier =
           backupVerifier ??
           ((backup) => FullBackupService.instance.verify(backup)),
       _backupLister =
           backupLister ?? (() => FullBackupService.instance.listBackups()),
       _restoreDrill =
           restoreDrill ??
           ((backup) => FullBackupService.instance.drillRestore(backup)),
       _backupRestorer =
           backupRestorer ??
           ((backup) => FullBackupService.instance.restore(backup)),
       _clock = clock ?? DateTime.now;

  static final AgentBackupService instance = AgentBackupService();

  final Future<File> Function(String label) _backupCreator;
  final Future<FullBackupVerification> Function(File backup) _backupVerifier;
  final Future<List<File>> Function() _backupLister;
  final Future<FullBackupDrillResult> Function(File backup) _restoreDrill;
  final Future<void> Function(File backup) _backupRestorer;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> forceBackup(Map<String, dynamic> params) async {
    _validateParameterKeys(params, const {'label', 'request_id', 'verify'});
    final label = _normalizeLabel(params['label']);
    final verify = _parseOptionalBool(params['verify']) ?? true;

    final backup = await _backupCreator(label);
    if (!await backup.exists()) {
      throw const AgentBackupExecutionException(
        'BACKUP_FILE_NOT_CREATED',
        'El respaldo no fue creado por el servicio local',
      );
    }

    FullBackupVerification? verification;
    if (verify) {
      verification = await _backupVerifier(backup);
      if (!verification.ok) {
        throw AgentBackupExecutionException(
          'BACKUP_VERIFICATION_FAILED',
          verification.message,
        );
      }
    }

    final sizeBytes = await backup.length();
    final checksum = await sha256.bind(backup.openRead()).first;
    return {
      'format': 'MERKAERP_AGENT_BACKUP_1',
      'backup_ref': p.basename(backup.path),
      'checksum': checksum.toString(),
      'checksum_algorithm': 'SHA-256',
      'size_bytes': sizeBytes,
      'size_mb': double.parse((sizeBytes / (1024 * 1024)).toStringAsFixed(3)),
      'verified': verification?.ok ?? false,
      'entries': verification?.entries,
      'document_files': verification?.documentFiles,
      'database_version': verification?.databaseVersion,
      'created_at': _clock().toUtc().toIso8601String(),
      'local_path_disclosed': false,
    };
  }

  Future<Map<String, dynamic>> restoreBackup(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {
      'backup_ref',
      'checksum',
      'request_id',
    });
    final backupRef = _normalizeBackupRef(params['backup_ref']);
    final expectedChecksum = _normalizeChecksum(params['checksum']);
    final backup = await _findBackup(backupRef);

    final actualChecksum = await sha256.bind(backup.openRead()).first;
    if (actualChecksum.toString() != expectedChecksum) {
      throw const AgentBackupExecutionException(
        'BACKUP_CHECKSUM_MISMATCH',
        'El checksum SHA-256 del respaldo no coincide',
      );
    }

    final verification = await _backupVerifier(backup);
    if (!verification.ok) {
      throw AgentBackupExecutionException(
        'BACKUP_VERIFICATION_FAILED',
        verification.message,
      );
    }

    final drill = await _restoreDrill(backup);
    if (!drill.ok) {
      throw AgentBackupExecutionException(
        'RESTORE_DRILL_FAILED',
        drill.message,
      );
    }

    final snapshot = await _backupCreator('cc_pre_restore');
    if (!await snapshot.exists()) {
      throw const AgentBackupExecutionException(
        'PRE_RESTORE_BACKUP_NOT_CREATED',
        'No fue posible crear el respaldo previo a restauración',
      );
    }
    final snapshotChecksum = await sha256.bind(snapshot.openRead()).first;

    await _backupRestorer(backup);

    return {
      'format': 'MERKAERP_AGENT_RESTORE_1',
      'backup_ref': backupRef,
      'checksum': expectedChecksum,
      'checksum_algorithm': 'SHA-256',
      'pre_restore_backup_ref': p.basename(snapshot.path),
      'pre_restore_checksum': snapshotChecksum.toString(),
      'restored_at': _clock().toUtc().toIso8601String(),
      'verified': true,
      'restore_drill_ok': true,
      'database_version': verification.databaseVersion ?? drill.databaseVersion,
      'tables_checked': drill.tables,
      'document_references': drill.documentReferences,
      'missing_document_references': drill.missingDocumentReferences,
      'local_path_disclosed': false,
    };
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentBackupRequestException(
        'UNSUPPORTED_BACKUP_PARAMETER',
        'Parametro de respaldo no permitido: ${unsupported.first}',
      );
    }
  }

  String _normalizeLabel(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return 'cc_forzado';
    if (value.length > 40 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const AgentBackupRequestException(
        'INVALID_BACKUP_LABEL',
        'label solo permite letras, numeros, guion y guion bajo',
      );
    }
    return value;
  }

  Future<File> _findBackup(String backupRef) async {
    final backups = await _backupLister();
    for (final backup in backups) {
      if (p.basename(backup.path) == backupRef) {
        if (!await backup.exists()) break;
        return backup;
      }
    }
    throw const AgentBackupExecutionException(
      'BACKUP_NOT_FOUND',
      'El respaldo solicitado no existe en el catálogo local',
    );
  }

  String _normalizeBackupRef(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null ||
        value.isEmpty ||
        value.length > 160 ||
        value.contains('/') ||
        value.contains('\\') ||
        p.basename(value) != value ||
        !value.endsWith('.mkbackup')) {
      throw const AgentBackupRequestException(
        'INVALID_BACKUP_REF',
        'backup_ref debe ser un nombre local de respaldo .mkbackup',
      );
    }
    return value;
  }

  String _normalizeChecksum(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const AgentBackupRequestException(
        'INVALID_BACKUP_CHECKSUM',
        'checksum debe ser SHA-256 hexadecimal de 64 caracteres',
      );
    }
    return value;
  }

  bool? _parseOptionalBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) {
      if (value == 1) return true;
      if (value == 0) return false;
    }
    final text = value.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    throw const AgentBackupRequestException(
      'INVALID_BACKUP_VERIFY_VALUE',
      'verify debe ser booleano',
    );
  }
}
