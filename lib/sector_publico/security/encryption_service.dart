/// Servicio de Encriptación AES-256
/// Encriptación de datos sensibles en reposo
/// 
/// ESTRATEGIA DE GESTIÓN DE CLAVES:
/// - La clave maestra se almacena en FlutterSecureStorage (keystore del sistema operativo)
/// - iOS: Keychain con kSecAttrAccessibleWhenUnlocked
/// - Android: Keystore con KeyStore.getInstance("AndroidKeyStore")
/// - La clave nunca se hardcodea ni se almacena en la base de datos
/// 
/// ESTRATEGIA DE ROTACIÓN DE CLAVE:
/// - La rotación automática está deshabilitada hasta disponer de una migración
///   transaccional que re-encripte y verifique todos los registros.
/// - Nunca se reemplaza la clave maestra si eso puede dejar ciphertext legado
///   sin una ruta verificable de recuperación.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';
import 'auditoria_service.dart';

enum TipoDatoSensible {
  terceroIdentificacion,
  terceroDireccion,
  terceroTelefono,
  terceroEmail,
  cuentaBancaria,
  nominaSalario,
  nominaCuentaBancaria,
  otro,
}

class EncryptionService {
  final FlutterSecureStorage _secureStorage;
  final AuditoriaService? auditoriaService;
  
  // Clave maestra encriptada almacenada en secure storage
  static const String _claveMaestraKey = 'encryption_master_key';
  static const String _ivKey = 'encryption_iv';
  static const String _rotacionTimestampKey = 'encryption_rotation_timestamp';

  EncryptionService({
    FlutterSecureStorage? secureStorage,
    this.auditoriaService,
  }) : _secureStorage = secureStorage ?? FlutterSecureStorage();

  /// Inicializa el servicio de encriptación
  Future<void> inicializar() async {
    final claveMaestra = await _secureStorage.read(key: _claveMaestraKey);
    final legacyIv = await _secureStorage.read(key: _ivKey);
    final rotationTimestamp = await _secureStorage.read(
      key: _rotacionTimestampKey,
    );

    if (claveMaestra == null) {
      await _secureStorage.write(
        key: _claveMaestraKey,
        value: _generarClaveAleatoria(),
      );
    }
    // El IV global se conserva únicamente para descifrar sobres legacy.
    if (legacyIv == null) {
      await _secureStorage.write(key: _ivKey, value: _generarIV());
    }
    if (rotationTimestamp == null) {
      await _secureStorage.write(
        key: _rotacionTimestampKey,
        value: DateTime.now().toIso8601String(),
      );
    }
  }

  /// Rotación de clave maestra.
  ///
  /// FAIL-CLOSED: una rotación segura exige re-encriptar todos los registros en
  /// una transacción recuperable y verificar cada ciphertext antes de retirar
  /// la clave anterior. La implementación histórica cambiaba la clave sin hacer
  /// esa migración y podía volver ilegibles los datos, por lo que se bloquea.
  Future<void> rotarClaveMaestra({
    required String entidadId,
    required String usuarioId,
  }) async {
    throw UnsupportedError(
      'Rotación de clave deshabilitada: requiere una migración transaccional de todos los datos cifrados antes de cambiar la clave maestra.',
    );
  }

  /// Obtiene la fecha de la última rotación de clave
  Future<DateTime?> obtenerFechaUltimaRotacion() async {
    final timestamp = await _secureStorage.read(key: _rotacionTimestampKey);
    if (timestamp == null) return null;
    return DateTime.parse(timestamp);
  }

  /// Verifica si es necesario rotar la clave (recomendado: 1 año)
  Future<bool> requiereRotacion({Duration periodoRotacion = const Duration(days: 365)}) async {
    final ultimaRotacion = await obtenerFechaUltimaRotacion();
    if (ultimaRotacion == null) return false;
    
    final tiempoDesdeRotacion = DateTime.now().difference(ultimaRotacion);
    return tiempoDesdeRotacion >= periodoRotacion;
  }

  /// Encripta un dato sensible.
  ///
  /// Los registros nuevos usan un IV aleatorio por dato y Encrypt-then-MAC
  /// (AES-256-CBC + HMAC-SHA256). El formato legacy continúa siendo legible
  /// para no romper bases existentes.
  Future<String> encriptar({
    required String dato,
    required TipoDatoSensible tipo,
    required String referenciaId,
  }) async {
    final claveMaestra = await _obtenerClaveMaestra();
    final iv = _generarIVBytes();
    final datos = Uint8List.fromList(utf8.encode(dato));
    final encriptado = _encriptarAES256(datos, claveMaestra, iv);
    final tag = _calcularHmac(claveMaestra, iv, encriptado);

    final resultado = {
      'version': 2,
      'algoritmo': 'AES-256-CBC-HMAC-SHA256',
      'iv': base64.encode(iv),
      'dato': base64.encode(encriptado),
      'tag': base64.encode(tag),
      'metadatos': {
        'tipo': tipo.toString(),
        'referencia_id': referenciaId,
        'timestamp': DateTime.now().toIso8601String(),
      },
    };
    return jsonEncode(resultado);
  }

  /// Desencripta un dato sensible. Verifica autenticidad antes de descifrar los
  /// sobres v2; los sobres legacy sin versión se leen con el IV histórico.
  Future<String> desencriptar(String datoEncriptado) async {
    final claveMaestra = await _obtenerClaveMaestra();
    final decoded = jsonDecode(datoEncriptado);
    if (decoded is! Map) throw const FormatException('Sobre cifrado inválido');
    final datos = Map<String, dynamic>.from(decoded);

    final ciphertextText = datos['dato']?.toString();
    if (ciphertextText == null || ciphertextText.isEmpty) {
      throw const FormatException('Ciphertext ausente');
    }
    final ciphertext = Uint8List.fromList(base64.decode(ciphertextText));

    if (datos['version'] == 2) {
      final ivText = datos['iv']?.toString();
      final tagText = datos['tag']?.toString();
      if (ivText == null || tagText == null) {
        throw const FormatException('Sobre cifrado v2 incompleto');
      }
      final iv = Uint8List.fromList(base64.decode(ivText));
      final tag = Uint8List.fromList(base64.decode(tagText));
      if (iv.length != 16 || tag.length != 32) {
        throw const FormatException('Parámetros criptográficos inválidos');
      }
      final expectedTag = _calcularHmac(claveMaestra, iv, ciphertext);
      if (!_constantTimeEquals(tag, expectedTag)) {
        throw StateError('Integridad del dato cifrado no válida');
      }
      final plain = _desencriptarAES256(ciphertext, claveMaestra, iv);
      return utf8.decode(plain);
    }

    // Compatibilidad de solo lectura con sobres legacy (CBC + IV global).
    final legacyIv = await _obtenerIV();
    final plain = _desencriptarAES256(ciphertext, claveMaestra, legacyIv);
    return utf8.decode(plain);
  }

  /// Encripta datos de tercero
  Future<Map<String, String>> encriptarDatosTercero({
    required String terceroId,
    required String identificacion,
    required String direccion,
    required String telefono,
    String? email,
  }) async {
    return {
      'identificacion': await encriptar(
        dato: identificacion,
        tipo: TipoDatoSensible.terceroIdentificacion,
        referenciaId: terceroId,
      ),
      'direccion': await encriptar(
        dato: direccion,
        tipo: TipoDatoSensible.terceroDireccion,
        referenciaId: terceroId,
      ),
      'telefono': await encriptar(
        dato: telefono,
        tipo: TipoDatoSensible.terceroTelefono,
        referenciaId: terceroId,
      ),
      if (email != null) 'email': await encriptar(
        dato: email,
        tipo: TipoDatoSensible.terceroEmail,
        referenciaId: terceroId,
      ),
    };
  }

  /// Desencripta datos de tercero
  Future<Map<String, String>> desencriptarDatosTercero(
    Map<String, String> datosEncriptados,
  ) async {
    final resultado = <String, String>{};
    
    for (final entry in datosEncriptados.entries) {
      resultado[entry.key] = await desencriptar(entry.value);
    }
    
    return resultado;
  }

  /// Encripta datos de nómina
  Future<Map<String, String>> encriptarDatosNomina({
    required String empleadoId,
    required double salario,
    required String cuentaBancaria,
  }) async {
    return {
      'salario': await encriptar(
        dato: salario.toString(),
        tipo: TipoDatoSensible.nominaSalario,
        referenciaId: empleadoId,
      ),
      'cuenta_bancaria': await encriptar(
        dato: cuentaBancaria,
        tipo: TipoDatoSensible.nominaCuentaBancaria,
        referenciaId: empleadoId,
      ),
    };
  }

  /// Desencripta datos de nómina
  Future<Map<String, String>> desencriptarDatosNomina(
    Map<String, String> datosEncriptados,
  ) async {
    final resultado = <String, String>{};
    
    for (final entry in datosEncriptados.entries) {
      resultado[entry.key] = await desencriptar(entry.value);
    }
    
    return resultado;
  }

  /// Encripta cuenta bancaria
  Future<String> encriptarCuentaBancaria({
    required String cuentaId,
    required String numeroCuenta,
  }) async {
    return await encriptar(
      dato: numeroCuenta,
      tipo: TipoDatoSensible.cuentaBancaria,
      referenciaId: cuentaId,
    );
  }

  /// Desencripta cuenta bancaria
  Future<String> desencriptarCuentaBancaria(String cuentaEncriptada) async {
    return await desencriptar(cuentaEncriptada);
  }

  /// Obtiene la clave maestra desde secure storage
  Future<Uint8List> _obtenerClaveMaestra() async {
    final clave = await _secureStorage.read(key: _claveMaestraKey);
    if (clave == null) throw Exception('Clave maestra no encontrada. Inicialice el servicio primero.');
    return base64.decode(clave);
  }

  /// Obtiene el IV desde secure storage
  Future<Uint8List> _obtenerIV() async {
    final iv = await _secureStorage.read(key: _ivKey);
    if (iv == null) throw Exception('IV no encontrado. Inicialice el servicio primero.');
    return base64.decode(iv);
  }

  /// Genera una clave aleatoria de 32 bytes (256 bits)
  String _generarClaveAleatoria() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64.encode(bytes);
  }

  /// Genera un IV aleatorio de 16 bytes.
  Uint8List _generarIVBytes() {
    final random = Random.secure();
    final bytes = Uint8List(16);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  String _generarIV() => base64.encode(_generarIVBytes());

  Uint8List _calcularHmac(
    Uint8List clave,
    Uint8List iv,
    Uint8List ciphertext,
  ) {
    // Separación de clave mediante un contexto fijo antes de autenticar el
    // IV+ciphertext. No se reutiliza directamente la clave AES como clave MAC.
    final macKey = Hmac(sha256, clave)
        .convert(utf8.encode('MerkaERP-AES-CBC-HMAC-v2'))
        .bytes;
    final payload = <int>[...iv, ...ciphertext];
    return Uint8List.fromList(Hmac(sha256, macKey).convert(payload).bytes);
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Encripta usando AES-256-CBC
  Uint8List _encriptarAES256(Uint8List datos, Uint8List clave, Uint8List iv) {
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        ParametersWithIV<KeyParameter>(KeyParameter(clave), iv),
      );

    return cipher.process(datos);
  }

  /// Desencripta usando AES-256-CBC
  Uint8List _desencriptarAES256(Uint8List datos, Uint8List clave, Uint8List iv) {
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        false,
        ParametersWithIV<KeyParameter>(KeyParameter(clave), iv),
      );

    return cipher.process(datos);
  }
}
