import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../db_helper.dart';
import '../core/app/app_version.dart';
import '../core/backup/full_backup_service.dart';
import 'control_center_endpoint.dart';
import 'licencia_service.dart';
import 'license_validation_service.dart';

enum CanalActualizacion { stable, beta, hotfix }

enum EstadoDescarga { pendiente, descargando, completado, error, pausado }

class InfoVersion {
  const InfoVersion({
    required this.version,
    required this.canal,
    required this.fechaPublicacion,
    required this.urlDescarga,
    required this.tamanoBytes,
    required this.sha256,
    this.notas,
    this.obligatoria = false,
    this.manifestToken,
  });

  final String version;
  final CanalActualizacion canal;
  final DateTime fechaPublicacion;
  final String urlDescarga;
  final int tamanoBytes;
  final String sha256;
  final String? notas;
  final bool obligatoria;
  final String? manifestToken;

  bool esMayorQue(String versionActual) {
    final actual = versionActual.split('.').map(int.parse).toList();
    final nueva = version.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final a = i < actual.length ? actual[i] : 0;
      final n = i < nueva.length ? nueva[i] : 0;
      if (n > a) return true;
      if (n < a) return false;
    }
    return false;
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'canal': canal.name,
      'fecha_publicacion': fechaPublicacion.toIso8601String(),
      'url_descarga': urlDescarga,
      'tamano_bytes': tamanoBytes,
      'sha256': sha256,
      'notas': notas,
      'obligatoria': obligatoria,
    };
  }

  static InfoVersion fromJson(Map<String, dynamic> json) {
    return InfoVersion(
      version: json['version'] as String,
      canal: CanalActualizacion.values.firstWhere(
        (e) => e.name == json['canal'],
        orElse: () => CanalActualizacion.stable,
      ),
      fechaPublicacion: DateTime.parse(json['fecha_publicacion'] as String),
      urlDescarga: json['url_descarga'] as String,
      tamanoBytes: json['tamano_bytes'] as int,
      sha256: json['sha256'] as String,
      notas: json['notas'] as String?,
      obligatoria: json['obligatoria'] as bool? ?? false,
      manifestToken: json['manifest_token'] as String?,
    );
  }
}

class ProgresoDescarga {
  const ProgresoDescarga({
    required this.estado,
    this.bytesDescargados = 0,
    this.totalBytes = 0,
    this.porcentaje = 0.0,
    this.velocidadKbps = 0.0,
    this.error,
  });

  final EstadoDescarga estado;
  final int bytesDescargados;
  final int totalBytes;
  final double porcentaje;
  final double velocidadKbps;
  final String? error;

  ProgresoDescarga copyWith({
    EstadoDescarga? estado,
    int? bytesDescargados,
    int? totalBytes,
    double? porcentaje,
    double? velocidadKbps,
    String? error,
  }) {
    return ProgresoDescarga(
      estado: estado ?? this.estado,
      bytesDescargados: bytesDescargados ?? this.bytesDescargados,
      totalBytes: totalBytes ?? this.totalBytes,
      porcentaje: porcentaje ?? this.porcentaje,
      velocidadKbps: velocidadKbps ?? this.velocidadKbps,
      error: error ?? this.error,
    );
  }
}

class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  static const String _claveConfigCanal = 'update_canal';
  static const String _claveConfigUltimaRevision = 'update_ultima_revision';
  static const String _claveConfigVersionIgnorada = 'update_version_ignorada';
  static const String rollbackSnapshotConfigKey =
      'cc_update_last_preupdate_snapshot';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  ProgresoDescarga? _progresoActual;
  CancelToken? _cancelToken;
  final List<void Function(ProgresoDescarga)> _listeners = [];

  CanalActualizacion get canal => CanalActualizacion.stable;

  ProgresoDescarga? get progresoActual => _progresoActual;

  Future<CanalActualizacion> obtenerCanalConfigurado() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: [_claveConfigCanal],
      limit: 1,
    );

    if (rows.isEmpty) return CanalActualizacion.stable;

    final valor = rows.first['valor']?.toString();
    return CanalActualizacion.values.firstWhere(
      (e) => e.name == valor,
      orElse: () => CanalActualizacion.stable,
    );
  }

  Future<void> configurarCanal(CanalActualizacion canal) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': _claveConfigCanal,
      'valor': canal.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'UPDATE_CANAL_CONFIGURADO',
      entidad: 'update_service',
      detalle: 'Canal: ${canal.name}',
    );
  }

  Future<InfoVersion?> buscarActualizacion() async {
    try {
      final license = await LicenciaService.instance.obtenerLicencia();
      final token = license?.offlineToken;
      final installationId = license?.installationId;
      if (token == null ||
          token.isEmpty ||
          installationId == null ||
          installationId.isEmpty) {
        return null;
      }

      final endpoint = await _controlCenterEndpoint();
      final channel = await obtenerCanalConfigurado();
      final uri =
          Uri.parse(
            ControlCenterEndpoint.buildUrl(endpoint, 'updates/check'),
          ).replace(
            queryParameters: {
              'version': AppVersion.version,
              'canal': channel.name,
              'installationId': installationId,
            },
          );
      final response = await _dio.getUri<Map<String, dynamic>>(
        uri,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data;
      if (data == null || data['disponible'] != true) return null;
      final manifest = data['manifest_token']?.toString();
      if (manifest == null || manifest.isEmpty) return null;

      final payload = LicenseValidationService().validatePublisherToken(
        manifest,
        kind: 'merkaerp-update',
        installationId: installationId,
      );
      final update = payload?['update'];
      if (update is! Map) return null;
      final json = Map<String, dynamic>.from(update);
      json['manifest_token'] = manifest;
      final info = InfoVersion.fromJson(json);
      if (!info.esMayorQue(AppVersion.version) ||
          !_secureDownloadUrl(info.urlDescarga)) {
        return null;
      }

      final ignored = await _ignoredVersion();
      if (!info.obligatoria && ignored == info.version) return null;
      return info;
    } catch (e) {
      debugPrint('Revisión de actualización omitida de forma segura: $e');
      return null;
    } finally {
      await _registrarUltimaRevision();
    }
  }

  Future<String> descargarActualizacion(
    InfoVersion version, {
    void Function(ProgresoDescarga)? onProgreso,
  }) async {
    if (_progresoActual?.estado == EstadoDescarga.descargando) {
      throw Exception('Ya hay una descarga en progreso');
    }
    await _requireValidManifest(version);

    if (onProgreso != null) {
      _listeners.add(onProgreso);
    }

    _cancelToken = CancelToken();
    _progresoActual = ProgresoDescarga(
      estado: EstadoDescarga.descargando,
      totalBytes: version.tamanoBytes,
    );

    try {
      final directorioDescargas = await _obtenerDirectorioDescargas();
      final archivoDestino = File(
        p.join(
          directorioDescargas.path,
          'merkaerp_update_${version.version}.exe',
        ),
      );

      if (await archivoDestino.exists()) {
        await archivoDestino.delete();
      }

      await _dio.download(
        version.urlDescarga,
        archivoDestino.path,
        cancelToken: _cancelToken,
        onReceiveProgress: (recibidos, total) {
          final porcentaje = total > 0 ? (recibidos / total) * 100 : 0.0;
          _progresoActual = _progresoActual!.copyWith(
            bytesDescargados: recibidos,
            porcentaje: porcentaje,
          );
          _notificarListeners();
        },
      );

      if (await archivoDestino.exists()) {
        final hash = await _calcularSha256(archivoDestino);
        if (hash.toLowerCase() != version.sha256.toLowerCase()) {
          await archivoDestino.delete();
          throw Exception('Hash SHA256 no coincide. Descarga corrupta.');
        }

        _progresoActual = _progresoActual!.copyWith(
          estado: EstadoDescarga.completado,
          porcentaje: 100.0,
        );
        _notificarListeners();

        final manifest = version.manifestToken;
        if (manifest == null || manifest.isEmpty) {
          await archivoDestino.delete();
          throw StateError(
            'El paquete descargado no tiene manifiesto firmado.',
          );
        }
        await File(
          '${archivoDestino.path}.manifest',
        ).writeAsString(manifest, flush: true);

        await DatabaseHelper.instance.registrarEventoAuditoria(
          accion: 'UPDATE_DESCARGA_COMPLETADA',
          entidad: 'update_service',
          detalle: 'Versión: ${version.version}; sha256=$hash',
        );
        return archivoDestino.path;
      }
      throw StateError('El instalador descargado no quedó disponible.');
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _progresoActual = _progresoActual!.copyWith(
          estado: EstadoDescarga.pausado,
        );
      } else {
        _progresoActual = _progresoActual!.copyWith(
          estado: EstadoDescarga.error,
          error: e.toString(),
        );
      }
      _notificarListeners();
      rethrow;
    } finally {
      _cancelToken = null;
    }
  }

  Future<void> pausarDescarga() async {
    _cancelToken?.cancel();
  }

  Future<void> aplicarActualizacion(String rutaInstalador) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'La aplicación automática de instaladores está habilitada únicamente para Windows.',
      );
    }
    final installer = File(rutaInstalador);
    final manifestFile = File('$rutaInstalador.manifest');
    if (!await installer.exists() || !await manifestFile.exists()) {
      throw StateError('Instalador o manifiesto firmado no disponible.');
    }

    final license = await LicenciaService.instance.obtenerLicencia();
    final installationId = license?.installationId;
    if (installationId == null || installationId.isEmpty) {
      throw StateError(
        'No existe identidad de instalación para validar la actualización.',
      );
    }
    final manifest = await manifestFile.readAsString();
    final payload = LicenseValidationService().validatePublisherToken(
      manifest,
      kind: 'merkaerp-update',
      installationId: installationId,
    );
    final update = payload?['update'];
    if (update is! Map) {
      throw StateError('Manifiesto de actualización inválido o expirado.');
    }
    final info = InfoVersion.fromJson(Map<String, dynamic>.from(update));
    if (!info.esMayorQue(AppVersion.version)) {
      throw StateError(
        'El paquete no representa una versión posterior a la instalada.',
      );
    }
    final hash = await _calcularSha256(installer);
    if (hash.toLowerCase() != info.sha256.toLowerCase()) {
      throw StateError('El instalador cambió después de su verificación.');
    }

    final backup = await FullBackupService.instance.createFullBackup(
      label: 'merkaerp_preupdate_${info.version.replaceAll('.', '_')}',
    );
    final backupHash = await _calcularSha256(backup);
    await _recordPreUpdateRollbackSnapshot(info, backup, backupHash);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'UPDATE_INSTALADOR_VERIFICADO',
      entidad: 'update_service',
      detalle:
          'version=${info.version}; backup=${backup.path}; sha256=$hash; backup_sha256=$backupHash',
    );

    await Process.start(
      installer.path,
      const [],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }

  Future<void> ignorarVersion(String version) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': _claveConfigVersionIgnorada,
      'valor': version,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> rollbackForzado() async {
    throw StateError(
      'Rollback remoto deshabilitado hasta contar con paquetes firmados y un mecanismo local de restauración verificado.',
    );
  }

  Future<void> _recordPreUpdateRollbackSnapshot(
    InfoVersion info,
    File backup,
    String backupSha256,
  ) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': rollbackSnapshotConfigKey,
      'valor': jsonEncode({
        'format': 'MERKAERP_UPDATE_ROLLBACK_SNAPSHOT_1',
        'from_version': AppVersion.version,
        'to_version': info.version,
        'channel': info.canal.name,
        'backup_ref': p.basename(backup.path),
        'backup_sha256': backupSha256.toLowerCase(),
        'installer_sha256': info.sha256.toLowerCase(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void agregarListener(void Function(ProgresoDescarga) listener) {
    _listeners.add(listener);
  }

  void removerListener(void Function(ProgresoDescarga) listener) {
    _listeners.remove(listener);
  }

  void _notificarListeners() {
    for (final listener in _listeners) {
      listener(_progresoActual!);
    }
  }

  Future<Directory> _obtenerDirectorioDescargas() async {
    final directorio = await getApplicationDocumentsDirectory();
    final dirDescargas = Directory(
      p.join(directorio.path, 'merkaerp', 'updates'),
    );
    if (!await dirDescargas.exists()) {
      await dirDescargas.create(recursive: true);
    }
    return dirDescargas;
  }

  Future<String> _calcularSha256(File archivo) async {
    final digest = await sha256.bind(archivo.openRead()).first;
    return digest.toString();
  }

  Future<void> _requireValidManifest(InfoVersion version) async {
    final manifest = version.manifestToken;
    final license = await LicenciaService.instance.obtenerLicencia();
    final installationId = license?.installationId;
    if (manifest == null ||
        manifest.isEmpty ||
        installationId == null ||
        installationId.isEmpty) {
      throw StateError(
        'Actualización sin manifiesto firmado para esta instalación.',
      );
    }
    final payload = LicenseValidationService().validatePublisherToken(
      manifest,
      kind: 'merkaerp-update',
      installationId: installationId,
    );
    final update = payload?['update'];
    if (update is! Map) {
      throw StateError('Manifiesto de actualización inválido o expirado.');
    }
    final signed = InfoVersion.fromJson(Map<String, dynamic>.from(update));
    if (signed.version != version.version ||
        signed.sha256.toLowerCase() != version.sha256.toLowerCase() ||
        signed.urlDescarga != version.urlDescarga ||
        signed.tamanoBytes != version.tamanoBytes ||
        !_secureDownloadUrl(signed.urlDescarga)) {
      throw StateError(
        'Los metadatos de la descarga no coinciden con el manifiesto firmado.',
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

  Future<String> _controlCenterEndpoint() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: ['control_center_endpoint'],
      limit: 1,
    );
    return ControlCenterEndpoint.normalize(
      rows.isEmpty ? null : rows.first['valor']?.toString(),
    );
  }

  Future<String?> _ignoredVersion() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [_claveConfigVersionIgnorada],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['valor']?.toString();
  }

  Future<void> _registrarUltimaRevision() async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': _claveConfigUltimaRevision,
      'valor': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DateTime?> obtenerUltimaRevision() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: [_claveConfigUltimaRevision],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final valor = rows.first['valor']?.toString();
    return valor != null ? DateTime.tryParse(valor) : null;
  }

  Future<void> limpiarDescargasAntiguas() async {
    try {
      final directorio = await _obtenerDirectorioDescargas();
      final archivos = directorio.listSync().whereType<File>().toList();

      final ahora = DateTime.now();
      for (final archivo in archivos) {
        final modificado = await archivo.lastModified();
        final dias = ahora.difference(modificado).inDays;
        if (dias > 7) {
          await archivo.delete();
        }
      }
    } catch (e) {
      debugPrint('Error al limpiar descargas antiguas: $e');
    }
  }
}
