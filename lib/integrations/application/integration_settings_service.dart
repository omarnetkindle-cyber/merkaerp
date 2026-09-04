import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import '../../services/licencia_service.dart';
import '../../licensing/domain/product_family.dart';
import '../domain/integration_definition.dart';
import '../domain/integration_profile.dart';

class IntegrationSettingsService {
  IntegrationSettingsService._();
  static final IntegrationSettingsService instance = IntegrationSettingsService._();

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  Future<void> createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS integration_profiles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        provider_key TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0,
        config_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'not_configured',
        last_checked_at TEXT,
        last_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, provider_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS integration_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        provider_key TEXT NOT NULL,
        event_type TEXT NOT NULL,
        success INTEGER NOT NULL,
        message TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_integration_profiles_company ON integration_profiles(company_id, provider_key)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_integration_events_company ON integration_events(company_id, created_at)');
    await _migrateLegacyPaymentIntegrations(db);
  }

  Future<void> _migrateLegacyPaymentIntegrations(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'integraciones'",
    );
    if (tables.isEmpty) return;

    final legacyRows = await db.query(
      'integraciones',
      where: "LOWER(tipo) IN ('nequi', 'pse')",
    );
    for (final row in legacyRows) {
      final companyId = (row['company_id'] as num?)?.toInt();
      if (companyId == null || companyId <= 0) continue;
      final provider = row['tipo']?.toString().trim().toLowerCase();
      if (provider != 'nequi' && provider != 'pse') continue;

      Map<String, dynamic> legacy = const {};
      try {
        final decoded = jsonDecode(row['config']?.toString() ?? '{}');
        if (decoded is Map) legacy = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // No se elimina un registro que no se pudo interpretar.
        continue;
      }

      final publicConfig = <String, String>{};
      final secretFields = <String, String>{};
      if (provider == 'nequi') {
        publicConfig['endpoint'] = legacy['endpoint']?.toString() ?? '';
        publicConfig['client_id'] = legacy['client_id']?.toString() ?? '';
        secretFields['api_key'] = legacy['api_key']?.toString() ?? '';
        secretFields['client_secret'] = legacy['client_secret']?.toString() ?? '';
      } else {
        publicConfig['endpoint'] = legacy['endpoint']?.toString() ?? '';
        publicConfig['merchant_id'] = legacy['merchant_id']?.toString() ?? '';
        secretFields['api_key'] = legacy['api_key']?.toString() ?? '';
      }

      try {
        for (final entry in secretFields.entries) {
          if (entry.value.trim().isNotEmpty) {
            await _secure.write(
              key: _secretKey(companyId, provider!, entry.key),
              value: entry.value.trim(),
            );
          }
        }
        final now = DateTime.now().toUtc().toIso8601String();
        await db.insert(
          'integration_profiles',
          {
            'company_id': companyId,
            'provider_key': provider,
            'enabled': row['activo'] == 1 ? 1 : 0,
            'config_json': jsonEncode(publicConfig),
            'status': row['activo'] == 1 ? 'configured' : 'disabled',
            'created_at': row['creado_en']?.toString() ?? now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await db.delete('integraciones', where: 'id = ?', whereArgs: [row['id']]);
      } catch (error) {
        debugPrint('Legacy $provider migration retained source row: $error');
      }
    }
  }

  Future<int> _companyId(DatabaseExecutor db) => DatabaseHelper.instance.obtenerEmpresaActivaId(db);

  String _secretKey(int companyId, String provider, String field) =>
      'merka.integration.v1.$companyId.$provider.$field';

  Future<IntegrationProfile> load(String providerKey) async {
    final db = await DatabaseHelper.instance.database;
    await createTables(db);
    final companyId = await _companyId(db);
    final rows = await db.query(
      'integration_profiles',
      where: 'company_id = ? AND provider_key = ?',
      whereArgs: [companyId, providerKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return IntegrationProfile(
        providerKey: providerKey,
        enabled: false,
        config: const {},
        status: 'not_configured',
      );
    }
    final row = rows.first;
    Map<String, String> config = {};
    try {
      final decoded = jsonDecode(row['config_json']?.toString() ?? '{}');
      if (decoded is Map) {
        config = decoded.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
      }
    } catch (_) {}
    return IntegrationProfile(
      providerKey: providerKey,
      enabled: row['enabled'] == 1,
      config: config,
      status: row['status']?.toString() ?? 'not_configured',
      lastCheckedAt: DateTime.tryParse(row['last_checked_at']?.toString() ?? ''),
      lastMessage: row['last_message']?.toString(),
    );
  }

  Future<Map<String, String>> loadValues(IntegrationDefinition definition) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await _companyId(db);
    final profile = await load(definition.key);
    final values = <String, String>{...profile.config};
    for (final field in definition.fields.where((field) => field.isSecret)) {
      final stored = await _secure.read(key: _secretKey(companyId, definition.key, field.key));
      if (stored != null && stored.isNotEmpty) values[field.key] = stored;
    }
    for (final field in definition.fields) {
      values.putIfAbsent(field.key, () => field.defaultValue ?? '');
    }
    return values;
  }

  Future<void> save(
    IntegrationDefinition definition, {
    required Map<String, String> values,
    required bool enabled,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await createTables(db);
    final companyId = await _companyId(db);
    final publicConfig = <String, String>{};

    for (final field in definition.fields) {
      final value = (values[field.key] ?? '').trim();
      if (field.isSecret) {
        final key = _secretKey(companyId, definition.key, field.key);
        // Un campo secreto vacío en la interfaz significa "conservar".
        // La revocación se realiza deshabilitando la integración o sustituyendo
        // explícitamente la credencial, evitando borrar secretos por accidente.
        if (value.isNotEmpty) {
          await _secure.write(key: key, value: value);
        }
      } else {
        publicConfig[field.key] = value;
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query(
      'integration_profiles',
      where: 'company_id = ? AND provider_key = ?',
      whereArgs: [companyId, definition.key],
      limit: 1,
    );
    final data = {
      'company_id': companyId,
      'provider_key': definition.key,
      'enabled': enabled ? 1 : 0,
      'config_json': jsonEncode(publicConfig),
      'status': enabled ? 'configured' : 'disabled',
      'updated_at': now,
    };
    if (existing.isEmpty) {
      await db.insert('integration_profiles', {...data, 'created_at': now});
    } else {
      await db.update(
        'integration_profiles',
        data,
        where: 'company_id = ? AND provider_key = ?',
        whereArgs: [companyId, definition.key],
      );
    }
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'INTEGRACION_CONFIGURADA',
      entidad: 'integration_profiles',
      detalle: '${definition.key}; enabled=$enabled',
    );
  }

  /// Actualiza únicamente campos públicos de una integración sin leer ni
  /// reescribir secretos. Es útil para preferencias operativas (por ejemplo,
  /// retención de respaldos) que comparten perfil con credenciales sensibles.
  Future<void> updatePublicConfig(
    String providerKey,
    Map<String, String> patch,
  ) async {
    final definition = IntegrationRegistry.byKey(providerKey);
    final allowed = {
      for (final field in definition.fields.where((field) => !field.isSecret))
        field.key,
    };
    final invalid = patch.keys.where((key) => !allowed.contains(key)).toList();
    if (invalid.isNotEmpty) {
      throw ArgumentError('Campos no públicos/no soportados: ${invalid.join(', ')}');
    }

    final db = await DatabaseHelper.instance.database;
    await createTables(db);
    final companyId = await _companyId(db);
    final rows = await db.query(
      'integration_profiles',
      where: 'company_id = ? AND provider_key = ?',
      whereArgs: [companyId, providerKey],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    Map<String, dynamic> config = <String, dynamic>{};
    var enabled = false;
    if (rows.isNotEmpty) {
      enabled = rows.first['enabled'] == 1;
      try {
        final decoded = jsonDecode(rows.first['config_json']?.toString() ?? '{}');
        if (decoded is Map) config = Map<String, dynamic>.from(decoded);
      } catch (_) {
        config = <String, dynamic>{};
      }
    }
    for (final entry in patch.entries) {
      config[entry.key] = entry.value.trim();
    }
    final data = {
      'company_id': companyId,
      'provider_key': providerKey,
      'enabled': enabled ? 1 : 0,
      'config_json': jsonEncode(config),
      'status': enabled ? 'configured' : 'disabled',
      'updated_at': now,
    };
    if (rows.isEmpty) {
      await db.insert('integration_profiles', {...data, 'created_at': now});
    } else {
      await db.update(
        'integration_profiles',
        data,
        where: 'company_id = ? AND provider_key = ?',
        whereArgs: [companyId, providerKey],
      );
    }
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'INTEGRACION_CONFIG_PUBLICA_ACTUALIZADA',
      entidad: 'integration_profiles',
      detalle: '$providerKey; campos=${patch.keys.join(',')}',
    );
  }

  Future<bool> isConfigured(String providerKey) async {
    final definition = IntegrationRegistry.byKey(providerKey);
    final values = await loadValues(definition);
    final profile = await load(providerKey);
    if (!profile.enabled) return false;
    return definition.fields
        .where((field) => field.required)
        .every((field) => (values[field.key] ?? '').trim().isNotEmpty);
  }

  Future<String?> secret(String providerKey, String fieldKey) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await _companyId(db);
    return _secure.read(key: _secretKey(companyId, providerKey, fieldKey));
  }

  Future<String?> config(String providerKey, String fieldKey) async {
    final profile = await load(providerKey);
    return profile.config[fieldKey];
  }

  Future<IntegrationCheckResult> testConnection(IntegrationDefinition definition) async {
    final values = await loadValues(definition);
    final missing = definition.fields
        .where((field) => field.required && (values[field.key] ?? '').trim().isEmpty)
        .map((field) => field.label)
        .toList();
    if (missing.isNotEmpty) {
      return _recordCheck(definition.key, false, 'Faltan campos requeridos: ${missing.join(', ')}');
    }

    try {
      final result = switch (definition.key) {
        'whatsapp_meta' => await _testWhatsApp(values),
        'stripe' => await _testBearerGet(Uri.parse('https://api.stripe.com/v1/balance'), values['secret_key']!),
        'mercadopago' => await _testBearerGet(Uri.parse('https://api.mercadopago.com/users/me'), values['access_token']!),
        'paypal' => await _testPayPal(values),
        // DIAN usa su propio verificador: en modo DIRECTO no llama /health
        // porque la DIAN no expone endpoint público previo a habilitación.
        'dian' => await _testDian(values),
        'payroll_electronic' || 'external_api' || 'transparency_portal' || 'nequi' || 'pse' || 'pila_operator' || 'bpin_service' || 'secop_ii' || 'chip_cgn' || 'siif_nacion' || 'signature_provider' || 'trm_source' => await _testConfigurableHttp(values),
        'cloud_backup' => await _testCloudBackup(values),
        'smtp' => await _testSmtp(values),
        _ => const IntegrationCheckResult(true, 'Configuración completa. Este conector valida credenciales durante su operación específica.'),
      };
      return _recordCheck(definition.key, result.ok, result.message);
    } on SocketException {
      return _recordCheck(definition.key, false, 'No fue posible establecer conexión de red.');
    } catch (e) {
      debugPrint('Integration test ${definition.key}: $e');
      return _recordCheck(definition.key, false, 'La verificación falló sin exponer detalles sensibles.');
    }
  }

  Future<IntegrationCheckResult> _testSmtp(Map<String, String> values) async {
    // Valida que los campos requeridos estén presentes y que el servidor SMTP
    // sea alcanzable mediante una conexión TCP.
    // NO envía correo — el envío real se hace desde el botón dedicado en la UI.
    final host = (values['host'] ?? '').trim();
    final port = int.tryParse(values['port'] ?? '') ?? 587;
    final username = (values['username'] ?? '').trim();
    final password = values['password'] ?? '';
    final sender = (values['sender_email'] ?? '').trim();
    if (host.isEmpty || username.isEmpty || password.isEmpty || sender.isEmpty) {
      return const IntegrationCheckResult(false, 'Faltan campos requeridos: host, usuario, contraseña y correo remitente.');
    }
    if (!sender.contains('@')) {
      return const IntegrationCheckResult(false, 'El correo remitente configurado no es válido (falta @).');
    }
    // Verificar alcanzabilidad del host/puerto mediante conexión TCP.
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      await socket.close();
      return IntegrationCheckResult(
        true,
        'Servidor SMTP "$host:$port" alcanzable. '
        'Usa "Enviar correo de prueba" para verificar autenticación y envío reales.',
      );
    } on SocketException catch (e) {
      return IntegrationCheckResult(
        false,
        'No fue posible conectar con "$host:$port". '
        'Verifica el host, el puerto y que no esté bloqueado por firewall. '
        '(${e.message})',
      );
    } catch (_) {
      return IntegrationCheckResult(false, 'Error verificando conectividad SMTP con "$host:$port".');
    }
  }

  Future<IntegrationCheckResult> _testWhatsApp(
      Map<String, String> values) async {
    final version = values['api_version']!.trim();
    final phoneId = values['phone_number_id']!.trim();
    final uri = Uri.parse(
        'https://graph.facebook.com/$version/$phoneId?fields=display_phone_number,verified_name');
    return _testBearerGet(uri, values['access_token']!);
  }

  /// Verificación DIAN: comportamiento diferente según el modo configurado.
  ///   • PTA (proveedor tecnológico): intenta alcanzar el health_path del PTA.
  ///   • DIRECTO: no llama a ningún endpoint externo; verifica campos locales.
  Future<IntegrationCheckResult> _testDian(Map<String, String> values) async {
    final mode = (values['mode'] ?? 'PTA').trim().toUpperCase();
    if (mode == 'DIRECTO') {
      // Modo DIRECTO — verificar campos críticos localmente.
      final softwareId = (values['software_id'] ?? '').trim();
      final pin = (values['software_pin'] ?? '').trim();
      final cert = (values['certificate_path'] ?? '').trim();
      if (softwareId.isEmpty || pin.isEmpty) {
        return const IntegrationCheckResult(
          false,
          'Modo DIRECTO: se requieren Software ID y Software PIN.',
        );
      }
      if (cert.isEmpty) {
        return const IntegrationCheckResult(
          false,
          'Modo DIRECTO: especifica la ruta o alias del certificado digital.',
        );
      }
      // La DIAN no ofrece endpoint de salud público previo a habilitación.
      return const IntegrationCheckResult(
        true,
        'Modo DIRECTO: configuración local completa (Software ID + PIN + '
        'certificado). La validación definitiva ocurre al transmitir el '
        'primer documento. El proveedor no ofrece endpoint de salud previo.',
      );
    }
    // Modo PTA: el PTA tiene un endpoint de salud propio.
    final base = (values['base_url'] ?? '').trim();
    if (base.isEmpty) {
      return const IntegrationCheckResult(
        false, 'Modo PTA: configura la URL base del proveedor tecnológico.');
    }
    final healthPath = (values['health_path'] ?? '/health').trim();
    return _testConfigurableHttp({...values, 'health_path': healthPath});
  }

  Future<IntegrationCheckResult> _testBearerGet(Uri uri, String token) async {
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const IntegrationCheckResult(true, 'Conexión verificada correctamente.');
    }
    return IntegrationCheckResult(false, 'El proveedor respondió HTTP ${response.statusCode}. Revisa credenciales y permisos.');
  }

  Future<IntegrationCheckResult> _testPayPal(Map<String, String> values) async {
    final live = values['environment'] == 'live';
    final host = live ? 'api-m.paypal.com' : 'api-m.sandbox.paypal.com';
    final credential = base64Encode(utf8.encode('${values['client_id']}:${values['client_secret']}'));
    final response = await http.post(
      Uri.https(host, '/v1/oauth2/token'),
      headers: {'Authorization': 'Basic $credential', 'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=client_credentials',
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return const IntegrationCheckResult(true, 'Credenciales OAuth verificadas correctamente.');
    }
    return IntegrationCheckResult(false, 'PayPal respondió HTTP ${response.statusCode}.');
  }

  Future<IntegrationCheckResult> _testConfigurableHttp(Map<String, String> values) async {
    final base = (values['base_url'] ?? values['endpoint'] ?? '').trim();
    final rawPath = (values['health_path'] ?? '').trim();
    if (!_isAllowedRemoteBase(base)) {
      return const IntegrationCheckResult(false, 'Se exige HTTPS para endpoints remotos. HTTP solo se admite en localhost.');
    }
    final baseUri = Uri.parse(base);
    final uri = rawPath.isEmpty ? baseUri : baseUri.resolve(rawPath);
    final headers = _authHeaders(values);
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 400) {
      return const IntegrationCheckResult(true, 'Endpoint accesible y credenciales aceptadas.');
    }
    return IntegrationCheckResult(false, 'El endpoint respondió HTTP ${response.statusCode}. Revisa URL, credenciales y permisos.');
  }

  Future<IntegrationCheckResult> _testCloudBackup(Map<String, String> values) async {
    final endpoint = (values['endpoint'] ?? '').trim();
    if (!_isAllowedRemoteBase(endpoint)) {
      return const IntegrationCheckResult(false, 'Se exige HTTPS para el destino remoto de respaldos.');
    }
    final provider = (values['provider'] ?? '').trim().toUpperCase();
    final uri = Uri.parse(endpoint);
    final user = (values['access_key'] ?? '').trim();
    final secret = (values['secret_key'] ?? '').trim();
    try {
      if (provider == 'WEBDAV') {
        if (user.isEmpty || secret.isEmpty) {
          return const IntegrationCheckResult(false, 'WebDAV requiere usuario y contraseña.');
        }
        final credential = base64Encode(utf8.encode('$user:$secret'));
        final client = http.Client();
        try {
          final request = http.Request('OPTIONS', uri)
            ..headers['Authorization'] = 'Basic $credential';
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 12));
          if (response.statusCode >= 200 &&
              response.statusCode < 500 &&
              response.statusCode != 401 &&
              response.statusCode != 403) {
            return const IntegrationCheckResult(true, 'Destino WebDAV accesible y autenticación aceptada.');
          }
          return IntegrationCheckResult(false, 'WebDAV respondió HTTP ${response.statusCode}.');
        } finally {
          client.close();
        }
      }
      if (provider == 'AZURE_BLOB_SAS') {
        final token = (values['sas_token'] ?? '').trim().replaceFirst(RegExp(r'^\?'), '');
        if (token.isEmpty) {
          return const IntegrationCheckResult(false, 'Azure Blob requiere un SAS limitado al contenedor.');
        }
        final sasUri = uri.replace(queryParameters: {...uri.queryParameters, ...Uri.splitQueryString(token)});
        final response = await http.head(sasUri).timeout(const Duration(seconds: 12));
        if (response.statusCode >= 200 && response.statusCode < 400) {
          return const IntegrationCheckResult(true, 'Endpoint Azure Blob y SAS aceptados.');
        }
        return IntegrationCheckResult(false, 'Azure Blob respondió HTTP ${response.statusCode}.');
      }
      if (provider == 'S3_COMPATIBLE') {
        if (user.isEmpty || secret.isEmpty) {
          return const IntegrationCheckResult(false, 'S3-compatible requiere access key y secret key.');
        }
        final response = await http.head(uri).timeout(const Duration(seconds: 12));
        if (response.statusCode < 500) {
          return const IntegrationCheckResult(
            true,
            'Endpoint S3 accesible. La firma AWS SigV4 se valida de forma concluyente al subir el primer respaldo cifrado.',
          );
        }
        return IntegrationCheckResult(false, 'El endpoint S3 respondió HTTP ${response.statusCode}.');
      }
      return const IntegrationCheckResult(false, 'Proveedor de respaldo remoto no soportado.');
    } catch (_) {
      return const IntegrationCheckResult(false, 'No fue posible alcanzar el destino de respaldos.');
    }
  }

  Map<String, String> _authHeaders(Map<String, String> values) {
    final headers = <String, String>{'Accept': 'application/json'};
    final authType = (values['auth_type'] ?? '').trim().toUpperCase();
    final credential = (values['credential'] ?? values['api_key'] ?? '').trim();
    final username = (values['username'] ?? '').trim();
    if (authType == 'BASIC' && (username.isNotEmpty || credential.isNotEmpty)) {
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$username:$credential'))}';
    } else if (authType == 'API_KEY' && credential.isNotEmpty) {
      headers[username.isEmpty ? 'X-API-Key' : username] = credential;
    } else if ((authType == 'BEARER' || authType.isEmpty) && credential.isNotEmpty) {
      headers['Authorization'] = 'Bearer $credential';
    }
    final clientId = (values['client_id'] ?? '').trim();
    final clientSecret = (values['client_secret'] ?? '').trim();
    if (authType.isEmpty && clientId.isNotEmpty && clientSecret.isNotEmpty) {
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}';
    }
    final xroad = (values['xroad_client_id'] ?? '').trim();
    if (xroad.isNotEmpty) headers['X-Road-Client'] = xroad;
    return headers;
  }

  bool _isAllowedRemoteBase(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) return false;
    if (uri.scheme.toLowerCase() == 'https') return true;
    final host = uri.host.toLowerCase();
    return uri.scheme.toLowerCase() == 'http' &&
        (host == 'localhost' || host == '127.0.0.1' || host == '::1');
  }

  Future<IntegrationCheckResult> _recordCheck(String provider, bool ok, String message) async {
    final db = await DatabaseHelper.instance.database;
    await createTables(db);
    final companyId = await _companyId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'integration_profiles',
      {'status': ok ? 'connected' : 'error', 'last_checked_at': now, 'last_message': message, 'updated_at': now},
      where: 'company_id = ? AND provider_key = ?',
      whereArgs: [companyId, provider],
    );
    await db.insert('integration_events', {
      'company_id': companyId,
      'provider_key': provider,
      'event_type': 'connection_test',
      'success': ok ? 1 : 0,
      'message': message,
      'created_at': now,
    });
    return IntegrationCheckResult(ok, message);
  }

  Future<List<IntegrationDefinition>> definitionsForCurrentLicense() async {
    final license = await LicenciaService.instance.obtenerLicencia();
    return IntegrationRegistry.forFamily(license?.productFamily ?? ProductFamily.commercial);
  }
}
