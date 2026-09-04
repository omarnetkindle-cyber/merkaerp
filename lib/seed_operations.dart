import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';

void main(List<String> args) async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;

  // Herramienta destructiva de desarrollo: nunca intenta adivinar rutas ni toca
  // bases instaladas automáticamente. Exige una ruta explícita y confirmación.
  String? databasePath = Platform.environment['MERKAERP_SEED_DB'];
  for (final arg in args) {
    if (arg.startsWith('--database=')) {
      databasePath = arg.substring('--database='.length);
    }
  }
  // Se recomienda ejecutar con
  // MERKAERP_SEED_DB=<ruta> y MERKAERP_ALLOW_DESTRUCTIVE_SEED=YES.
  if (databasePath == null || databasePath.trim().isEmpty) {
    stderr.writeln(
      'Seed cancelado: defina MERKAERP_SEED_DB con la ruta explícita de la base.',
    );
    exitCode = 64;
    return;
  }
  if (Platform.environment['MERKAERP_ALLOW_DESTRUCTIVE_SEED'] != 'YES') {
    stderr.writeln(
      'Seed cancelado: esta operación borra datos. Defina '
      'MERKAERP_ALLOW_DESTRUCTIVE_SEED=YES para confirmarla.',
    );
    exitCode = 77;
    return;
  }

  final dbPaths = <String>[databasePath.trim()];

  for (final dbPath in dbPaths) {
    print("\n=========================================");
    print("Processing database at: $dbPath");
    print("=========================================");

    final file = File(dbPath);
    if (!file.existsSync()) {
      print("Database file does not exist at $dbPath. Skipping.");
      continue;
    }

    Database db;
    try {
      db = await databaseFactory.openDatabase(dbPath);
    } catch (e) {
      print("Could not open database at $dbPath: $e. Skipping.");
      continue;
    }

    try {
      // 1. Obtener ID de la empresa activa o crear una si no hay
      final List<Map<String, dynamic>> companies = await db.query('companies');
      int companyId = 1;
      if (companies.isNotEmpty) {
        companyId = companies.first['id'] as int;
        print("Found existing company with ID: $companyId");
      } else {
        print("No companies found. Seeding a default company...");
        companyId = await db.insert('companies', {
          'nombre': 'Merka S.A.S',
          'nit': '123456789',
          'regimen': 'comun',
          'direccion': 'Calle 26 # 69-76, Bogotá',
          'telefono': '6014567890',
          'created_at': DateTime.now()
              .subtract(const Duration(days: 365))
              .toIso8601String(),
        });
      }

      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      int moneySql(String value) =>
          MoneyValue.fromMajorUnits(value, currency: currency).toSql();

      // 2. Limpiar datos viejos de transacciones para no duplicar
      print("Cleaning transaction history...");
      await db.delete('ventas_detalle');
      await db.delete('ventas');
      await db.delete('compras_detalle');
      await db.delete('compras');
      await db.delete('movimientos_inventario');
      await db.delete('movimientos_caja');
      await db.delete('cierres_caja');
      await db.delete('asiento_lineas');
      await db.delete('asientos_contables');
      await db.delete('lotes');
      await db.delete('cuentas_por_cobrar');
      await db.delete('cuentas_por_pagar');
      await db.delete('abonos_cxp');
      await db.delete('proveedores');
      await db.delete('clientes');
      await db.delete('productos');
      await db.delete('usuarios');

      // Re-sembrar usuario administrador predeterminado
      await db.insert('usuarios', {
        'company_id': companyId,
        'nombre': 'Administrador',
        'usuario': 'admin',
        'rol': 'administrador',
        'pin': null,
        'activo': 1,
        'fecha': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Asegurar onboarding completado
      await db.insert('company_settings', {
        'company_id': companyId,
        'setting_key': 'onboarding_completed',
        'setting_value': '1',
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Asegurar empresa activa en app_config
      await db.insert('app_config', {
        'clave': 'company_active_id',
        'valor': companyId.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 3. Crear Clientes
      final clientsInfo = [
        {
          'nombre': 'Juan Pérez',
          'documento': '1015432120',
          'telefono': '3101234567',
          'email': 'juan@gmail.com',
          'company_id': companyId,
        },
        {
          'nombre': 'María Gómez',
          'documento': '52432981',
          'telefono': '3159876543',
          'email': 'maria@gmail.com',
          'company_id': companyId,
        },
        {
          'nombre': 'Carlos Rodríguez',
          'documento': '80123456',
          'telefono': '3204561234',
          'email': 'carlos@gmail.com',
          'company_id': companyId,
        },
        {
          'nombre': 'Distribuidora Central',
          'documento': '900123456-7',
          'telefono': '6013334444',
          'email': 'ventas@central.com',
          'company_id': companyId,
        },
      ];
      final Map<String, int> clientIds = {};
      for (final c in clientsInfo) {
        final id = await db.insert('clientes', c);
        clientIds[c['nombre'] as String] = id;
      }
      print("Seeded ${clientIds.length} clients.");

      // 4. Crear Proveedores
      final suppliersInfo = [
        {
          'nombre': 'Colanta S.A.',
          'nit': '890900123-1',
          'contacto': 'Ventas Colanta',
          'telefono': '6044445555',
          'email': 'pedidos@colanta.com.co',
          'company_id': companyId,
        },
        {
          'nombre': 'Nestlé Colombia',
          'nit': '860002130-9',
          'contacto': 'Pedidos Nestlé',
          'telefono': '6012223333',
          'email': 'pedidos@nestle.com',
          'company_id': companyId,
        },
        {
          'nombre': 'Alpina Productos Lácteos',
          'nit': '860005432-2',
          'contacto': 'Logística Alpina',
          'telefono': '6018889999',
          'email': 'pedidos@alpina.com',
          'company_id': companyId,
        },
        {
          'nombre': 'Molino Tres Castillos',
          'nit': '890480020-4',
          'contacto': 'Ventas Harina',
          'telefono': '6056667777',
          'email': 'harinas@trescastillos.com',
          'company_id': companyId,
        },
      ];
      final Map<String, int> supplierIds = {};
      for (final s in suppliersInfo) {
        final id = await db.insert('proveedores', s);
        supplierIds[s['nombre'] as String] = id;
      }
      print("Seeded ${supplierIds.length} suppliers.");

      // 5. Crear Productos
      final productsInfo = [
        {
          'nombre': 'Leche Entera Colanta 1L',
          'unidad_base': 'unid.',
          'stock': 120,
          'costo': moneySql('2800.00'),
          'precio': moneySql('3800.00'),
          'impuesto_pct': 19,
          'codigo_barras': '7702001002003',
          'company_id': companyId,
        },
        {
          'nombre': 'Yogurt Alpina Fresa 150g',
          'unidad_base': 'unid.',
          'stock': 85,
          'costo': moneySql('1800.00'),
          'precio': moneySql('2600.00'),
          'impuesto_pct': 19,
          'codigo_barras': '7702002003004',
          'company_id': companyId,
        },
        {
          'nombre': 'Café Nescafé Tradición 200g',
          'unidad_base': 'unid.',
          'stock': 4,
          'costo': moneySql('8500.00'),
          'precio': moneySql('12500.00'),
          'impuesto_pct': 19,
          'codigo_barras': '7703001004005',
          'company_id': companyId,
        },
        {
          'nombre': 'Harina de Trigo Tres Castillos 1kg',
          'unidad_base': 'unid.',
          'stock': 2,
          'costo': moneySql('3200.00'),
          'precio': moneySql('4500.00'),
          'impuesto_pct': 0,
          'codigo_barras': '7704001005006',
          'company_id': companyId,
        },
        {
          'nombre': 'Aceite de Girasol Gourmet 1L',
          'unidad_base': 'unid.',
          'stock': 45,
          'costo': moneySql('12000.00'),
          'precio': moneySql('16900.00'),
          'impuesto_pct': 19,
          'codigo_barras': '7705001006007',
          'company_id': companyId,
        },
        {
          'nombre': 'Arroz Diana Premium 1kg',
          'unidad_base': 'unid.',
          'stock': 200,
          'costo': moneySql('2200.00'),
          'precio': moneySql('3200.00'),
          'impuesto_pct': 0,
          'codigo_barras': '7706001007008',
          'company_id': companyId,
        },
        {
          'nombre': 'Chocolate Sol 500g',
          'unidad_base': 'unid.',
          'stock': 60,
          'costo': moneySql('4200.00'),
          'precio': moneySql('5900.00'),
          'impuesto_pct': 19,
          'codigo_barras': '7707001008009',
          'company_id': companyId,
        },
        {
          'nombre': 'Queso Doble Crema Colanta 500g',
          'unidad_base': 'unid.',
          'stock': 30,
          'costo': moneySql('8000.00'),
          'precio': moneySql('11900.00'),
          'impuesto_pct': 19,
          'codigo_barras': '7708001009010',
          'company_id': companyId,
        },
      ];

      final Map<String, int> productIds = {};
      for (final p in productsInfo) {
        final id = await db.insert('productos', p);
        productIds[p['nombre'] as String] = id;
      }
      print("Seeded ${productIds.length} products.");

      // 6. Registrar Lotes y Vencimientos
      await db.insert('lotes', {
        'company_id': companyId,
        'producto_id': productIds['Leche Entera Colanta 1L'],
        'codigo_lote': 'L-COL102',
        'fecha_vencimiento': DateTime.now()
            .add(const Duration(days: 10))
            .toIso8601String()
            .split('T')
            .first,
        'cantidad': 50,
        'costo': moneySql('2800.00'),
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('lotes', {
        'company_id': companyId,
        'producto_id': productIds['Yogurt Alpina Fresa 150g'],
        'codigo_lote': 'L-ALP998',
        'fecha_vencimiento': DateTime.now()
            .add(const Duration(days: 20))
            .toIso8601String()
            .split('T')
            .first,
        'cantidad': 35,
        'costo': moneySql('1800.00'),
        'created_at': DateTime.now().toIso8601String(),
      });
      print("Seeded active batches (lotes).");

      // 7. Cuentas contables IDs
      final List<Map<String, dynamic>> ccCaja = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['110505'],
      );
      final List<Map<String, dynamic>> ccBanco = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['111005'],
      );
      final List<Map<String, dynamic>> ccClientes = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['130505'],
      );
      final List<Map<String, dynamic>> ccProveedores = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['220505'],
      );
      final List<Map<String, dynamic>> ccVentas = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['413505'],
      );
      final List<Map<String, dynamic>> ccCostos = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['613505'],
      );
      final List<Map<String, dynamic>> ccInventario = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['143505'],
      );
      final List<Map<String, dynamic>> ccIvaGenerado = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['240805'],
      );
      final List<Map<String, dynamic>> ccIvaDescontable = await db.query(
        'cuentas_contables',
        where: 'codigo = ?',
        whereArgs: ['240810'],
      );

      final int idCaja = ccCaja.isNotEmpty ? ccCaja.first['id'] as int : 1;
      final int idBanco = ccBanco.isNotEmpty ? ccBanco.first['id'] as int : 2;
      final int idClientes = ccClientes.isNotEmpty
          ? ccClientes.first['id'] as int
          : 3;
      final int idProveedores = ccProveedores.isNotEmpty
          ? ccProveedores.first['id'] as int
          : 4;
      final int idVentas = ccVentas.isNotEmpty
          ? ccVentas.first['id'] as int
          : 5;
      final int idCostos = ccCostos.isNotEmpty
          ? ccCostos.first['id'] as int
          : 6;
      final int idInventario = ccInventario.isNotEmpty
          ? ccInventario.first['id'] as int
          : 7;
      final int idIvaGenerado = ccIvaGenerado.isNotEmpty
          ? ccIvaGenerado.first['id'] as int
          : 8;
      final int idIvaDescontable = ccIvaDescontable.isNotEmpty
          ? ccIvaDescontable.first['id'] as int
          : 9;

      // 8. Generar HISTORIAL DE VENTAS (último año)
      print("Generating 1 year of sales history...");
      final List<String> productKeys = productIds.keys.toList();
      final List<String> clientKeys = clientIds.keys.toList();

      int saleCounter = 0;
      for (int dayOffset = 360; dayOffset >= 5; dayOffset -= 5) {
        final saleDate = DateTime.now().subtract(Duration(days: dayOffset));
        final dateStr = saleDate.toIso8601String().split('.').first;

        final clientName = clientKeys[saleCounter % clientKeys.length];
        final clientId = clientIds[clientName];
        final isCredit = saleCounter % 6 == 0;

        final numItems = (saleCounter % 3) + 1;
        var saleSubtotal = MoneyValue(minorUnits: 0, currency: currency);
        var saleImpuestos = MoneyValue(minorUnits: 0, currency: currency);
        var saleCostoTotal = MoneyValue(minorUnits: 0, currency: currency);

        final List<Map<String, dynamic>> saleDetails = [];

        for (int i = 0; i < numItems; i++) {
          final pName = productKeys[(saleCounter + i) % productKeys.length];
          final pId = productIds[pName]!;
          final pInfo = productsInfo.firstWhere((p) => p['nombre'] == pName);

          final int qty = ((saleCounter + i) % 3) + 1;
          final price = MoneyValue.fromSql(pInfo['precio'], currency: currency);
          final cost = MoneyValue.fromSql(pInfo['costo'], currency: currency);
          final int taxPct = (pInfo['impuesto_pct'] as num).toInt();

          final itemSubtotal = price * qty;
          final itemTax = itemSubtotal.multiplyRatio(
            numerator: taxPct,
            denominator: 100,
          );
          final itemCost = cost * qty;

          saleSubtotal += itemSubtotal;
          saleImpuestos += itemTax;
          saleCostoTotal += itemCost;

          saleDetails.add({
            'company_id': companyId,
            'producto_id': pId,
            'producto': pName,
            'cantidad': qty,
            'precio_unitario': price.toSql(),
            'subtotal': itemSubtotal.toSql(),
          });
        }

        final saleTotal = saleSubtotal + saleImpuestos;
        final int paymentMethod = isCredit ? 3 : 1;

        final saleId = await db.insert('ventas', {
          'company_id': companyId,
          'producto_id': saleDetails.first['producto_id'],
          'producto': saleDetails.first['producto'],
          'cantidad': saleDetails.first['cantidad'],
          'precio_unitario': saleDetails.first['precio_unitario'],
          'costo_unitario': productsInfo.firstWhere(
            (p) => p['nombre'] == saleDetails.first['producto'],
          )['costo'],
          'subtotal': saleSubtotal.toSql(),
          'impuesto_pct': 19,
          'impuesto_total': saleImpuestos.toSql(),
          'total': saleTotal.toSql(),
          'fecha': dateStr,
          'metodo_pago_id': paymentMethod,
          'estado': 'emitida',
        });

        for (final d in saleDetails) {
          d['venta_id'] = saleId;
          await db.insert('ventas_detalle', d);

          await db.insert('movimientos_inventario', {
            'company_id': companyId,
            'producto_id': d['producto_id'],
            'tipo': 'salida',
            'cantidad': d['cantidad'],
            'motivo': 'Venta POS #$saleId',
            'fecha': dateStr,
          });
        }

        if (isCredit) {
          await db.insert('cuentas_por_cobrar', {
            'company_id': companyId,
            'cliente_id': clientId,
            'cliente': clientName,
            'venta_id': saleId,
            'total': saleTotal.toSql(),
            'saldo': saleTotal.toSql(),
            'fecha': dateStr,
            'estado': 'pendiente',
          });
        } else {
          await db.insert('movimientos_caja', {
            'company_id': companyId,
            'tipo': 'ingreso',
            'concepto': 'Venta POS #$saleId',
            'monto': saleTotal.toSql(),
            'fecha': dateStr,
            'origen': 'caja',
          });
        }

        final seatId = await db.insert('asientos_contables', {
          'company_id': companyId,
          'fecha': dateStr,
          'concepto': 'Venta POS #$saleId',
          'referencia': 'V-$saleId',
          'origen': 'ventas',
          'estado': 'borrador',
        });

        await db.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': seatId,
          'cuenta_id': isCredit ? idClientes : idCaja,
          'descripcion': 'Cobro Venta #$saleId',
          'debito': saleTotal.toSql(),
          'credito': 0,
          'tercero': clientName,
        });

        await db.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': seatId,
          'cuenta_id': idVentas,
          'descripcion': 'Ingreso Venta #$saleId',
          'debito': 0,
          'credito': saleSubtotal.toSql(),
          'tercero': clientName,
        });

        if (saleImpuestos.minorUnits > 0) {
          await db.insert('asiento_lineas', {
            'company_id': companyId,
            'asiento_id': seatId,
            'cuenta_id': idIvaGenerado,
            'descripcion': 'IVA Generado Venta #$saleId',
            'debito': 0,
            'credito': saleImpuestos.toSql(),
            'tercero': clientName,
          });
        }

        await db.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': seatId,
          'cuenta_id': idCostos,
          'descripcion': 'Costo Venta #$saleId',
          'debito': saleCostoTotal.toSql(),
          'credito': 0,
          'tercero': clientName,
        });

        await db.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': seatId,
          'cuenta_id': idInventario,
          'descripcion': 'Baja Inventario Venta #$saleId',
          'debito': 0,
          'credito': saleCostoTotal.toSql(),
          'tercero': clientName,
        });

        await db.update(
          'asientos_contables',
          {'estado': 'registrado'},
          where: 'id = ?',
          whereArgs: [seatId],
        );

        saleCounter++;
      }
      print("Successfully seeded $saleCounter sales over 1 year.");

      // 9. Generar HISTORIAL DE COMPRAS (último año)
      print("Generating 1 year of purchases history...");
      final List<String> supplierKeys = supplierIds.keys.toList();

      int purchaseCounter = 0;
      for (int dayOffset = 340; dayOffset >= 15; dayOffset -= 25) {
        final purchaseDate = DateTime.now().subtract(Duration(days: dayOffset));
        final dateStr = purchaseDate.toIso8601String().split('.').first;

        final supplierName =
            supplierKeys[purchaseCounter % supplierKeys.length];
        final supplierId = supplierIds[supplierName];
        final isCredit = purchaseCounter % 3 == 0;

        var purchaseSubtotal = MoneyValue(minorUnits: 0, currency: currency);
        var purchaseImpuestos = MoneyValue(minorUnits: 0, currency: currency);
        final List<Map<String, dynamic>> purchaseDetails = [];

        for (int i = 0; i < 2; i++) {
          final pName = productKeys[(purchaseCounter + i) % productKeys.length];
          final pId = productIds[pName]!;
          final pInfo = productsInfo.firstWhere((p) => p['nombre'] == pName);

          const int qty = 30;
          final cost = MoneyValue.fromSql(pInfo['costo'], currency: currency);
          final int taxPct = (pInfo['impuesto_pct'] as num).toInt();

          final itemSubtotal = cost * qty;
          final itemTax = itemSubtotal.multiplyRatio(
            numerator: taxPct,
            denominator: 100,
          );

          purchaseSubtotal += itemSubtotal;
          purchaseImpuestos += itemTax;

          purchaseDetails.add({
            'company_id': companyId,
            'producto_id': pId,
            'producto': pName,
            'cantidad': qty,
            'costo_unitario': cost.toSql(),
            'subtotal': itemSubtotal.toSql(),
          });
        }

        final purchaseTotal = purchaseSubtotal + purchaseImpuestos;
        final int paymentMethod = isCredit ? 3 : 2;

        final purchaseId = await db.insert('compras', {
          'company_id': companyId,
          'proveedor_id': supplierId,
          'proveedor': supplierName,
          'numero_factura': 'FAC-${1000 + purchaseCounter}',
          'subtotal': purchaseSubtotal.toSql(),
          'impuesto_pct': 19,
          'impuesto_total': purchaseImpuestos.toSql(),
          'total': purchaseTotal.toSql(),
          'fecha': dateStr,
          'fecha_factura': dateStr,
          'metodo_pago_id': paymentMethod,
          'estado': isCredit ? 'pendiente' : 'pagada',
          'efectivo': 0,
          'transferencia': isCredit ? 0 : purchaseTotal.toSql(),
          'credito': isCredit ? purchaseTotal.toSql() : 0,
          'observacion': 'Compra de abastecimiento general',
        });

        for (final d in purchaseDetails) {
          d['compra_id'] = purchaseId;
          await db.insert('compras_detalle', d);

          await db.insert('movimientos_inventario', {
            'company_id': companyId,
            'producto_id': d['producto_id'],
            'tipo': 'entrada',
            'cantidad': d['cantidad'],
            'motivo': 'Compra Proveedor #$purchaseId',
            'fecha': dateStr,
          });
        }

        if (isCredit) {
          await db.insert('cuentas_por_pagar', {
            'company_id': companyId,
            'proveedor': supplierName,
            'total': purchaseTotal.toSql(),
            'saldo': purchaseTotal.toSql(),
            'fecha': dateStr,
            'estado': 'pendiente',
            'descripcion': 'Factura de compra #FAC-${1000 + purchaseCounter}',
          });
        }

        final seatId = await db.insert('asientos_contables', {
          'company_id': companyId,
          'fecha': dateStr,
          'concepto': 'Compra Proveedor #$purchaseId',
          'referencia': 'C-$purchaseId',
          'origen': 'compras',
          'estado': 'borrador',
        });

        await db.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': seatId,
          'cuenta_id': idInventario,
          'descripcion': 'Entrada Inventario Compra #$purchaseId',
          'debito': purchaseSubtotal.toSql(),
          'credito': 0,
          'tercero': supplierName,
        });

        if (purchaseImpuestos.minorUnits > 0) {
          await db.insert('asiento_lineas', {
            'company_id': companyId,
            'asiento_id': seatId,
            'cuenta_id': idIvaDescontable,
            'descripcion': 'IVA Descontable Compra #$purchaseId',
            'debito': purchaseImpuestos.toSql(),
            'credito': 0,
            'tercero': supplierName,
          });
        }

        await db.insert('asiento_lineas', {
          'company_id': companyId,
          'asiento_id': seatId,
          'cuenta_id': isCredit ? idProveedores : idBanco,
          'descripcion': 'Pago Compra #$purchaseId',
          'debito': 0,
          'credito': purchaseTotal.toSql(),
          'tercero': supplierName,
        });

        await db.update(
          'asientos_contables',
          {'estado': 'registrado'},
          where: 'id = ?',
          whereArgs: [seatId],
        );

        purchaseCounter++;
      }
      print("Successfully seeded $purchaseCounter purchases over 1 year.");

      // 10. Generar cierres de caja históricos
      print("Generating historical cash closings...");
      for (int dayOffset = 300; dayOffset >= 10; dayOffset -= 15) {
        final closeDate = DateTime.now().subtract(Duration(days: dayOffset));
        final dateStr = closeDate.toIso8601String().split('.').first;

        await db.insert('cierres_caja', {
          'company_id': companyId,
          'fecha': dateStr,
          'saldo_sistema': moneySql('350000.00'),
          'efectivo_contado': moneySql('350000.00'),
          'diferencia': 0,
          'observacion':
              'Desglose: [3x\$50k, 8x\$20k, 4x\$10k]. Cierre de caja operativo exitoso.',
        });
      }
      print("Successfully seeded historical closures.");
    } catch (e, stack) {
      print("Error during seed execution for $dbPath: $e");
      print(stack);
    } finally {
      await db.close();
      print("Database $dbPath closed.");
    }
  }
  print("\nAll database seeding passes completed successfully!");
}
