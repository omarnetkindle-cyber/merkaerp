import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:crypto/crypto.dart';
import '../db_helper.dart';

class ApiKey {
  const ApiKey({
    required this.id,
    required this.companyId,
    required this.nombre,
    required this.key,
    required this.permisos,
    required this.activo,
    required this.creadoEn,
    this.ultimaUso,
    this.rateLimit = 100,
    this.rateWindowMinutes = 1,
  });

  final int id;
  final int companyId;
  final String nombre;
  final String key;
  final List<String> permisos;
  final bool activo;
  final DateTime creadoEn;
  final DateTime? ultimaUso;
  final int rateLimit;
  final int rateWindowMinutes;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'nombre': nombre,
      'key': key,
      'permisos': jsonEncode(permisos),
      'activo': activo ? 1 : 0,
      'creado_en': creadoEn.toIso8601String(),
      'ultima_uso': ultimaUso?.toIso8601String(),
      'rate_limit': rateLimit,
      'rate_window_minutes': rateWindowMinutes,
    };
  }

  static ApiKey fromMap(Map<String, dynamic> map, {String? secret}) {
    final companyId = (map['company_id'] as num?)?.toInt();
    if (companyId == null || companyId <= 0) {
      throw StateError('La API key no está asociada a una empresa válida.');
    }
    return ApiKey(
      id: map['id'] as int,
      companyId: companyId,
      nombre: map['nombre'] as String,
      // El secreto solo está disponible al crearlo o durante la autenticación.
      // Nunca se recupera el valor persistido (que es únicamente su hash).
      key: secret ?? '',
      permisos: (jsonDecode(map['permisos'] as String) as List)
          .map((e) => e.toString())
          .toList(),
      activo: (map['activo'] as int) == 1,
      creadoEn: DateTime.parse(map['creado_en'] as String),
      ultimaUso: map['ultima_uso'] != null
          ? DateTime.parse(map['ultima_uso'] as String)
          : null,
      rateLimit: map['rate_limit'] as int? ?? 100,
      rateWindowMinutes: map['rate_window_minutes'] as int? ?? 1,
    );
  }
}

class ApiAuthService {
  ApiAuthService._();

  static final ApiAuthService instance = ApiAuthService._();

  final Map<String, List<DateTime>> _rateLimitCache = {};
  static const int _defaultRateLimit = 100;
  static const int _defaultRateWindowMinutes = 1;

  Future<String> generarApiKey() async {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final digest = sha256.convert(bytes);
    return 'merka_${digest.toString().substring(0, 32)}';
  }

  String _hashKey(String key) => sha256.convert(utf8.encode(key)).toString();

  Future<ApiKey> crearApiKey({
    required String nombre,
    List<String> permisos = const [],
    int rateLimit = _defaultRateLimit,
    int rateWindowMinutes = _defaultRateWindowMinutes,
  }) async {
    final key = await generarApiKey();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final id = await db.insert('api_keys', {
      'company_id': companyId,
      'nombre': nombre,
      'key': _hashKey(key),
      'permisos': jsonEncode(permisos),
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
      'rate_limit': rateLimit,
      'rate_window_minutes': rateWindowMinutes,
    });

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'API_KEY_CREADA',
      entidad: 'api_auth',
      detalle: 'Nombre: $nombre, ID: $id',
    );

    return ApiKey(
      id: id,
      companyId: companyId,
      nombre: nombre,
      key: key,
      permisos: permisos,
      activo: true,
      creadoEn: DateTime.now(),
      rateLimit: rateLimit,
      rateWindowMinutes: rateWindowMinutes,
    );
  }

  Future<ApiKey?> validarApiKey(String key) async {
    final db = await DatabaseHelper.instance.database;
    final keyHash = _hashKey(key);
    final rows = await db.query(
      'api_keys',
      // La segunda condición permite migrar de forma segura claves antiguas que
      // se almacenaban en texto plano. Se reemplazan por el hash al primer uso.
      where: '(key = ? OR key = ?) AND activo = ? AND company_id IS NOT NULL',
      whereArgs: [keyHash, key, 1],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final apiKey = ApiKey.fromMap(rows.first, secret: key);

    // Actualizar última uso
    await db.update(
      'api_keys',
      {'key': keyHash, 'ultima_uso': DateTime.now().toIso8601String()},
      where: 'id = ? AND company_id = ?',
      whereArgs: [apiKey.id, apiKey.companyId],
    );

    return apiKey;
  }

  Future<bool> tienePermiso(ApiKey apiKey, String permiso) async {
    if (apiKey.permisos.contains('*')) return true;
    return apiKey.permisos.contains(permiso);
  }

  Future<void> revocarApiKey(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await db.update(
      'api_keys',
      {'activo': 0},
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'API_KEY_REVOCADA',
      entidad: 'api_auth',
      detalle: 'ID: $id',
    );
  }

  Future<List<ApiKey>> obtenerApiKeys() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final rows = await db.query(
      'api_keys',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'creado_en DESC',
    );
    return rows.map((row) => ApiKey.fromMap(row)).toList();
  }

  Middleware authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final authHeader = request.headers['Authorization'];

        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response.unauthorized(
            jsonEncode({'error': 'Missing or invalid Authorization header'}),
          );
        }

        final token = authHeader.substring(7);
        final apiKey = await validarApiKey(token);

        if (apiKey == null) {
          return Response.unauthorized(
            jsonEncode({'error': 'Invalid API key'}),
          );
        }

        // Agregar API key al contexto de la request
        return await innerHandler(request.change(context: {'apiKey': apiKey}));
      };
    };
  }

  Middleware rateLimitMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final apiKey = request.context['apiKey'] as ApiKey?;

        if (apiKey == null) {
          return await innerHandler(request);
        }

        final now = DateTime.now();
        final key = '${apiKey.companyId}:${apiKey.id}';

        // Limpiar entradas viejas del cache
        _rateLimitCache.removeWhere((k, timestamps) {
          timestamps.removeWhere(
            (t) => now.difference(t).inMinutes > apiKey.rateWindowMinutes,
          );
          return timestamps.isEmpty;
        });

        final timestamps = _rateLimitCache[key] ?? [];

        if (timestamps.length >= apiKey.rateLimit) {
          return Response(
            429,
            body: jsonEncode({
              'error': 'Rate limit exceeded',
              'limit': apiKey.rateLimit,
              'window': '${apiKey.rateWindowMinutes}m',
            }),
          );
        }

        timestamps.add(now);
        _rateLimitCache[key] = timestamps;

        return await innerHandler(request);
      };
    };
  }

  Middleware corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final response = await innerHandler(request);

        return response.change(
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods':
                'GET, POST, PUT, PATCH, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Authorization, Content-Type',
            ...response.headers,
          },
        );
      };
    };
  }

  Future<void> registrarAcceso(
    ApiKey apiKey,
    String endpoint,
    String metodo,
  ) async {
    final db = await DatabaseHelper.instance.database;

    await db.insert('api_access_logs', {
      'api_key_id': apiKey.id,
      'endpoint': endpoint,
      'metodo': metodo,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> limpiarLogsAntiguos({int dias = 30}) async {
    final db = await DatabaseHelper.instance.database;
    final fechaCorte = DateTime.now().subtract(Duration(days: dias));

    await db.delete(
      'api_access_logs',
      where: 'timestamp < ?',
      whereArgs: [fechaCorte.toIso8601String()],
    );
  }
}
