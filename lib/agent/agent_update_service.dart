import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/app/app_version.dart';
import '../core/backup/full_backup_service.dart';
import '../db_helper.dart';
import '../services/licencia_service.dart';
import '../services/license_validation_service.dart';
import '../services/update_service.dart';
import 'agent_binary_rollback_service.dart';
import 'agent_managed_config_service.dart';
import 'agent_repair_service.dart';

final class AgentUpdateRequestException implements Exception {
  const AgentUpdateRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentUpdateExecutionException implements Exception {
  const AgentUpdateExecutionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentUpdateService {
  AgentUpdateService({
    Future<InfoVersion?> Function()? updateChecker,
    Future<String> Function(InfoVersion info)? updateDownloader,
    Future<void> Function(String installerPath)? updateApplier,
    Future<List<File>> Function()? rollbackBackupLister,
    Future<FullBackupVerification> Function(File backup)?
    rollbackBackupVerifier,
    Future<FullBackupDrillResult> Function(File backup)? rollbackRestoreDrill,
    Future<void> Function(File backup)? rollbackRestorer,
    Future<Map<String, dynamic>?> Function(
      String token,
      String? installationId,
    )?
    rollbackPublisherTokenValidator,
    Future<List<File>> Function()? rollbackInstallerLister,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> plan)?
    binaryRollbackScheduler,
    Future<Map<String, dynamic>?> Function(
      String token,
      String? installationId,
    )?
    publisherTokenValidator,
    Future<File> Function(String label)? hotfixBackupCreator,
    Future<FullBackupVerification> Function(File backup)? hotfixBackupVerifier,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params)?
    safeRepairRunner,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params)?
    configurationApplier,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params)?
    featureFlagsApplier,
    DateTime Function()? clock,
  }) : _updateChecker =
           updateChecker ??
           (() => UpdateService.instance.buscarActualizacion()),
       _updateDownloader =
           updateDownloader ??
           ((info) => UpdateService.instance.descargarActualizacion(info)),
       _updateApplier =
           updateApplier ??
           ((installerPath) =>
               UpdateService.instance.aplicarActualizacion(installerPath)),
       _rollbackBackupLister =
           rollbackBackupLister ??
           (() => FullBackupService.instance.listBackups()),
       _rollbackBackupVerifier =
           rollbackBackupVerifier ??
           ((backup) => FullBackupService.instance.verify(backup)),
       _rollbackRestoreDrill =
           rollbackRestoreDrill ??
           ((backup) => FullBackupService.instance.drillRestore(backup)),
       _rollbackRestorer =
           rollbackRestorer ??
           ((backup) => FullBackupService.instance.restore(backup)),
       _rollbackPublisherTokenValidator =
           rollbackPublisherTokenValidator ??
           ((token, installationId) async =>
               LicenseValidationService().validatePublisherToken(
                 token,
                 kind: 'merkaerp-rollback',
                 installationId: installationId,
               )),
       _rollbackInstallerLister =
           rollbackInstallerLister ??
           (() => AgentBinaryRollbackService.instance.listRollbackInstallers()),
       _binaryRollbackScheduler =
           binaryRollbackScheduler ??
           ((plan) =>
               AgentBinaryRollbackService.instance.scheduleRollback(plan)),
       _publisherTokenValidator =
           publisherTokenValidator ??
           ((token, installationId) async =>
               LicenseValidationService().validatePublisherToken(
                 token,
                 kind: 'merkaerp-hotfix',
                 installationId: installationId,
               )),
       _hotfixBackupCreator =
           hotfixBackupCreator ??
           ((label) =>
               FullBackupService.instance.createFullBackup(label: label)),
       _hotfixBackupVerifier =
           hotfixBackupVerifier ??
           ((backup) => FullBackupService.instance.verify(backup)),
       _safeRepairRunner =
           safeRepairRunner ??
           ((params) => AgentRepairService.instance.runSafeRepair(params)),
       _configurationApplier =
           configurationApplier ??
           ((params) =>
               AgentManagedConfigService.instance.applyConfiguration(params)),
       _featureFlagsApplier =
           featureFlagsApplier ??
           ((params) =>
               AgentManagedConfigService.instance.applyFeatureFlags(params)),
       _clock = clock ?? DateTime.now;

  static final AgentUpdateService instance = AgentUpdateService();

  final Future<InfoVersion?> Function() _updateChecker;
  final Future<String> Function(InfoVersion info) _updateDownloader;
  final Future<void> Function(String installerPath) _updateApplier;
  final Future<List<File>> Function() _rollbackBackupLister;
  final Future<FullBackupVerification> Function(File backup)
  _rollbackBackupVerifier;
  final Future<FullBackupDrillResult> Function(File backup)
  _rollbackRestoreDrill;
  final Future<void> Function(File backup) _rollbackRestorer;
  final Future<Map<String, dynamic>?> Function(
    String token,
    String? installationId,
  )
  _rollbackPublisherTokenValidator;
  final Future<List<File>> Function() _rollbackInstallerLister;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> plan)
  _binaryRollbackScheduler;
  final Future<Map<String, dynamic>?> Function(
    String token,
    String? installationId,
  )
  _publisherTokenValidator;
  final Future<File> Function(String label) _hotfixBackupCreator;
  final Future<FullBackupVerification> Function(File backup)
  _hotfixBackupVerifier;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> params)
  _safeRepairRunner;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> params)
  _configurationApplier;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> params)
  _featureFlagsApplier;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> forceUpdate(Map<String, dynamic> params) async {
    _validateParameterKeys(params, const {
      'target_version',
      'version',
      'canal',
      'channel',
      'request_id',
    });
    final requestedVersion = _normalizeVersion(
      params['target_version'] ?? params['version'],
    );
    final requestedChannel = _normalizeChannel(
      params['canal'] ?? params['channel'],
    );

    final info = await _updateChecker();
    if (info == null) {
      throw const AgentUpdateExecutionException(
        'UPDATE_NOT_AVAILABLE',
        'No hay actualización firmada disponible para esta instalación',
      );
    }
    _validateInfo(info);
    if (requestedVersion != null && info.version != requestedVersion) {
      throw AgentUpdateExecutionException(
        'UPDATE_TARGET_NOT_AVAILABLE',
        'La versión disponible no coincide con $requestedVersion',
      );
    }
    if (requestedChannel != null && info.canal.name != requestedChannel) {
      throw AgentUpdateExecutionException(
        'UPDATE_CHANNEL_NOT_AVAILABLE',
        'El canal disponible no coincide con $requestedChannel',
      );
    }

    final installerPath = await _updateDownloader(info);
    final installer = File(installerPath);
    if (!await installer.exists()) {
      throw const AgentUpdateExecutionException(
        'UPDATE_INSTALLER_NOT_FOUND',
        'El instalador descargado no quedó disponible',
      );
    }

    await _updateApplier(installerPath);

    return {
      'format': 'MERKAERP_AGENT_UPDATE_1',
      'installed_version': info.version,
      'channel': info.canal.name,
      'mandatory': info.obligatoria,
      'download_ref': p.basename(installerPath),
      'checksum': info.sha256.toLowerCase(),
      'checksum_algorithm': 'SHA-256',
      'manifest_verified': true,
      'applied': true,
      'completed_at': _clock().toUtc().toIso8601String(),
      'local_path_disclosed': false,
    };
  }

  Future<Map<String, dynamic>> rollbackUpdate(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {
      'target_version',
      'version',
      'backup_ref',
      'checksum',
      'manifest_token',
      'request_id',
    });
    final targetVersion = _normalizeRequiredVersion(
      params['target_version'] ?? params['version'],
      fieldName: 'target_version',
    );
    final requestedBackupRef = params.containsKey('backup_ref')
        ? _normalizeBackupRef(params['backup_ref'])
        : null;
    final requestedChecksum = params.containsKey('checksum')
        ? _normalizeChecksum(params['checksum'])
        : null;
    final manifestToken = params.containsKey('manifest_token')
        ? _normalizeManifestToken(params['manifest_token'])
        : null;

    final snapshot = await _loadRollbackSnapshot();
    if (snapshot == null) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_SNAPSHOT_UNAVAILABLE',
        'No existe snapshot pre-update local verificable para rollback',
      );
    }
    if (snapshot.fromVersion != targetVersion) {
      throw AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_TARGET_UNAVAILABLE',
        'El snapshot local no corresponde a $targetVersion',
      );
    }
    if (requestedBackupRef != null &&
        requestedBackupRef != snapshot.backupRef) {
      throw const AgentUpdateRequestException(
        'UPDATE_ROLLBACK_SNAPSHOT_MISMATCH',
        'backup_ref no coincide con el snapshot pre-update registrado',
      );
    }
    if (requestedChecksum != null &&
        requestedChecksum.toLowerCase() != snapshot.backupSha256) {
      throw const AgentUpdateRequestException(
        'UPDATE_ROLLBACK_CHECKSUM_MISMATCH',
        'checksum no coincide con el snapshot pre-update registrado',
      );
    }

    final binaryRollback = manifestToken == null
        ? null
        : await _loadBinaryRollbackPackage(
            manifestToken,
            targetVersion,
            snapshot,
          );

    final backup = await _findRollbackBackup(snapshot.backupRef);
    final actualChecksum = await sha256.bind(backup.openRead()).first;
    if (actualChecksum.toString().toLowerCase() != snapshot.backupSha256) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_CHECKSUM_MISMATCH',
        'El respaldo local de rollback cambió desde su registro',
      );
    }

    final verification = await _rollbackBackupVerifier(backup);
    if (!verification.ok) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_BACKUP_INVALID',
        'El snapshot pre-update no superó la verificación integral',
      );
    }
    final drill = await _rollbackRestoreDrill(backup);
    if (!drill.ok) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_DRILL_FAILED',
        'El simulacro de rollback no superó las validaciones',
      );
    }

    await _rollbackRestorer(backup);
    final binaryResult = binaryRollback == null
        ? null
        : await _binaryRollbackScheduler({
            'target_version': binaryRollback.targetVersion,
            'from_version': binaryRollback.fromVersion,
            'installer_ref': binaryRollback.installerRef,
            'installer_path': binaryRollback.installer.path,
            'installer_sha256': binaryRollback.installerSha256,
            'data_backup_ref': snapshot.backupRef,
            'data_backup_sha256': snapshot.backupSha256,
          });

    return {
      'format': 'MERKAERP_AGENT_ROLLBACK_1',
      'restored_version': targetVersion,
      'rolled_back_from_version': snapshot.toVersion,
      'backup_ref': snapshot.backupRef,
      'checksum': snapshot.backupSha256,
      'checksum_algorithm': 'SHA-256',
      'database_version': verification.databaseVersion,
      'entries': verification.entries,
      'document_files': verification.documentFiles,
      'data_snapshot_restored': true,
      'binary_rollback_applied': false,
      'binary_rollback_scheduled': binaryResult != null,
      'requires_signed_installer_rollback': binaryResult == null,
      if (binaryResult != null)
        'binary_rollback_ref': binaryResult['installer_ref'],
      if (binaryResult != null)
        'binary_rollback_plan_ref': binaryResult['plan_ref'],
      'completed_at': _clock().toUtc().toIso8601String(),
      'local_path_disclosed': false,
    };
  }

  Future<Map<String, dynamic>> applyHotfix(Map<String, dynamic> params) async {
    _validateParameterKeys(params, const {
      'hotfix_id',
      'hotfix_ref',
      'target_version',
      'version',
      'checksum',
      'manifest_token',
      'request_id',
    });
    final requestedHotfixRef = _normalizeHotfixRef(
      params['hotfix_id'] ?? params['hotfix_ref'],
    );
    final requestedVersion =
        params.containsKey('target_version') || params.containsKey('version')
        ? _normalizeVersion(params['target_version'] ?? params['version'])
        : null;
    final requestedChecksum = params.containsKey('checksum')
        ? _normalizeChecksum(params['checksum'])
        : null;
    final manifestToken = params.containsKey('manifest_token')
        ? _normalizeManifestToken(params['manifest_token'])
        : throw const AgentUpdateRequestException(
            'UPDATE_HOTFIX_MANIFEST_REQUIRED',
            'manifest_token firmado es obligatorio para aplicar hotfix',
          );

    final license = await LicenciaService.instance.obtenerLicencia();
    final installationId = license?.installationId;
    if (installationId == null || installationId.isEmpty) {
      throw const AgentUpdateExecutionException(
        'UPDATE_HOTFIX_IDENTITY_UNAVAILABLE',
        'No existe identidad de instalación para validar el hotfix',
      );
    }

    final payload = await _publisherTokenValidator(
      manifestToken,
      installationId,
    );
    if (payload == null) {
      throw const AgentUpdateExecutionException(
        'UPDATE_HOTFIX_MANIFEST_INVALID',
        'El manifiesto firmado del hotfix no es válido para esta instalación',
      );
    }
    final rawHotfix = payload['hotfix'];
    if (rawHotfix is! Map) {
      throw const AgentUpdateExecutionException(
        'UPDATE_HOTFIX_MANIFEST_INVALID',
        'El manifiesto firmado no contiene definición de hotfix',
      );
    }
    final hotfix = _parseHotfixManifest(Map<String, dynamic>.from(rawHotfix));
    if (hotfix.hotfixId != requestedHotfixRef) {
      throw const AgentUpdateRequestException(
        'UPDATE_HOTFIX_REF_MISMATCH',
        'hotfix_id no coincide con el manifiesto firmado',
      );
    }
    if (requestedVersion != null && requestedVersion != hotfix.targetVersion) {
      throw const AgentUpdateRequestException(
        'UPDATE_HOTFIX_TARGET_MISMATCH',
        'target_version no coincide con el manifiesto firmado',
      );
    }
    if (hotfix.targetVersion != AppVersion.version) {
      throw AgentUpdateExecutionException(
        'UPDATE_HOTFIX_INCOMPATIBLE_VERSION',
        'El hotfix no es compatible con MerkaERP ${AppVersion.version}',
      );
    }
    if (requestedChecksum != null &&
        hotfix.checksum != null &&
        requestedChecksum != hotfix.checksum) {
      throw const AgentUpdateRequestException(
        'UPDATE_HOTFIX_CHECKSUM_MISMATCH',
        'checksum no coincide con el manifiesto firmado',
      );
    }

    final preHotfixBackup = await _hotfixBackupCreator(
      'merkaerp_prehotfix_${hotfix.hotfixId.replaceAll('.', '_')}',
    );
    if (!await preHotfixBackup.exists()) {
      throw const AgentUpdateExecutionException(
        'UPDATE_HOTFIX_BACKUP_NOT_FOUND',
        'No se pudo crear snapshot previo al hotfix',
      );
    }
    final backupVerification = await _hotfixBackupVerifier(preHotfixBackup);
    if (!backupVerification.ok) {
      throw const AgentUpdateExecutionException(
        'UPDATE_HOTFIX_BACKUP_INVALID',
        'El snapshot previo al hotfix no superó la verificación integral',
      );
    }
    final backupChecksum = await sha256.bind(preHotfixBackup.openRead()).first;

    final applied = <Map<String, dynamic>>[];
    try {
      for (final operation in hotfix.operations) {
        applied.add(await _applyHotfixOperation(operation));
      }
    } catch (_) {
      try {
        await _rollbackRestorer(preHotfixBackup);
      } catch (_) {
        // El snapshot queda disponible para recuperación manual.
      }
      throw const AgentUpdateExecutionException(
        'UPDATE_HOTFIX_APPLY_FAILED',
        'El hotfix falló y se intentó restaurar el snapshot previo',
      );
    }

    await _recordAppliedHotfix(
      hotfix,
      p.basename(preHotfixBackup.path),
      backupChecksum.toString(),
    );

    return {
      'format': 'MERKAERP_AGENT_HOTFIX_1',
      'hotfix_id': hotfix.hotfixId,
      'target_version': hotfix.targetVersion,
      'checksum': hotfix.checksum,
      'manifest_verified': true,
      'pre_hotfix_backup_ref': p.basename(preHotfixBackup.path),
      'pre_hotfix_backup_checksum': backupChecksum.toString(),
      'checksum_algorithm': 'SHA-256',
      'operations_applied': applied,
      'operation_count': applied.length,
      'completed_at': _clock().toUtc().toIso8601String(),
      'local_path_disclosed': false,
    };
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentUpdateRequestException(
        'UNSUPPORTED_UPDATE_PARAMETER',
        'Parametro de actualización no permitido: ${unsupported.first}',
      );
    }
  }

  String? _normalizeVersion(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return null;
    if (!RegExp(
      r'^[0-9]+[.][0-9]+[.][0-9]+([+.-][A-Za-z0-9_.-]+)?$',
    ).hasMatch(value)) {
      throw const AgentUpdateRequestException(
        'INVALID_UPDATE_VERSION',
        'target_version debe ser una versión semántica segura',
      );
    }
    return value;
  }

  String _normalizeRequiredVersion(dynamic raw, {required String fieldName}) {
    final value = _normalizeVersion(raw);
    if (value == null) {
      throw AgentUpdateRequestException(
        'MISSING_UPDATE_VERSION',
        '$fieldName es obligatorio',
      );
    }
    return value;
  }

  String _normalizeHotfixRef(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null ||
        value.isEmpty ||
        value.length > 80 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(value)) {
      throw const AgentUpdateRequestException(
        'INVALID_HOTFIX_REF',
        'hotfix_id debe ser un identificador seguro',
      );
    }
    return value;
  }

  String _normalizeChecksum(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw const AgentUpdateRequestException(
        'INVALID_UPDATE_CHECKSUM',
        'checksum debe ser SHA-256 hexadecimal de 64 caracteres',
      );
    }
    return value;
  }

  String _normalizeBackupRef(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null ||
        value.isEmpty ||
        value.length > 160 ||
        p.basename(value) != value ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*[.]mkbackup$').hasMatch(value)) {
      throw const AgentUpdateRequestException(
        'INVALID_UPDATE_BACKUP_REF',
        'backup_ref debe ser una referencia local segura',
      );
    }
    return value;
  }

  String _normalizeManifestToken(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null ||
        value.isEmpty ||
        value.length > 12000 ||
        value.contains(RegExp(r'\s'))) {
      throw const AgentUpdateRequestException(
        'INVALID_UPDATE_MANIFEST',
        'manifest_token debe ser un token firmado compacto',
      );
    }
    return value;
  }

  _HotfixManifest _parseHotfixManifest(Map<String, dynamic> json) {
    _validateParameterKeys(json, const {
      'hotfix_id',
      'hotfix_ref',
      'target_version',
      'version',
      'checksum',
      'operations',
      'notas',
      'notes',
    });
    final hotfixId = _normalizeHotfixRef(
      json['hotfix_id'] ?? json['hotfix_ref'],
    );
    final targetVersion = _normalizeRequiredVersion(
      json['target_version'] ?? json['version'],
      fieldName: 'target_version',
    );
    final checksum = json.containsKey('checksum')
        ? _normalizeChecksum(json['checksum'])
        : null;
    final rawOperations = json['operations'];
    if (rawOperations is! List ||
        rawOperations.isEmpty ||
        rawOperations.length > 10) {
      throw const AgentUpdateRequestException(
        'INVALID_HOTFIX_OPERATIONS',
        'operations debe contener entre 1 y 10 operaciones permitidas',
      );
    }
    final operations = <_HotfixOperation>[];
    for (final rawOperation in rawOperations) {
      if (rawOperation is! Map) {
        throw const AgentUpdateRequestException(
          'INVALID_HOTFIX_OPERATION',
          'Cada operación de hotfix debe ser un mapa',
        );
      }
      operations.add(
        _parseHotfixOperation(Map<String, dynamic>.from(rawOperation)),
      );
    }
    return _HotfixManifest(
      hotfixId: hotfixId,
      targetVersion: targetVersion,
      checksum: checksum,
      operations: operations,
    );
  }

  _HotfixOperation _parseHotfixOperation(Map<String, dynamic> json) {
    final type = json['type']?.toString().trim();
    if (type == null || type.isEmpty) {
      throw const AgentUpdateRequestException(
        'INVALID_HOTFIX_OPERATION',
        'La operación de hotfix requiere type',
      );
    }
    return switch (type) {
      'repair' => _parseRepairHotfix(json),
      'configuration' => _parseConfigurationHotfix(json),
      'feature_flags' => _parseFeatureFlagsHotfix(json),
      _ => throw AgentUpdateRequestException(
        'UNSUPPORTED_HOTFIX_OPERATION',
        'Operación de hotfix no permitida: $type',
      ),
    };
  }

  _HotfixOperation _parseRepairHotfix(Map<String, dynamic> json) {
    _validateParameterKeys(json, const {'type', 'repair_code', 'code'});
    final code = json['repair_code'] ?? json['code'];
    final repairCode = code?.toString().trim();
    if (repairCode == null ||
        !AgentRepairService.supportedRepairs.contains(repairCode)) {
      throw const AgentUpdateRequestException(
        'UNSUPPORTED_HOTFIX_REPAIR',
        'repair_code no está registrado como reparación segura',
      );
    }
    return _HotfixOperation(
      type: 'repair',
      params: {'repair_code': repairCode},
    );
  }

  _HotfixOperation _parseConfigurationHotfix(Map<String, dynamic> json) {
    _validateParameterKeys(json, const {'type', 'settings'});
    if (json['settings'] is! Map) {
      throw const AgentUpdateRequestException(
        'INVALID_HOTFIX_CONFIGURATION',
        'settings debe ser un mapa de configuración administrada',
      );
    }
    return _HotfixOperation(
      type: 'configuration',
      params: {'settings': Map<String, dynamic>.from(json['settings'] as Map)},
    );
  }

  _HotfixOperation _parseFeatureFlagsHotfix(Map<String, dynamic> json) {
    _validateParameterKeys(json, const {
      'type',
      'flags',
      'business_features',
      'technical_flags',
    });
    final params = <String, dynamic>{};
    if (json.containsKey('flags')) {
      if (json['flags'] is! Map) {
        throw const AgentUpdateRequestException(
          'INVALID_HOTFIX_FEATURE_FLAGS',
          'flags debe ser un mapa',
        );
      }
      params['flags'] = Map<String, dynamic>.from(json['flags'] as Map);
    }
    if (json.containsKey('business_features')) {
      if (json['business_features'] is! Map) {
        throw const AgentUpdateRequestException(
          'INVALID_HOTFIX_FEATURE_FLAGS',
          'business_features debe ser un mapa',
        );
      }
      params['business_features'] = Map<String, dynamic>.from(
        json['business_features'] as Map,
      );
    }
    if (json.containsKey('technical_flags')) {
      if (json['technical_flags'] is! Map) {
        throw const AgentUpdateRequestException(
          'INVALID_HOTFIX_FEATURE_FLAGS',
          'technical_flags debe ser un mapa',
        );
      }
      params['technical_flags'] = Map<String, dynamic>.from(
        json['technical_flags'] as Map,
      );
    }
    if (params.isEmpty) {
      throw const AgentUpdateRequestException(
        'INVALID_HOTFIX_FEATURE_FLAGS',
        'La operación feature_flags requiere flags compatibles',
      );
    }
    return _HotfixOperation(type: 'feature_flags', params: params);
  }

  Future<Map<String, dynamic>> _applyHotfixOperation(
    _HotfixOperation operation,
  ) async {
    final result = switch (operation.type) {
      'repair' => await _safeRepairRunner(operation.params),
      'configuration' => await _configurationApplier(operation.params),
      'feature_flags' => await _featureFlagsApplier(operation.params),
      _ => throw StateError('Operación local no registrada'),
    };
    return {
      'type': operation.type,
      'result_format': result['format'],
      if (result['repair_code'] != null) 'repair_code': result['repair_code'],
      if (result['applied_settings'] != null)
        'applied_settings': result['applied_settings'],
      if (result['applied_business_features'] != null)
        'applied_business_features': result['applied_business_features'],
      if (result['applied_technical_flags'] != null)
        'applied_technical_flags': result['applied_technical_flags'],
    };
  }

  Future<void> _recordAppliedHotfix(
    _HotfixManifest hotfix,
    String backupRef,
    String backupChecksum,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': 'cc_last_applied_hotfix',
      'valor': jsonEncode({
        'format': 'MERKAERP_APPLIED_HOTFIX_1',
        'hotfix_id': hotfix.hotfixId,
        'target_version': hotfix.targetVersion,
        'operation_count': hotfix.operations.length,
        'pre_hotfix_backup_ref': backupRef,
        'pre_hotfix_backup_checksum': backupChecksum,
        'applied_at': _clock().toUtc().toIso8601String(),
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_APLICAR_HOTFIX',
      entidad: 'control_center',
      detalle:
          'hotfix=${hotfix.hotfixId}; operations=${hotfix.operations.length}; backup=$backupRef',
    );
  }

  String? _normalizeChannel(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if (!CanalActualizacion.values.any((channel) => channel.name == value)) {
      throw const AgentUpdateRequestException(
        'INVALID_UPDATE_CHANNEL',
        'canal debe ser stable, beta o hotfix',
      );
    }
    return value;
  }

  void _validateInfo(InfoVersion info) {
    if (!_secureDownloadUrl(info.urlDescarga)) {
      throw const AgentUpdateExecutionException(
        'UPDATE_INSECURE_URL',
        'La URL de descarga no usa HTTPS ni localhost de desarrollo',
      );
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(info.sha256)) {
      throw const AgentUpdateExecutionException(
        'UPDATE_INVALID_CHECKSUM',
        'El manifiesto no contiene SHA-256 válido',
      );
    }
    if (info.tamanoBytes <= 0 || info.tamanoBytes > 1024 * 1024 * 1024) {
      throw const AgentUpdateExecutionException(
        'UPDATE_INVALID_SIZE',
        'El tamaño declarado del instalador no es aceptable',
      );
    }
    final manifest = info.manifestToken?.trim();
    if (manifest == null || manifest.isEmpty) {
      throw const AgentUpdateExecutionException(
        'UPDATE_MANIFEST_REQUIRED',
        'La actualización no incluye manifiesto RS256',
      );
    }
  }

  bool _secureDownloadUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      return false;
    }
    if (uri.scheme.toLowerCase() == 'https') return true;
    final host = uri.host.toLowerCase();
    return uri.scheme.toLowerCase() == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(host);
  }

  Future<_RollbackSnapshot?> _loadRollbackSnapshot() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [UpdateService.rollbackSnapshotConfigKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['valor']?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      if (json['format'] != 'MERKAERP_UPDATE_ROLLBACK_SNAPSHOT_1') {
        return null;
      }
      return _RollbackSnapshot(
        fromVersion: _normalizeRequiredVersion(
          json['from_version'],
          fieldName: 'from_version',
        ),
        toVersion: _normalizeRequiredVersion(
          json['to_version'],
          fieldName: 'to_version',
        ),
        backupRef: _normalizeBackupRef(json['backup_ref']),
        backupSha256: _normalizeChecksum(json['backup_sha256']),
      );
    } on AgentUpdateRequestException {
      rethrow;
    } catch (_) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_SNAPSHOT_INVALID',
        'El catálogo local de rollback no es válido',
      );
    }
  }

  Future<File> _findRollbackBackup(String backupRef) async {
    final backups = await _rollbackBackupLister();
    for (final backup in backups) {
      if (p.basename(backup.path) == backupRef && await backup.exists()) {
        return backup;
      }
    }
    throw const AgentUpdateExecutionException(
      'UPDATE_ROLLBACK_BACKUP_NOT_FOUND',
      'El snapshot local de rollback no está disponible',
    );
  }

  Future<_BinaryRollbackPackage> _loadBinaryRollbackPackage(
    String manifestToken,
    String targetVersion,
    _RollbackSnapshot snapshot,
  ) async {
    final license = await LicenciaService.instance.obtenerLicencia();
    final installationId = license?.installationId;
    if (installationId == null || installationId.isEmpty) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_IDENTITY_UNAVAILABLE',
        'No existe identidad de instalación para validar el rollback binario',
      );
    }

    final payload = await _rollbackPublisherTokenValidator(
      manifestToken,
      installationId,
    );
    if (payload == null) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_MANIFEST_INVALID',
        'El manifiesto firmado del rollback no es válido para esta instalación',
      );
    }
    final rawRollback = payload['rollback'];
    if (rawRollback is! Map) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_MANIFEST_INVALID',
        'El manifiesto firmado no contiene definición de rollback',
      );
    }
    final rollback = _parseBinaryRollbackManifest(
      Map<String, dynamic>.from(rawRollback),
    );
    if (rollback.targetVersion != targetVersion ||
        rollback.targetVersion != snapshot.fromVersion ||
        rollback.fromVersion != snapshot.toVersion) {
      throw const AgentUpdateRequestException(
        'UPDATE_ROLLBACK_TARGET_MISMATCH',
        'El rollback binario no coincide con el snapshot pre-update local',
      );
    }

    final installer = await _findRollbackInstaller(rollback.installerRef);
    final actualChecksum = await sha256.bind(installer.openRead()).first;
    if (actualChecksum.toString().toLowerCase() != rollback.installerSha256) {
      throw const AgentUpdateExecutionException(
        'UPDATE_ROLLBACK_INSTALLER_CHECKSUM_MISMATCH',
        'El instalador local de rollback cambió desde su manifiesto',
      );
    }

    return _BinaryRollbackPackage(
      targetVersion: rollback.targetVersion,
      fromVersion: rollback.fromVersion,
      installerRef: rollback.installerRef,
      installerSha256: rollback.installerSha256,
      installer: installer,
    );
  }

  _BinaryRollbackManifest _parseBinaryRollbackManifest(
    Map<String, dynamic> json,
  ) {
    _validateParameterKeys(json, const {
      'target_version',
      'version',
      'from_version',
      'current_version',
      'installer_ref',
      'package_ref',
      'installer_sha256',
      'checksum',
      'notes',
      'notas',
    });
    final targetVersion = _normalizeRequiredVersion(
      json['target_version'] ?? json['version'],
      fieldName: 'target_version',
    );
    final fromVersion = _normalizeRequiredVersion(
      json['from_version'] ?? json['current_version'],
      fieldName: 'from_version',
    );
    return _BinaryRollbackManifest(
      targetVersion: targetVersion,
      fromVersion: fromVersion,
      installerRef: _normalizeInstallerRef(
        json['installer_ref'] ?? json['package_ref'],
      ),
      installerSha256: _normalizeChecksum(
        json['installer_sha256'] ?? json['checksum'],
      ),
    );
  }

  String _normalizeInstallerRef(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null ||
        value.isEmpty ||
        value.length > 160 ||
        p.basename(value) != value ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_.+-]*[.](exe|msix)$',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw const AgentUpdateRequestException(
        'INVALID_ROLLBACK_INSTALLER_REF',
        'installer_ref debe ser una referencia local segura',
      );
    }
    return value;
  }

  Future<File> _findRollbackInstaller(String installerRef) async {
    final installers = await _rollbackInstallerLister();
    for (final installer in installers) {
      if (p.basename(installer.path).toLowerCase() ==
              installerRef.toLowerCase() &&
          await installer.exists()) {
        return installer;
      }
    }
    throw const AgentUpdateExecutionException(
      'UPDATE_ROLLBACK_INSTALLER_NOT_FOUND',
      'El instalador firmado de rollback no está disponible localmente',
    );
  }
}

final class _RollbackSnapshot {
  const _RollbackSnapshot({
    required this.fromVersion,
    required this.toVersion,
    required this.backupRef,
    required this.backupSha256,
  });

  final String fromVersion;
  final String toVersion;
  final String backupRef;
  final String backupSha256;
}

final class _BinaryRollbackManifest {
  const _BinaryRollbackManifest({
    required this.targetVersion,
    required this.fromVersion,
    required this.installerRef,
    required this.installerSha256,
  });

  final String targetVersion;
  final String fromVersion;
  final String installerRef;
  final String installerSha256;
}

final class _BinaryRollbackPackage {
  const _BinaryRollbackPackage({
    required this.targetVersion,
    required this.fromVersion,
    required this.installerRef,
    required this.installerSha256,
    required this.installer,
  });

  final String targetVersion;
  final String fromVersion;
  final String installerRef;
  final String installerSha256;
  final File installer;
}

final class _HotfixManifest {
  const _HotfixManifest({
    required this.hotfixId,
    required this.targetVersion,
    required this.checksum,
    required this.operations,
  });

  final String hotfixId;
  final String targetVersion;
  final String? checksum;
  final List<_HotfixOperation> operations;
}

final class _HotfixOperation {
  const _HotfixOperation({required this.type, required this.params});

  final String type;
  final Map<String, dynamic> params;
}
