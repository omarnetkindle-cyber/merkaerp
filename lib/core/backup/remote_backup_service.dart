import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import '../../db_helper.dart';
import '../../integrations/application/integration_settings_service.dart';
import '../../integrations/domain/integration_definition.dart';

class RemoteBackupResult {
  const RemoteBackupResult({
    required this.provider,
    required this.remoteObject,
    required this.bytes,
    required this.sha256,
  });

  final String provider;
  final String remoteObject;
  final int bytes;
  final String sha256;
}

class RemoteBackupService {
  RemoteBackupService._();
  static final RemoteBackupService instance = RemoteBackupService._();

  static const _magic = 'MERKABK2';
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _iterations = 150000;

  Future<RemoteBackupResult> uploadBackup(File plainBackup) async {
    if (!await plainBackup.exists()) {
      throw StateError('El respaldo local no existe.');
    }
    final settings = IntegrationSettingsService.instance;
    final definition = IntegrationRegistry.byKey('cloud_backup');
    final profile = await settings.load('cloud_backup');
    if (!profile.enabled) {
      throw StateError('El respaldo remoto no está habilitado en Integraciones.');
    }
    final values = await settings.loadValues(definition);
    _validate(values);

    final passphrase = values['encryption_passphrase']!.trim();
    final encrypted = await encryptFile(plainBackup, passphrase);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final now = DateTime.now().toUtc();
    final objectKey = [
      'merkaerp',
      companyId.toString(),
      now.year.toString(),
      now.month.toString().padLeft(2, '0'),
      '${p.basename(plainBackup.path)}.merkaerp.enc',
    ].join('/');
    final bytes = await encrypted.readAsBytes();
    final provider = values['provider']!.trim().toUpperCase();
    try {
      final remote = switch (provider) {
        'WEBDAV' => await _putWebDav(values, objectKey, bytes),
        'S3_COMPATIBLE' => await _putS3(values, objectKey, bytes),
        'AZURE_BLOB_SAS' => await _putAzureSas(values, objectKey, bytes),
        _ => throw StateError('Proveedor de respaldo remoto no soportado: $provider'),
      };
      final digest = crypto.sha256.convert(bytes).toString();
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'RESPALDO_REMOTO_COMPLETADO',
        entidad: 'backup',
        detalle: '$provider;$remote;bytes=${bytes.length};sha256=$digest',
      );
      return RemoteBackupResult(
        provider: provider,
        remoteObject: remote,
        bytes: bytes.length,
        sha256: digest,
      );
    } finally {
      if (await encrypted.exists()) {
        await encrypted.delete();
      }
    }
  }

  Future<File> encryptFile(File input, String passphrase) async {
    if (passphrase.trim().length < 12) {
      throw StateError('La clave de cifrado del respaldo debe tener al menos 12 caracteres.');
    }
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = _deriveKey(passphrase, salt);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final plain = await input.readAsBytes();
    final ciphertext = cipher.process(plain);
    final envelope = BytesBuilder(copy: false)
      ..add(utf8.encode(_magic))
      ..add(salt)
      ..add(nonce)
      ..add(ciphertext);
    final target = File('${input.path}.merkaerp.enc.tmp');
    await target.writeAsBytes(envelope.takeBytes(), flush: true);
    return target;
  }

  Future<File> decryptFile({
    required File encrypted,
    required String passphrase,
    required String outputPath,
  }) async {
    final envelope = await encrypted.readAsBytes();
    final magicBytes = utf8.encode(_magic);
    final minimum = magicBytes.length + _saltLength + _nonceLength + 16;
    if (envelope.length < minimum ||
        utf8.decode(envelope.sublist(0, magicBytes.length), allowMalformed: true) != _magic) {
      throw StateError('Formato de respaldo cifrado no reconocido.');
    }
    var offset = magicBytes.length;
    final salt = Uint8List.fromList(envelope.sublist(offset, offset + _saltLength));
    offset += _saltLength;
    final nonce = Uint8List.fromList(envelope.sublist(offset, offset + _nonceLength));
    offset += _nonceLength;
    final cipherText = Uint8List.fromList(envelope.sublist(offset));
    final key = _deriveKey(passphrase, salt);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
      final plain = cipher.process(cipherText);
      final output = File(outputPath);
      await output.writeAsBytes(plain, flush: true);
      return output;
    } catch (_) {
      throw StateError('No fue posible autenticar/descifrar el respaldo. Revisa la clave o la integridad del archivo.');
    }
  }

  void _validate(Map<String, String> values) {
    for (final key in ['provider', 'endpoint', 'bucket', 'encryption_passphrase']) {
      if ((values[key] ?? '').trim().isEmpty) {
        throw StateError('Falta configurar $key para respaldo remoto.');
      }
    }
    final endpoint = Uri.tryParse(values['endpoint']!.trim());
    if (endpoint == null || !endpoint.hasAuthority || endpoint.userInfo.isNotEmpty) {
      throw StateError('Endpoint de respaldo inválido.');
    }
    final local = const {'localhost', '127.0.0.1', '::1'}.contains(endpoint.host.toLowerCase());
    if (endpoint.scheme.toLowerCase() != 'https' && !(local && endpoint.scheme.toLowerCase() == 'http')) {
      throw StateError('El respaldo remoto exige HTTPS salvo en localhost.');
    }
    final provider = values['provider']!.trim().toUpperCase();
    if ((provider == 'WEBDAV' || provider == 'S3_COMPATIBLE') &&
        ((values['access_key'] ?? '').trim().isEmpty || (values['secret_key'] ?? '').trim().isEmpty)) {
      throw StateError('El proveedor seleccionado requiere usuario/access key y contraseña/secret key.');
    }
    if (provider == 'AZURE_BLOB_SAS' && (values['sas_token'] ?? '').trim().isEmpty) {
      throw StateError('Azure Blob requiere un SAS limitado al contenedor.');
    }
  }

  Future<String> _putWebDav(Map<String, String> v, String objectKey, Uint8List bytes) async {
    final bucket = v['bucket']!.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final relative = [bucket, ...objectKey.split('/')]
        .where((e) => e.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final uri = _resolve(v['endpoint']!, relative);
    final credential = base64Encode(utf8.encode('${v['access_key']}:${v['secret_key']}'));
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Basic $credential',
        'Content-Type': 'application/octet-stream',
        'Content-Length': bytes.length.toString(),
      },
      body: bytes,
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('WebDAV rechazó el respaldo (HTTP ${response.statusCode}).');
    }
    return uri.toString();
  }

  Future<String> _putAzureSas(Map<String, String> v, String objectKey, Uint8List bytes) async {
    final container = v['bucket']!.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final relative = [container, ...objectKey.split('/')]
        .where((e) => e.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final base = _resolve(v['endpoint']!, relative);
    final token = v['sas_token']!.trim().replaceFirst(RegExp(r'^\?'), '');
    final sas = Uri.splitQueryString(token);
    final uri = base.replace(queryParameters: {...base.queryParameters, ...sas});
    final response = await http.put(
      uri,
      headers: {
        'x-ms-blob-type': 'BlockBlob',
        'Content-Type': 'application/octet-stream',
        'Content-Length': bytes.length.toString(),
      },
      body: bytes,
    ).timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Azure Blob rechazó el respaldo (HTTP ${response.statusCode}).');
    }
    return base.toString();
  }

  Future<String> _putS3(Map<String, String> v, String objectKey, Uint8List bytes) async {
    final bucket = v['bucket']!.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final relative = [bucket, ...objectKey.split('/')]
        .where((e) => e.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final uri = _resolve(v['endpoint']!, relative);
    final region = (v['region'] ?? '').trim().isEmpty ? 'us-east-1' : v['region']!.trim();
    final accessKey = v['access_key']!.trim();
    final secretKey = v['secret_key']!.trim();
    final sessionToken = (v['session_token'] ?? '').trim();
    final now = DateTime.now().toUtc();
    final amzDate = _amzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final payloadHash = crypto.sha256.convert(bytes).toString();
    final canonicalHeadersMap = <String, String>{
      'host': uri.hasPort ? '${uri.host}:${uri.port}' : uri.host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      if (sessionToken.isNotEmpty) 'x-amz-security-token': sessionToken,
    };
    final sortedKeys = canonicalHeadersMap.keys.toList()..sort();
    final canonicalHeaders = sortedKeys
        .map((k) => '$k:${canonicalHeadersMap[k]!.trim()}\n')
        .join();
    final signedHeaders = sortedKeys.join(';');
    final canonicalQuery = _canonicalQuery(uri.queryParametersAll);
    final canonicalRequest = [
      'PUT',
      uri.path.isEmpty ? '/' : uri.path,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    final scope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      crypto.sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final signingKey = _awsSigningKey(secretKey, dateStamp, region);
    final signature = _hmacHex(signingKey, stringToSign);
    final authorization =
        'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
    final requestHeaders = <String, String>{
      'Authorization': authorization,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      if (sessionToken.isNotEmpty) 'x-amz-security-token': sessionToken,
      'Content-Type': 'application/octet-stream',
      'Content-Length': bytes.length.toString(),
    };
    final response = await http
        .put(uri, headers: requestHeaders, body: bytes)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('S3 rechazó el respaldo (HTTP ${response.statusCode}).');
    }
    return uri.toString();
  }

  Uri _resolve(String rawBase, String relative) {
    final base = Uri.parse(rawBase.trim());
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '$basePath$relative'.replaceAll(RegExp(r'/{2,}'), '/'));
  }

  String _canonicalQuery(Map<String, List<String>> params) {
    final pairs = <String>[];
    final keys = params.keys.toList()..sort();
    for (final key in keys) {
      final values = [...params[key]!]..sort();
      for (final value in values) {
        pairs.add('${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}');
      }
    }
    return pairs.join('&');
  }

  String _amzDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$year${two(value.month)}${two(value.day)}T${two(value.hour)}${two(value.minute)}${two(value.second)}Z';
  }

  Uint8List _awsSigningKey(String secret, String dateStamp, String region) {
    final kDate = _hmac(Uint8List.fromList(utf8.encode('AWS4$secret')), dateStamp);
    final kRegion = _hmac(kDate, region);
    final kService = _hmac(kRegion, 's3');
    return _hmac(kService, 'aws4_request');
  }

  Uint8List _hmac(Uint8List key, String value) => Uint8List.fromList(
        crypto.Hmac(crypto.sha256, key).convert(utf8.encode(value)).bytes,
      );

  String _hmacHex(Uint8List key, String value) =>
      crypto.Hmac(crypto.sha256, key).convert(utf8.encode(value)).toString();

  Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
