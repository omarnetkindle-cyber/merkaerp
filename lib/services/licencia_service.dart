import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../db_helper.dart';
import 'control_center_license_client.dart';
import 'control_center_secret_store.dart';
import 'hardware_fingerprint_service.dart';
import 'license_secure_store.dart';
import 'license_validation_service.dart';
import '../licensing/domain/product_family.dart';

enum TipoPlan { basico, profesional, enterprise, trial }

enum EstadoLicencia { activa, expirada, suspendida, trial }

enum TipoLicencia { suscripcion, perpetua }

enum LicenseOperationalState {
  onlineValid,
  offlineGrace,
  refreshRequired,
  onlineDenied,
  invalidLocalToken,
  graceExpired,
}

class LicenseReconciliationResult {
  const LicenseReconciliationResult({
    required this.state,
    required this.allowsOperation,
    this.requiresSignedRefresh = false,
  });

  final LicenseOperationalState state;
  final bool allowsOperation;
  final bool requiresSignedRefresh;
}

class LicenciaInfo {
  const LicenciaInfo({
    required this.uuid,
    required this.plan,
    required this.estado,
    required this.fechaExpiracion,
    required this.modulosHabilitados,
    this.productFamily = ProductFamily.commercial,
    this.limiteDbMb,
    this.alertaVencimientoDias = 30,
    this.tipoLicencia = TipoLicencia.suscripcion,
    this.hardwareFingerprint,
    this.offlineToken,
    this.clientId,
    this.clientName,
    this.maxUsers,
    this.maxDevices,
    this.maxBranches,
    this.installationId,
    this.postgresCredentials,
    this.lastSuccessfulValidationAt,
    this.signedTokenIssuedAt,
  });

  final String uuid;
  final TipoPlan plan;
  final EstadoLicencia estado;
  final DateTime fechaExpiracion;
  final List<String> modulosHabilitados;
  final ProductFamily productFamily;
  final int? limiteDbMb;
  final int alertaVencimientoDias;
  final TipoLicencia tipoLicencia;
  final String? hardwareFingerprint;
  final String? offlineToken;
  final String? clientId;
  final String? clientName;
  final int? maxUsers;
  final int? maxDevices;
  final int? maxBranches;
  final String? installationId;
  final Map<String, dynamic>? postgresCredentials;
  final DateTime? lastSuccessfulValidationAt;
  final DateTime? signedTokenIssuedAt;

  bool get esValida =>
      (estado == EstadoLicencia.activa || estado == EstadoLicencia.trial) &&
      !estaExpirada;

  bool get estaPorVencer {
    // Licencias perpetuas no vencen
    if (tipoLicencia == TipoLicencia.perpetua) return false;

    final diasRestantes = fechaExpiracion.difference(DateTime.now()).inDays;
    return diasRestantes <= alertaVencimientoDias && diasRestantes > 0;
  }

  bool get estaExpirada {
    // Licencias perpetuas no expiran
    if (tipoLicencia == TipoLicencia.perpetua) return false;
    return DateTime.now().isAfter(fechaExpiracion);
  }

  bool tieneModulo(String modulo) => modulosHabilitados.contains(modulo);

  bool get requiereValidacionOnline => tipoLicencia == TipoLicencia.suscripcion;

  Map<String, Object?> toMap() {
    return {
      'uuid': uuid,
      'plan': plan.name,
      'estado': estado.name,
      'fecha_expiracion': fechaExpiracion.toIso8601String(),
      'modulos_habilitados': jsonEncode(modulosHabilitados),
      'product_family': productFamily.storageValue,
      'limite_db_mb': limiteDbMb,
      'alerta_vencimiento_dias': alertaVencimientoDias,
      'tipo_licencia': tipoLicencia.name,
      'hardware_fingerprint': hardwareFingerprint,
      'offline_token': offlineToken,
      'client_id': clientId,
      'client_name': clientName,
      'max_users': maxUsers,
      'max_devices': maxDevices,
      'max_branches': maxBranches,
      'installation_id': installationId,
      'postgres_credentials': postgresCredentials,
      'last_successful_validation_at': lastSuccessfulValidationAt
          ?.toIso8601String(),
      'signed_token_issued_at': signedTokenIssuedAt?.toIso8601String(),
    };
  }

  static LicenciaInfo fromMap(Map<String, dynamic> map) {
    return LicenciaInfo(
      uuid: map['uuid'] as String,
      plan: TipoPlan.values.firstWhere(
        (e) => e.name == map['plan'],
        orElse: () => TipoPlan.basico,
      ),
      estado: EstadoLicencia.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoLicencia.trial,
      ),
      fechaExpiracion: DateTime.parse(map['fecha_expiracion'] as String),
      modulosHabilitados:
          (jsonDecode(map['modulos_habilitados'] as String) as List)
              .map((e) => e.toString())
              .toList(),
      productFamily: parseProductFamily(
        map['product_family'],
        modules: (jsonDecode(map['modulos_habilitados'] as String) as List),
      ),
      limiteDbMb: map['limite_db_mb'] as int?,
      alertaVencimientoDias: map['alerta_vencimiento_dias'] as int? ?? 30,
      tipoLicencia: TipoLicencia.values.firstWhere(
        (e) => e.name == map['tipo_licencia'],
        orElse: () => TipoLicencia.suscripcion,
      ),
      hardwareFingerprint: map['hardware_fingerprint'] as String?,
      offlineToken: map['offline_token'] as String?,
      clientId: map['client_id'] as String?,
      clientName: map['client_name'] as String?,
      maxUsers: _toInt(map['max_users']),
      maxDevices: _toInt(map['max_devices']),
      maxBranches: _toInt(map['max_branches']),
      installationId: map['installation_id'] as String?,
      postgresCredentials: map['postgres_credentials'] is Map
          ? (map['postgres_credentials'] as Map).cast<String, dynamic>()
          : null,
      lastSuccessfulValidationAt: map['last_successful_validation_at'] is String
          ? DateTime.tryParse(map['last_successful_validation_at'] as String)
          : null,
      signedTokenIssuedAt: map['signed_token_issued_at'] is String
          ? DateTime.tryParse(map['signed_token_issued_at'] as String)
          : null,
    );
  }

  LicenciaInfo copyWith({
    EstadoLicencia? estado,
    DateTime? fechaExpiracion,
    List<String>? modulosHabilitados,
    ProductFamily? productFamily,
    int? limiteDbMb,
    String? offlineToken,
    String? clientId,
    String? clientName,
    int? maxUsers,
    int? maxDevices,
    int? maxBranches,
    String? installationId,
    Map<String, dynamic>? postgresCredentials,
    DateTime? lastSuccessfulValidationAt,
    DateTime? signedTokenIssuedAt,
  }) {
    return LicenciaInfo(
      uuid: uuid,
      plan: plan,
      estado: estado ?? this.estado,
      fechaExpiracion: fechaExpiracion ?? this.fechaExpiracion,
      modulosHabilitados: modulosHabilitados ?? this.modulosHabilitados,
      productFamily: productFamily ?? this.productFamily,
      limiteDbMb: limiteDbMb ?? this.limiteDbMb,
      alertaVencimientoDias: alertaVencimientoDias,
      tipoLicencia: tipoLicencia,
      hardwareFingerprint: hardwareFingerprint,
      offlineToken: offlineToken ?? this.offlineToken,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      maxUsers: maxUsers ?? this.maxUsers,
      maxDevices: maxDevices ?? this.maxDevices,
      maxBranches: maxBranches ?? this.maxBranches,
      installationId: installationId ?? this.installationId,
      postgresCredentials: postgresCredentials ?? this.postgresCredentials,
      lastSuccessfulValidationAt:
          lastSuccessfulValidationAt ?? this.lastSuccessfulValidationAt,
      signedTokenIssuedAt: signedTokenIssuedAt ?? this.signedTokenIssuedAt,
    );
  }

  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class LicenciaService {
  LicenciaService._();

  static final LicenciaService instance = LicenciaService._();

  LicenciaInfo? _licenciaCache;
  static const Duration gracePeriod = Duration(days: 7);
  LicenseSecureStore _secureStore = LicenseSecureStore();

  void configureSecureStoreForTests(LicenseSecureStore store) {
    _secureStore = store;
    _licenciaCache = null;
  }

  Future<LicenciaInfo?> obtenerLicencia() async {
    if (_licenciaCache != null) return _licenciaCache;

    try {
      final map = await _secureStore.read();
      if (map == null) return null;
      _licenciaCache = LicenciaInfo.fromMap(map);
      return _licenciaCache;
    } catch (e) {
      debugPrint('Error al parsear licencia: $e');
      return null;
    }
  }

  Future<void> guardarLicencia(LicenciaInfo licencia) async {
    await _secureStore.write(licencia.toMap());
    _licenciaCache = licencia;

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'LICENCIA_ACTUALIZADA',
      entidad: 'licencia',
      detalle: 'Plan: ${licencia.plan.name}, Estado: ${licencia.estado.name}',
    );
  }

  Future<void> limpiarLicenciaDuplicada() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave IN (?, ?)',
      whereArgs: [
        LicenseSecureStore.legacyConfigKey,
        LicenseSecureStore.encryptedConfigKey,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final licencia = await obtenerLicencia();
    if (licencia == null) return;
    if (licencia.estado == EstadoLicencia.activa ||
        licencia.estado == EstadoLicencia.trial) {
      return;
    }

    await db.delete(
      'app_config',
      where: 'clave IN (?, ?)',
      whereArgs: [
        LicenseSecureStore.legacyConfigKey,
        LicenseSecureStore.encryptedConfigKey,
      ],
    );
    _licenciaCache = null;
  }

  Future<void> generarLicenciaInicial() async {
    final existente = await obtenerLicencia();
    if (existente != null) return;

    final uuid = _generarUuid();
    final licenciaInicial = LicenciaInfo(
      uuid: uuid,
      plan: TipoPlan.trial,
      estado: EstadoLicencia.trial,
      fechaExpiracion: DateTime.now().add(const Duration(days: 30)),
      modulosHabilitados: _modulosPorPlan(TipoPlan.trial),
      limiteDbMb: 100,
    );

    await guardarLicencia(licenciaInicial);
  }

  Future<bool> validarModulo(String modulo) async {
    final licencia = await obtenerLicencia();
    if (licencia == null) {
      await generarLicenciaInicial();
      return (await obtenerLicencia())?.tieneModulo(modulo) ?? false;
    }

    if (!await permiteOperacionLocal()) return false;
    return licencia.tieneModulo(modulo);
  }

  Future<bool> permiteOperacionLocal({DateTime? now}) async {
    final licencia = await obtenerLicencia();
    if (licencia == null || !licencia.esValida) return false;
    final state = await obtenerEstadoOperativo();
    if (state == LicenseOperationalState.onlineDenied ||
        state == LicenseOperationalState.invalidLocalToken ||
        state == LicenseOperationalState.graceExpired) {
      return false;
    }
    if (state == LicenseOperationalState.offlineGrace) {
      final effectiveNow = (now ?? DateTime.now()).toUtc();
      return _validarModoGracia(
        licencia,
        licencia.fechaExpiracion.toUtc(),
        effectiveNow,
      );
    }
    return true;
  }

  Future<LicenseOperationalState?> obtenerEstadoOperativo() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: ['license_operational_state'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['valor']?.toString();
    for (final state in LicenseOperationalState.values) {
      if (state.name == value) return state;
    }
    return null;
  }

  Future<bool> verificarLimiteDb(int tamanoMbActual) async {
    final licencia = await obtenerLicencia();
    if (licencia == null || licencia.limiteDbMb == null) return true;

    return tamanoMbActual <= licencia.limiteDbMb!;
  }

  Future<bool> activarDesdeControlCenter({
    required String email,
    required String password,
    ControlCenterLicenseClient? client,
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
  }) async {
    final hardwareService = fingerprintService ?? HardwareFingerprintService();
    final fingerprint =
        currentHardwareFingerprint ??
        await hardwareService.generateFingerprint();
    final ccClient = client ?? const ControlCenterLicenseClient();
    final response = await ccClient.activate(
      email: email,
      password: password,
      hardwareFingerprint: fingerprint,
    );
    final token = _extractString(response, const [
      'license_token',
      'token',
      'jwt',
    ]);
    if (token == null || token.trim().isEmpty) return false;

    final validator = validationService ?? LicenseValidationService();
    final tokenData = await validator.validateOfflineTokenForDevice(
      token,
      fingerprint,
    );
    if (tokenData == null) return false;

    final licenseData = _extractMap(response, const ['license', 'data']);
    final metadata = licenseData ?? response;
    final userData = _extractMap(response, const ['user']);
    final modules = (tokenData['md'] as List)
        .map((value) => value.toString())
        .toList();
    final expiry = DateTime.parse(tokenData['ed'] as String);
    final licenseType = tokenData['lt'] as String;
    final status = tokenData['st'] as String;
    final signedInstallationId = _extractString(tokenData, const [
      'installation_id',
      'installationId',
    ]);
    if (tokenData['token_type'] != 'license' ||
        signedInstallationId == null ||
        signedInstallationId.trim().isEmpty ||
        (tokenData['pf'] != 'COMMERCIAL' && tokenData['pf'] != 'PUBLIC')) {
      return false;
    }

    final licencia = LicenciaInfo(
      uuid: await hardwareService.generateUUID(),
      plan: _determinarPlanDesdeModulos(modules),
      estado: _estadoDesdeControlCenter(status),
      fechaExpiracion: expiry,
      modulosHabilitados: modules,
      productFamily: parseProductFamily(tokenData['pf'], modules: modules),
      tipoLicencia: licenseType.toUpperCase() == 'PERPETUA'
          ? TipoLicencia.perpetua
          : TipoLicencia.suscripcion,
      hardwareFingerprint: fingerprint,
      offlineToken: token,
      clientId:
          _extractString(metadata, const ['client_id', 'clientId']) ??
          (userData == null
              ? null
              : _extractString(userData, const ['client_id', 'clientId'])) ??
          _extractString(tokenData, const ['client_id', 'clientId']),
      clientName:
          _extractString(metadata, const ['client_name', 'clientName']) ??
          (userData == null
              ? null
              : _extractString(userData, const [
                  'client_name',
                  'clientName',
                ])) ??
          _extractString(tokenData, const ['client_name', 'clientName']),
      maxUsers: _extractInt(metadata, const ['max_users', 'maxUsers']),
      maxDevices: _extractInt(metadata, const ['max_devices', 'maxDevices']),
      maxBranches: _extractInt(metadata, const ['max_branches', 'maxBranches']),
      installationId: signedInstallationId,
      postgresCredentials:
          _extractMap(metadata, const [
            'postgres_credentials',
            'postgresCredentials',
          ]) ??
          _extractMap(response, const [
            'postgres_credentials',
            'postgresCredentials',
          ]),
      lastSuccessfulValidationAt: DateTime.now().toUtc(),
      signedTokenIssuedAt: _issuedAtFromToken(tokenData),
    );

    await guardarLicencia(licencia);

    final commandSecret =
        _extractString(response, const ['command_secret', 'commandSecret']) ??
        _extractString(metadata, const ['command_secret', 'commandSecret']);
    final installationId = licencia.installationId;
    if ((commandSecret != null && commandSecret.trim().isNotEmpty) ||
        (installationId != null && installationId.trim().isNotEmpty)) {
      final db = await DatabaseHelper.instance.database;
      if (commandSecret != null && commandSecret.trim().isNotEmpty) {
        await ControlCenterSecretStore.instance.writeCommandSecret(
          commandSecret,
        );
      }
      if (installationId != null && installationId.trim().isNotEmpty) {
        await db.rawInsert(
          'INSERT OR REPLACE INTO app_config (clave, valor) VALUES (?, ?)',
          ['control_center_installation_id', installationId],
        );
      }
    }
    return true;
  }

  /// Reconcilia la identidad local con el `installation_id` contenido en el
  /// JWT RS256 ya verificado para este equipo. Esto permite reparar de forma
  /// segura activaciones de servidores antiguos que devolvían el identificador
  /// solo dentro del token o únicamente en el nivel superior de la respuesta.
  Future<String?> reconciliarIdentidadInstalacionFirmada({
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
  }) async {
    final licencia = await obtenerLicencia();
    final token = licencia?.offlineToken;
    if (licencia == null || token == null || token.trim().isEmpty) {
      return licencia?.installationId;
    }

    final hardwareService = fingerprintService ?? HardwareFingerprintService();
    final fingerprint =
        currentHardwareFingerprint ??
        await hardwareService.generateFingerprint();
    final validator = validationService ?? LicenseValidationService();
    final tokenData = await validator.validateOfflineTokenForDevice(
      token,
      fingerprint,
    );
    if (tokenData == null) return licencia.installationId;

    final signedInstallationId = _extractString(tokenData, const [
      'installation_id',
      'installationId',
    ])?.trim();
    if (signedInstallationId == null || signedInstallationId.isEmpty) {
      return licencia.installationId;
    }

    if (licencia.installationId != signedInstallationId) {
      await guardarLicencia(
        licencia.copyWith(installationId: signedInstallationId),
      );
    }
    final db = await DatabaseHelper.instance.database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO app_config (clave, valor) VALUES (?, ?)',
      ['control_center_installation_id', signedInstallationId],
    );
    return signedInstallationId;
  }

  Future<bool> validarConControlCenterOGracia({
    ControlCenterLicenseClient? client,
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
    DateTime? now,
  }) async {
    final result = await reconciliarEstadoOperativo(
      client: client,
      validationService: validationService,
      fingerprintService: fingerprintService,
      currentHardwareFingerprint: currentHardwareFingerprint,
      now: now,
    );
    return result.allowsOperation;
  }

  Future<LicenseReconciliationResult> reconciliarEstadoOperativo({
    ControlCenterLicenseClient? client,
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
    DateTime? now,
  }) async {
    final licencia = await obtenerLicencia();
    final token = licencia?.offlineToken;
    if (licencia == null || token == null || token.trim().isEmpty) {
      return _operationalResult(
        LicenseOperationalState.invalidLocalToken,
        allowsOperation: false,
      );
    }

    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final hardwareService = fingerprintService ?? HardwareFingerprintService();
    final fingerprint =
        currentHardwareFingerprint ??
        await hardwareService.generateFingerprint();
    final validator = validationService ?? LicenseValidationService();
    final tokenData = validator.validateOfflineToken(token);
    if (tokenData == null ||
        !await validator.verifyHardwareFingerprint(
          tokenData['hfp']?.toString() ?? '',
          fingerprint,
        ) ||
        !_licenseMatchesSignedClaims(licencia, tokenData)) {
      return _operationalResult(
        LicenseOperationalState.invalidLocalToken,
        allowsOperation: false,
      );
    }

    final tokenExpiry = DateTime.parse(tokenData['ed'] as String).toUtc();
    final signedState = _estadoDesdeControlCenter(tokenData['st'].toString());
    if (signedState == EstadoLicencia.suspendida ||
        signedState == EstadoLicencia.expirada ||
        (licencia.tipoLicencia != TipoLicencia.perpetua &&
            effectiveNow.isAfter(tokenExpiry))) {
      return _operationalResult(
        LicenseOperationalState.invalidLocalToken,
        allowsOperation: false,
      );
    }

    try {
      final ccClient = client ?? const ControlCenterLicenseClient();
      final response = await ccClient.validate(
        licenseToken: token,
        hardwareFingerprint: fingerprint,
        installationId: licencia.installationId ?? licencia.uuid,
      );
      final valid = response['valid'] == true || response['success'] == true;
      if (!valid) {
        return _operationalResult(
          LicenseOperationalState.onlineDenied,
          allowsOperation: false,
        );
      }
      await guardarLicencia(
        licencia.copyWith(lastSuccessfulValidationAt: effectiveNow),
      );
      final refreshRequired = _serverStateDiffersFromSignedClaims(
        response,
        tokenData,
      );
      return _operationalResult(
        refreshRequired
            ? LicenseOperationalState.refreshRequired
            : LicenseOperationalState.onlineValid,
        allowsOperation: true,
        requiresSignedRefresh: refreshRequired,
      );
    } on ControlCenterHttpException catch (error) {
      if (error.statusCode == 401 ||
          error.statusCode == 403 ||
          error.statusCode == 404) {
        return _operationalResult(
          LicenseOperationalState.onlineDenied,
          allowsOperation: false,
        );
      }
      return _graceResult(licencia, tokenExpiry, effectiveNow);
    } on ControlCenterNetworkException {
      return _graceResult(licencia, tokenExpiry, effectiveNow);
    } on SocketException {
      return _graceResult(licencia, tokenExpiry, effectiveNow);
    } on TimeoutException {
      return _graceResult(licencia, tokenExpiry, effectiveNow);
    }
  }

  /// Reemplaza el estado local únicamente con claims provenientes del JWT
  /// RS256. Los campos paralelos del comando nunca participan en la decisión.
  Future<LicenseUpdateResult> aplicarActualizacionFirmada({
    required String token,
    required String expectedInstallationId,
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
    DateTime? now,
  }) async {
    final current = await obtenerLicencia();
    if (current == null || current.installationId != expectedInstallationId) {
      return const LicenseUpdateResult.rejected(
        'LICENSE_INSTALLATION_MISMATCH',
      );
    }

    final hardwareService = fingerprintService ?? HardwareFingerprintService();
    final fingerprint =
        currentHardwareFingerprint ??
        await hardwareService.generateFingerprint();
    final validator = validationService ?? LicenseValidationService();
    final payload = await validator.validateAgentLicenseUpdate(
      token,
      currentFingerprint: fingerprint,
      expectedInstallationId: expectedInstallationId,
      expectedProductFamily: current.productFamily.wireValue,
      now: now,
    );
    if (payload == null) {
      return const LicenseUpdateResult.rejected('LICENSE_TOKEN_INVALID');
    }

    final issuedAt = _issuedAtFromToken(payload);
    final previousIssuedAt = current.signedTokenIssuedAt;
    if (issuedAt == null ||
        (previousIssuedAt != null && issuedAt.isBefore(previousIssuedAt))) {
      return const LicenseUpdateResult.rejected('LICENSE_TOKEN_ROLLBACK');
    }

    final modules = (payload['md'] as List).cast<String>();
    final expiry = DateTime.parse(payload['ed'] as String).toUtc();
    final licenseType = payload['lt'] == 'PERPETUA'
        ? TipoLicencia.perpetua
        : TipoLicencia.suscripcion;
    var status = _estadoDesdeControlCenter(payload['st'].toString());
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    if (licenseType != TipoLicencia.perpetua && effectiveNow.isAfter(expiry)) {
      status = EstadoLicencia.expirada;
    }

    final updated = LicenciaInfo(
      uuid: current.uuid,
      plan: _determinarPlanDesdeModulos(modules),
      estado: status,
      fechaExpiracion: expiry,
      modulosHabilitados: modules,
      productFamily: current.productFamily,
      limiteDbMb: current.limiteDbMb,
      alertaVencimientoDias: current.alertaVencimientoDias,
      tipoLicencia: licenseType,
      hardwareFingerprint: fingerprint,
      offlineToken: token,
      clientId:
          _extractString(payload, const ['client_id']) ?? current.clientId,
      clientName:
          _extractString(payload, const ['client_name']) ?? current.clientName,
      maxUsers: current.maxUsers,
      maxDevices: current.maxDevices,
      maxBranches: current.maxBranches,
      installationId: expectedInstallationId,
      postgresCredentials: current.postgresCredentials,
      lastSuccessfulValidationAt: effectiveNow,
      signedTokenIssuedAt: issuedAt,
    );
    await guardarLicencia(updated);
    await _persistOperationalState(LicenseOperationalState.onlineValid);
    return LicenseUpdateResult.applied(
      modules: modules,
      status: status.name,
      productFamily: current.productFamily.wireValue,
      expiresAt: expiry,
    );
  }

  /// Activar licencia desde token offline
  Future<bool> activarDesdeTokenOffline(
    String token, {
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
  }) async {
    final validator = validationService ?? LicenseValidationService();
    final hardwareService = fingerprintService ?? HardwareFingerprintService();

    final currentFingerprint =
        currentHardwareFingerprint ??
        await hardwareService.generateFingerprint();
    final tokenData = await validator.validateOfflineTokenForDevice(
      token,
      currentFingerprint,
    );
    if (tokenData == null) {
      debugPrint('Token inválido');
      return false;
    }

    // Crear licencia desde token
    final tipoLicencia = tokenData['lt'] == 'PERPETUA'
        ? TipoLicencia.perpetua
        : TipoLicencia.suscripcion;

    final estado = tokenData['st'] == 'ACTIVO'
        ? EstadoLicencia.activa
        : EstadoLicencia.trial;

    final plan = _determinarPlanDesdeModulos(tokenData['md'] as List);

    final licencia = LicenciaInfo(
      uuid: await hardwareService.generateUUID(),
      plan: plan,
      estado: estado,
      fechaExpiracion: DateTime.parse(tokenData['ed'] as String),
      modulosHabilitados: (tokenData['md'] as List)
          .map((e) => e.toString())
          .toList(),
      productFamily: parseProductFamily(
        tokenData['pf'],
        modules: tokenData['md'] as List,
      ),
      tipoLicencia: tipoLicencia,
      hardwareFingerprint: currentFingerprint,
      offlineToken: token,
    );

    await guardarLicencia(licencia);
    return true;
  }

  /// Validar licencia local (para uso offline)
  Future<bool> validarLicenciaLocal({
    LicenseValidationService? validationService,
    HardwareFingerprintService? fingerprintService,
    String? currentHardwareFingerprint,
  }) async {
    final licencia = await obtenerLicencia();
    final token = licencia?.offlineToken;
    if (licencia == null || token == null || token.trim().isEmpty) return false;

    final validator = validationService ?? LicenseValidationService();
    final hardwareService = fingerprintService ?? HardwareFingerprintService();
    final currentFingerprint =
        currentHardwareFingerprint ??
        await hardwareService.generateFingerprint();
    final tokenData = await validator.validateOfflineTokenForDevice(
      token,
      currentFingerprint,
    );
    if (tokenData == null) return false;
    final tokenFingerprint = tokenData['hfp'] as String;

    final expectedType = tokenData['lt'] == 'PERPETUA'
        ? TipoLicencia.perpetua
        : TipoLicencia.suscripcion;
    final expectedStatus = tokenData['st'] == 'ACTIVO'
        ? EstadoLicencia.activa
        : EstadoLicencia.trial;
    final expectedExpiry = DateTime.parse(tokenData['ed'] as String);
    final expectedModules = (tokenData['md'] as List)
        .map((module) => module.toString())
        .toList();

    return licencia.tipoLicencia == expectedType &&
        licencia.estado == expectedStatus &&
        licencia.plan == _determinarPlanDesdeModulos(expectedModules) &&
        licencia.fechaExpiracion.toUtc().millisecondsSinceEpoch ==
            expectedExpiry.toUtc().millisecondsSinceEpoch &&
        licencia.hardwareFingerprint == tokenFingerprint &&
        licencia.productFamily ==
            parseProductFamily(tokenData['pf'], modules: expectedModules) &&
        _sameModules(licencia.modulosHabilitados, expectedModules);
  }

  /// Validar hardware fingerprint actual contra licencia
  Future<bool> validarHardwareFingerprint() async {
    final licencia = await obtenerLicencia();
    if (licencia == null || licencia.hardwareFingerprint == null) return false;

    final fingerprintService = HardwareFingerprintService();
    final currentFingerprint = await fingerprintService.generateFingerprint();

    return currentFingerprint == licencia.hardwareFingerprint;
  }

  /// Verificar si se requiere reactivación (cambio de hardware)
  Future<bool> requiereReactivacion() async {
    final licencia = await obtenerLicencia();
    if (licencia == null) return true;

    if (licencia.hardwareFingerprint == null) return false;

    return !(await validarHardwareFingerprint());
  }

  /// Obtener días de gracia restantes para suscripciones
  int getDiasGraciaRestantes() {
    final licencia = _licenciaCache;
    final last = licencia?.lastSuccessfulValidationAt;
    if (last == null) return 0;
    final deadline = last.toUtc().add(gracePeriod);
    final remaining = deadline.difference(DateTime.now().toUtc()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  bool _validarModoGracia(
    LicenciaInfo licencia,
    DateTime tokenExpiry,
    DateTime now,
  ) {
    final last = licencia.lastSuccessfulValidationAt;
    if (last == null) return false;
    final graceDeadline = last.toUtc().add(gracePeriod);
    final effectiveDeadline = tokenExpiry.isBefore(graceDeadline)
        ? tokenExpiry
        : graceDeadline;
    return !now.isAfter(effectiveDeadline);
  }

  Future<LicenseReconciliationResult> _graceResult(
    LicenciaInfo licencia,
    DateTime tokenExpiry,
    DateTime now,
  ) {
    final allowed = _validarModoGracia(licencia, tokenExpiry, now);
    return _operationalResult(
      allowed
          ? LicenseOperationalState.offlineGrace
          : LicenseOperationalState.graceExpired,
      allowsOperation: allowed,
    );
  }

  Future<LicenseReconciliationResult> _operationalResult(
    LicenseOperationalState state, {
    required bool allowsOperation,
    bool requiresSignedRefresh = false,
  }) async {
    await _persistOperationalState(state);
    return LicenseReconciliationResult(
      state: state,
      allowsOperation: allowsOperation,
      requiresSignedRefresh: requiresSignedRefresh,
    );
  }

  Future<void> _persistOperationalState(LicenseOperationalState state) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_config (clave, valor) VALUES (?, ?)',
        ['license_operational_state', state.name],
      );
      await txn.rawInsert(
        'INSERT OR REPLACE INTO app_config (clave, valor) VALUES (?, ?)',
        [
          'license_operational_checked_at',
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    });
  }

  bool _licenseMatchesSignedClaims(
    LicenciaInfo licencia,
    Map<String, dynamic> tokenData,
  ) {
    final modules = (tokenData['md'] as List)
        .map((value) => value.toString())
        .toList();
    final installationId = tokenData['installation_id']?.toString();
    return licencia.tipoLicencia ==
            (tokenData['lt'] == 'PERPETUA'
                ? TipoLicencia.perpetua
                : TipoLicencia.suscripcion) &&
        licencia.estado ==
            _estadoDesdeControlCenter(tokenData['st'].toString()) &&
        licencia.fechaExpiracion.toUtc().millisecondsSinceEpoch ==
            DateTime.parse(
              tokenData['ed'] as String,
            ).toUtc().millisecondsSinceEpoch &&
        licencia.hardwareFingerprint == tokenData['hfp'] &&
        licencia.productFamily ==
            parseProductFamily(tokenData['pf'], modules: modules) &&
        _sameModules(licencia.modulosHabilitados, modules) &&
        (installationId == null ||
            installationId.isEmpty ||
            installationId == licencia.installationId);
  }

  bool _serverStateDiffersFromSignedClaims(
    Map<String, dynamic> response,
    Map<String, dynamic> tokenData,
  ) {
    final rawLicense = response['license'];
    if (rawLicense is! Map) return false;
    final server = rawLicense.cast<String, dynamic>();
    final serverModules = server['modules'];
    final signedModules = (tokenData['md'] as List)
        .map((value) => value.toString())
        .toList();
    final serverExpiry = DateTime.tryParse(
      server['expires_at']?.toString() ?? '',
    );
    final signedExpiry = DateTime.parse(tokenData['ed'] as String);
    final serverFamily = parseProductFamily(
      server['product_family'],
      modules: serverModules is List ? serverModules : const [],
    );
    final signedFamily = parseProductFamily(
      tokenData['pf'],
      modules: signedModules,
    );
    final serverType = server['license_type']?.toString().toUpperCase();
    final serverStatus = _estadoDesdeControlCenter(
      server['status']?.toString() ?? '',
    );
    final signedStatus = _estadoDesdeControlCenter(tokenData['st'].toString());
    final responseInstallation = response['installation_id']?.toString();
    final signedInstallation = tokenData['installation_id']?.toString();
    return serverModules is! List ||
        !_sameModules(
          serverModules.map((value) => value.toString()).toList(),
          signedModules,
        ) ||
        serverExpiry == null ||
        serverExpiry.toUtc().millisecondsSinceEpoch !=
            signedExpiry.toUtc().millisecondsSinceEpoch ||
        serverFamily != signedFamily ||
        serverType != tokenData['lt'] ||
        serverStatus != signedStatus ||
        (responseInstallation != null &&
            responseInstallation != signedInstallation);
  }

  TipoPlan _determinarPlanDesdeModulos(List<dynamic> modulos) {
    final modulosSet = modulos.map((e) => e.toString()).toSet();

    if (modulosSet.contains('nomina') || modulosSet.contains('activos_fijos')) {
      return TipoPlan.enterprise;
    } else if (modulosSet.contains('contabilidad') ||
        modulosSet.contains('cartera')) {
      return TipoPlan.profesional;
    } else {
      return TipoPlan.basico;
    }
  }

  bool _sameModules(List<String> local, List<String> signed) {
    if (local.length != signed.length) return false;
    return local.toSet().containsAll(signed) &&
        signed.toSet().containsAll(local);
  }

  List<String> _modulosPorPlan(TipoPlan plan) {
    switch (plan) {
      case TipoPlan.basico:
        return ['ventas', 'inventario', 'caja', 'reportes_basicos'];
      case TipoPlan.profesional:
        return [
          'ventas',
          'inventario',
          'caja',
          'bancos',
          'cartera',
          'contabilidad',
          'reportes_basicos',
          'reportes_avanzados',
        ];
      case TipoPlan.enterprise:
        return [
          'ventas',
          'inventario',
          'caja',
          'bancos',
          'cartera',
          'contabilidad',
          'nomina',
          'activos_fijos',
          'conciliacion',
          'auditoria',
          'reportes_basicos',
          'reportes_avanzados',
          'crm',
          'produccion',
          'api_publica',
          'ecommerce_sync',
          'portal_clientes',
        ];
      case TipoPlan.trial:
        return ['ventas', 'inventario', 'caja', 'reportes_basicos'];
    }
  }

  String _generarUuid() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final random = DateTime.now().microsecondsSinceEpoch.toString();
    final data = '$timestamp-$random';
    final digest = sha256.convert(utf8.encode(data));
    return 'MERKA-${digest.toString().substring(0, 32).toUpperCase()}';
  }

  Future<void> limpiarCache() {
    _licenciaCache = null;
    return Future.value();
  }

  String? _extractString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }

  DateTime? _issuedAtFromToken(Map<String, dynamic> tokenData) {
    final value = tokenData['iat'];
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  int? _extractInt(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value != null) {
        final parsed = int.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Map<String, dynamic>? _extractMap(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return value.cast<String, dynamic>();
    }
    return null;
  }

  EstadoLicencia _estadoDesdeControlCenter(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVO':
      case 'ACTIVE':
        return EstadoLicencia.activa;
      case 'SUSPENDIDO':
      case 'SUSPENDED':
        return EstadoLicencia.suspendida;
      case 'EXPIRADO':
      case 'EXPIRED':
        return EstadoLicencia.expirada;
      case 'TRIAL':
      default:
        return EstadoLicencia.trial;
    }
  }
}

class LicenseUpdateResult {
  const LicenseUpdateResult._({
    required this.applied,
    required this.errorCode,
    this.modules = const [],
    this.status,
    this.productFamily,
    this.expiresAt,
  });

  const LicenseUpdateResult.rejected(String errorCode)
    : this._(applied: false, errorCode: errorCode);

  LicenseUpdateResult.applied({
    required List<String> modules,
    required String status,
    required String productFamily,
    required DateTime expiresAt,
  }) : this._(
         applied: true,
         errorCode: null,
         modules: List.unmodifiable(modules),
         status: status,
         productFamily: productFamily,
         expiresAt: expiresAt,
       );

  final bool applied;
  final String? errorCode;
  final List<String> modules;
  final String? status;
  final String? productFamily;
  final DateTime? expiresAt;
}
