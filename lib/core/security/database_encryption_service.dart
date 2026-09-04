// ============================================================
// database_encryption_service.dart
// Gestión de material criptográfico para una futura integración SQLCipher.
//
// IMPORTANTE: sqflite/sqflite_common_ffi abre actualmente SQLite estándar.
// Este servicio NO afirma que el archivo .db esté cifrado. Hasta conectar un
// motor SQLCipher/SQLite3MC soportado en todas las plataformas objetivo,
// `isDatabaseEncrypted()` devuelve false de forma deliberada (fail-closed).
// ============================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DatabaseEncryptionService {
  static final DatabaseEncryptionService instance =
      DatabaseEncryptionService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _encryptionKey = 'db_encryption_key';
  static const String _encryptionSalt = 'db_encryption_salt';
  static const int _keyIterations = 120000;
  static const int _keyLength = 32;

  DatabaseEncryptionService._internal();

  /// PBKDF2-HMAC-SHA256 estándar. Reutiliza el salt almacenado al verificar;
  /// nunca genera silenciosamente un salt nuevo para una clave existente.
  Future<String> deriveKeyFromPassword(String password, {String? salt}) async {
    if (password.isEmpty) {
      throw ArgumentError('La contraseña de derivación no puede estar vacía.');
    }

    var effectiveSalt = salt;
    if (effectiveSalt == null) {
      effectiveSalt = await _secureStorage.read(key: _encryptionSalt);
      if (effectiveSalt == null || effectiveSalt.isEmpty) {
        effectiveSalt = _generateSalt();
        await _secureStorage.write(
          key: _encryptionSalt,
          value: effectiveSalt,
        );
      }
    }

    final key = _pbkdf2(
      utf8.encode(password),
      base64.decode(effectiveSalt),
      iterations: _keyIterations,
      keyLength: _keyLength,
    );
    return base64.encode(key);
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64.encode(bytes);
  }

  Uint8List _pbkdf2(
    List<int> password,
    List<int> salt, {
    required int iterations,
    required int keyLength,
  }) {
    if (iterations <= 0 || keyLength <= 0) {
      throw ArgumentError('Parámetros PBKDF2 inválidos.');
    }
    final prf = Hmac(sha256, password);
    const hashLength = 32;
    final blocks = (keyLength + hashLength - 1) ~/ hashLength;
    final output = BytesBuilder(copy: false);

    for (var block = 1; block <= blocks; block++) {
      final suffix = <int>[
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = prf.convert(<int>[...salt, ...suffix]).bytes;
      final t = Uint8List.fromList(u);
      for (var round = 1; round < iterations; round++) {
        u = prf.convert(u).bytes;
        for (var i = 0; i < hashLength; i++) {
          t[i] ^= u[i];
        }
      }
      output.add(t);
    }

    return Uint8List.fromList(output.takeBytes().take(keyLength).toList());
  }

  /// El motor actual es SQLite estándar, por lo tanto el archivo NO está
  /// cifrado aunque exista material de clave preparado en Secure Storage.
  Future<bool> isDatabaseEncrypted() async => false;

  Future<bool> isKeyMaterialProvisioned() async {
    final key = await _secureStorage.read(key: _encryptionKey);
    final salt = await _secureStorage.read(key: _encryptionSalt);
    return key != null && key.isNotEmpty && salt != null && salt.isNotEmpty;
  }

  Future<String?> getStoredKey() =>
      _secureStorage.read(key: _encryptionKey);

  Future<void> storeKey(String key) async {
    if (key.trim().isEmpty) {
      throw ArgumentError('La clave no puede estar vacía.');
    }
    await _secureStorage.write(key: _encryptionKey, value: key.trim());
  }

  Future<void> removeKey() async {
    await _secureStorage.delete(key: _encryptionKey);
    await _secureStorage.delete(key: _encryptionSalt);
  }

  /// Prepara material criptográfico, pero NO cifra el SQLite actual.
  /// El nombre se conserva por compatibilidad de API.
  Future<String> initializeEncryption(String password) async {
    final existingKey = await getStoredKey();
    if (existingKey != null && existingKey.isNotEmpty) {
      final testKey = await deriveKeyFromPassword(password);
      if (!_constantTimeEquals(testKey, existingKey)) {
        throw Exception('Contraseña incorrecta');
      }
      return existingKey;
    }

    final newKey = await deriveKeyFromPassword(password);
    await storeKey(newKey);
    return newKey;
  }

  Future<String> changePassword(String oldPassword, String newPassword) async {
    final existingKey = await getStoredKey();
    if (existingKey == null || existingKey.isEmpty) {
      throw Exception('No hay material criptográfico preparado');
    }

    final oldKey = await deriveKeyFromPassword(oldPassword);
    if (!_constantTimeEquals(oldKey, existingKey)) {
      throw Exception('Contraseña antigua incorrecta');
    }

    // Rotar también el salt para la nueva contraseña.
    await _secureStorage.delete(key: _encryptionSalt);
    final newKey = await deriveKeyFromPassword(newPassword);
    await storeKey(newKey);
    return newKey;
  }

  Future<String> generateRandomKey() async {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64.encode(keyBytes);
    await storeKey(key);
    return key;
  }

  Future<bool> verifyKeyIntegrity(String key) async {
    final storedKey = await getStoredKey();
    return storedKey != null && _constantTimeEquals(storedKey, key);
  }

  Future<Map<String, dynamic>> getEncryptionStatus() async {
    final prepared = await isKeyMaterialProvisioned();
    return {
      'encrypted': false,
      'key_material_provisioned': prepared,
      'engine': 'sqlite-plaintext',
      'required_engine': 'SQLCipher/SQLite3MC',
      'key_iterations': _keyIterations,
      'key_length': _keyLength,
      'key_derivation': 'PBKDF2-HMAC-SHA256',
      'warning':
          'La base SQLite activa no está cifrada en reposo hasta integrar un motor compatible.',
    };
  }

  Future<void> resetEncryption() => removeKey();

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
