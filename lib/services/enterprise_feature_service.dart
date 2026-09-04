import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/currency/currency.dart';
import '../core/currency/money_currency_resolver.dart';
import '../core/currency/money_value.dart';
import '../inventory/application/inventory_movement_service.dart';
import '../db_helper.dart';

class EnterpriseLineItem {
  const EnterpriseLineItem({
    required this.productoId,
    required this.producto,
    required this.cantidad,
    required this.precioUnitario,
  });

  final int productoId;
  final String producto;
  final double cantidad;
  final MoneyValue precioUnitario;

  MoneyValue get subtotal =>
      precioUnitario.multiplyDecimal(cantidad.toString());
}

class EnterpriseFeatureService {
  EnterpriseFeatureService({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  Future<int> registrarBodega({
    required String codigo,
    required String nombre,
    String direccion = '',
    String telefono = '',
    String estado = 'activa',
  }) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    return db.insert('bodegas', {
      'company_id': companyId,
      'codigo': codigo.trim().toUpperCase(),
      'nombre': nombre.trim(),
      'direccion': direccion.trim(),
      'telefono': telefono.trim(),
      'estado': estado,
      'activa': estado == 'activa' ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> crearCotizacion({
    int? clienteId,
    String cliente = 'Consumidor final',
    required List<EnterpriseLineItem> items,
    DateTime? venceEn,
    String observacion = '',
  }) async {
    _validarItems(items);
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final totals = _totales(items, currency);
    return db.transaction((txn) async {
      final id = await txn.insert('cotizaciones', {
        'company_id': companyId,
        'cliente_id': clienteId,
        'cliente': cliente,
        'estado': 'borrador',
        'subtotal': totals.subtotal.toSql(),
        'impuesto': totals.impuesto.toSql(),
        'total': totals.total.toSql(),
        'fecha': DateTime.now().toIso8601String(),
        'vence_en': venceEn?.toIso8601String(),
        'observacion': observacion,
      });
      for (final item in items) {
        await txn.insert('cotizacion_detalle', {
          'company_id': companyId,
          'cotizacion_id': id,
          'producto_id': item.productoId,
          'producto': item.producto,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioUnitario.toSql(),
          'subtotal': item.subtotal.toSql(),
        });
      }
      await _registrarEventoApi(txn, companyId, 'cotizacion.creada', {
        'id': id,
        'cliente': cliente,
        'total': totals.total.toWireMap(),
      });
      return id;
    });
  }

  Future<int> convertirCotizacionAPedido(int cotizacionId) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    return db.transaction((txn) async {
      final cotizaciones = await txn.query(
        'cotizaciones',
        where: 'id = ? AND company_id = ?',
        whereArgs: [cotizacionId, companyId],
        limit: 1,
      );
      if (cotizaciones.isEmpty) {
        throw StateError('La cotizacion no existe.');
      }
      final cotizacion = cotizaciones.first;
      final pedidoId = await txn.insert('pedidos', {
        'company_id': companyId,
        'cotizacion_id': cotizacionId,
        'cliente_id': cotizacion['cliente_id'],
        'cliente': cotizacion['cliente'],
        'estado': 'aprobado',
        'subtotal': cotizacion['subtotal'],
        'impuesto': cotizacion['impuesto'],
        'total': cotizacion['total'],
        'fecha': DateTime.now().toIso8601String(),
        'entrega_en': null,
        'observacion': cotizacion['observacion'],
      });
      final detalles = await txn.query(
        'cotizacion_detalle',
        where: 'cotizacion_id = ? AND company_id = ?',
        whereArgs: [cotizacionId, companyId],
      );
      for (final item in detalles) {
        await txn.insert('pedido_detalle', {
          'company_id': companyId,
          'pedido_id': pedidoId,
          'producto_id': item['producto_id'],
          'producto': item['producto'],
          'cantidad': item['cantidad'],
          'precio_unitario': item['precio_unitario'],
          'subtotal': item['subtotal'],
        });
      }
      await txn.update(
        'cotizaciones',
        {'estado': 'aprobado'},
        where: 'id = ? AND company_id = ?',
        whereArgs: [cotizacionId, companyId],
      );
      await _registrarEventoApi(txn, companyId, 'pedido.creado', {
        'id': pedidoId,
        'cotizacion_id': cotizacionId,
      });
      return pedidoId;
    });
  }

  Future<int> facturarPedido(
    int pedidoId, {
    int metodoPagoId = 1,
    int? bodegaId,
  }) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    return db.transaction((txn) async {
      final pedidos = await txn.query(
        'pedidos',
        where: 'id = ? AND company_id = ?',
        whereArgs: [pedidoId, companyId],
        limit: 1,
      );
      if (pedidos.isEmpty) throw StateError('El pedido no existe.');
      final pedido = pedidos.first;
      final detalles = await txn.query(
        'pedido_detalle',
        where: 'pedido_id = ? AND company_id = ?',
        whereArgs: [pedidoId, companyId],
      );
      if (detalles.isEmpty) {
        throw StateError('El pedido no tiene productos.');
      }

      for (final item in detalles) {
        final productoId = (item['producto_id'] as num).toInt();
        final cantidad = (item['cantidad'] as num).toDouble();
        await _descontarStock(txn, companyId, productoId, cantidad, bodegaId);
      }

      final ventaId = await txn.insert('ventas', {
        'company_id': companyId,
        'producto_id': 0,
        'producto': 'Pedido #$pedidoId',
        'cantidad': 1,
        'precio_unitario': pedido['total'],
        'costo_unitario': 0,
        'subtotal': pedido['subtotal'],
        'impuesto_pct': 0,
        'impuesto_total': pedido['impuesto'],
        'total': pedido['total'],
        'fecha': DateTime.now().toIso8601String(),
        'metodo_pago_id': metodoPagoId,
        'estado': 'emitida',
      });
      for (final item in detalles) {
        await txn.insert('ventas_detalle', {
          'company_id': companyId,
          'venta_id': ventaId,
          'producto_id': item['producto_id'],
          'producto': item['producto'],
          'cantidad': item['cantidad'],
          'precio_unitario': item['precio_unitario'],
          'subtotal': item['subtotal'],
        });
      }
      await txn.update(
        'pedidos',
        {'estado': 'facturado'},
        where: 'id = ? AND company_id = ?',
        whereArgs: [pedidoId, companyId],
      );
      await _registrarEventoApi(txn, companyId, 'venta.creada', {
        'id': ventaId,
        'pedido_id': pedidoId,
        'total': pedido['total'],
      });
      return ventaId;
    });
  }

  Future<int> registrarDevolucionVenta({
    required int ventaId,
    required List<EnterpriseLineItem> items,
    String motivo = '',
  }) async {
    _validarItems(items);
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    var total = MoneyValue(minorUnits: 0, currency: currency);
    for (final item in items) {
      total += item.subtotal;
    }
    return db.transaction((txn) async {
      final id = await txn.insert('devoluciones_ventas', {
        'company_id': companyId,
        'venta_id': ventaId,
        'nota_credito': 'NC-$ventaId-${DateTime.now().millisecondsSinceEpoch}',
        'total': total.toSql(),
        'motivo': motivo,
        'estado': 'emitida',
        'fecha': DateTime.now().toIso8601String(),
      });
      for (final item in items) {
        await txn.insert('devoluciones_ventas_detalle', {
          'company_id': companyId,
          'devolucion_id': id,
          'venta_id': ventaId,
          'producto_id': item.productoId,
          'producto': item.producto,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioUnitario.toSql(),
          'subtotal': item.subtotal.toSql(),
        });
        await _sumarStock(txn, companyId, item.productoId, item.cantidad);
      }
      await _registrarEventoApi(txn, companyId, 'nota_credito.creada', {
        'id': id,
        'venta_id': ventaId,
        'total': total.toWireMap(),
      });
      return id;
    });
  }

  Future<int> registrarDevolucionCompra({
    required int compraId,
    required List<EnterpriseLineItem> items,
    String motivo = '',
  }) async {
    _validarItems(items);
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    var total = MoneyValue(minorUnits: 0, currency: currency);
    for (final item in items) {
      total += item.subtotal;
    }
    return db.transaction((txn) async {
      final id = await txn.insert('devoluciones_compras', {
        'company_id': companyId,
        'compra_id': compraId,
        'total': total.toSql(),
        'motivo': motivo,
        'estado': 'emitida',
        'fecha': DateTime.now().toIso8601String(),
      });
      for (final item in items) {
        await txn.insert('devoluciones_compras_detalle', {
          'company_id': companyId,
          'devolucion_id': id,
          'compra_id': compraId,
          'producto_id': item.productoId,
          'producto': item.producto,
          'cantidad': item.cantidad,
          'costo_unitario': item.precioUnitario.toSql(),
          'subtotal': item.subtotal.toSql(),
        });
        await _descontarStock(txn, companyId, item.productoId, item.cantidad);
      }
      await _registrarEventoApi(txn, companyId, 'devolucion_compra.creada', {
        'id': id,
        'compra_id': compraId,
        'total': total.toWireMap(),
      });
      return id;
    });
  }

  Future<int> configurarComision({
    int? usuarioId,
    int? productoId,
    required double porcentaje,
  }) async {
    if (porcentaje < 0 || porcentaje > 100) {
      throw ArgumentError('La comision debe estar entre 0 y 100.');
    }
    final db = await _db.database;
    return db.insert('comisiones_vendedor', {
      'company_id': await _db.obtenerEmpresaActivaId(),
      'usuario_id': usuarioId,
      'producto_id': productoId,
      'porcentaje': porcentaje,
      'activa': 1,
      'actualizado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<double> liquidarComisionVenta({
    required int ventaId,
    int? usuarioId,
  }) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final ventas = await db.query(
      'ventas',
      where: 'id = ? AND company_id = ?',
      whereArgs: [ventaId, companyId],
      limit: 1,
    );
    if (ventas.isEmpty) throw StateError('La venta no existe.');
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final base = MoneyValue.fromSql(ventas.first['total'], currency: currency);
    final rules = await db.query(
      'comisiones_vendedor',
      where:
          'company_id = ? AND activa = 1 AND (usuario_id IS NULL OR usuario_id = ?)',
      whereArgs: [companyId, usuarioId],
      orderBy: 'usuario_id DESC, producto_id DESC',
      limit: 1,
    );
    final porcentaje = rules.isEmpty
        ? 0.0
        : (rules.first['porcentaje'] as num?)?.toDouble() ?? 0.0;
    final comision = base.percent(porcentaje.toString());
    await db.insert('comisiones_liquidadas', {
      'company_id': companyId,
      'venta_id': ventaId,
      'usuario_id': usuarioId,
      'base': base.toSql(),
      'porcentaje': porcentaje,
      'comision': comision.toSql(),
      'periodo': DateTime.now().toIso8601String().substring(0, 7),
      'fecha': DateTime.now().toIso8601String(),
    });
    return comision.toMajorUnitsDoubleForDisplay();
  }

  Future<int> crearPresupuesto({
    required String periodo,
    int? cuentaId,
    String categoria = '',
    required MoneyValue monto,
    double alertaPct = 90,
  }) async {
    final db = await _db.database;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: await _db.obtenerEmpresaActivaId(),
    );
    if (monto.currencyCode != currency.code ||
        monto.decimalPlaces != currency.decimalPlaces) {
      throw StateError('Budget currency does not match the company currency');
    }
    return db.insert('presupuesto_lineas', {
      'company_id': await _db.obtenerEmpresaActivaId(),
      'periodo': periodo,
      'cuenta_id': cuentaId,
      'categoria': categoria,
      'monto_presupuestado': monto.toSql(),
      'alerta_pct': alertaPct,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> presupuestoVsReal(String periodo) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final rows = await db.query(
      'presupuesto_lineas',
      where: 'company_id = ? AND periodo = ?',
      whereArgs: [companyId, periodo],
      orderBy: 'categoria ASC',
    );
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final ventas = await _sum(
      db,
      'ventas',
      'total',
      companyId,
      periodo,
      currency,
    );
    final compras = await _sum(
      db,
      'compras',
      'total',
      companyId,
      periodo,
      currency,
    );
    return rows.map((row) {
      final categoria = row['categoria']?.toString().toLowerCase() ?? '';
      final real = categoria.contains('venta') || categoria.contains('ingreso')
          ? ventas
          : compras;
      final presupuesto = MoneyValue.fromSql(
        row['monto_presupuestado'],
        currency: currency,
      );
      final pct = presupuesto.minorUnits == 0
          ? 0
          : real.minorUnits * 100 / presupuesto.minorUnits;
      return {
        ...row,
        'real': real.toWireMap(),
        'porcentaje_consumido': pct,
        'alerta': pct >= ((row['alerta_pct'] as num?)?.toDouble() ?? 90),
      };
    }).toList();
  }

  Future<int> crearRecordatorio({
    required String titulo,
    required DateTime fechaEvento,
    String detalle = '',
    String tipo = 'tarea',
    String prioridad = 'info',
    String? entidad,
    int? entidadId,
  }) async {
    final db = await _db.database;
    return db.insert('recordatorios', {
      'company_id': await _db.obtenerEmpresaActivaId(),
      'titulo': titulo,
      'detalle': detalle,
      'tipo': tipo,
      'prioridad': prioridad,
      'entidad': entidad,
      'entidad_id': entidadId,
      'fecha_evento': fechaEvento.toIso8601String(),
      'notificar_48h': 1,
      'notificar_24h': 1,
      'completado': 0,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> recordatoriosPendientes() async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    return db.query(
      'recordatorios',
      where: 'company_id = ? AND completado = 0',
      whereArgs: [companyId],
      orderBy: 'fecha_evento ASC',
    );
  }

  Future<int> guardarPlantillaFactura({
    required String nombre,
    required String tipo,
    String colorPrimario = '#2563EB',
    bool mostrarLogo = true,
    bool mostrarImpuestos = true,
    Map<String, Object?> campos = const {},
    bool activa = false,
  }) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    return db.transaction((txn) async {
      if (activa) {
        await txn.update(
          'plantillas_factura',
          {'activa': 0},
          where: 'company_id = ? AND tipo = ?',
          whereArgs: [companyId, tipo],
        );
      }
      return txn.insert('plantillas_factura', {
        'company_id': companyId,
        'nombre': nombre,
        'tipo': tipo,
        'color_primario': colorPrimario,
        'mostrar_logo': mostrarLogo ? 1 : 0,
        'mostrar_impuestos': mostrarImpuestos ? 1 : 0,
        'campos_json': jsonEncode(campos),
        'activa': activa ? 1 : 0,
        'actualizado_en': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<int> importarCsv({
    required String entidad,
    required String csv,
  }) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final lines = const LineSplitter()
        .convert(csv)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return 0;
    final headers = _parseCsvLine(
      lines.first,
    ).map((header) => header.trim().toLowerCase()).toList();
    var count = 0;
    for (final line in lines.skip(1)) {
      final values = _parseCsvLine(line);
      final row = <String, String>{};
      for (var i = 0; i < headers.length && i < values.length; i++) {
        row[headers[i]] = values[i].trim();
      }
      if (entidad == 'productos') {
        await db.insert('productos', {
          'company_id': companyId,
          'nombre': row['nombre'] ?? '',
          'unidad_base': row['unidad'] ?? 'UND',
          'stock': double.tryParse(row['stock'] ?? '') ?? 0,
          'costo': MoneyValue.fromMajorUnits(
            row['costo'] ?? '0',
            currency: currency,
          ).toSql(),
          'precio': MoneyValue.fromMajorUnits(
            row['precio'] ?? '0',
            currency: currency,
          ).toSql(),
          'impuesto_pct': double.tryParse(row['impuesto'] ?? '') ?? 0,
          'codigo_barras': row['codigo_barras'] ?? '',
          'referencia': row['referencia'] ?? '',
          'descripcion': row['descripcion'] ?? '',
          'ubicacion_codigo': row['ubicacion'] ?? '',
        });
        count++;
      } else if (entidad == 'clientes') {
        await db.insert('clientes', {
          'company_id': companyId,
          'nombre': row['nombre'] ?? '',
          'documento': row['documento'] ?? row['nit'] ?? '',
          'telefono': row['telefono'] ?? '',
          'email': row['email'] ?? '',
          'direccion': row['direccion'] ?? '',
          'estado': 'activo',
          'fecha': DateTime.now().toIso8601String(),
        });
        count++;
      } else if (entidad == 'proveedores') {
        await db.insert('proveedores', {
          'company_id': companyId,
          'nombre': row['nombre'] ?? '',
          'nit': row['nit'] ?? row['documento'] ?? '',
          'telefono': row['telefono'] ?? '',
          'email': row['email'] ?? '',
          'direccion': row['direccion'] ?? '',
          'estado': 'activo',
          'fecha': DateTime.now().toIso8601String(),
        });
        count++;
      }
    }
    return count;
  }

  String generarEtiquetaSvg({
    required String nombre,
    required String codigo,
    required MoneyValue precio,
    String size = '2x3',
  }) {
    final bars = codigo.codeUnits
        .take(32)
        .map((unit) => (unit % 4) + 1)
        .toList();
    var x = 18;
    final rects = <String>[];
    for (var i = 0; i < bars.length; i++) {
      final width = bars[i];
      if (i.isEven) {
        rects.add('<rect x="$x" y="72" width="$width" height="58"/>');
      }
      x += width + 2;
    }
    return '''
<svg xmlns="http://www.w3.org/2000/svg" width="288" height="192" viewBox="0 0 288 192">
  <rect width="288" height="192" rx="12" fill="#FFFFFF"/>
  <text x="18" y="34" font-family="Inter, Arial" font-size="18" font-weight="700" fill="#1F2937">${_xml(nombre)}</text>
  <text x="18" y="58" font-family="Inter, Arial" font-size="14" fill="#4B5563">${_xml(size)} - ${_xml(codigo)}</text>
  <g fill="#111827">${rects.join()}</g>
  <text x="18" y="162" font-family="Inter, Arial" font-size="24" font-weight="700" fill="#2563EB">\$${precio.toMajorUnitsDoubleForDisplay().toStringAsFixed(0)}</text>
</svg>
''';
  }

  Future<int> registrarWebhook({
    required String evento,
    required String url,
  }) async {
    final db = await _db.database;
    return db.insert('api_webhooks', {
      'company_id': await _db.obtenerEmpresaActivaId(),
      'evento': evento,
      'url': url,
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  void _validarItems(List<EnterpriseLineItem> items) {
    if (items.isEmpty) throw ArgumentError('Debe agregar productos.');
    for (final item in items) {
      if (item.productoId <= 0 || item.cantidad <= 0) {
        throw ArgumentError('Producto y cantidad son obligatorios.');
      }
    }
  }

  ({MoneyValue subtotal, MoneyValue impuesto, MoneyValue total}) _totales(
    List<EnterpriseLineItem> items,
    Currency currency,
  ) {
    var subtotal = MoneyValue(minorUnits: 0, currency: currency);
    for (final item in items) {
      subtotal += item.subtotal;
    }
    final impuesto = MoneyValue(minorUnits: 0, currency: currency);
    return (subtotal: subtotal, impuesto: impuesto, total: subtotal);
  }

  Future<void> _descontarStock(
    Transaction txn,
    int companyId,
    int productoId,
    double cantidad, [
    int? bodegaId,
  ]) async {
    final productos = await txn.query(
      'productos',
      where: 'id = ? AND company_id = ?',
      whereArgs: [productoId, companyId],
      limit: 1,
    );
    if (productos.isEmpty) throw StateError('El producto no existe.');
    final tipoItem = productos.first['tipo_item']?.toString() ?? 'producto';
    if (tipoItem == 'servicio') {
      // Los servicios son intangibles y no inventariables: no descuentan stock ni registran Kardex
      return;
    }
    final stockActual = (productos.first['stock'] as num?)?.toDouble() ?? 0;
    if (stockActual < cantidad) {
      throw StateError('Stock insuficiente para el producto #$productoId.');
    }
    await txn.update(
      'productos',
      {'stock': stockActual - cantidad},
      where: 'id = ? AND company_id = ?',
      whereArgs: [productoId, companyId],
    );
    if (bodegaId != null) {
      await txn.rawUpdate(
        '''
        UPDATE stock_bodega
        SET cantidad = cantidad - ?, actualizado_en = ?
        WHERE producto_id = ? AND bodega_id = ? AND cantidad >= ?
        ''',
        [
          cantidad,
          DateTime.now().toIso8601String(),
          productoId,
          bodegaId,
          cantidad,
        ],
      );
    }
    await InventoryMovementService.record(
      db: txn,
      companyId: companyId,
      productId: productoId,
      type: 'salida',
      quantity: cantidad,
      stockBefore: stockActual,
      stockAfter: stockActual - cantidad,
      reason: 'FACTURACION PEDIDO',
      date: DateTime.now().toIso8601String(),
      documentType: 'pedido',
    );
  }

  Future<void> _sumarStock(
    Transaction txn,
    int companyId,
    int productoId,
    double cantidad,
  ) async {
    final productos = await txn.query(
      'productos',
      where: 'id = ? AND company_id = ?',
      whereArgs: [productoId, companyId],
      limit: 1,
    );
    if (productos.isEmpty) throw StateError('El producto no existe.');
    final tipoItem = productos.first['tipo_item']?.toString() ?? 'producto';
    if (tipoItem == 'servicio') {
      return;
    }
    final stockActual = (productos.first['stock'] as num?)?.toDouble() ?? 0;
    await txn.update(
      'productos',
      {'stock': stockActual + cantidad},
      where: 'id = ? AND company_id = ?',
      whereArgs: [productoId, companyId],
    );
    await InventoryMovementService.record(
      db: txn,
      companyId: companyId,
      productId: productoId,
      type: 'entrada',
      quantity: cantidad,
      stockBefore: stockActual,
      stockAfter: stockActual + cantidad,
      reason: 'DEVOLUCION VENTA',
      date: DateTime.now().toIso8601String(),
      documentType: 'devolucion_venta',
    );
  }

  Future<MoneyValue> _sum(
    Database db,
    String table,
    String column,
    int companyId,
    String periodo,
    Currency currency,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM($column), 0) AS total
      FROM $table
      WHERE company_id = ? AND substr(fecha, 1, 7) = ?
      ''',
      [companyId, periodo],
    );
    return MoneyValue.fromSql(rows.first['total'], currency: currency);
  }

  Future<void> _registrarEventoApi(
    DatabaseExecutor db,
    int companyId,
    String evento,
    Map<String, Object?> payload,
  ) async {
    await db.insert('api_eventos_pendientes', {
      'company_id': companyId,
      'evento': evento,
      'payload_json': jsonEncode(payload),
      'estado': 'pendiente',
      'intentos': 0,
      'creado_en': DateTime.now().toIso8601String(),
    });
  }

  List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        quoted = !quoted;
      } else if (char == ',' && !quoted) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }

  String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
