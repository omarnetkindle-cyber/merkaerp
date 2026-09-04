import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../commerce/application/payment_policy.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../../inventory/application/inventory_movement_service.dart';

class PurchaseItemInput {
  const PurchaseItemInput({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.subtotal,
    required this.taxAmount,
  });

  final int productId;
  final String productName;
  final double quantity;
  final MoneyValue unitCost;
  final MoneyValue subtotal;
  final MoneyValue taxAmount;

  factory PurchaseItemInput.fromCart(
    Map<String, dynamic> item, {
    required Currency currency,
  }) {
    return PurchaseItemInput(
      productId: (item['producto_id'] as num).toInt(),
      productName: item['producto'].toString(),
      quantity: (item['cantidad'] as num).toDouble(),
      unitCost: _moneyFromInput(item['costo'], currency),
      subtotal: _moneyFromInput(item['subtotal'], currency),
      taxAmount: _moneyFromInput(item['impuesto_linea'], currency),
    );
  }
}

class CreatePurchaseRequest {
  const CreatePurchaseRequest({
    required this.supplierId,
    required this.supplierName,
    required this.invoiceNumber,
    required this.observation,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.taxRate,
    required this.items,
    required this.manualCash,
    required this.manualBank,
    required this.manualCredit,
    this.date,
    required this.retefuente,
    required this.reteiva,
    required this.reteica,
    this.retefuenteConcepto = 'compras',
    this.retefuenteBase,
    this.retefuenteTasa,
  });

  final int supplierId;
  final String supplierName;
  final String invoiceNumber;
  final String observation;
  final int paymentMethodId;
  final String paymentMethodName;
  final double taxRate;
  final MoneyValue manualCash;
  final MoneyValue manualBank;
  final MoneyValue manualCredit;
  final List<PurchaseItemInput> items;
  final DateTime? date;
  final MoneyValue retefuente;
  final MoneyValue reteiva;
  final MoneyValue reteica;
  final String retefuenteConcepto;
  final MoneyValue? retefuenteBase;
  final double? retefuenteTasa;
}

class CreatePurchaseResult {
  const CreatePurchaseResult({
    required this.purchaseId,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.payment,
  });

  final int purchaseId;
  final MoneyValue subtotal;
  final MoneyValue tax;
  final MoneyValue total;
  final PaymentAllocation payment;
}

class CreatePurchaseUseCase {
  CreatePurchaseUseCase({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  Future<CreatePurchaseResult> execute(CreatePurchaseRequest request) async {
    if (request.items.isEmpty) {
      throw Exception('Agrega productos para registrar la compra.');
    }

    await _db.validarFeatureHabilitada(FeatureKey.purchases);
    if (await _db.operacionBloqueadaPorCierre()) {
      throw Exception('Operacion bloqueada por cierre de caja.');
    }

    final purchaseDate = request.date ?? DateTime.now();
    if (await _db.periodoEstaCerrado(purchaseDate)) {
      throw Exception('El periodo contable de la fecha actual esta cerrado.');
    }

    final database = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      database,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    final subtotal = request.items.fold<MoneyValue>(
      zero,
      (sum, item) => sum + item.subtotal,
    );
    final tax = request.items.fold<MoneyValue>(
      zero,
      (sum, item) => sum + item.taxAmount,
    );
    final total = subtotal + tax;
    final retefuenteBase =
        request.retefuenteBase ??
        (request.retefuente.minorUnits > 0 ? subtotal : zero);
    final retefuenteTasa =
        request.retefuenteTasa ??
        (retefuenteBase.minorUnits <= 0
            ? 0.0
            : request.retefuente.minorUnits * 100 / retefuenteBase.minorUnits);
    final payment = PaymentPolicy.allocatePurchase(
      total: total,
      method: request.paymentMethodName,
      manualCash: request.manualCash,
      manualBank: request.manualBank,
      manualCredit: request.manualCredit,
    );

    if (payment.cash.minorUnits > 0) {
      final cashBalance = await _db.obtenerSaldoPorCuenta('caja');
      if (cashBalance < payment.cash) {
        throw Exception('Saldo insuficiente en caja.');
      }
    }
    if (payment.bank.minorUnits > 0) {
      final bankBalance = await _db.obtenerSaldoPorCuenta('banco');
      if (bankBalance < payment.bank) {
        throw Exception('Saldo insuficiente en banco.');
      }
    }

    final now = purchaseDate.toIso8601String();
    final status = payment.credit.minorUnits > 0 ? 'pendiente' : 'pagada';
    late int purchaseId;

    await database.transaction((txn) async {
      purchaseId = await txn.insert('compras', {
        'company_id': companyId,
        'proveedor_id': request.supplierId,
        'proveedor': request.supplierName,
        'numero_factura': request.invoiceNumber,
        'fecha_factura': now,
        'observacion': request.observation,
        'subtotal': subtotal.toSql(),
        'impuesto_pct': request.taxRate,
        'impuesto_total': tax.toSql(),
        'total': total.toSql(),
        'efectivo': payment.cash.toSql(),
        'transferencia': payment.bank.toSql(),
        'credito': payment.credit.toSql(),
        'fecha': now,
        'metodo_pago_id': request.paymentMethodId,
        'estado': status,
        'retefuente': request.retefuente.toSql(),
        'retefuente_concepto': request.retefuenteConcepto,
        'retefuente_base': retefuenteBase.toSql(),
        'retefuente_tasa': retefuenteTasa,
        'reteiva': request.reteiva.toSql(),
        'reteica': request.reteica.toSql(),
      });

      for (final item in request.items) {
        final products = await txn.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [item.productId, companyId],
          limit: 1,
        );
        if (products.isEmpty) {
          throw Exception('Producto no encontrado: ${item.productName}');
        }
        final currentStock = (products.first['stock'] as num).toDouble();
        final currentCost = MoneyValue.fromSql(
          products.first['costo'],
          currency: currency,
          nullableAsZero: true,
        );
        final newStock = currentStock + item.quantity;

        // Costeo Promedio Ponderado
        // average_cost = ((Stock actual * Costo actual) + (Nueva cantidad * Nuevo costo)) / (Stock actual + Nueva cantidad)
        final averageCost = newStock > 0
            ? (currentCost.multiplyDecimal(currentStock.toString()) +
                      item.unitCost.multiplyDecimal(item.quantity.toString()))
                  .divideDecimal(newStock.toString())
            : item.unitCost;

        await txn.insert('compras_detalle', {
          'company_id': companyId,
          'compra_id': purchaseId,
          'producto_id': item.productId,
          'producto': item.productName,
          'cantidad': item.quantity,
          'costo_unitario': item.unitCost.toSql(),
          'subtotal': item.subtotal.toSql(),
          'impuesto_pct': request.taxRate,
          'impuesto_total': item.taxAmount.toSql(),
        });
        await txn.update(
          'productos',
          {'stock': newStock, 'costo': averageCost.toSql()},
          where: 'id = ? AND company_id = ?',
          whereArgs: [item.productId, companyId],
        );
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: item.productId,
          type: 'entrada',
          quantity: item.quantity,
          stockBefore: currentStock,
          stockAfter: newStock,
          costBeforeMinor: currentCost.toSql(),
          costAfterMinor: averageCost.toSql(),
          costTotalMinor: item.subtotal.toSql(),
          reason: 'COMPRA #$purchaseId',
          date: now,
          documentType: 'compra',
          documentId: purchaseId,
        );
      }

      if (payment.credit.minorUnits > 0) {
        await txn.insert('cuentas_por_pagar', {
          'company_id': companyId,
          'proveedor': request.supplierName,
          'proveedor_id': request.supplierId,
          'compra_id': purchaseId,
          'numero_factura': request.invoiceNumber,
          'total': payment.credit.toSql(),
          'saldo': payment.credit.toSql(),
          'estado': 'pendiente',
          'fecha': now,
          'descripcion': 'Credito desde compra #$purchaseId',
        });
      }

      if (payment.cash.minorUnits > 0) {
        await txn.insert('movimientos_caja', {
          'company_id': companyId,
          'tipo': 'egreso',
          'concepto': 'Compra #$purchaseId (Caja)',
          'monto': payment.cash.toSql(),
          'fecha': now,
          'origen': 'caja',
        });
      }
      if (payment.bank.minorUnits > 0) {
        await txn.insert('movimientos_caja', {
          'company_id': companyId,
          'tipo': 'egreso',
          'concepto': 'Compra #$purchaseId (Banco)',
          'monto': payment.bank.toSql(),
          'fecha': now,
          'origen': 'banco',
        });
      }
      await _db.registrarAsientoCompra(
        compraId: purchaseId,
        total: total,
        pagoCaja: payment.cash,
        pagoBanco: payment.bank,
        credito: payment.credit,
        proveedor: request.supplierName,
        impuesto: tax,
        txn: txn,
      );
    });

    // Trigger asíncrono: Encolar sincronización con Control Center
    Future.microtask(() async {
      try {
        final payload = {
          'purchase_id': purchaseId,
          'total': _wireMoney(total),
          'subtotal': _wireMoney(subtotal),
          'tax': _wireMoney(tax),
          'supplier_name': request.supplierName,
          'supplier_id': request.supplierId,
          'invoice_number': request.invoiceNumber,
          'date': purchaseDate.toIso8601String(),
          'payment_method': request.paymentMethodName,
          'status': status,
          'items': request.items
              .map(
                (item) => {
                  'product_id': item.productId,
                  'product_name': item.productName,
                  'quantity': item.quantity,
                  'unit_cost': _wireMoney(item.unitCost),
                  'subtotal': _wireMoney(item.subtotal),
                },
              )
              .toList(),
        };
        await _db.enqueueSync(
          table: 'purchases',
          recordId: purchaseId.toString(),
          action: 'INSERT',
          payload: jsonEncode(payload),
        );
      } catch (e) {
        // Loguear error pero no afectar la operación principal
        debugPrint('Error en enqueueSync para compra: $e');
      }
    });

    return CreatePurchaseResult(
      purchaseId: purchaseId,
      subtotal: subtotal,
      tax: tax,
      total: total,
      payment: payment,
    );
  }
}

MoneyValue _moneyFromInput(Object? value, Currency currency) {
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
