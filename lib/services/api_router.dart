import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter/foundation.dart';
import '../core/currency/money_currency_resolver.dart';
import '../core/app/app_version.dart';
import '../core/currency/money_value.dart';
import '../db_helper.dart';
import '../documento_pdf_service.dart';
import '../inventory/application/inventory_movement_service.dart';
import '../sales/application/create_sale_use_case.dart';
import 'api_auth_service.dart';

class ApiRouter {
  ApiRouter._();

  static final ApiRouter instance = ApiRouter._();

  Response _errorResponse(Object error, {int status = 500}) {
    debugPrint('API error ($status): $error');
    final clientError = status >= 400 && status < 500;
    final safe = error is FormatException || error is ArgumentError;
    return Response(
      status,
      body: jsonEncode({
        'success': false,
        'error': clientError && safe ? error.toString() : 'request_failed',
      }),
      headers: const {'content-type': 'application/json'},
    );
  }

  Future<Router> crearRouter() async {
    final router = Router();

    // Health check
    router.get('/api/v1/health', _healthCheckHandler);

    // Productos
    router.get('/api/v1/products', _listarProductosHandler);
    router.get('/api/v1/products/<id>', _obtenerProductoHandler);
    router.get('/api/v1/products/<id>/stock', _consultarStockHandler);
    router.patch('/api/v1/products/<id>/stock', _actualizarStockHandler);

    // Clientes
    router.get('/api/v1/customers', _listarClientesHandler);
    router.post('/api/v1/customers', _crearClienteHandler);
    router.get('/api/v1/customers/<id>', _obtenerClienteHandler);

    // Órdenes/Ventas
    router.post('/api/v1/orders', _crearOrdenHandler);
    router.get('/api/v1/orders/<id>', _obtenerOrdenHandler);

    // Facturas
    router.get('/api/v1/invoices/<id>', _obtenerFacturaHandler);

    // Pagos
    router.post('/api/v1/payments', _registrarPagoHandler);

    // Webhooks
    router.post('/api/v1/webhooks', _procesarWebhookHandler);

    return router;
  }

  Future<Response?> _requirePermission(
    Request request,
    String permission,
  ) async {
    final apiKey = request.context['apiKey'] as ApiKey?;
    if (apiKey == null) {
      return Response.unauthorized(
        jsonEncode({'success': false, 'error': 'API key no autenticada'}),
      );
    }
    if (!await ApiAuthService.instance.tienePermiso(apiKey, permission)) {
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        request.url.path,
        request.method,
      );
      return Response(
        403,
        body: jsonEncode({
          'success': false,
          'error': 'Permiso insuficiente',
          'required_permission': permission,
        }),
      );
    }
    return null;
  }

  Future<Response> _healthCheckHandler(Request request) async {
    final db = await DatabaseHelper.instance.database;
    try {
      await db.rawQuery('SELECT 1');
      return Response.ok(
        jsonEncode({
          'status': 'healthy',
          'timestamp': DateTime.now().toIso8601String(),
          'version': AppVersion.version,
        }),
      );
    } catch (e) {
      return _errorResponse(e, status: 503);
    }
  }

  Future<Response> _listarProductosHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'products:read');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/products',
        'GET',
      );

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final productos = await db.query(
        'productos',
        where: 'company_id = ?',
        whereArgs: [companyId],
        columns: ['id', 'nombre', 'stock', 'precio', 'codigo_barras'],
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'data': productos,
          'count': productos.length,
        }),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _obtenerProductoHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'products:read');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      final id = int.parse(request.params['id'] as String);
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/products/$id',
        'GET',
      );

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final productos = await db.query(
        'productos',
        where: 'id = ? AND company_id = ?',
        whereArgs: [id, companyId],
      );

      if (productos.isEmpty) {
        return Response(
          404,
          body: jsonEncode({
            'success': false,
            'error': 'Producto no encontrado',
          }),
        );
      }

      return Response.ok(
        jsonEncode({'success': true, 'data': productos.first}),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _consultarStockHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'products:read');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      final id = int.parse(request.params['id'] as String);
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/products/$id/stock',
        'GET',
      );

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final productos = await db.query(
        'productos',
        where: 'id = ? AND company_id = ?',
        whereArgs: [id, companyId],
        columns: ['id', 'nombre', 'stock'],
      );

      if (productos.isEmpty) {
        return Response(
          404,
          body: jsonEncode({
            'success': false,
            'error': 'Producto no encontrado',
          }),
        );
      }

      return Response.ok(
        jsonEncode({
          'success': true,
          'data': {
            'id': productos.first['id'],
            'nombre': productos.first['nombre'],
            'stock': productos.first['stock'],
          },
        }),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _actualizarStockHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'inventory:write');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      final id = int.parse(request.params['id'] as String);
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/products/$id/stock',
        'PATCH',
      );

      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final nuevoStock = (body['stock'] as num?)?.toDouble();
      if (nuevoStock == null || nuevoStock < 0) {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': 'Se requiere stock mayor o igual a cero',
          }),
        );
      }

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      var found = false;
      double stockAnterior = 0;
      await db.transaction((txn) async {
        final rows = await txn.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [id, companyId],
          limit: 1,
        );
        if (rows.isEmpty) return;
        found = true;
        stockAnterior = (rows.first['stock'] as num?)?.toDouble() ?? 0;
        if (stockAnterior == nuevoStock) return;
        final costo = MoneyValue.fromSql(
          rows.first['costo'],
          currency: currency,
          nullableAsZero: true,
        );
        await txn.update(
          'productos',
          {'stock': nuevoStock},
          where: 'id = ? AND company_id = ?',
          whereArgs: [id, companyId],
        );
        final delta = nuevoStock - stockAnterior;
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: id,
          type: delta > 0 ? 'entrada' : 'salida',
          quantity: delta.abs(),
          stockBefore: stockAnterior,
          stockAfter: nuevoStock,
          costBeforeMinor: costo.toSql(),
          costAfterMinor: costo.toSql(),
          costTotalMinor: costo.multiplyDecimal(delta.abs().toString()).toSql(),
          reason: body['motivo']?.toString().trim().isNotEmpty == true
              ? body['motivo'].toString().trim()
              : 'AJUSTE API',
          date: DateTime.now().toIso8601String(),
          documentType: 'api_stock_adjustment',
          createdBy: 'api:${apiKey.id}',
        );
      });

      if (!found) {
        return Response(
          404,
          body: jsonEncode({
            'success': false,
            'error': 'Producto no encontrado',
          }),
        );
      }
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'API_STOCK_ACTUALIZADO',
        entidad: 'productos',
        detalle: 'Producto ID: $id, Stock: $stockAnterior -> $nuevoStock',
      );
      return Response.ok(
        jsonEncode({
          'success': true,
          'data': {'id': id, 'stock': nuevoStock},
        }),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _listarClientesHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'customers:read');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/customers',
        'GET',
      );

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final clientes = await db.query(
        'clientes',
        where: 'company_id = ?',
        whereArgs: [companyId],
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'data': clientes,
          'count': clientes.length,
        }),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _crearClienteHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'customers:write');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/customers',
        'POST',
      );

      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final nombre = body['nombre'] as String?;
      final nit = body['nit'] as String?;
      final telefono = body['telefono'] as String?;
      final direccion = body['direccion'] as String?;
      final email = body['email'] as String?;

      if (nombre == null) {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': 'Se requiere el campo nombre',
          }),
        );
      }

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final id = await db.insert('clientes', {
        'company_id': companyId,
        'nombre': nombre,
        'nit': nit ?? '',
        'telefono': telefono ?? '',
        'direccion': direccion ?? '',
        'email': email ?? '',
        'estado': 'activo',
        'fecha': DateTime.now().toIso8601String(),
      });

      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'API_CLIENTE_CREADO',
        entidad: 'clientes',
        detalle: 'Cliente ID: $id, Nombre: $nombre',
      );

      return Response(
        201,
        body: jsonEncode({
          'success': true,
          'data': {'id': id, 'nombre': nombre},
        }),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _obtenerClienteHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'customers:read');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      final id = int.parse(request.params['id'] as String);
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/customers/$id',
        'GET',
      );

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final clientes = await db.query(
        'clientes',
        where: 'id = ? AND company_id = ?',
        whereArgs: [id, companyId],
      );

      if (clientes.isEmpty) {
        return Response(
          404,
          body: jsonEncode({
            'success': false,
            'error': 'Cliente no encontrado',
          }),
        );
      }

      return Response.ok(jsonEncode({'success': true, 'data': clientes.first}));
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _crearOrdenHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'orders:write');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/orders',
        'POST',
      );
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final rawItems = body['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': 'Se requiere al menos un item en la orden',
          }),
        );
      }

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      final zero = MoneyValue(minorUnits: 0, currency: currency);
      final items = <SaleItemInput>[];
      for (final raw in rawItems) {
        if (raw is! Map) {
          return Response(
            400,
            body: jsonEncode({'success': false, 'error': 'Item inválido'}),
          );
        }
        final productId = (raw['producto_id'] as num?)?.toInt();
        final quantity = (raw['cantidad'] as num?)?.toDouble() ?? 0;
        if (productId == null || quantity <= 0) {
          return Response(
            400,
            body: jsonEncode({
              'success': false,
              'error': 'producto_id y cantidad válidos son obligatorios',
            }),
          );
        }
        final products = await db.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [productId, companyId],
          limit: 1,
        );
        if (products.isEmpty) {
          return Response(
            404,
            body: jsonEncode({
              'success': false,
              'error': 'Producto $productId no encontrado',
            }),
          );
        }
        final product = products.first;
        final unitPrice = MoneyValue.fromMajorUnits(
          (raw['precio'] ?? product['precio'] ?? 0).toString(),
          currency: currency,
        );
        final unitCost = MoneyValue.fromSql(
          product['costo'],
          currency: currency,
          nullableAsZero: true,
        );
        final subtotal = unitPrice.multiplyDecimal(quantity.toString());
        final taxRate = (raw['impuesto_pct'] as num?)?.toDouble() ?? 0;
        final taxTotal = taxRate == 0
            ? zero
            : subtotal.percent(taxRate.toString());
        items.add(
          SaleItemInput(
            productId: productId,
            productName: product['nombre']?.toString() ?? 'Producto $productId',
            quantity: quantity,
            unitPrice: unitPrice,
            unitCost: unitCost,
            subtotal: subtotal,
            taxRate: taxRate,
            taxTotal: taxTotal,
          ),
        );
      }

      final paymentMethodId = (body['metodo_pago_id'] as num?)?.toInt() ?? 1;
      final methodRows = await db.query(
        'metodos_pago',
        where: 'id = ?',
        whereArgs: [paymentMethodId],
        limit: 1,
      );
      final paymentMethodName =
          body['metodo_pago']?.toString().trim().isNotEmpty == true
          ? body['metodo_pago'].toString().trim()
          : (methodRows.isEmpty
                ? 'EFECTIVO'
                : methodRows.first['nombre'].toString());
      final clientId = (body['cliente_id'] as num?)?.toInt();
      var clientName = body['cliente']?.toString().trim() ?? '';
      if (clientId != null) {
        final clients = await db.query(
          'clientes',
          where: 'id = ? AND company_id = ?',
          whereArgs: [clientId, companyId],
          limit: 1,
        );
        if (clients.isEmpty) {
          return Response(
            404,
            body: jsonEncode({
              'success': false,
              'error': 'Cliente no encontrado',
            }),
          );
        }
        if (clientName.isEmpty) {
          clientName = clients.first['nombre']?.toString() ?? '';
        }
      }
      if (clientName.isEmpty) clientName = 'Cliente general';
      MoneyValue amount(Object? value) => value == null
          ? zero
          : MoneyValue.fromMajorUnits(value.toString(), currency: currency);

      final result = await CreateSaleUseCase().execute(
        CreateSaleRequest(
          items: items,
          paymentMethodId: paymentMethodId,
          paymentMethodName: paymentMethodName,
          clientId: clientId,
          clientName: clientName,
          efectivo: amount(body['efectivo']),
          transferencia: amount(body['transferencia']),
          credito: amount(body['credito']),
          retefuente: amount(body['retefuente']),
          reteiva: amount(body['reteiva']),
          reteica: amount(body['reteica']),
        ),
      );

      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'API_ORDEN_CREADA',
        entidad: 'ventas',
        detalle: 'Venta ID: ${result.saleId}, Total: ${result.total.format()}',
      );
      return Response(
        201,
        body: jsonEncode({
          'success': true,
          'data': {'id': result.saleId, 'total': result.total.toWireMap()},
        }),
      );
    } catch (e) {
      return _errorResponse(e, status: 422);
    }
  }

  Future<Response> _obtenerOrdenHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'orders:read');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      final id = int.parse(request.params['id'] as String);
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/orders/$id',
        'GET',
      );

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final ventas = await db.query(
        'ventas',
        where: 'id = ? AND company_id = ?',
        whereArgs: [id, companyId],
      );

      if (ventas.isEmpty) {
        return Response(
          404,
          body: jsonEncode({'success': false, 'error': 'Orden no encontrada'}),
        );
      }

      final detalles = await db.query(
        'ventas_detalle',
        where: 'venta_id = ? AND company_id = ?',
        whereArgs: [id, companyId],
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'data': {'venta': ventas.first, 'detalles': detalles},
        }),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _obtenerFacturaHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'invoices:read');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      final id = int.parse(request.params['id'] as String);
      final formato = request.url.queryParameters['format'] ?? 'json';

      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/invoices/$id',
        'GET',
      );

      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;

      final ventas = await db.query(
        'ventas',
        where: 'id = ? AND company_id = ?',
        whereArgs: [id, companyId],
      );

      if (ventas.isEmpty) {
        return Response(
          404,
          body: jsonEncode({
            'success': false,
            'error': 'Factura no encontrada',
          }),
        );
      }

      if (formato == 'json') {
        return Response.ok(jsonEncode({'success': true, 'data': ventas.first}));
      }

      if (formato.toLowerCase() == 'pdf') {
        final archivo = await DocumentoPdfService.crearFacturaVenta(
          Map<String, dynamic>.from(ventas.first),
        );
        final bytes = await archivo.readAsBytes();
        return Response.ok(
          bytes,
          headers: {
            'content-type': 'application/pdf',
            'content-disposition': 'inline; filename="factura_$id.pdf"',
            'cache-control': 'no-store',
          },
        );
      }

      return Response(
        400,
        body: jsonEncode({
          'success': false,
          'error': 'Formato no soportado. Use json o pdf.',
        }),
      );
    } catch (e) {
      return _errorResponse(e);
    }
  }

  Future<Response> _registrarPagoHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'payments:write');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/payments',
        'POST',
      );
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final facturaId = (body['factura_id'] as num?)?.toInt();
      final metodo = body['metodo']?.toString().trim();
      final referencia = body['referencia']?.toString().trim() ?? '';
      if (facturaId == null ||
          metodo == null ||
          metodo.isEmpty ||
          body['monto'] == null) {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': 'factura_id, monto y metodo son obligatorios',
          }),
        );
      }
      final db = await DatabaseHelper.instance.database;
      final companyId = apiKey.companyId;
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      final monto = MoneyValue.fromMajorUnits(
        body['monto'].toString(),
        currency: currency,
      );
      if (monto.minorUnits <= 0) {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': 'El monto debe ser mayor que cero',
          }),
        );
      }
      final ventas = await db.query(
        'ventas',
        columns: ['id'],
        where: 'id = ? AND company_id = ?',
        whereArgs: [facturaId, companyId],
        limit: 1,
      );
      if (ventas.isEmpty) {
        return Response(
          404,
          body: jsonEncode({
            'success': false,
            'error': 'Factura no encontrada',
          }),
        );
      }
      final cuentas = await db.query(
        'cuentas_por_cobrar',
        where: 'venta_id = ? AND company_id = ? AND saldo > 0',
        whereArgs: [facturaId, companyId],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (cuentas.isEmpty) {
        return Response(
          409,
          body: jsonEncode({
            'success': false,
            'error': 'La factura no tiene una cuenta por cobrar pendiente',
          }),
        );
      }
      final cuentaId = (cuentas.first['id'] as num).toInt();
      await DatabaseHelper.instance.registrarAbonoCXC(
        cuentaId: cuentaId,
        monto: monto,
        metodoPago: metodo,
        observacion: referencia.isEmpty ? 'Pago recibido por API' : referencia,
      );
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'API_PAGO_REGISTRADO',
        entidad: 'cuentas_por_cobrar',
        detalle:
            'Factura: $facturaId, CxC: $cuentaId, Monto: ${monto.format()}, Método: $metodo',
      );
      return Response(
        201,
        body: jsonEncode({
          'success': true,
          'data': {
            'factura_id': facturaId,
            'cuenta_id': cuentaId,
            'monto': monto.toWireMap(),
            'referencia': referencia,
          },
        }),
      );
    } catch (e) {
      return _errorResponse(e, status: 422);
    }
  }

  Future<Response> _procesarWebhookHandler(Request request) async {
    try {
      final denied = await _requirePermission(request, 'webhooks:write');
      if (denied != null) return denied;
      final apiKey = request.context['apiKey'] as ApiKey;
      final rawBody = await request.readAsString();
      final signature = request.headers['X-Webhook-Signature']?.trim() ?? '';
      if (signature.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'success': false,
            'error': 'Falta X-Webhook-Signature',
          }),
        );
      }
      final expected = Hmac(
        sha256,
        utf8.encode(apiKey.key),
      ).convert(utf8.encode(rawBody)).toString();
      if (!_constantTimeEquals(
        signature.toLowerCase(),
        expected.toLowerCase(),
      )) {
        return Response(
          401,
          body: jsonEncode({'success': false, 'error': 'Firma HMAC inválida'}),
        );
      }
      final decoded = rawBody.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        return Response(
          400,
          body: jsonEncode({'success': false, 'error': 'JSON inválido'}),
        );
      }
      final evento =
          request.headers['X-Webhook-Event'] ?? decoded['event']?.toString();
      await ApiAuthService.instance.registrarAcceso(
        apiKey,
        '/api/v1/webhooks',
        'POST',
      );
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'API_WEBHOOK_RECIBIDO',
        entidad: 'webhooks',
        detalle: 'Evento: ${evento ?? 'sin_tipo'}; firma HMAC verificada',
      );
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Webhook autenticado'}),
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({'success': false, 'error': 'Webhook inválido'}),
      );
    }
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
