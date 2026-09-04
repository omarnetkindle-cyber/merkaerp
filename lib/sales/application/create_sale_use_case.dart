import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../commerce/application/payment_policy.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../../inventory/application/inventory_movement_service.dart';
import '../../sync/application/merka_sale_sync_outbox.dart';
import '../../taxes/retention_policy.dart';
import '../../taxes/retention_rule_service.dart';
import 'commission_service.dart';

class SaleItemInput {
  const SaleItemInput({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    required this.subtotal,
    required this.taxRate,
    required this.taxTotal,
  });

  final int productId;
  final String productName;
  final double quantity;
  final MoneyValue unitPrice;
  final MoneyValue unitCost;
  final MoneyValue subtotal;
  final double taxRate;
  final MoneyValue taxTotal;

  factory SaleItemInput.fromCart(
    Map<String, dynamic> item, {
    required Currency currency,
  }) {
    return SaleItemInput(
      productId: (item['producto_id'] as num).toInt(),
      productName: item['producto'].toString(),
      quantity: (item['cantidad'] as num).toDouble(),
      unitPrice: _moneyFromUiValue(item['precio'], currency),
      unitCost: _moneyFromUiValue(item['costo'] ?? 0, currency),
      subtotal: _moneyFromUiValue(item['subtotal'], currency),
      taxRate: (item['impuesto_pct'] as num?)?.toDouble() ?? 0,
      taxTotal: _moneyFromUiValue(item['impuesto_total'] ?? 0, currency),
    );
  }
}

class CreateSaleRequest {
  const CreateSaleRequest({
    required this.items,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.clientName,
    this.clientId,
    this.date,
    required this.efectivo,
    required this.transferencia,
    required this.credito,
    required this.retefuente,
    required this.reteiva,
    required this.reteica,
    this.retefuenteConcepto = 'otros_ingresos',
    this.retefuenteBase,
    this.retefuenteTasa,
    this.salespersonId,
    this.salespersonName,
  });

  final List<SaleItemInput> items;
  final int paymentMethodId;
  final String paymentMethodName;
  final int? clientId;
  final String clientName;
  final DateTime? date;
  final MoneyValue efectivo;
  final MoneyValue transferencia;
  final MoneyValue credito;
  final MoneyValue retefuente;
  final MoneyValue reteiva;
  final MoneyValue reteica;
  final String retefuenteConcepto;
  final MoneyValue? retefuenteBase;
  final double? retefuenteTasa;

  /// ID del vendedor (usuario) para calcular comisiones automáticamente.
  /// Si es null, no se genera comisión.
  final int? salespersonId;

  /// Nombre del vendedor para registrar en la tabla de comisiones.
  final String? salespersonName;
}

class CreateSaleResult {
  const CreateSaleResult({
    required this.saleId,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.costOfSale,
  });

  final int saleId;
  final MoneyValue subtotal;
  final MoneyValue tax;
  final MoneyValue total;
  final MoneyValue costOfSale;
}

class CreateSaleUseCase {
  CreateSaleUseCase({DatabaseHelper? db, SaleSyncOutboxWriter? saleSyncOutbox})
    : _db = db ?? DatabaseHelper.instance,
      _saleSyncOutbox = saleSyncOutbox ?? const MerkaSaleSyncOutboxWriter();

  final DatabaseHelper _db;
  final SaleSyncOutboxWriter _saleSyncOutbox;

  Future<CreateSaleResult> execute(CreateSaleRequest request) async {
    if (request.items.isEmpty) {
      throw Exception('Agrega productos para emitir la factura.');
    }

    await _db.validarFeatureHabilitada(FeatureKey.pos);
    if (await _db.operacionBloqueadaPorCierre()) {
      throw Exception('Operacion bloqueada por cierre de caja.');
    }

    final saleDate = request.date ?? DateTime.now();
    if (await _db.periodoEstaCerrado(saleDate)) {
      throw Exception('El periodo contable de la fecha actual esta cerrado.');
    }

    final database = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      database,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);

    // Obtener parámetros de impuestos del año actual
    final reteicaRules = await database.query(
      'reglas_retenciones_empresa',
      columns: ['tasa', 'base_minima'],
      where:
          'company_id = ? AND activo = 1 AND aplica_ventas = 1 AND codigo LIKE ?',
      whereArgs: [companyId, 'RTEICA%'],
      orderBy: 'id ASC',
      limit: 1,
    );
    final reteicaRatePercent = reteicaRules.isEmpty
        ? '0'
        : reteicaRules.first['tasa'].toString();
    final reteicaMinimumBase = reteicaRules.isEmpty
        ? zero
        : MoneyValue.fromSql(
            reteicaRules.first['base_minima'],
            currency: currency,
          );

    // Obtener banderas fiscales del cliente si existe
    bool isAutoretainer = false;
    bool isDeclarante = true;
    if (request.clientId != null) {
      final clientRows = await database.query(
        'clientes',
        where: 'id = ? AND company_id = ?',
        whereArgs: [request.clientId, companyId],
        limit: 1,
      );
      if (clientRows.isNotEmpty) {
        isAutoretainer = (clientRows.first['autorretenedor'] as int?) == 1;
        isDeclarante = (clientRows.first['declarante'] as int?) != 0;
      }
    }

    // Calcular retenciones automáticamente si el cliente no es autorretenedor
    var calculatedRetefuente = request.retefuente;
    final calculatedReteiva = request.reteiva;
    var calculatedReteica = request.reteica;

    final subtotal = request.items.fold<MoneyValue>(
      zero,
      (sum, item) => sum + item.subtotal,
    );

    if (!isAutoretainer && calculatedRetefuente.minorUnits == 0) {
      // Calcular retefuente basado en el subtotal y tipo de cliente
      // (Simplificado - debería usar tabla UVT completa)
      final concept = request.retefuenteConcepto.trim().toLowerCase();
      final configuredRule = await const RetentionRuleService().findApplicable(
        db: database,
        companyId: companyId,
        currency: currency,
        concept: concept,
        isDeclarante: isDeclarante,
        saleFlow: true,
      );
      final retentionThreshold =
          configuredRule?.minimumBase ??
          RetentionPolicy.baseForConcept(concept: concept, currency: currency);
      if (subtotal > retentionThreshold) {
        calculatedRetefuente =
            configuredRule?.calculate(subtotal) ?? calculatedRetefuente;
      }
    }

    if (!isAutoretainer && subtotal >= reteicaMinimumBase) {
      calculatedReteica = subtotal.percent(reteicaRatePercent);
    }

    final tax = request.items.fold<MoneyValue>(
      zero,
      (sum, item) => sum + item.taxTotal,
    );
    final total =
        subtotal +
        tax -
        calculatedRetefuente -
        calculatedReteiva -
        calculatedReteica;
    final taxRate = subtotal.minorUnits <= 0
        ? 0.0
        : (tax.minorUnits * 100) / subtotal.minorUnits;
    final retefuenteBase =
        request.retefuenteBase ??
        (calculatedRetefuente.minorUnits > 0 ? subtotal : zero);
    final retefuenteTasa =
        request.retefuenteTasa ??
        (retefuenteBase.minorUnits <= 0
            ? 0.0
            : calculatedRetefuente.minorUnits *
                  100 /
                  retefuenteBase.minorUnits);
    final paymentMethod = request.paymentMethodName.toUpperCase().trim();

    final ef = request.efectivo;
    final tf = request.transferencia;
    final cr = request.credito;
    final isMixed =
        paymentMethod == 'PAGO MIXTO' || (ef + tf + cr).minorUnits > 0;

    if (isMixed) {
      if (ef + tf + cr != total) {
        throw Exception(
          'La suma del pago mixto debe igualar el total de la factura.',
        );
      }
    }

    final origin = PaymentPolicy.cashOriginForSale(paymentMethod);
    late int saleId;
    var costOfSale = zero;

    await database.transaction((txn) async {
      for (final item in request.items) {
        final productRows = await txn.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [item.productId, companyId],
          limit: 1,
        );
        if (productRows.isEmpty ||
            ((productRows.first['stock'] as num?)?.toDouble() ?? 0) <
                item.quantity) {
          throw Exception('Stock insuficiente para ${item.productName}');
        }
      }

      saleId = await txn.insert('ventas', {
        'company_id': companyId,
        'producto_id': 0,
        'producto': 'Factura POS',
        'cantidad': request.items.length,
        'precio_unitario': 0,
        'costo_unitario': 0,
        'subtotal': subtotal.toSql(),
        'impuesto_pct': taxRate,
        'impuesto_total': tax.toSql(),
        'total': total.toSql(),
        'fecha': saleDate.toIso8601String(),
        'metodo_pago_id': request.paymentMethodId,
        'cliente_id': request.clientId,
        'cliente': request.clientName,
        'estado': 'emitida',
        'efectivo': request.efectivo.toSql(),
        'transferencia': request.transferencia.toSql(),
        'credito': request.credito.toSql(),
        'retefuente': calculatedRetefuente.toSql(),
        'retefuente_concepto': request.retefuenteConcepto,
        'retefuente_base': retefuenteBase.toSql(),
        'retefuente_tasa': retefuenteTasa,
        'reteiva': calculatedReteiva.toSql(),
        'reteica': calculatedReteica.toSql(),
      });

      await txn.update(
        'ventas',
        {'producto': 'Factura POS #$saleId'},
        where: 'id = ? AND company_id = ?',
        whereArgs: [saleId, companyId],
      );

      final ef = request.efectivo;
      final tf = request.transferencia;
      final cr = request.credito;

      if ((ef + tf + cr).minorUnits == 0) {
        await txn.insert('movimientos_caja', {
          'company_id': companyId,
          'tipo': 'ingreso',
          'concepto': origin == 'cartera'
              ? 'Cuenta por cobrar factura POS #$saleId'
              : 'Factura POS #$saleId',
          'monto': total.toSql(),
          'fecha': saleDate.toIso8601String(),
          'origen': origin,
        });
      } else {
        if (ef.minorUnits > 0) {
          await txn.insert('movimientos_caja', {
            'company_id': companyId,
            'tipo': 'ingreso',
            'concepto': 'Factura POS #$saleId (Efectivo)',
            'monto': ef.toSql(),
            'fecha': saleDate.toIso8601String(),
            'origen': 'caja',
          });
        }
        if (tf.minorUnits > 0) {
          await txn.insert('movimientos_caja', {
            'company_id': companyId,
            'tipo': 'ingreso',
            'concepto': 'Factura POS #$saleId (Transferencia)',
            'monto': tf.toSql(),
            'fecha': saleDate.toIso8601String(),
            'origen': 'banco',
          });
        }
        if (cr.minorUnits > 0) {
          await txn.insert('movimientos_caja', {
            'company_id': companyId,
            'tipo': 'ingreso',
            'concepto': 'Cuenta por cobrar factura POS #$saleId',
            'monto': cr.toSql(),
            'fecha': saleDate.toIso8601String(),
            'origen': 'cartera',
          });
        }
      }

      final receivableAmount = cr.minorUnits > 0
          ? cr
          : (origin == 'cartera' ? total : zero);
      if (receivableAmount.minorUnits > 0) {
        await txn.insert('cuentas_por_cobrar', {
          'company_id': companyId,
          'cliente_id': request.clientId,
          'cliente': request.clientName,
          'venta_id': saleId,
          'total': receivableAmount.toSql(),
          'saldo': receivableAmount.toSql(),
          'estado': 'pendiente',
          'fecha': saleDate.toIso8601String(),
          'descripcion': 'Factura POS #$saleId a crédito',
        });
      }

      for (final item in request.items) {
        final productRows = await txn.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [item.productId, companyId],
          limit: 1,
        );
        final currentStock = (productRows.first['stock'] as num).toDouble();
        final currentCost = MoneyValue.fromSql(
          productRows.first['costo'],
          currency: currency,
          nullableAsZero: true,
        );
        costOfSale += currentCost.multiplyDecimal(item.quantity.toString());
        final newStock = currentStock - item.quantity;

        await txn.update(
          'productos',
          {'stock': newStock},
          where: 'id = ? AND company_id = ?',
          whereArgs: [item.productId, companyId],
        );
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: item.productId,
          type: 'salida',
          quantity: item.quantity,
          stockBefore: currentStock,
          stockAfter: newStock,
          costBeforeMinor: currentCost.toSql(),
          costAfterMinor: currentCost.toSql(),
          costTotalMinor: currentCost
              .multiplyDecimal(item.quantity.toString())
              .toSql(),
          reason: 'FACTURA POS #$saleId',
          date: saleDate.toIso8601String(),
          documentType: 'venta',
          documentId: saleId,
        );
        await txn.insert('ventas_detalle', {
          'company_id': companyId,
          'venta_id': saleId,
          'producto_id': item.productId,
          'producto': item.productName,
          'cantidad': item.quantity,
          'precio_unitario': item.unitPrice.toSql(),
          'subtotal': item.subtotal.toSql(),
          'impuesto_pct': item.taxRate,
          'impuesto_total': item.taxTotal.toSql(),
        });
      }
      await _db.registrarAsientoVenta(
        ventaId: saleId,
        total: total,
        metodoPago: paymentMethod,
        costoVenta: costOfSale,
        impuesto: tax,
        txn: txn,
      );
    });

    await _enqueueMerkaSyncSaleEvent(database, companyId, saleId);

    // Trigger asíncrono: Disparar webhooks (Fire-and-Forget)
    // No bloquea la operación principal, si falla solo se loguea el error
    Future.microtask(() async {
      try {
        final payload = {
          'invoice_id': saleId,
          'total': _wireMoney(total),
          'subtotal': _wireMoney(subtotal),
          'tax': _wireMoney(tax),
          'client_name': request.clientName,
          'client_id': request.clientId,
          'date': saleDate.toIso8601String(),
          'payment_method': paymentMethod,
          'status': 'emitida',
        };
        await _db.dispararWebhooks('invoice.created', payload);
      } catch (e) {
        // Loguear error en auditoría pero no afectar la operación principal
        await _db.registrarEventoAuditoria(
          accion: 'ERROR_WEBHOOK',
          entidad: 'webhooks',
          entidadId: saleId,
          detalle: 'Error al disparar webhook invoice.created: $e',
        );
      }
    });

    // Trigger asíncrono: Crear garantías automáticas para productos con has_warranty = true
    Future.microtask(() async {
      try {
        for (final item in request.items) {
          final productRows = await database.query(
            'productos',
            where: 'id = ? AND company_id = ?',
            whereArgs: [item.productId, companyId],
            limit: 1,
          );

          if (productRows.isNotEmpty) {
            final product = productRows.first;
            final hasWarranty = (product['has_warranty'] as int?) == 1;
            final warrantyDays = (product['warranty_days'] as int?) ?? 365;

            if (hasWarranty) {
              await _db.registrarGarantia(
                ventaId: saleId,
                productoId: item.productId,
                descripcionProblema:
                    'Garantía automática generada al momento de venta',
                diasGarantia: warrantyDays,
              );
            }
          }
        }
      } catch (e) {
        // Loguear error en auditoría pero no afectar la operación principal
        await _db.registrarEventoAuditoria(
          accion: 'ERROR_GARANTIA_AUTOMATICA',
          entidad: 'warranties',
          entidadId: saleId,
          detalle: 'Error al crear garantía automática: $e',
        );
      }
    });

    // Trigger asíncrono: Encolar sincronización con Control Center
    Future.microtask(() async {
      try {
        final payload = {
          'invoice_id': saleId,
          'total': _wireMoney(total),
          'subtotal': _wireMoney(subtotal),
          'tax': _wireMoney(tax),
          'client_name': request.clientName,
          'client_id': request.clientId,
          'date': saleDate.toIso8601String(),
          'payment_method': paymentMethod,
          'status': 'emitida',
          'items': request.items
              .map(
                (item) => {
                  'product_id': item.productId,
                  'product_name': item.productName,
                  'quantity': item.quantity,
                  'unit_price': _wireMoney(item.unitPrice),
                  'subtotal': _wireMoney(item.subtotal),
                },
              )
              .toList(),
        };
        await _db.enqueueSync(
          table: 'invoices',
          recordId: saleId.toString(),
          action: 'INSERT',
          payload: jsonEncode(payload),
        );
      } catch (e) {
        // Loguear error pero no afectar la operación principal
        debugPrint('Error en enqueueSync para venta: $e');
      }
    });

    // Trigger asíncrono: Calcular y registrar comisión si el request incluye
    // un vendedor. Fire-and-forget: un fallo nunca cancela la venta confirmada.
    Future.microtask(() async {
      try {
        final salespersonId = request.salespersonId;
        if (salespersonId != null && salespersonId > 0) {
          final saleAmountDouble = total.toMajorUnitsDoubleForDisplay();
          if (saleAmountDouble > 0) {
            await CommissionService.instance.generateCommissionForSale(
              database,
              companyId,
              saleId,
              'FV-$saleId',
              saleAmountDouble,
              salespersonId,
              request.salespersonName ?? request.clientName,
            );
          }
        }
      } catch (e) {
        await _db.registrarEventoAuditoria(
          accion: 'ERROR_COMISION_VENTA',
          entidad: 'commissions',
          entidadId: saleId,
          detalle: 'No se pudo registrar comisión para venta $saleId: $e',
        );
      }
    });

    return CreateSaleResult(
      saleId: saleId,
      subtotal: subtotal,
      tax: tax,
      total: total,
      costOfSale: costOfSale,
    );
  }

  Future<void> _enqueueMerkaSyncSaleEvent(
    DatabaseExecutor db,
    int companyId,
    int saleId,
  ) async {
    try {
      await _saleSyncOutbox.enqueueSaleConfirmed(
        db: db,
        companyId: companyId,
        saleId: saleId,
      );
    } catch (e) {
      // La sincronización nunca debe romper la venta local/offline.
      debugPrint('Error en merka_sync_outbox para venta: $e');
    }
  }
}

MoneyValue _moneyFromUiValue(Object? value, Currency currency) {
  if (value is MoneyValue) return value;
  return MoneyValue.fromMajorUnits(
    value?.toString() ?? '0',
    currency: currency,
  );
}

Map<String, Object> _wireMoney(MoneyValue value) => {
  'minor_units': value.minorUnits,
  'currency': value.currencyCode,
  'scale': value.decimalPlaces,
};
