import 'dart:io';

import 'package:dio/dio.dart';
import '../core/currency/money_currency_resolver.dart';
import '../core/currency/money_value.dart';
import '../db_helper.dart';
import '../integrations/application/integration_settings_service.dart';
import '../integrations/domain/integration_definition.dart';

enum PseTransactionStatus { pendiente, procesando, exitoso, fallido, expirado }

class PseConfig {
  const PseConfig({
    required this.apiKey,
    required this.merchantId,
    required this.endpoint,
    this.activo = true,
  });

  final String apiKey;
  final String merchantId;
  final String endpoint;
  final bool activo;
}

class PseTransaction {
  const PseTransaction({
    required this.transactionId,
    required this.reference,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.bankCode,
    this.bankName,
    this.returnUrl,
    this.processedAt,
  });

  final String transactionId;
  final String reference;
  final MoneyValue amount;
  final PseTransactionStatus status;
  final DateTime createdAt;
  final String? bankCode;
  final String? bankName;
  final String? returnUrl;
  final DateTime? processedAt;

  Map<String, dynamic> toMap() {
    return {
      'transaction_id': transactionId,
      'reference': reference,
      'amount': amount.toSql(),
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'bank_code': bankCode,
      'bank_name': bankName,
      'return_url': returnUrl,
      'processed_at': processedAt?.toIso8601String(),
    };
  }

  static PseTransaction fromMap(
    Map<String, dynamic> map, {
    required MoneyValue Function(Object?) amountFromSql,
  }) {
    return PseTransaction(
      transactionId: map['transaction_id'] as String,
      reference: map['reference'] as String,
      amount: amountFromSql(map['amount']),
      status: PseTransactionStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => PseTransactionStatus.pendiente,
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      bankCode: map['bank_code'] as String?,
      bankName: map['bank_name'] as String?,
      returnUrl: map['return_url'] as String?,
      processedAt: map['processed_at'] != null
          ? DateTime.parse(map['processed_at'] as String)
          : null,
    );
  }
}

class PseService {
  PseService._();

  static final PseService instance = PseService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  Future<PseConfig?> obtenerConfiguracion() async {
    final settings = IntegrationSettingsService.instance;
    if (!await settings.isConfigured('pse')) return null;
    final values = await settings.loadValues(IntegrationRegistry.byKey('pse'));
    final endpoint = (values['endpoint'] ?? '').trim();
    if (!_endpointPermitido(endpoint)) {
      throw StateError('El endpoint PSE/proveedor debe usar HTTPS salvo localhost.');
    }
    return PseConfig(
      apiKey: values['api_key'] ?? '',
      merchantId: values['merchant_id'] ?? '',
      endpoint: endpoint.replaceAll(RegExp(r'/+$'), ''),
      activo: true,
    );
  }

  /// Compatibilidad para consumidores antiguos: redirige la configuración al
  /// Centro de Integraciones, evitando secretos persistidos en SQLite.
  Future<void> guardarConfiguracion(PseConfig config) async {
    await IntegrationSettingsService.instance.save(
      IntegrationRegistry.byKey('pse'),
      values: {
        'endpoint': config.endpoint,
        'api_key': config.apiKey,
        'merchant_id': config.merchantId,
      },
      enabled: config.activo,
    );
  }

  bool _endpointPermitido(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) return false;
    if (uri.scheme.toLowerCase() == 'https') return true;
    return uri.scheme.toLowerCase() == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase());
  }

  Future<PseTransaction> iniciarTransaccion({
    required String reference,
    required MoneyValue amount,
    required String returnUrl,
    String? bankCode,
    String? description,
  }) async {
    final config = await obtenerConfiguracion();
    if (config == null || !config.activo) {
      throw Exception('PSE no configurado o inactivo');
    }

    try {
      _dio.options.headers['Authorization'] = 'Bearer ${config.apiKey}';

      final response = await _dio.post(
        '${config.endpoint}/transactions',
        data: {
          'merchant_id': config.merchantId,
          'reference': reference,
          'amount': amount.toMajorUnitsString(),
          'currency': 'COP',
          'return_url': returnUrl,
          'bank_code': bankCode,
          'description': description ?? 'Pago PSE MerkaERP',
        },
      );

      if (response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        final transaction = PseTransaction(
          transactionId: data['transaction_id'] as String,
          reference: reference,
          amount: amount,
          status: PseTransactionStatus.pendiente,
          createdAt: DateTime.now(),
          bankCode: bankCode,
          returnUrl: returnUrl,
        );

        await _guardarTransaccion(transaction);

        await DatabaseHelper.instance.registrarEventoAuditoria(
          accion: 'PSE_TRANSACCION_INICIADA',
          entidad: 'pagos',
          detalle: 'Reference: $reference, Amount: $amount',
        );

        return transaction;
      }

      throw Exception('Error al iniciar transacción: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error en PSE: $e');
    }
  }

  Future<PseTransactionStatus> consultarEstado(String transactionId) async {
    final config = await obtenerConfiguracion();
    if (config == null || !config.activo) {
      throw Exception('PSE no configurado o inactivo');
    }

    try {
      _dio.options.headers['Authorization'] = 'Bearer ${config.apiKey}';

      final response = await _dio.get(
        '${config.endpoint}/transactions/$transactionId',
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final statusStr = data['status'] as String;

        final status = PseTransactionStatus.values.firstWhere(
          (e) => e.name == statusStr.toLowerCase(),
          orElse: () => PseTransactionStatus.pendiente,
        );

        // Actualizar estado en BD
        await _actualizarEstadoTransaccion(transactionId, status);

        return status;
      }

      throw Exception('Error al consultar estado: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error en PSE: $e');
    }
  }

  Future<void> procesarWebhook(Map<String, dynamic> webhookData) async {
    final transactionId = webhookData['transaction_id'] as String?;
    final statusStr = webhookData['status'] as String?;

    if (transactionId == null || statusStr == null) {
      throw Exception('Webhook inválido: faltan datos requeridos');
    }

    final status = PseTransactionStatus.values.firstWhere(
      (e) => e.name == statusStr.toLowerCase(),
      orElse: () => PseTransactionStatus.pendiente,
    );

    await _actualizarEstadoTransaccion(transactionId, status);

    // Si el pago fue exitoso, procesar el pago en el sistema
    if (status == PseTransactionStatus.exitoso) {
      final transaccion = await _obtenerTransaccion(transactionId);
      if (transaccion != null) {
        await _procesarPagoExitoso(transaccion);
      }
    }

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'PSE_WEBHOOK_PROCESADO',
      entidad: 'pagos',
      detalle: 'Transaction ID: $transactionId, Status: $statusStr',
    );
  }

  Future<void> _guardarTransaccion(PseTransaction transaction) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.insert('pse_transacciones', {
      'company_id': companyId,
      ...transaction.toMap(),
    });
  }

  Future<void> _actualizarEstadoTransaccion(
    String transactionId,
    PseTransactionStatus status,
  ) async {
    final db = await DatabaseHelper.instance.database;

    await db.update(
      'pse_transacciones',
      {'status': status.name, 'processed_at': DateTime.now().toIso8601String()},
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<PseTransaction?> _obtenerTransaccion(String transactionId) async {
    final db = await DatabaseHelper.instance.database;

    final rows = await db.query(
      'pse_transacciones',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: await DatabaseHelper.instance.obtenerEmpresaActivaId(),
    );
    return PseTransaction.fromMap(
      rows.first,
      amountFromSql: (value) => MoneyValue.fromSql(value, currency: currency),
    );
  }

  Future<void> _procesarPagoExitoso(PseTransaction transaction) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    // Registrar movimiento de caja
    await db.insert('movimientos_caja', {
      'company_id': companyId,
      'tipo': 'ingreso',
      'concepto': 'Pago PSE - Ref: ${transaction.reference}',
      'monto': transaction.amount.toSql(),
      'fecha': DateTime.now().toIso8601String(),
      'origen': 'pse',
    });

    // Si la referencia corresponde a una factura, actualizarla
    final facturas = await db.query(
      'cuentas_por_cobrar',
      where: 'descripcion LIKE ?',
      whereArgs: ['%${transaction.reference}%'],
    );

    for (final factura in facturas) {
      await db.insert('abonos_cxc', {
        'company_id': companyId,
        'cuenta_id': factura['id'],
        'monto': transaction.amount.toSql(),
        'metodo_pago': 'PSE',
        'observacion': 'Transacción PSE: ${transaction.transactionId}',
        'fecha': DateTime.now().toIso8601String(),
      });
    }

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'PSE_PAGO_PROCESADO',
      entidad: 'pagos',
      detalle:
          'Transaction ID: ${transaction.transactionId}, Amount: ${transaction.amount}',
    );
  }

  Future<List<Map<String, dynamic>>> obtenerBancos() async {
    final config = await obtenerConfiguracion();
    if (config == null || !config.activo) {
      throw Exception('PSE no configurado o inactivo');
    }

    try {
      _dio.options.headers['Authorization'] = 'Bearer ${config.apiKey}';

      final response = await _dio.get('${config.endpoint}/banks');

      if (response.statusCode == 200) {
        return (response.data['banks'] as List)
            .map((bank) => bank as Map<String, dynamic>)
            .toList();
      }

      throw Exception('Error al obtener bancos: ${response.statusCode}');
    } catch (e) {
      throw Exception('Error en PSE: $e');
    }
  }

  Future<void> probarConexion() async {
    final config = await obtenerConfiguracion();
    if (config == null) {
      throw Exception('PSE no configurado');
    }
    // El endpoint de verificación es configurable desde el Centro de
    // Integraciones. La conexión TCP al host confirma alcanzabilidad
    // sin asumir una ruta /health que el proveedor PSE puede no tener.
    try {
      final uri = Uri.parse(config.endpoint);
      final host = uri.host;
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 10));
      await socket.close();
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'PSE_CONEXION_EXITOSA',
        entidad: 'integraciones',
        detalle: 'Merchant ID: ${config.merchantId} — host alcanzable',
      );
    } catch (e) {
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'PSE_CONEXION_FALLIDA',
        entidad: 'integraciones',
        detalle: 'Error: $e',
      );
      rethrow;
    }
  }
}
