import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite/sqflite.dart';

import '../db_helper.dart';

class LicenseSecureStore {
  LicenseSecureStore({FlutterSecureStorage? secureStorage, String? testKey})
    : _secureStorage = secureStorage,
      _testKey = testKey;

  static const encryptedConfigKey = 'licencia_info_encrypted_v1';
  static const legacyConfigKey = 'licencia_info';
  static const _secureKeyName = 'merka_license_store_key_v1';

  final FlutterSecureStorage? _secureStorage;
  final String? _testKey;

  Future<void> write(Map<String, Object?> value) async {
    final db = await DatabaseHelper.instance.database;
    final key = await _loadOrCreateKey();
    final encrypted = _encrypt(jsonEncode(value), key);
    await db.insert('app_config', {
      'clave': encryptedConfigKey,
      'valor': encrypted,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> read() async {
    final db = await DatabaseHelper.instance.database;
    final encrypted = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: [encryptedConfigKey],
      limit: 1,
    );
    if (encrypted.isNotEmpty) {
      final key = await _loadOrCreateKey();
      final rawEnvelope = encrypted.first['valor'] as String;
      final decrypted = _decrypt(rawEnvelope, key);
      final envelope = jsonDecode(rawEnvelope) as Map<String, dynamic>;
      if (envelope['alg'] == 'AES-256-CBC') {
        await db.update(
          'app_config',
          {'valor': _encrypt(decrypted, key)},
          where: 'clave = ?',
          whereArgs: [encryptedConfigKey],
        );
      }
      return jsonDecode(decrypted) as Map<String, dynamic>;
    }

    final legacy = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: [legacyConfigKey],
      limit: 1,
    );
    if (legacy.isEmpty) return null;
    final decoded = jsonDecode(legacy.first['valor'] as String);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  }

  Future<void> delete() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_config',
      where: 'clave IN (?, ?)',
      whereArgs: [encryptedConfigKey, legacyConfigKey],
    );
  }

  Future<Uint8List> _loadOrCreateKey() async {
    if (_testKey != null) {
      return Uint8List.fromList(sha256.convert(utf8.encode(_testKey)).bytes);
    }

    const storage = FlutterSecureStorage();
    final effectiveStorage = _secureStorage ?? storage;
    final existing = await effectiveStorage.read(key: _secureKeyName);
    if (existing != null && existing.isNotEmpty) {
      final decoded = base64Decode(existing);
      if (decoded.length != 32) {
        throw StateError(
          'La clave segura de licencia tiene longitud inválida.',
        );
      }
      return Uint8List.fromList(decoded);
    }
    final generated = _randomBytes(32);
    await effectiveStorage.write(
      key: _secureKeyName,
      value: base64Encode(generated),
    );
    return generated;
  }

  String _encrypt(String plainText, Uint8List key) {
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final encrypted = cipher.process(
      Uint8List.fromList(utf8.encode(plainText)),
    );
    return jsonEncode({
      'v': 2,
      'alg': 'AES-256-GCM',
      'nonce': base64Encode(nonce),
      'data': base64Encode(encrypted),
    });
  }

  String _decrypt(String encryptedJson, Uint8List key) {
    final envelope = jsonDecode(encryptedJson) as Map<String, dynamic>;
    if (envelope['alg'] == 'AES-256-GCM') {
      final nonce = base64Decode(envelope['nonce'] as String);
      final encrypted = base64Decode(envelope['data'] as String);
      try {
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(
              KeyParameter(key),
              128,
              Uint8List.fromList(nonce),
              Uint8List(0),
            ),
          );
        return utf8.decode(cipher.process(Uint8List.fromList(encrypted)));
      } catch (_) {
        throw StateError(
          'La licencia cifrada no superó la verificación de integridad.',
        );
      }
    }
    if (envelope['alg'] != 'AES-256-CBC') {
      throw StateError('Formato de licencia cifrada no soportado');
    }
    return _decryptLegacyCbc(envelope, key);
  }

  String _decryptLegacyCbc(Map<String, dynamic> envelope, Uint8List key) {
    final iv = base64Decode(envelope['iv'] as String);
    final encrypted = base64Decode(envelope['data'] as String);
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
              null,
            ),
          );
    return utf8.decode(cipher.process(Uint8List.fromList(encrypted)));
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
