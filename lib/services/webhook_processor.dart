import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../db_helper.dart';
import '../integrations/application/integration_settings_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'pse_service.dart';
import 'nequi_service.dart';

enum WebhookSource { woocommerce, shopify, pse, nequi, custom }

enum WebhookStatus { recibido, procesado, error, reintentando }

class WebhookEvent {
  const WebhookEvent({
    required this.id,
    required this.source,
    required this.eventType,
    required this.payload,
    required this.status,
    required this.receivedAt,
    this.signature,
    this.processedAt,
    this.errorMessage,
    this.retryCount = 0,
  });

  final int id;
  final WebhookSource source;
  final String eventType;
  final Map<String, dynamic> payload;
  final WebhookStatus status;
  final DateTime receivedAt;
  final String? signature;
  final DateTime? processedAt;
  final String? errorMessage;
  final int retryCount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source': source.name,
      'event_type': eventType,
      'payload': jsonEncode(payload),
      'status': status.name,
      'received_at': receivedAt.toIso8601String(),
      'signature': signature,
      'processed_at': processedAt?.toIso8601String(),
      'error_message': errorMessage,
      'retry_count': retryCount,
    };
  }

  static WebhookEvent fromMap(Map<String, dynamic> map) {
    return WebhookEvent(
      id: map['id'] as int,
      source: WebhookSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => WebhookSource.custom,
      ),
      eventType: map['event_type'] as String,
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      status: WebhookStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => WebhookStatus.recibido,
      ),
      receivedAt: DateTime.parse(map['received_at'] as String),
      signature: map['signature'] as String?,
      processedAt: map['processed_at'] != null 
          ? DateTime.parse(map['processed_at'] as String) 
          : null,
      errorMessage: map['error_message'] as String?,
      retryCount: map['retry_count'] as int? ?? 0,
    );
  }

  WebhookEvent copyWith({
    WebhookStatus? status,
    DateTime? processedAt,
    String? errorMessage,
    int? retryCount,
  }) {
    return WebhookEvent(
      id: id,
      source: source,
      eventType: eventType,
      payload: payload,
      status: status ?? this.status,
      receivedAt: receivedAt,
      signature: signature,
      processedAt: processedAt ?? this.processedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

class WebhookProcessor {
  WebhookProcessor._();

  static final WebhookProcessor instance = WebhookProcessor._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  final Map<WebhookSource, String> _webhookSecrets = {};

  String _secureKey(WebhookSource source) => 'merka_webhook_secret_${source.name}';
  String _legacyKey(WebhookSource source) => 'webhook_secret_${source.name}';

  Future<void> configurarSecret(WebhookSource source, String secret) async {
    final normalized = secret.trim();
    if (normalized.length < 32) {
      throw ArgumentError('El secreto HMAC debe tener al menos 32 caracteres.');
    }

    await _secureStorage.write(key: _secureKey(source), value: normalized);
    _webhookSecrets[source] = normalized;

    // Eliminar cualquier copia heredada almacenada en SQLite.
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_config',
      where: 'clave = ?',
      whereArgs: [_legacyKey(source)],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'WEBHOOK_SECRET_CONFIGURADO',
      entidad: 'webhooks',
      detalle: 'Source: ${source.name}',
    );
  }

  Future<String?> obtenerSecret(WebhookSource source) async {
    final cached = _webhookSecrets[source];
    if (cached != null && cached.isNotEmpty) return cached;

    final secure = (await _secureStorage.read(key: _secureKey(source)))?.trim();
    if (secure != null && secure.isNotEmpty) {
      _webhookSecrets[source] = secure;
      return secure;
    }

    // PSE y Nequi usan el mismo secreto configurado por empresa en el Centro
    // de Integraciones; no se duplica en SQLite ni en otra pantalla.
    if (source == WebhookSource.pse || source == WebhookSource.nequi) {
      final provider = source == WebhookSource.pse ? 'pse' : 'nequi';
      final integrationSecret =
          (await IntegrationSettingsService.instance.secret(provider, 'webhook_secret'))?.trim();
      if (integrationSecret != null && integrationSecret.isNotEmpty) {
        _webhookSecrets[source] = integrationSecret;
        return integrationSecret;
      }
    }

    // Migración única desde instalaciones antiguas. Si el almacenamiento
    // seguro falla, se propaga el error: SQLite nunca vuelve a ser fallback.
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [_legacyKey(source)],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final legacy = rows.first['valor']?.toString().trim();
    if (legacy == null || legacy.isEmpty) {
      await db.delete('app_config', where: 'clave = ?', whereArgs: [_legacyKey(source)]);
      return null;
    }

    await _secureStorage.write(key: _secureKey(source), value: legacy);
    await db.delete('app_config', where: 'clave = ?', whereArgs: [_legacyKey(source)]);
    _webhookSecrets[source] = legacy;
    return legacy;
  }

  bool validarFirmaHmac(
    WebhookSource source,
    String payload,
    String signature,
    String secret,
  ) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    final normalizedSignature = signature.trim().toLowerCase().replaceFirst(RegExp(r'^sha256='), '');

    // Comparar de forma segura para evitar timing attacks.
    return _constantTimeEquals(digest.toString(), normalizedSignature);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  Future<WebhookEvent> procesarWebhook(
    WebhookSource source,
    String eventType,
    Map<String, dynamic> payload, {
    String? signature,
  }) async {
    final secret = await obtenerSecret(source);

    // Fail-closed: una integración que haya configurado HMAC nunca puede
    // degradarse silenciosamente a aceptar solicitudes sin firma. Para
    // webhooks custom se exige siempre un secreto, ya que son la entrada
    // genérica expuesta por la API local.
    if (source == WebhookSource.custom && (secret == null || secret.isEmpty)) {
      throw StateError('Webhook custom no configurado: falta secreto HMAC.');
    }
    if (secret != null && secret.isNotEmpty) {
      if (signature == null || signature.trim().isEmpty) {
        throw Exception('Falta firma HMAC');
      }
      final payloadStr = jsonEncode(payload);
      if (!validarFirmaHmac(source, payloadStr, signature, secret)) {
        throw Exception('Firma HMAC inválida');
      }
    }

    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    // Guardar webhook recibido
    final id = await db.insert('webhooks_recibidos', {
      'company_id': companyId,
      'source': source.name,
      'event_type': eventType,
      'payload': jsonEncode(payload),
      'signature': signature,
      'status': WebhookStatus.recibido.name,
      'received_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });

    final webhookEvent = WebhookEvent(
      id: id,
      source: source,
      eventType: eventType,
      payload: payload,
      status: WebhookStatus.recibido,
      receivedAt: DateTime.now(),
      signature: signature,
    );

    try {
      await _procesarPorSource(webhookEvent);
      
      // Actualizar estado a procesado
      await db.update(
        'webhooks_recibidos',
        {
          'status': WebhookStatus.procesado.name,
          'processed_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      return webhookEvent.copyWith(
        status: WebhookStatus.procesado,
        processedAt: DateTime.now(),
      );
    } catch (e) {
      // Actualizar estado a error
      await db.update(
        'webhooks_recibidos',
        {
          'status': WebhookStatus.error.name,
          'error_message': e.toString(),
          'processed_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'WEBHOOK_PROCESAMIENTO_ERROR',
        entidad: 'webhooks',
        detalle: 'Source: ${source.name}, Event: $eventType, Error: $e',
      );

      rethrow;
    }
  }

  Future<void> _procesarPorSource(WebhookEvent event) async {
    switch (event.source) {
      case WebhookSource.woocommerce:
        await _procesarWooCommerceWebhook(event);
        break;
      case WebhookSource.shopify:
        await _procesarShopifyWebhook(event);
        break;
      case WebhookSource.pse:
        await PseService.instance.procesarWebhook(event.payload);
        break;
      case WebhookSource.nequi:
        await NequiService.instance.procesarWebhook(event.payload);
        break;
      case WebhookSource.custom:
        await _procesarCustomWebhook(event);
        break;
    }
  }

  Future<void> _procesarWooCommerceWebhook(WebhookEvent event) async {
    switch (event.eventType) {
      case 'order.created':
      case 'order.updated':
        // Sincronizar orden con el sistema
        final orderId = event.payload['id'] as int?;
        if (orderId != null) {
          // Aquí se implementaría la lógica de sincronización
          await DatabaseHelper.instance.registrarEventoAuditoria(
            accion: 'WOO_WEBHOOK_ORDER_PROCESADO',
            entidad: 'webhooks',
            detalle: 'Order ID: $orderId',
          );
        }
        break;
      case 'product.updated':
        final productId = event.payload['id'] as int?;
        if (productId != null) {
          // Actualizar producto local
          await DatabaseHelper.instance.registrarEventoAuditoria(
            accion: 'WOO_WEBHOOK_PRODUCT_PROCESADO',
            entidad: 'webhooks',
            detalle: 'Product ID: $productId',
          );
        }
        break;
      default:
        await DatabaseHelper.instance.registrarEventoAuditoria(
          accion: 'WOO_WEBHOOK_EVENTO_DESCONOCIDO',
          entidad: 'webhooks',
          detalle: 'Event: ${event.eventType}',
        );
    }
  }

  Future<void> _procesarShopifyWebhook(WebhookEvent event) async {
    switch (event.eventType) {
      case 'orders/create':
      case 'orders/updated':
        final orderId = event.payload['id'] as int?;
        if (orderId != null) {
          await DatabaseHelper.instance.registrarEventoAuditoria(
            accion: 'SHOPIFY_WEBHOOK_ORDER_PROCESADO',
            entidad: 'webhooks',
            detalle: 'Order ID: $orderId',
          );
        }
        break;
      case 'products/create':
      case 'products/update':
        final productId = event.payload['id'] as int?;
        if (productId != null) {
          await DatabaseHelper.instance.registrarEventoAuditoria(
            accion: 'SHOPIFY_WEBHOOK_PRODUCT_PROCESADO',
            entidad: 'webhooks',
            detalle: 'Product ID: $productId',
          );
        }
        break;
      case 'app/uninstalled':
        // Desactivar integración Shopify
        await DatabaseHelper.instance.registrarEventoAuditoria(
          accion: 'SHOPIFY_APP_DESINSTALADA',
          entidad: 'webhooks',
          detalle: 'App desinstalada',
        );
        break;
      default:
        await DatabaseHelper.instance.registrarEventoAuditoria(
          accion: 'SHOPIFY_WEBHOOK_EVENTO_DESCONOCIDO',
          entidad: 'webhooks',
          detalle: 'Event: ${event.eventType}',
        );
    }
  }

  Future<void> _procesarCustomWebhook(WebhookEvent event) async {
    // Procesar webhooks personalizados según configuración
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final handlers = await db.query(
      'api_webhooks',
      where: 'company_id = ? AND evento = ? AND activo = ?',
      whereArgs: [companyId, event.eventType, 1],
    );

    for (final handler in handlers) {
      final url = handler['url'] as String;
      // Aquí se podría reenviar el webhook a una URL personalizada
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'CUSTOM_WEBHOOK_PROCESADO',
        entidad: 'webhooks',
        detalle: 'URL: $url',
      );
    }
  }

  Future<void> reintentarWebhooksFallidos({int maxRetries = 3}) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final webhooks = await db.query(
      'webhooks_recibidos',
      where: 'company_id = ? AND status = ? AND retry_count < ?',
      whereArgs: [companyId, WebhookStatus.error.name, maxRetries],
    );

    for (final webhook in webhooks) {
      final event = WebhookEvent.fromMap(webhook);
      
      try {
        await _procesarPorSource(event);
        
        await db.update(
          'webhooks_recibidos',
          {
            'status': WebhookStatus.procesado.name,
            'processed_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [event.id],
        );
      } catch (e) {
        await db.update(
          'webhooks_recibidos',
          {
            'retry_count': event.retryCount + 1,
            'error_message': e.toString(),
          },
          where: 'id = ?',
          whereArgs: [event.id],
        );
      }
    }
  }

  Future<List<WebhookEvent>> obtenerWebhooks({
    WebhookSource? source,
    WebhookStatus? status,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    String where = 'company_id = ?';
    List<dynamic> whereArgs = [companyId];

    if (source != null) {
      where += ' AND source = ?';
      whereArgs.add(source.name);
    }

    if (status != null) {
      where += ' AND status = ?';
      whereArgs.add(status.name);
    }

    if (desde != null) {
      where += ' AND received_at >= ?';
      whereArgs.add(desde.toIso8601String());
    }

    if (hasta != null) {
      where += ' AND received_at <= ?';
      whereArgs.add(hasta.toIso8601String());
    }

    final rows = await db.query(
      'webhooks_recibidos',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'received_at DESC',
      limit: 100,
    );

    return rows.map((row) => WebhookEvent.fromMap(row)).toList();
  }

  Future<void> limpiarWebhooksAntiguos({int dias = 30}) async {
    final db = await DatabaseHelper.instance.database;
    final fechaCorte = DateTime.now().subtract(Duration(days: dias));
    
    await db.delete(
      'webhooks_recibidos',
      where: 'received_at < ? AND status = ?',
      whereArgs: [fechaCorte.toIso8601String(), WebhookStatus.procesado.name],
    );
  }
}
