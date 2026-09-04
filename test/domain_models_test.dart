import 'package:merka_erp/inventory/domain/inventory_summary.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/purchases/domain/purchase.dart';
import 'package:merka_erp/sales/domain/sale.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_money.dart';

void main() {
  group('Product domain', () {
    test('calcula resumen de inventario por costo, venta y stock bajo', () {
      final products = [
        Product(
          name: 'Pan',
          unit: 'und',
          stock: 4,
          cost: testMoney('1000'),
          price: testMoney('1500'),
          taxRate: 0,
        ),
        Product(
          name: 'Cafe',
          unit: 'lb',
          stock: 10,
          cost: testMoney('12000'),
          price: testMoney('18000'),
          taxRate: 19,
        ),
      ];

      final summary = InventorySummary.fromProducts(products);

      expect(summary.costValue, testMoney('124000'));
      expect(summary.saleValue, testMoney('186000'));
      expect(summary.productCount, 2);
      expect(summary.lowStockCount, 1);
    });
  });

  group('Sales domain', () {
    test('convierte mapas legacy a modelo de venta', () {
      final sale = Sale.fromMap({
        'id': 7,
        'company_id': 2,
        'producto': 'Factura POS #7',
        'cantidad': 2,
        'subtotal': 20000,
        'impuesto_pct': 19,
        'impuesto_total': 3800,
        'total': 23800,
        'fecha': '2026-05-19T10:00:00',
        'metodo_pago_id': 3,
        'cliente_id': 5,
        'cliente': 'Cliente demo',
        'estado': 'anulada',
      }, currency: testCop);

      expect(sale.id, 7);
      expect(sale.companyId, 2);
      expect(sale.total, testMoney('238.00'));
      expect(sale.isCanceled, isTrue);
      expect(sale.toMap()['cliente'], 'Cliente demo');
    });
  });

  group('Purchases domain', () {
    test('convierte mapas legacy a modelo de compra', () {
      final purchase = Purchase.fromMap({
        'id': 11,
        'company_id': 2,
        'proveedor_id': 9,
        'proveedor': 'Proveedor demo',
        'numero_factura': 'FV-1',
        'subtotal': 50000,
        'impuesto_pct': 19,
        'impuesto_total': 9500,
        'total': 59500,
        'efectivo': 10000,
        'transferencia': 0,
        'credito': 49500,
        'fecha': '2026-05-19T11:00:00',
        'metodo_pago_id': 4,
        'estado': 'pendiente',
      }, currency: testCop);

      expect(purchase.id, 11);
      expect(purchase.supplierId, 9);
      expect(purchase.total, testMoney('595.00'));
      expect(purchase.hasCredit, isTrue);
      expect(purchase.toMap()['proveedor'], 'Proveedor demo');
    });
  });
}
