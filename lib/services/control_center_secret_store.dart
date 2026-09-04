import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../db_helper.dart';

/// Almacena secretos del Control Center fuera de SQLite.
///
/// Si encuentra valores heredados en app_config los migra una sola vez al
/// almacén seguro y elimina la copia en texto plano.
class ControlCenterSecretStore {
  ControlCenterSecretStore._();

  static final ControlCenterSecretStore instance = ControlCenterSecretStore._();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _commandSecretKey = 'merka_cc_command_hmac_secret';
  static const String _syncTokenKey = 'merka_cc_sync_auth_token';

  String? _commandSecretOverrideForTests;

  /// Test seam: lets unit tests exercise signed remote commands without
  /// depending on an OS keychain/credential manager. Production code never
  /// sets this value. Pass null in tearDown to restore the real secure store.
  void configureCommandSecretForTests(String? value) {
    _commandSecretOverrideForTests = value;
  }

  Future<String?> readCommandSecret() {
    final testValue = _commandSecretOverrideForTests;
    if (testValue != null) return Future<String?>.value(testValue);
    return _readAndMigrate(
      secureKey: _commandSecretKey,
      legacyConfigKey: 'control_center_hmac_secret',
    );
  }

  Future<void> writeCommandSecret(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('El secreto HMAC no puede estar vacío.');
    }
    await _storage.write(key: _commandSecretKey, value: normalized);
    await _deleteLegacy('control_center_hmac_secret');
  }

  Future<String?> readSyncToken() => _readAndMigrate(
        secureKey: _syncTokenKey,
        legacyConfigKey: 'sync_auth_token',
      );

  Future<void> writeSyncToken(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await deleteSyncToken();
      return;
    }
    await _storage.write(key: _syncTokenKey, value: normalized);
    await _deleteLegacy('sync_auth_token');
  }

  Future<void> deleteSyncToken() async {
    await _storage.delete(key: _syncTokenKey);
    await _deleteLegacy('sync_auth_token');
  }

  Future<String?> _readAndMigrate({
    required String secureKey,
    required String legacyConfigKey,
  }) async {
    final secure = await _storage.read(key: secureKey);
    if (secure != null && secure.trim().isNotEmpty) return secure.trim();

    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [legacyConfigKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final legacy = rows.first['valor']?.toString().trim();
    if (legacy == null || legacy.isEmpty) {
      await _deleteLegacy(legacyConfigKey);
      return null;
    }

    // Si el almacén seguro falla, propagamos el error: nunca volvemos a usar
    // SQLite como fallback para secretos.
    await _storage.write(key: secureKey, value: legacy);
    await _deleteLegacy(legacyConfigKey);
    return legacy;
  }

  Future<void> _deleteLegacy(String key) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('app_config', where: 'clave = ?', whereArgs: [key]);
  }
}
