// ============================================================
// payment_service.dart
// Servicio de integración con pasarelas de pago
// ============================================================

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../core/currency/money_value.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../integrations/application/payment_checkout_service.dart';
import '../../integrations/application/institutional_connector_service.dart';
import 'payment_gateway.dart';

class PaymentService {
  static final PaymentService instance = PaymentService._internal();


  PaymentService._internal();

  /// Crea las tablas necesarias para pasarelas de pago
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_gateways (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        config TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        gateway_id INTEGER NOT NULL,
        transaction_id TEXT,
        amount INTEGER NOT NULL,
        currency TEXT DEFAULT 'USD',
        status TEXT DEFAULT 'pending',
        payment_method TEXT,
        metadata TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (gateway_id) REFERENCES payment_gateways(id)
      )
    ''');

    // Índices
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gateways_company ON payment_gateways(company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_company ON payment_transactions(company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_status ON payment_transactions(status)',
    );

    // Versiones antiguas permitían serializar credenciales de pasarelas
    // remotas dentro de SQLite. Desde el Centro de Integraciones los secretos
    // viven en almacenamiento seguro; por seguridad se purga el JSON heredado.
    await db.rawUpdate(
      "UPDATE payment_gateways SET config = ? WHERE type IN ('stripe','paypal','mercadopago','custom') AND config <> ?",
      [jsonEncode({'credentials': 'managed_by_integration_center'}), jsonEncode({'credentials': 'managed_by_integration_center'})],
    );
  }

  bool _usesIntegrationCenter(PaymentGatewayType type) =>
      type == PaymentGatewayType.stripe ||
      type == PaymentGatewayType.paypal ||
      type == PaymentGatewayType.mercadopago ||
      type == PaymentGatewayType.custom;

  /// Registra una pasarela de pago
  Future<int> registerGateway(Database db, PaymentGateway gateway) async {
    final id = await db.insert('payment_gateways', {
      'company_id': gateway.companyId,
      'type': gateway.type.name,
      'name': gateway.name,
      'config': jsonEncode(
        _usesIntegrationCenter(gateway.type)
            ? {'credentials': 'managed_by_integration_center'}
            : gateway.config,
      ),
      'is_active': gateway.isActive ? 1 : 0,
      'is_default': gateway.isDefault ? 1 : 0,
      'created_at': gateway.createdAt.toIso8601String(),
      'updated_at': gateway.updatedAt?.toIso8601String(),
    });

    return id;
  }

  /// Obtiene la pasarela de pago por defecto
  Future<PaymentGateway?> getDefaultGateway(Database db, int companyId) async {
    final maps = await db.query(
      'payment_gateways',
      where: 'company_id = ? AND is_default = 1 AND is_active = 1',
      whereArgs: [companyId],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    return PaymentGateway(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      type: PaymentGatewayType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => PaymentGatewayType.local,
      ),
      name: map['name'] as String,
      config: jsonDecode(map['config'] as String) as Map<String, dynamic>,
      isActive: (map['is_active'] as int) == 1,
      isDefault: (map['is_default'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// Obtiene todas las pasarelas activas de una empresa
  Future<List<PaymentGateway>> getActiveGateways(
    Database db,
    int companyId,
  ) async {
    final maps = await db.query(
      'payment_gateways',
      where: 'company_id = ? AND is_active = 1',
      whereArgs: [companyId],
    );

    return maps
        .map(
          (map) => PaymentGateway(
            id: map['id'] as int?,
            companyId: map['company_id'] as int,
            type: PaymentGatewayType.values.firstWhere(
              (e) => e.name == map['type'],
              orElse: () => PaymentGatewayType.local,
            ),
            name: map['name'] as String,
            config: jsonDecode(map['config'] as String) as Map<String, dynamic>,
            isActive: (map['is_active'] as int) == 1,
            isDefault: (map['is_default'] as int) == 1,
            createdAt: DateTime.parse(map['created_at'] as String),
            updatedAt: map['updated_at'] != null
                ? DateTime.parse(map['updated_at'] as String)
                : null,
          ),
        )
        .toList();
  }

  /// Procesa un pago
  Future<Map<String, dynamic>> processPayment(
    Database db,
    int companyId,
    MoneyValue amount,
    String currency,
    Map<String, dynamic> paymentData,
  ) async {
    final gateway = await getDefaultGateway(db, companyId);
    if (gateway == null) {
      throw Exception('No hay pasarela de pago configurada');
    }

    switch (gateway.type) {
      case PaymentGatewayType.stripe:
        return await _processStripePayment(
          gateway,
          amount,
          currency,
          paymentData,
        );
      case PaymentGatewayType.paypal:
        return await _processPayPalPayment(
          gateway,
          amount,
          currency,
          paymentData,
        );
      case PaymentGatewayType.mercadopago:
        return await _processMercadoPagoPayment(
          gateway,
          amount,
          currency,
          paymentData,
        );
      case PaymentGatewayType.local:
        return await _processLocalPayment(
          gateway,
          amount,
          currency,
          paymentData,
        );
      case PaymentGatewayType.custom:
        return await _processCustomPayment(
          gateway,
          amount,
          currency,
          paymentData,
        );
    }
  }

  /// Inicia pago con Stripe. Crear un PaymentIntent NO acredita el pago.
  Future<Map<String, dynamic>> _processStripePayment(
    PaymentGateway gateway,
    MoneyValue amount,
    String currency,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      final reference = paymentData['reference']?.toString().trim();
      if (reference == null || reference.isEmpty) {
        throw ArgumentError('El checkout remoto requiere una referencia.');
      }
      final session = await PaymentCheckoutService.instance.createStripeIntent(
        companyId: gateway.companyId,
        amount: amount,
        reference: reference,
        description: paymentData['description']?.toString(),
      );
      return {
        'success': true,
        ...session.toMap(),
        'status': 'pending_external_confirmation',
        'message': 'Checkout creado. El pago aún NO está confirmado.',
      };
    } catch (e) {
      return {'success': false, 'status': 'failed', 'message': e.toString()};
    }
  }

  /// Inicia una orden PayPal. La captura se confirma por el flujo del proveedor.
  Future<Map<String, dynamic>> _processPayPalPayment(
    PaymentGateway gateway,
    MoneyValue amount,
    String currency,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      final reference = paymentData['reference']?.toString().trim();
      if (reference == null || reference.isEmpty) {
        throw ArgumentError('El checkout remoto requiere una referencia.');
      }
      final session = await PaymentCheckoutService.instance.createPayPalOrder(
        companyId: gateway.companyId,
        amount: amount,
        reference: reference,
        description: paymentData['description']?.toString(),
        returnUrl: paymentData['return_url']?.toString(),
        cancelUrl: paymentData['cancel_url']?.toString(),
      );
      return {
        'success': true,
        ...session.toMap(),
        'status': 'pending_external_confirmation',
        'message': 'Orden creada. El pago aún NO está confirmado.',
      };
    } catch (e) {
      return {'success': false, 'status': 'failed', 'message': e.toString()};
    }
  }

  /// Crea una preferencia Mercado Pago sin reconocer todavía el ingreso.
  Future<Map<String, dynamic>> _processMercadoPagoPayment(
    PaymentGateway gateway,
    MoneyValue amount,
    String currency,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      final reference = paymentData['reference']?.toString().trim();
      if (reference == null || reference.isEmpty) {
        throw ArgumentError('El checkout remoto requiere una referencia.');
      }
      final session = await PaymentCheckoutService.instance.createMercadoPagoPreference(
        companyId: gateway.companyId,
        amount: amount,
        reference: reference,
        title: paymentData['title']?.toString() ?? paymentData['description']?.toString() ?? 'Pago MerkaERP',
        returnUrl: paymentData['return_url']?.toString(),
      );
      return {
        'success': true,
        ...session.toMap(),
        'status': 'pending_external_confirmation',
        'message': 'Preferencia creada. El pago aún NO está confirmado.',
      };
    } catch (e) {
      return {'success': false, 'status': 'failed', 'message': e.toString()};
    }
  }

  /// Procesa pago local (efectivo, transferencia, etc.)
  Future<Map<String, dynamic>> _processLocalPayment(
    PaymentGateway gateway,
    MoneyValue amount,
    String currency,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      final paymentMethod = paymentData['payment_method'] as String? ?? 'cash';

      return {
        'success': true,
        'transaction_id': 'local_${DateTime.now().millisecondsSinceEpoch}',
        'status': 'completed',
        'message': 'Pago local procesado',
        'payment_method': paymentMethod,
      };
    } catch (e) {
      return {'success': false, 'status': 'failed', 'message': e.toString()};
    }
  }

  /// Inicia un checkout con una pasarela personalizada configurada en el
  /// Centro de Integraciones. Un 2xx confirma únicamente que el proveedor
  /// aceptó crear la operación; nunca acredita por sí solo el recaudo.
  Future<Map<String, dynamic>> _processCustomPayment(
    PaymentGateway gateway,
    MoneyValue amount,
    String currency,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      final reference = paymentData['reference']?.toString().trim();
      if (reference == null || reference.isEmpty) {
        throw ArgumentError('El checkout personalizado requiere una referencia.');
      }
      final response = await InstitutionalConnectorService.instance.postJson(
        'custom_payment',
        pathField: 'submission_path',
        payload: {
          'amount_minor': amount.toSql(),
          'amount': amount.toMajorUnitsString(),
          'currency': currency,
          'reference': reference,
          ...paymentData,
        },
      );
      if (!response.ok) {
        return {
          'success': false,
          'status': 'failed',
          'message': response.message,
          'provider_http_status': response.statusCode,
        };
      }
      return {
        'success': true,
        'status': 'pending_external_confirmation',
        'provider_http_status': response.statusCode,
        'provider_response': response.data,
        'provider_verified': false,
        'message': 'Checkout aceptado por el proveedor. El pago aún NO está confirmado.',
      };
    } catch (e) {
      return {'success': false, 'status': 'failed', 'message': e.toString()};
    }
  }

  /// Registra una transacción de pago
  Future<int> recordTransaction(
    Database db,
    int companyId,
    int gatewayId,
    String transactionId,
    MoneyValue amount,
    String currency,
    String status, {
    String? paymentMethod,
    Map<String, dynamic>? metadata,
  }) async {
    if (status.toLowerCase() == 'completed') {
      final gatewayRows = await db.query(
        'payment_gateways',
        columns: ['type'],
        where: 'id = ? AND company_id = ?',
        whereArgs: [gatewayId, companyId],
        limit: 1,
      );
      if (gatewayRows.isNotEmpty) {
        final type = gatewayRows.first['type']?.toString();
        final remote = type == 'stripe' ||
            type == 'paypal' ||
            type == 'mercadopago' ||
            type == 'custom';
        if (remote) {
          throw StateError(
            'Una pasarela remota nunca puede insertarse directamente como completada. Registre la operación pendiente y use verifyAndCompleteRemoteTransaction para acreditarla.',
          );
        }
      }
    }

    final id = await db.insert('payment_transactions', {
      'company_id': companyId,
      'gateway_id': gatewayId,
      'transaction_id': transactionId,
      'amount': amount.toSql(),
      'currency': currency,
      'status': status,
      'payment_method': paymentMethod,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    return id;
  }

  /// Verifica contra el proveedor y solo entonces acredita una transacción remota.
  /// También compara referencia, importe y moneda para impedir confirmaciones
  /// parciales o reutilizadas para otra operación.
  Future<Map<String, Object?>> verifyAndCompleteRemoteTransaction(
    Database db,
    int companyId,
    int transactionId, {
    required String reference,
  }) async {
    final rows = await db.rawQuery('''
      SELECT t.*, g.type AS gateway_type
      FROM payment_transactions t
      JOIN payment_gateways g ON g.id = t.gateway_id AND g.company_id = t.company_id
      WHERE t.id = ? AND t.company_id = ?
      LIMIT 1
    ''', [transactionId, companyId]);
    if (rows.isEmpty) throw StateError('Transacción de pago no encontrada.');
    final row = rows.first;
    final type = row['gateway_type']?.toString();
    if (!{'stripe', 'paypal', 'mercadopago'}.contains(type)) {
      throw StateError(
        type == 'custom'
            ? 'La pasarela personalizada requiere un verificador autenticado específico antes de acreditar el pago.'
            : 'La transacción seleccionada no utiliza una pasarela remota verificable.',
      );
    }
    final externalId = row['transaction_id']?.toString().trim();
    if (externalId == null || externalId.isEmpty) {
      throw StateError('La transacción no contiene identificador externo para verificar.');
    }
    final currencyCode = row['currency']?.toString().trim().toUpperCase() ?? '';
    final currency = await MoneyCurrencyResolver.resolve(db, companyId: companyId, explicitCode: currencyCode);
    final expectedAmount = MoneyValue.fromSql(row['amount'], currency: currency);

    final Map<String, Object?> verification;
    switch (type) {
      case 'stripe':
        verification = await PaymentCheckoutService.instance.verifyStripeIntent(
          companyId: companyId,
          paymentIntentId: externalId,
          reference: reference,
          expectedAmount: expectedAmount,
        );
        break;
      case 'paypal':
        verification = await PaymentCheckoutService.instance.verifyPayPalOrder(
          companyId: companyId,
          orderId: externalId,
          reference: reference,
          expectedAmount: expectedAmount,
        );
        break;
      case 'mercadopago':
        verification = await PaymentCheckoutService.instance.verifyMercadoPagoPayment(
          companyId: companyId,
          paymentId: externalId,
          reference: reference,
          expectedAmount: expectedAmount,
        );
        break;
      default:
        throw StateError('Proveedor de pago no soportado.');
    }
    if (verification['provider_verified'] != true) {
      return {
        ...verification,
        'status': 'pending_external_confirmation',
        'message': 'El proveedor todavía no confirma referencia, importe, moneda y estado del pago.',
      };
    }

    var metadata = <String, dynamic>{};
    final rawMetadata = row['metadata']?.toString();
    if (rawMetadata != null && rawMetadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    metadata.addAll({
      ...verification,
      'provider_verified': true,
      'verification_source': 'payment_checkout_service',
      'verified_reference': reference,
      'verified_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.update(
      'payment_transactions',
      {
        'status': 'completed',
        'metadata': jsonEncode(metadata),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [transactionId, companyId],
    );
    return {
      ...verification,
      'status': 'completed',
      'message': 'Pago verificado por el proveedor y acreditado en MerkaERP.',
    };
  }

  /// Obtiene transacciones de una empresa
  Future<List<Map<String, dynamic>>> getTransactions(
    Database db,
    int companyId, {
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String where = 'company_id = ?';
    final whereArgs = <Object>[companyId];

    if (status != null) {
      where += ' AND status = ?';
      whereArgs.add(status);
    }

    if (startDate != null) {
      where += ' AND created_at >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      where += ' AND created_at <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    final maps = await db.query(
      'payment_transactions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    return maps;
  }

  /// Actualiza el estado de una transacción
  Future<void> updateTransactionStatus(
    Database db,
    int transactionId,
    String status,
  ) async {
    final rows = await db.rawQuery('''
      SELECT t.company_id, t.metadata, g.type AS gateway_type
      FROM payment_transactions t
      JOIN payment_gateways g ON g.id = t.gateway_id AND g.company_id = t.company_id
      WHERE t.id = ?
      LIMIT 1
    ''', [transactionId]);
    if (rows.isEmpty) throw StateError('Transacción de pago no encontrada.');
    final normalized = status.trim().toLowerCase();
    final type = rows.first['gateway_type']?.toString();
    if (normalized == 'completed' && {'stripe', 'paypal', 'mercadopago', 'custom'}.contains(type)) {
      var verified = false;
      final rawMetadata = rows.first['metadata']?.toString();
      if (rawMetadata != null && rawMetadata.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawMetadata);
          verified = decoded is Map &&
              decoded['provider_verified'] == true &&
              decoded['verification_source'] == 'payment_checkout_service';
        } catch (_) {}
      }
      if (!verified) {
        throw StateError(
          'Una pasarela remota no puede marcarse como completada manualmente. Use la verificación autenticada del proveedor.',
        );
      }
    }
    await db.update(
      'payment_transactions',
      {'status': normalized, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND company_id = ?',
      whereArgs: [transactionId, rows.first['company_id']],
    );
  }

  /// Obtiene estadísticas de pagos
  Future<Map<String, dynamic>> getPaymentStatistics(
    Database db,
    int companyId,
  ) async {
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final totalResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count, SUM(amount) as total
      FROM payment_transactions
      WHERE company_id = ? AND status = 'completed'
    ''',
      [companyId],
    );

    final pendingResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count, SUM(amount) as total
      FROM payment_transactions
      WHERE company_id = ? AND status = 'pending'
    ''',
      [companyId],
    );

    final failedResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count, SUM(amount) as total
      FROM payment_transactions
      WHERE company_id = ? AND status = 'failed'
    ''',
      [companyId],
    );

    return {
      'completed': {
        'count': (totalResult.first['count'] as int?) ?? 0,
        'total': MoneyValue.fromSql(
          totalResult.first['total'],
          currency: currency,
          nullableAsZero: true,
        ).toWireMap(),
      },
      'pending': {
        'count': (pendingResult.first['count'] as int?) ?? 0,
        'total': MoneyValue.fromSql(
          pendingResult.first['total'],
          currency: currency,
          nullableAsZero: true,
        ).toWireMap(),
      },
      'failed': {
        'count': (failedResult.first['count'] as int?) ?? 0,
        'total': MoneyValue.fromSql(
          failedResult.first['total'],
          currency: currency,
          nullableAsZero: true,
        ).toWireMap(),
      },
    };
  }
}
