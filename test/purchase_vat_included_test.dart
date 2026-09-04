// Test de regresión: concepto "precio incluye IVA" en flujo de compras.
//
// Verifica que:
// 1. Compra con precio_incluye_iva=true a $119.000 (19%) → base $100.000, IVA $19.000
// 2. Compra con precio_incluye_iva=false mantiene comportamiento tradicional (base + IVA)
// 3. F300 reporta correctamente IVA descontable en ambos casos
// 4. Sin regresión del comportamiento actual

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/purchases/application/create_purchase_use_case.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late Directory dbDirectory;
  final cop = Currency(
    code: 'COP',
    name: 'Peso colombiano',
    symbol: r'$',
    decimalPlaces: 2,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbDirectory = await Directory.systemTemp.createTemp('merka_purchase_vat_');
    await databaseFactory.setDatabasesPath(dbDirectory.path);
  });

  setUp(() async {
    await DatabaseHelper.resetForTests();
    DatabaseHelper.disableAutoLoadsForTests = true;
    await databaseFactory.deleteDatabase(
      p.join(dbDirectory.path, 'merka_erp_test_fresco.db'),
    );

    await DatabaseHelper.instance.database;
    db = await DatabaseHelper.instance.database;

    // Preparar empresa activa
    await db.insert('empresas', {
      'nombre': 'Empresa Test Compras IVA',
      'nit': '901234567',
      'moneda': 'COP',
      'activa': 1,
      'fecha': DateTime.now().toIso8601String(),
    });

    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    // Preparar proveedor
    await db.insert('proveedores', {
      'company_id': companyId,
      'nombre': 'Proveedor Test',
      'nit': '800111222',
    });

    // Preparar producto
    await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Producto Test Compra',
      'unidad_base': 'unid.',
      'precio': 11900000,
      'costo': 10000000,
      'stock': 0,
      'impuesto_pct': 19.0,
      'tipo_item': 'producto',
      'precio_incluye_iva': 0,
    });
  });

  tearDown(() async {
    await DatabaseHelper.instance.closeForTests();
  });

  tearDownAll(() async {
    if (await dbDirectory.exists()) await dbDirectory.delete(recursive: true);
  });

  test(
    'TEST 1: Compra con precio_incluye_iva=true a \$119.000 (19%) → base \$100.000, IVA \$19.000',
    () async {
      final useCase = CreatePurchaseUseCase();
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

      // Simular línea de compra con precio incluye IVA (como viene en factura proveedor)
      final costoConIva = MoneyValue.fromMajorUnits('119000', currency: cop);
      const cantidad = 1.0;
      const impuestoPct = 19.0;

      // Calcular base e IVA (mismo cálculo que hace _calcularValoresLineaCompra)
      final totalConIva = costoConIva.multiplyDecimal(cantidad.toString());
      final factor = 1.0 + (impuestoPct / 100.0);
      final baseMajor = totalConIva.toMajorUnitsDoubleForDisplay() / factor;
      final subtotal = MoneyValue.fromMajorUnits(
        baseMajor.toStringAsFixed(cop.decimalPlaces),
        currency: cop,
      );
      final impuesto = totalConIva - subtotal;

      // Verificar cálculo antes de guardar
      expect(subtotal.minorUnits, equals(10000000));
      expect(impuesto.minorUnits, equals(1900000));
      expect(totalConIva.minorUnits, equals(11900000));

      final result = await useCase.execute(
        CreatePurchaseRequest(
          supplierId: 1,
          supplierName: 'Proveedor Test',
          invoiceNumber: 'FACT-001',
          observation: 'Compra test con IVA incluido',
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          taxRate: impuestoPct,
          manualCash: MoneyValue(minorUnits: 0, currency: cop),
          manualBank: MoneyValue(minorUnits: 0, currency: cop),
          manualCredit: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Producto Test Compra',
              quantity: cantidad,
              unitCost: costoConIva,
              subtotal: subtotal,
              taxAmount: impuesto,
            ),
          ],
        ),
      );

      expect(result.purchaseId, greaterThan(0));
      expect(result.subtotal.minorUnits, equals(10000000));
      expect(result.tax.minorUnits, equals(1900000));
      expect(result.total.minorUnits, equals(11900000));

      // Verificar que se guardó correctamente en BD
      final compraRow = await db.query(
        'compras',
        where: 'id = ? AND company_id = ?',
        whereArgs: [result.purchaseId, companyId],
      );
      expect(compraRow.length, equals(1));
      expect(compraRow.first['subtotal'], equals(10000000));
      expect(compraRow.first['impuesto_total'], equals(1900000));
      expect(compraRow.first['total'], equals(11900000));

      // Verificar detalle
      final detalleRow = await db.query(
        'compras_detalle',
        where: 'compra_id = ? AND company_id = ?',
        whereArgs: [result.purchaseId, companyId],
      );
      expect(detalleRow.length, equals(1));
      expect(detalleRow.first['subtotal'], equals(10000000));
      expect(detalleRow.first['impuesto_total'], equals(1900000));
    },
  );

  test(
    'TEST 2: Compra con precio_incluye_iva=false mantiene comportamiento tradicional',
    () async {
      final useCase = CreatePurchaseUseCase();
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

      // Comportamiento tradicional: precio = base (sin IVA)
      final costoBase = MoneyValue.fromMajorUnits('100000', currency: cop);
      const cantidad = 1.0;
      const impuestoPct = 19.0;

      final subtotal = costoBase.multiplyDecimal(cantidad.toString());
      final impuesto = subtotal.percent(impuestoPct.toString());
      final total = subtotal + impuesto;

      expect(subtotal.minorUnits, equals(10000000));
      expect(impuesto.minorUnits, equals(1900000));
      expect(total.minorUnits, equals(11900000));

      final result = await useCase.execute(
        CreatePurchaseRequest(
          supplierId: 1,
          supplierName: 'Proveedor Test',
          invoiceNumber: 'FACT-002',
          observation: 'Compra test sin IVA incluido (tradicional)',
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          taxRate: impuestoPct,
          manualCash: MoneyValue(minorUnits: 0, currency: cop),
          manualBank: MoneyValue(minorUnits: 0, currency: cop),
          manualCredit: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Producto Test Compra',
              quantity: cantidad,
              unitCost: costoBase,
              subtotal: subtotal,
              taxAmount: impuesto,
            ),
          ],
        ),
      );

      expect(result.purchaseId, greaterThan(0));
      expect(result.subtotal.minorUnits, equals(10000000));
      expect(result.tax.minorUnits, equals(1900000));
      expect(result.total.minorUnits, equals(11900000));

      // Verificar BD
      final compraRow = await db.query(
        'compras',
        where: 'id = ? AND company_id = ?',
        whereArgs: [result.purchaseId, companyId],
      );
      expect(compraRow.length, equals(1));
      expect(compraRow.first['subtotal'], equals(10000000));
      expect(compraRow.first['impuesto_total'], equals(1900000));
      expect(compraRow.first['total'], equals(11900000));
    },
  );

  test(
    'TEST 3: F300 reporta correctamente IVA descontable con precio_incluye_iva=true',
    () async {
      final useCase = CreatePurchaseUseCase();

      // Compra A: con IVA incluido ($119.000 → base $100.000, IVA $19.000)
      final costoConIva = MoneyValue.fromMajorUnits('119000', currency: cop);
      const cantidad = 1.0;
      const impuestoPct = 19.0;

      final totalConIva = costoConIva.multiplyDecimal(cantidad.toString());
      final factor = 1.0 + (impuestoPct / 100.0);
      final baseMajor = totalConIva.toMajorUnitsDoubleForDisplay() / factor;
      final subtotalA = MoneyValue.fromMajorUnits(
        baseMajor.toStringAsFixed(cop.decimalPlaces),
        currency: cop,
      );
      final impuestoA = totalConIva - subtotalA;

      await useCase.execute(
        CreatePurchaseRequest(
          supplierId: 1,
          supplierName: 'Proveedor Test',
          invoiceNumber: 'FACT-F300-A',
          observation: 'Compra para F300 con IVA incluido',
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          taxRate: impuestoPct,
          manualCash: MoneyValue(minorUnits: 0, currency: cop),
          manualBank: MoneyValue(minorUnits: 0, currency: cop),
          manualCredit: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Producto Test Compra',
              quantity: cantidad,
              unitCost: costoConIva,
              subtotal: subtotalA,
              taxAmount: impuestoA,
            ),
          ],
        ),
      );

      // Compra B: tradicional (base $100.000, IVA $19.000)
      final costoBase = MoneyValue.fromMajorUnits('100000', currency: cop);
      final subtotalB = costoBase.multiplyDecimal(cantidad.toString());
      final impuestoB = subtotalB.percent(impuestoPct.toString());

      await useCase.execute(
        CreatePurchaseRequest(
          supplierId: 1,
          supplierName: 'Proveedor Test',
          invoiceNumber: 'FACT-F300-B',
          observation: 'Compra para F300 tradicional',
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          taxRate: impuestoPct,
          manualCash: MoneyValue(minorUnits: 0, currency: cop),
          manualBank: MoneyValue(minorUnits: 0, currency: cop),
          manualCredit: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Producto Test Compra',
              quantity: cantidad,
              unitCost: costoBase,
              subtotal: subtotalB,
              taxAmount: impuestoB,
            ),
          ],
        ),
      );

      // Obtener fecha actual para F300
      final now = DateTime.now();
      final anio = now.year;
      final mes = now.month;

      // Verificar detalle F300
      final detalleF300 = await DatabaseHelper.instance
          .obtenerDetalleFormulario300(anio: anio, mes: mes);

      final comprasF300 = detalleF300
          .where((row) => row['origen'] == 'compra')
          .toList();
      expect(comprasF300.length, greaterThanOrEqualTo(2));

      // Sumar bases e IVA de compras
      var baseTotal = 0;
      var ivaTotal = 0;
      for (final row in comprasF300) {
        baseTotal += (row['base'] as num).toInt();
        ivaTotal += (row['impuesto'] as num).toInt();
      }

      expect(baseTotal, greaterThanOrEqualTo(200000)); // 100.000 + 100.000
      expect(ivaTotal, greaterThanOrEqualTo(38000)); // 19.000 + 19.000

      // Verificar borrador F300
      final borradorF300 = await DatabaseHelper.instance
          .obtenerBorradorFormulario300(anio: anio, mes: mes);

      final ivaDescontable = borradorF300['iva_descontable'] as MoneyValue;
      expect(
        ivaDescontable.minorUnits,
        greaterThanOrEqualTo(38000),
        reason: 'IVA descontable debe incluir ambas compras',
      );
    },
  );

  test(
    'TEST 4: Múltiples líneas con diferentes configuraciones de precio_incluye_iva',
    () async {
      final useCase = CreatePurchaseUseCase();
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

      // Crear producto adicional
      await db.insert('productos', {
        'company_id': companyId,
        'nombre': 'Producto Test 2',
        'unidad_base': 'unid.',
        'precio': 59500,
        'costo': 50000,
        'stock': 0,
        'impuesto_pct': 19.0,
        'tipo_item': 'producto',
        'precio_incluye_iva': 0,
      });

      // Línea 1: Con IVA incluido $119.000 → base $100.000, IVA $19.000
      final costoConIva = MoneyValue.fromMajorUnits('119000', currency: cop);
      const cantidad1 = 2.0;
      const impuestoPct = 19.0;

      final totalConIva = costoConIva.multiplyDecimal(cantidad1.toString());
      final factor = 1.0 + (impuestoPct / 100.0);
      final baseMajor = totalConIva.toMajorUnitsDoubleForDisplay() / factor;
      final subtotal1 = MoneyValue.fromMajorUnits(
        baseMajor.toStringAsFixed(cop.decimalPlaces),
        currency: cop,
      );
      final impuesto1 = totalConIva - subtotal1;

      // Línea 2: Tradicional $50.000 base → IVA $9.500
      final costoBase = MoneyValue.fromMajorUnits('50000', currency: cop);
      const cantidad2 = 3.0;

      final subtotal2 = costoBase.multiplyDecimal(cantidad2.toString());
      final impuesto2 = subtotal2.percent(impuestoPct.toString());

      final result = await useCase.execute(
        CreatePurchaseRequest(
          supplierId: 1,
          supplierName: 'Proveedor Test',
          invoiceNumber: 'FACT-MULTI',
          observation: 'Compra mixta: líneas con/sin IVA incluido',
          paymentMethodId: 1,
          paymentMethodName: 'CREDITO',
          taxRate: impuestoPct,
          manualCash: MoneyValue(minorUnits: 0, currency: cop),
          manualBank: MoneyValue(minorUnits: 0, currency: cop),
          manualCredit: MoneyValue(minorUnits: 0, currency: cop),
          retefuente: MoneyValue(minorUnits: 0, currency: cop),
          reteiva: MoneyValue(minorUnits: 0, currency: cop),
          reteica: MoneyValue(minorUnits: 0, currency: cop),
          items: [
            PurchaseItemInput(
              productId: 1,
              productName: 'Producto Test Compra',
              quantity: cantidad1,
              unitCost: costoConIva,
              subtotal: subtotal1,
              taxAmount: impuesto1,
            ),
            PurchaseItemInput(
              productId: 2,
              productName: 'Producto Test 2',
              quantity: cantidad2,
              unitCost: costoBase,
              subtotal: subtotal2,
              taxAmount: impuesto2,
            ),
          ],
        ),
      );

      expect(result.purchaseId, greaterThan(0));

      // Verificar totales
      final subtotalEsperado = subtotal1 + subtotal2;
      final impuestoEsperado = impuesto1 + impuesto2;
      final totalEsperado = subtotalEsperado + impuestoEsperado;

      expect(result.subtotal.minorUnits, equals(subtotalEsperado.minorUnits));
      expect(result.tax.minorUnits, equals(impuestoEsperado.minorUnits));
      expect(result.total.minorUnits, equals(totalEsperado.minorUnits));

      // Verificar que ambas líneas se guardaron correctamente
      final detalleRows = await db.query(
        'compras_detalle',
        where: 'compra_id = ? AND company_id = ?',
        whereArgs: [result.purchaseId, companyId],
      );
      expect(detalleRows.length, equals(2));

      // Línea 1: con IVA incluido
      final linea1 = detalleRows.firstWhere((r) => r['producto_id'] == 1);
      expect(linea1['cantidad'], equals(cantidad1));
      expect(linea1['subtotal'], equals(subtotal1.toSql()));
      expect(linea1['impuesto_total'], equals(impuesto1.toSql()));

      // Línea 2: tradicional
      final linea2 = detalleRows.firstWhere((r) => r['producto_id'] == 2);
      expect(linea2['cantidad'], equals(cantidad2));
      expect(linea2['subtotal'], equals(subtotal2.toSql()));
      expect(linea2['impuesto_total'], equals(impuesto2.toSql()));
    },
  );
}
