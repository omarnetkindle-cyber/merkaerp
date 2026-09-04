import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../db_helper.dart';
import 'control_center_endpoint.dart';
import 'control_center_secret_store.dart';
import 'licencia_service.dart';

enum SyncStatus { idle, syncing, offline, error, conflict }

class SyncEvent {
  final String eventId;
  final String table;
  final String operation; // insert, update, delete
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final bool processed;

  SyncEvent({
    required this.eventId,
    required this.table,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.processed = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'table': table,
      'operation': operation,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'processed': processed ? 1 : 0,
    };
  }

  factory SyncEvent.fromMap(Map<String, dynamic> map) {
    return SyncEvent(
      eventId: map['eventId'] as String,
      table: map['table'] as String,
      operation: map['operation'] as String,
      data: jsonDecode(map['data'] as String),
      timestamp: DateTime.parse(map['timestamp'] as String),
      processed: (map['processed'] as int) == 1,
    );
  }
}

class SyncConflict {
  final int id;
  final String table;
  final String recordId;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime createdAt;
  bool resolved;
  String? resolution;
  Map<String, dynamic>? resolvedData;

  SyncConflict({
    required this.id,
    required this.table,
    required this.recordId,
    required this.localData,
    required this.remoteData,
    required this.createdAt,
    this.resolved = false,
    this.resolution,
    this.resolvedData,
  });
}

class SyncService {
  static const Set<String> _allowedRemoteTables = {
    'productos',
    'clientes',
    'ventas',
    'venta_items',
  };
  static const Set<String> _allowedRemoteOperations = {
    'insert',
    'update',
    'delete',
  };
  static const String _transportOutboxTable = 'control_center_sync_outbox';
  static const String _transportInboxTable = 'control_center_sync_inbox';
  static const String _transportConflictsTable =
      'control_center_sync_conflicts';

  SyncService._();

  static final SyncService instance = SyncService._();

  SyncStatus _status = SyncStatus.idle;
  Timer? _syncTimer;
  DateTime? _lastSyncTimestamp;
  String? _serverEndpoint;
  String? _installationId;
  String? _userId;
  String? _authToken;

  SyncStatus get status => _status;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;
  bool get isOnline =>
      _status != SyncStatus.offline && _status != SyncStatus.error;

  final List<void Function(SyncStatus)> _statusListeners = [];

  void addStatusListener(void Function(SyncStatus) listener) {
    _statusListeners.add(listener);
  }

  void removeStatusListener(void Function(SyncStatus) listener) {
    _statusListeners.remove(listener);
  }

  void _setStatus(SyncStatus newStatus) {
    _status = newStatus;
    for (final listener in _statusListeners) {
      listener(newStatus);
    }
  }

  Future<void> initialize() async {
    final db = await DatabaseHelper.instance.database;

    // Crear tabla de outbox de sincronización
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_transportOutboxTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT UNIQUE NOT NULL,
        user_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        processed INTEGER DEFAULT 0,
        error TEXT
      )
    ''');

    // Crear tabla de inbox de sincronización
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_transportInboxTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT UNIQUE NOT NULL,
        user_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        applied INTEGER DEFAULT 0
      )
    ''');

    // Crear tabla de conflictos de sincronización
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_transportConflictsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        local_data TEXT NOT NULL,
        remote_data TEXT NOT NULL,
        resolved INTEGER DEFAULT 0,
        resolution TEXT,
        resolved_data TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Obtener configuración del servidor
    await _loadConfiguration();

    // Iniciar sincronización automática
    _startAutoSync();
  }

  Future<void> _loadConfiguration() async {
    final db = await DatabaseHelper.instance.database;
    await LicenciaService.instance.reconciliarIdentidadInstalacionFirmada();
    final license = await LicenciaService.instance.obtenerLicencia();

    // Obtener endpoint del servidor
    final endpointRows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['sync_server_endpoint'],
      limit: 1,
    );
    const legacyEndpoint =
        'https://merkaerp-control-center-backend.onrender.com';
    final configuredEndpoint = endpointRows.isEmpty
        ? null
        : endpointRows.first['valor']?.toString();
    final normalizedEndpoint = ControlCenterEndpoint.normalize(
      configuredEndpoint,
    );
    _serverEndpoint = normalizedEndpoint == legacyEndpoint
        ? ControlCenterEndpoint.defaultEndpoint
        : normalizedEndpoint;
    if (configuredEndpoint != _serverEndpoint) {
      await db.insert('app_config', {
        'clave': 'sync_server_endpoint',
        'valor': _serverEndpoint,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Obtener installation ID
    final installationRows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['control_center_installation_id'],
      limit: 1,
    );
    _installationId = license?.installationId?.trim().isNotEmpty == true
        ? license!.installationId!.trim()
        : installationRows.isEmpty
        ? null
        : installationRows.first['valor']?.toString();

    // Obtener user_id y auth_token
    final userIdRows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['sync_user_id'],
      limit: 1,
    );
    _userId = license?.clientId?.trim().isNotEmpty == true
        ? license!.clientId!.trim()
        : userIdRows.isEmpty
        ? _installationId
        : userIdRows.first['valor']?.toString();

    final licenseToken = license?.offlineToken?.trim();
    _authToken = licenseToken != null && licenseToken.isNotEmpty
        ? licenseToken
        : await ControlCenterSecretStore.instance.readSyncToken();

    // Remote operational replication is intentionally unavailable. The
    // authenticated Control Center channel is push-only in this release: it
    // provides durable off-device transport without mutating operational rows.

    // Obtener último timestamp de sincronización
    final lastSyncRows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['last_sync_timestamp'],
      limit: 1,
    );
    if (lastSyncRows.isNotEmpty) {
      _lastSyncTimestamp = DateTime.tryParse(
        lastSyncRows.first['valor']?.toString() ?? '',
      );
    }
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    // Solo iniciar sincronización automática si hay usuario autenticado
    if (_userId != null && _authToken != null) {
      _syncTimer = Timer.periodic(
        const Duration(minutes: 1), // Cambiado a 1 minuto para pruebas
        (_) => sync(),
      );
    }
  }

  /// Recarga la sesión de transporte desde la licencia firmada. La sesión
  /// local del empleado y su PIN nunca se envían al Control Center.
  Future<void> refreshLicenseSession() async {
    await _loadConfiguration();
    _startAutoSync();
  }

  Future<bool> login(String username, String password) async {
    try {
      final dio = Dio();
      final url = ControlCenterEndpoint.buildUrl(_serverEndpoint, 'auth/login');
      final response = await dio.post(
        url,
        data: {
          'username': username,
          'password': password,
          'deviceInfo': 'MerkaERP Desktop',
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>?;
        if (data == null) return false;

        final token = data['token']?.toString();
        final userData = data['user'] as Map<String, dynamic>?;
        final userId =
            userData?['id']?.toString() ?? data['userId']?.toString();

        if (token == null ||
            token.isEmpty ||
            userId == null ||
            userId.isEmpty) {
          return false;
        }

        _authToken = token;
        _userId = userId;

        // Guardar en base de datos
        final db = await DatabaseHelper.instance.database;
        await db.insert('app_config', {
          'clave': 'sync_user_id',
          'valor': _userId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await ControlCenterSecretStore.instance.writeSyncToken(_authToken!);

        _startAutoSync();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Login error en SyncService: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      if (_authToken != null) {
        final dio = Dio();
        await dio.post(
          ControlCenterEndpoint.buildUrl(_serverEndpoint, 'auth/logout'),
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_authToken',
            },
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    }

    // Limpiar datos locales
    _userId = null;
    _authToken = null;
    stopAutoSync();

    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['sync_user_id'],
    );
    await ControlCenterSecretStore.instance.deleteSyncToken();
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
  }

  Future<void> sync() async {
    if (_status == SyncStatus.syncing) return;

    _setStatus(SyncStatus.syncing);

    try {
      // 1. Convertir la cola histórica de triggers al outbox durable actual.
      await _stageTrackedLocalChanges();

      // 2. Push autenticado y tenant-aware al servidor.
      await _pushChanges();

      // 3. No se aplican eventos remotos sobre tablas operacionales. Los
      // payloads históricos no contienen invariantes suficientes para recrear
      // ventas, Kardex, caja, cartera y contabilidad de forma atómica.

      // 4. Actualizar timestamp de última sincronización
      _lastSyncTimestamp = DateTime.now();
      await _saveLastSyncTimestamp();

      _setStatus(SyncStatus.idle);

      debugPrint('Sync completed successfully');
    } catch (e) {
      debugPrint('Sync error: $e');
      _setStatus(SyncStatus.error);

      // Si es error de conexión, marcar como offline
      if (e is SocketException || e is HttpException) {
        _setStatus(SyncStatus.offline);
      }
    }
  }

  Future<void> _stageTrackedLocalChanges() async {
    if (_userId == null || _installationId == null) return;

    final db = await DatabaseHelper.instance.database;
    // `local_changes` is maintained by the existing DB triggers. Staging an
    // event into sync_outbox is the durability boundary: once inserted there,
    // the legacy row may be marked synced even if the network push fails.
    final rows = await db.query(
      'local_changes',
      where: 'synced = 0',
      orderBy: 'id ASC',
      limit: 1000,
    );
    if (rows.isEmpty) return;

    await db.transaction((txn) async {
      for (final row in rows) {
        final table = row['table_name']?.toString() ?? '';
        final operation = row['operation']?.toString().toLowerCase() ?? '';
        if (!_allowedRemoteTables.contains(table) ||
            !_allowedRemoteOperations.contains(operation)) {
          continue;
        }
        final rawData = row['data']?.toString();
        if (rawData == null || rawData.isEmpty) continue;
        final decoded = jsonDecode(rawData);
        if (decoded is! Map) continue;

        final legacyId = row['id'];
        final eventId = 'lc_${_installationId}_${legacyId ?? row['record_id']}';
        await txn.insert(_transportOutboxTable, {
          'event_id': eventId,
          'user_id': _userId,
          'table_name': table,
          'operation': operation,
          'data': jsonEncode(decoded),
          'timestamp':
              row['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
          'processed': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (legacyId != null) {
          await txn.update(
            'local_changes',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [legacyId],
          );
        }
      }
    });
  }

  Future<void> _pushChanges() async {
    if (_serverEndpoint == null ||
        _installationId == null ||
        _userId == null ||
        _authToken == null) {
      throw Exception('Sync not configured or not authenticated');
    }

    final db = await DatabaseHelper.instance.database;

    // Obtener eventos no procesados
    final pendingEvents = await db.query(
      _transportOutboxTable,
      where: 'processed = 0',
      orderBy: 'timestamp ASC',
    );

    if (pendingEvents.isEmpty) return;

    final events = pendingEvents
        .map(
          (row) => {
            'eventId': row['event_id'] as String,
            'table': row['table_name'] as String,
            'operation': row['operation'] as String,
            'data': jsonDecode(row['data'] as String),
            'timestamp': row['timestamp'] as String,
          },
        )
        .toList();

    // Enviar al servidor con autenticación
    final dio = Dio();
    final response = await dio.post(
      ControlCenterEndpoint.buildUrl(
        _serverEndpoint,
        'installations/sync/push',
      ),
      data: {'installationId': _installationId, 'events': events},
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_authToken',
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    if (response.statusCode == 200) {
      // Marcar eventos como procesados
      for (final event in pendingEvents) {
        await db.update(
          _transportOutboxTable,
          {'processed': 1},
          where: 'id = ?',
          whereArgs: [event['id']],
        );
      }

      debugPrint('Pushed ${events.length} events to server');
    } else {
      throw Exception('Push failed: ${response.statusCode}');
    }
  }

  Future<void> queueEvent(
    String table,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final normalizedOperation = operation.toLowerCase();
    if (!_allowedRemoteTables.contains(table) ||
        !_allowedRemoteOperations.contains(normalizedOperation)) {
      throw ArgumentError(
        'Evento de sincronización no permitido: $table/$operation',
      );
    }
    if (_userId == null) {
      debugPrint('Cannot queue event: user not authenticated');
      return;
    }

    final db = await DatabaseHelper.instance.database;
    final eventId =
        'evt_${DateTime.now().millisecondsSinceEpoch}_${table}_$operation';

    await db.insert(_transportOutboxTable, {
      'event_id': eventId,
      'user_id': _userId,
      'table_name': table,
      'operation': normalizedOperation,
      'data': jsonEncode(data),
      'timestamp': DateTime.now().toIso8601String(),
      'processed': 0,
    });

    debugPrint('Queued sync event: $table $operation');
  }

  Future<void> _saveLastSyncTimestamp() async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': 'last_sync_timestamp',
      'valor': _lastSyncTimestamp?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SyncConflict>> getConflicts() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      _transportConflictsTable,
      where: 'resolved = 0',
      orderBy: 'created_at DESC',
    );

    return rows
        .map(
          (row) => SyncConflict(
            id: row['id'] as int,
            table: row['table_name'] as String,
            recordId: row['record_id'] as String,
            localData: jsonDecode(row['local_data'] as String),
            remoteData: jsonDecode(row['remote_data'] as String),
            createdAt: DateTime.parse(row['created_at'] as String),
            resolved: (row['resolved'] as int) == 1,
            resolution: row['resolution']?.toString(),
            resolvedData: row['resolved_data'] != null
                ? jsonDecode(row['resolved_data'] as String)
                : null,
          ),
        )
        .toList();
  }

  Future<void> resolveConflict(
    int conflictId,
    String resolution,
    Map<String, dynamic> data,
  ) async {
    if (resolution == 'remote') {
      throw UnsupportedError(
        'La aplicación directa de datos remotos está deshabilitada hasta contar con un replicador transaccional de dominio.',
      );
    }
    final db = await DatabaseHelper.instance.database;
    await db.update(
      _transportConflictsTable,
      {
        'resolved': 1,
        'resolution': resolution,
        'resolved_data': jsonEncode(data),
      },
      where: 'id = ?',
      whereArgs: [conflictId],
    );
  }

  Future<void> setServerEndpoint(String endpoint) async {
    final normalizedEndpoint = ControlCenterEndpoint.normalize(endpoint);
    final db = await DatabaseHelper.instance.database;
    await db.insert('app_config', {
      'clave': 'sync_server_endpoint',
      'valor': normalizedEndpoint,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _serverEndpoint = normalizedEndpoint;
  }

  /// Compatibilidad con integraciones antiguas.
  ///
  /// El transporte `/api/v1/sync/push` sin autenticación fue retirado por
  /// seguridad. Cualquier llamador legado se redirige al único canal
  /// autenticado y tenant-aware del servicio actual.
  Future<void> processQueue() async {
    if (_userId == null || _authToken == null || _installationId == null) {
      throw StateError(
        'Sincronización no configurada: autentique el usuario y active una instalación antes de sincronizar.',
      );
    }
    await sync();
  }
}
