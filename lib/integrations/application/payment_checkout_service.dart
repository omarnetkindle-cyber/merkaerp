import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../domain/integration_definition.dart';
import 'integration_settings_service.dart';

class PaymentCheckoutSession {
  const PaymentCheckoutSession({
    required this.provider,
    required this.externalId,
    required this.status,
    this.approvalUrl,
    this.clientSecret,
    this.rawMetadata = const {},
  });

  final String provider;
  final String externalId;
  final String status;
  final String? approvalUrl;
  final String? clientSecret;
  final Map<String, Object?> rawMetadata;

  Map<String, Object?> toMap() => {
        'provider': provider,
        'external_id': externalId,
        'provider_status': status,
        'approval_url': approvalUrl,
        'client_secret': clientSecret,
        'raw_metadata': rawMetadata,
        // Crear la sesión nunca equivale a acreditar el pago en MerkaERP.
        'payment_confirmed': false,
      };
}

/// Inicia checkouts remotos sin convertir una respuesta de creación en un
/// ingreso contable. La confirmación/captura se procesa por el flujo propio del
/// proveedor y debe validarse antes de registrar el pago en el ERP.
class PaymentCheckoutService {
  PaymentCheckoutService._();
  static final PaymentCheckoutService instance = PaymentCheckoutService._();

  final IntegrationSettingsService _settings = IntegrationSettingsService.instance;

  Future<void> _assertActiveCompany(int companyId) async {
    final db = await DatabaseHelper.instance.database;
    final active = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    if (active != companyId) {
      throw StateError('Las credenciales de pago pertenecen a la empresa activa.');
    }
  }

  Future<PaymentCheckoutSession> createStripeIntent({
    required int companyId,
    required MoneyValue amount,
    required String reference,
    String? description,
  }) async {
    await _assertActiveCompany(companyId);
    if (amount.minorUnits <= 0) throw ArgumentError('El valor debe ser positivo.');
    final definition = IntegrationRegistry.byKey('stripe');
    if (!await _settings.isConfigured(definition.key)) {
      throw StateError('Stripe no está configurado en el Centro de Integraciones.');
    }
    final values = await _settings.loadValues(definition);
    final response = await http.post(
      Uri.https('api.stripe.com', '/v1/payment_intents'),
      headers: {'Authorization': 'Bearer ${values['secret_key']}'},
      body: {
        'amount': amount.minorUnits.toString(),
        'currency': amount.currencyCode.toLowerCase(),
        'automatic_payment_methods[enabled]': 'true',
        'metadata[merka_reference]': reference,
        if ((description ?? '').trim().isNotEmpty) 'description': description!.trim(),
      },
    ).timeout(const Duration(seconds: 20));
    final json = _jsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Stripe rechazó la creación del checkout (HTTP ${response.statusCode}).');
    }
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) throw StateError('Stripe no devolvió un PaymentIntent válido.');
    await _audit('stripe', id, reference);
    return PaymentCheckoutSession(
      provider: 'stripe',
      externalId: id,
      status: json['status']?.toString() ?? 'created',
      clientSecret: json['client_secret']?.toString(),
      rawMetadata: {'livemode': json['livemode'], 'reference': reference},
    );
  }

  Future<PaymentCheckoutSession> createPayPalOrder({
    required int companyId,
    required MoneyValue amount,
    required String reference,
    String? description,
    String? returnUrl,
    String? cancelUrl,
  }) async {
    await _assertActiveCompany(companyId);
    if (amount.minorUnits <= 0) throw ArgumentError('El valor debe ser positivo.');
    final definition = IntegrationRegistry.byKey('paypal');
    if (!await _settings.isConfigured(definition.key)) {
      throw StateError('PayPal no está configurado en el Centro de Integraciones.');
    }
    final values = await _settings.loadValues(definition);
    final live = values['environment'] == 'live';
    final host = live ? 'api-m.paypal.com' : 'api-m.sandbox.paypal.com';
    final token = await _payPalAccessToken(host, values);

    final body = <String, Object?>{
      'intent': 'CAPTURE',
      'purchase_units': [
        {
          'reference_id': reference,
          if ((description ?? '').trim().isNotEmpty) 'description': description!.trim(),
          'amount': {
            'currency_code': amount.currencyCode.toUpperCase(),
            'value': amount.toMajorUnitsString(),
          },
        }
      ],
    };
    // application_context sigue siendo aceptado por el flujo Orders para las
    // URLs de retorno; se agrega solo cuando el consumidor las proporciona.
    if ((returnUrl ?? '').trim().isNotEmpty || (cancelUrl ?? '').trim().isNotEmpty) {
      body['application_context'] = {
        if ((returnUrl ?? '').trim().isNotEmpty) 'return_url': returnUrl!.trim(),
        if ((cancelUrl ?? '').trim().isNotEmpty) 'cancel_url': cancelUrl!.trim(),
      };
    }
    final response = await http.post(
      Uri.https(host, '/v2/checkout/orders'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'PayPal-Request-Id': 'merka-$companyId-$reference',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 20));
    final json = _jsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('PayPal rechazó la creación de la orden (HTTP ${response.statusCode}).');
    }
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) throw StateError('PayPal no devolvió una orden válida.');
    String? approvalUrl;
    final links = json['links'];
    if (links is List) {
      for (final raw in links) {
        if (raw is Map && raw['rel']?.toString() == 'approve') {
          approvalUrl = raw['href']?.toString();
          break;
        }
      }
    }
    await _audit('paypal', id, reference);
    return PaymentCheckoutSession(
      provider: 'paypal',
      externalId: id,
      status: json['status']?.toString() ?? 'CREATED',
      approvalUrl: approvalUrl,
      rawMetadata: {'environment': live ? 'live' : 'sandbox', 'reference': reference},
    );
  }

  Future<PaymentCheckoutSession> createMercadoPagoPreference({
    required int companyId,
    required MoneyValue amount,
    required String reference,
    required String title,
    String? returnUrl,
  }) async {
    await _assertActiveCompany(companyId);
    if (amount.minorUnits <= 0) throw ArgumentError('El valor debe ser positivo.');
    final definition = IntegrationRegistry.byKey('mercadopago');
    if (!await _settings.isConfigured(definition.key)) {
      throw StateError('Mercado Pago no está configurado en el Centro de Integraciones.');
    }
    final values = await _settings.loadValues(definition);
    final body = <String, Object?>{
      'items': [
        {
          'title': title.trim().isEmpty ? 'Pago MerkaERP' : title.trim(),
          'quantity': 1,
          'currency_id': amount.currencyCode.toUpperCase(),
          'unit_price': amount.toMajorUnitsDoubleForDisplay(),
        }
      ],
      'external_reference': reference,
      if ((returnUrl ?? '').trim().isNotEmpty)
        'back_urls': {
          'success': returnUrl!.trim(),
          'pending': returnUrl.trim(),
          'failure': returnUrl.trim(),
        },
    };
    final response = await http.post(
      Uri.https('api.mercadopago.com', '/checkout/preferences'),
      headers: {
        'Authorization': 'Bearer ${values['access_token']}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 20));
    final json = _jsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Mercado Pago rechazó la preferencia (HTTP ${response.statusCode}).');
    }
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) throw StateError('Mercado Pago no devolvió una preferencia válida.');
    final approvalUrl = (json['init_point'] ?? json['sandbox_init_point'])?.toString();
    await _audit('mercadopago', id, reference);
    return PaymentCheckoutSession(
      provider: 'mercadopago',
      externalId: id,
      status: 'preference_created',
      approvalUrl: approvalUrl,
      rawMetadata: {'reference': reference},
    );
  }

  Future<Map<String, Object?>> verifyStripeIntent({
    required int companyId,
    required String paymentIntentId,
    required String reference,
    required MoneyValue expectedAmount,
  }) async {
    await _assertActiveCompany(companyId);
    final definition = IntegrationRegistry.byKey('stripe');
    if (!await _settings.isConfigured(definition.key)) {
      throw StateError('Stripe no está configurado.');
    }
    final values = await _settings.loadValues(definition);
    final response = await http.get(
      Uri.https('api.stripe.com', '/v1/payment_intents/${Uri.encodeComponent(paymentIntentId)}'),
      headers: {'Authorization': 'Bearer ${values['secret_key']}'},
    ).timeout(const Duration(seconds: 20));
    final json = _jsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Stripe rechazó la verificación (HTTP ${response.statusCode}).');
    }
    final remoteReference = ((json['metadata'] is Map)
            ? (json['metadata'] as Map)['merka_reference']
            : null)
        ?.toString();
    final remoteAmount = int.tryParse((json['amount_received'] ?? json['amount'])?.toString() ?? '');
    final remoteCurrency = json['currency']?.toString().toUpperCase();
    final verified = json['status']?.toString() == 'succeeded' &&
        remoteReference == reference &&
        remoteAmount == expectedAmount.minorUnits &&
        remoteCurrency == expectedAmount.currencyCode.toUpperCase();
    await _auditVerification('stripe', paymentIntentId, reference, verified);
    return {
      'provider': 'stripe',
      'external_id': paymentIntentId,
      'provider_status': json['status']?.toString(),
      'reference': remoteReference,
      'amount_minor': remoteAmount,
      'currency': remoteCurrency,
      'provider_verified': verified,
    };
  }

  Future<Map<String, Object?>> verifyPayPalOrder({
    required int companyId,
    required String orderId,
    required String reference,
    required MoneyValue expectedAmount,
  }) async {
    await _assertActiveCompany(companyId);
    final definition = IntegrationRegistry.byKey('paypal');
    if (!await _settings.isConfigured(definition.key)) {
      throw StateError('PayPal no está configurado.');
    }
    final values = await _settings.loadValues(definition);
    final live = values['environment'] == 'live';
    final host = live ? 'api-m.paypal.com' : 'api-m.sandbox.paypal.com';
    final token = await _payPalAccessToken(host, values);
    final response = await http.get(
      Uri.https(host, '/v2/checkout/orders/${Uri.encodeComponent(orderId)}'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 20));
    final json = _jsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('PayPal rechazó la verificación (HTTP ${response.statusCode}).');
    }
    String? remoteReference;
    String? remoteValue;
    String? remoteCurrency;
    final units = json['purchase_units'];
    if (units is List && units.isNotEmpty && units.first is Map) {
      final unit = units.first as Map;
      remoteReference = unit['reference_id']?.toString();
      if (unit['amount'] is Map) {
        final amount = unit['amount'] as Map;
        remoteValue = amount['value']?.toString();
        remoteCurrency = amount['currency_code']?.toString().toUpperCase();
      }
    }
    final expectedMajor = expectedAmount.toMajorUnitsString();
    final verified = json['status']?.toString().toUpperCase() == 'COMPLETED' &&
        remoteReference == reference &&
        _sameDecimal(remoteValue, expectedMajor) &&
        remoteCurrency == expectedAmount.currencyCode.toUpperCase();
    await _auditVerification('paypal', orderId, reference, verified);
    return {
      'provider': 'paypal',
      'external_id': orderId,
      'provider_status': json['status']?.toString(),
      'reference': remoteReference,
      'amount': remoteValue,
      'currency': remoteCurrency,
      'provider_verified': verified,
    };
  }

  Future<Map<String, Object?>> verifyMercadoPagoPayment({
    required int companyId,
    required String paymentId,
    required String reference,
    required MoneyValue expectedAmount,
  }) async {
    await _assertActiveCompany(companyId);
    final definition = IntegrationRegistry.byKey('mercadopago');
    if (!await _settings.isConfigured(definition.key)) {
      throw StateError('Mercado Pago no está configurado.');
    }
    final values = await _settings.loadValues(definition);
    final response = await http.get(
      Uri.https('api.mercadopago.com', '/v1/payments/${Uri.encodeComponent(paymentId)}'),
      headers: {'Authorization': 'Bearer ${values['access_token']}'},
    ).timeout(const Duration(seconds: 20));
    final json = _jsonObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Mercado Pago rechazó la verificación (HTTP ${response.statusCode}).');
    }
    final remoteReference = json['external_reference']?.toString();
    final remoteValue = json['transaction_amount']?.toString();
    final remoteCurrency = json['currency_id']?.toString().toUpperCase();
    final verified = json['status']?.toString().toLowerCase() == 'approved' &&
        remoteReference == reference &&
        _sameDecimal(remoteValue, expectedAmount.toMajorUnitsString()) &&
        remoteCurrency == expectedAmount.currencyCode.toUpperCase();
    await _auditVerification('mercadopago', paymentId, reference, verified);
    return {
      'provider': 'mercadopago',
      'external_id': paymentId,
      'provider_status': json['status']?.toString(),
      'reference': remoteReference,
      'amount': remoteValue,
      'currency': remoteCurrency,
      'provider_verified': verified,
    };
  }

  bool _sameDecimal(String? left, String right) {
    if (left == null || left.trim().isEmpty) return false;
    final a = double.tryParse(left.trim());
    final b = double.tryParse(right.trim());
    if (a == null || b == null || !a.isFinite || !b.isFinite) return false;
    return (a - b).abs() < 0.0000001;
  }

  Future<String> _payPalAccessToken(
    String host,
    Map<String, String> values,
  ) async {
    final basic = base64Encode(utf8.encode('${values['client_id']}:${values['client_secret']}'));
    final response = await http.post(
      Uri.https(host, '/v1/oauth2/token'),
      headers: {
        'Authorization': 'Basic $basic',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'grant_type=client_credentials',
    ).timeout(const Duration(seconds: 20));
    final json = _jsonObject(response.body);
    final token = json['access_token']?.toString();
    if (response.statusCode < 200 || response.statusCode >= 300 || token == null || token.isEmpty) {
      throw StateError('PayPal no devolvió un token OAuth válido.');
    }
    return token;
  }

  Future<void> _auditVerification(
    String provider,
    String externalId,
    String reference,
    bool verified,
  ) async {
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: verified ? 'PAGO_EXTERNO_VERIFICADO' : 'PAGO_EXTERNO_NO_VERIFICADO',
      entidad: 'payments',
      detalle: 'provider=$provider; external_id=$externalId; reference=$reference; provider_verified=$verified',
    );
  }

  Map<String, dynamic> _jsonObject(String body) {
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    if (decoded is! Map) throw const FormatException('El proveedor devolvió JSON inválido.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _audit(String provider, String externalId, String reference) async {
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CHECKOUT_EXTERNO_CREADO',
      entidad: 'payments',
      detalle: 'provider=$provider; external_id=$externalId; reference=$reference; payment_confirmed=false',
    );
  }
}
