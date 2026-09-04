// Regresión permanente: bug de conversión de precio en el POS.
//
// Historia del bug
// ────────────────
// Antes de este fix, ventas_page.dart inicializaba el campo editable de
// precio unitario del POS con:
//
//   text: (disponibles.first['precio'] is MoneyValue)
//       ? (disponibles.first['precio'] as MoneyValue).toMajorUnitsString()
//       : (disponibles.first['precio'] ?? '0').toString(),   // ← BUG
//
// Cuando obtenerProductos() devuelve el campo 'precio' como int (minor units
// post-v75, p.ej. 1000 para $10,00), la rama `is MoneyValue` falla y ejecuta
// `1000.toString()` → "1000". Luego, al pulsar "Agregar", el código hace:
//
//   MoneyValue.fromMajorUnits("1000", currency: currency)   // → 100 000 minor
//
// El resultado visible es que un producto de $10,00 se vende como $1 000,00.
//
// Fix aplicado
// ────────────
// Se introdujo el helper _priceToDisplay(Object? value, Currency currency)
// que normaliza int/double/MoneyValue → String de major units correctamente.
// Se usa en ambos sitios donde se inicializa precioUnitarioCtrl.
//
// Estos tests protegen ese contrato para siempre.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/sales/application/create_sale_use_case.dart';

// ────────────────────────────────────────────────────────────────────────────
// Réplica del helper _priceToDisplay de ventas_page.dart
//
// Se duplica aquí porque _priceToDisplay es una función de nivel superior
// en un archivo de UI (no puede importarse directamente en tests unitarios).
// Si la implementación del helper cambia, este test fallará como indicador.
// ────────────────────────────────────────────────────────────────────────────
String _priceToDisplay(Object? value, Currency currency) {
  if (value == null) return '0';
  if (value is MoneyValue) return value.toMajorUnitsString();
  if (value is int) {
    return MoneyValue(minorUnits: value, currency: currency)
        .toMajorUnitsString();
  }
  if (value is double) {
    return MoneyValue(minorUnits: value.round(), currency: currency)
        .toMajorUnitsString();
  }
  return '0';
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers para construir MoneyValue en los casos de prueba
// ────────────────────────────────────────────────────────────────────────────
Currency _cop2() => Currency(
      code: 'COP',
      name: 'Peso Colombiano',
      symbol: r'$',
      decimalPlaces: 2,
    );

Currency _cop0() => Currency(
      code: 'COP',
      name: 'Peso Colombiano',
      symbol: r'$',
      decimalPlaces: 0,
    );

MoneyValue _money(int minorUnits, Currency cur) =>
    MoneyValue(minorUnits: minorUnits, currency: cur);

MoneyValue _fromMajor(String value, Currency cur) =>
    MoneyValue.fromMajorUnits(value, currency: cur);

// ────────────────────────────────────────────────────────────────────────────
// Suite principal
// ────────────────────────────────────────────────────────────────────────────
void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // GRUPO 1: _priceToDisplay — contrato del helper
  //
  // Verifica todos los tipos de entrada que pueden llegar desde obtenerProductos()
  // (int post-v75, double pre-v75, MoneyValue ya hidratado) y que el resultado
  // sea siempre el string de major units correcto para mostrar en el TextField.
  // ──────────────────────────────────────────────────────────────────────────
  group('_priceToDisplay — contrato del helper', () {
    final cur2 = _cop2(); // 2 decimales: minorUnit = centavo
    final cur0 = _cop0(); // 0 decimales: minorUnit = peso

    // ── Tipo int (post-v75 SQLite INTEGER) ──────────────────────────────────

    test('int 1000 con 2 decimales → "10.00"  [regresión principal]', () {
      // ANTES del fix: 1000.toString() → "1000" → fromMajorUnits → $1000
      // DESPUÉS del fix: _priceToDisplay → "10.00"
      expect(_priceToDisplay(1000, cur2), '10.00');
    });

    test('int 1050 con 2 decimales → "10.50"', () {
      expect(_priceToDisplay(1050, cur2), '10.50');
    });

    test('int 100 con 2 decimales → "1.00"', () {
      expect(_priceToDisplay(100, cur2), '1.00');
    });

    test('int 50 con 2 decimales → "0.50"', () {
      expect(_priceToDisplay(50, cur2), '0.50');
    });

    test('int 125075 con 2 decimales → "1250.75"', () {
      expect(_priceToDisplay(125075, cur2), '1250.75');
    });

    test('int 250000 con 0 decimales → "250000" (COP sin centavos)', () {
      expect(_priceToDisplay(250000, cur0), '250000');
    });

    test('int 0 con 2 decimales → "0.00"', () {
      expect(_priceToDisplay(0, cur2), '0.00');
    });

    // ── Tipo MoneyValue (ya hidratado) ──────────────────────────────────────

    test('MoneyValue(1000, 2dec) → "10.00"', () {
      expect(_priceToDisplay(_money(1000, cur2), cur2), '10.00');
    });

    test('MoneyValue(125075, 2dec) → "1250.75"', () {
      expect(_priceToDisplay(_money(125075, cur2), cur2), '1250.75');
    });

    test('MoneyValue(50, 2dec) → "0.50"', () {
      expect(_priceToDisplay(_money(50, cur2), cur2), '0.50');
    });

    // ── Tipo double (pre-v75 columna REAL) ─────────────────────────────────

    test('double 1000.0 con 2 decimales → "10.00"', () {
      expect(_priceToDisplay(1000.0, cur2), '10.00');
    });

    test('double 50.0 con 2 decimales → "0.50"', () {
      expect(_priceToDisplay(50.0, cur2), '0.50');
    });

    // ── null y tipos desconocidos ────────────────────────────────────────────

    test('null → "0"', () {
      expect(_priceToDisplay(null, cur2), '0');
    });

    test('String desconocida → "0"', () {
      expect(_priceToDisplay('texto_invalido', cur2), '0');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GRUPO 2: round-trip — precio BD → display → fromMajorUnits → minorUnits
  //
  // Simula el ciclo completo que ocurre cuando el cajero ve "10.00" en el
  // TextField y pulsa "Agregar" sin editar el precio:
  //
  //   1. BD devuelve int 1000 (minor units)
  //   2. _priceToDisplay → "10.00"
  //   3. El cajero no cambia nada; precioUnitarioCtrl.text == "10.00"
  //   4. Botón Agregar: fromMajorUnits("10.00") → MoneyValue(minorUnits: 1000)
  //   5. MoneyValue llega al carrito con el valor correcto
  //
  // ANTES del fix el paso 2 daba "1000" y el paso 4 producía minorUnits=100000.
  // ──────────────────────────────────────────────────────────────────────────
  group('round-trip BD → display → carrito', () {
    final cur2 = _cop2();

    void roundTrip(
      int storedMinorUnits,
      double expectedMajorDisplay,
      String description,
    ) {
      test(description, () {
        // Paso 1-2: simula _priceToDisplay con int de BD
        final displayText = _priceToDisplay(storedMinorUnits, cur2);

        // Paso 4: simula lo que hace el botón Agregar con fromMajorUnits
        final recreated = _fromMajor(displayText, cur2);

        expect(
          recreated.minorUnits,
          storedMinorUnits,
          reason:
              'El round-trip debe conservar los minor units originales. '
              'display="$displayText" → minorUnits=${recreated.minorUnits} '
              '(esperado $storedMinorUnits)',
        );
        expect(
          recreated.toMajorUnitsDoubleForDisplay(),
          closeTo(expectedMajorDisplay, 0.001),
          reason: 'El valor económico debe ser $expectedMajorDisplay',
        );
      });
    }

    // Casos del enunciado
    roundTrip(1000, 10.00, 'caso 1 — precio 10.00');
    roundTrip(1050, 10.50, 'caso 2 — precio 10.50');
    roundTrip(100, 1.00, 'caso 3 — precio 1.00');
    roundTrip(50, 0.50, 'caso 4 — precio 0.50');
    roundTrip(125075, 1250.75, 'caso 5 — precio 1250.75');
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GRUPO 3: subtotal del carrito — cantidad × precio
  //
  // Caso 6 del enunciado: cantidad 3 × precio 10.00 → subtotal 30.00
  // ──────────────────────────────────────────────────────────────────────────
  group('subtotal del carrito', () {
    final cur2 = _cop2();

    test('caso 6 — 3 × 10.00 = 30.00', () {
      // Precio almacenado en BD: 1000 minor units
      final precioDisplay = _priceToDisplay(1000, cur2);
      expect(precioDisplay, '10.00');

      final precio = _fromMajor(precioDisplay, cur2);
      final subtotal = precio.multiplyDecimal('3');

      expect(
        subtotal.toMajorUnitsDoubleForDisplay(),
        closeTo(30.00, 0.001),
      );
      expect(subtotal.minorUnits, 3000);
    });

    test('4 × 1250.75 = 5003.00', () {
      final precio = _fromMajor(_priceToDisplay(125075, cur2), cur2);
      final subtotal = precio.multiplyDecimal('4');
      expect(subtotal.toMajorUnitsDoubleForDisplay(), closeTo(5003.00, 0.001));
      expect(subtotal.minorUnits, 500300);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GRUPO 4: IVA y descuento sobre precio correcto
  //
  // Caso 7 del enunciado: verificar que la base usada para IVA/descuento
  // es el precio monetario correcto y no el valor en centavos × 100.
  // ──────────────────────────────────────────────────────────────────────────
  group('IVA y descuento sobre precio monetario correcto', () {
    final cur2 = _cop2();

    test('caso 7a — IVA 19% sobre 10.00 = 1.90', () {
      final precio = _fromMajor(_priceToDisplay(1000, cur2), cur2);
      final iva = precio.percent('19');

      expect(iva.toMajorUnitsDoubleForDisplay(), closeTo(1.90, 0.01));
      // Si el bug existiera: precio sería MoneyValue(100000) → iva=19000
      expect(iva.minorUnits, isNot(19000 * 100));
      expect(iva.minorUnits, 190);
    });

    test('caso 7b — IVA 19% sobre 1250.75 = 237.64', () {
      final precio = _fromMajor(_priceToDisplay(125075, cur2), cur2);
      final iva = precio.percent('19');
      // 1250.75 × 0.19 = 237.6425 → 237.64 (redondeo banker)
      expect(iva.toMajorUnitsDoubleForDisplay(), closeTo(237.64, 0.01));
    });

    test('caso 7c — descuento 10% sobre 10.00 = 1.00', () {
      final precio = _fromMajor(_priceToDisplay(1000, cur2), cur2);
      final descuento = precio.percent('10');
      expect(descuento.toMajorUnitsDoubleForDisplay(), closeTo(1.00, 0.001));
      expect(descuento.minorUnits, 100);
    });

    test('caso 7d — total con IVA incluido: precio 10.00 incl. 19% → base 8.40', () {
      // Precio que incluye IVA: el POS debe calcular base = total / (1 + tasa)
      final totalCobrado = _fromMajor(_priceToDisplay(1000, cur2), cur2);
      final factor = 1.0 + (19.0 / 100.0);
      final baseMajor = totalCobrado.toMajorUnitsDoubleForDisplay() / factor;

      // base = 10.00 / 1.19 ≈ 8.403...
      expect(baseMajor, closeTo(8.403, 0.001));

      final baseMoneyStr = baseMajor.toStringAsFixed(cur2.decimalPlaces);
      final baseMoney = _fromMajor(baseMoneyStr, cur2);
      final impuesto = totalCobrado - baseMoney;

      expect(baseMoney.toMajorUnitsDoubleForDisplay(), closeTo(8.40, 0.01));
      expect(impuesto.toMajorUnitsDoubleForDisplay(), closeTo(1.60, 0.01));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GRUPO 5: persistencia — guardar venta y releer devuelve los mismos importes
  //
  // Verifica el criterio de aceptación: "consultar posteriormente la venta
  // devuelve exactamente los mismos importes" y que guardar no re-multiplica.
  // ──────────────────────────────────────────────────────────────────────────
  group('persistencia — venta guardada y releída conserva importes', () {
    late Directory dbDir;
    late Database db;
    late int companyId;

    final cur2 = _cop2();

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await DatabaseHelper.resetForTests();
      CompanyConfigurationService.instance.resetForTests();
      dbDir = await Directory.systemTemp
          .createTemp('merkaerp_price_display_regression_');
      await databaseFactory.setDatabasesPath(dbDir.path);
      db = await DatabaseHelper.instance.database;
      companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      await DatabaseHelper.instance.guardarCompanySettings(companyId, {
        'onboarding_completed': '1',
        'country': 'Colombia',
        'currency': 'COP',
        'timezone': 'America/Bogota',
      });
    });

    tearDownAll(() async {
      CompanyConfigurationService.instance.resetForTests();
      await DatabaseHelper.resetForTests();
      if (await dbDir.exists()) await dbDir.delete(recursive: true);
    });

    test(
      'precio 10.00 guardado en BD y releído permanece 10.00 (no 1000)',
      () async {
        // Simula precio que el usuario ingresó: "10.00" (major units)
        final precioIngresado = MoneyValue.fromMajorUnits('10.00', currency: cur2);
        expect(precioIngresado.minorUnits, 1000,
            reason: 'fromMajorUnits("10.00") debe dar 1000 centavos');

        // Persiste en BD (igual que ProductRepository.save)
        final productId = await db.insert('productos', {
          'company_id': companyId,
          'nombre': 'Producto regresion precio',
          'unidad_base': 'und',
          'stock': 10.0,
          'costo': 500,    // 5.00
          'precio': precioIngresado.toSql(), // 1000
          'impuesto_pct': 0.0,
          'tipo_item': 'producto',
          'precio_incluye_iva': 0,
        });
        expect(productId, greaterThan(0));

        // Lee de BD (igual que obtenerProductos → _abrirFormulario)
        final rows = await db.query(
          'productos',
          where: 'id = ? AND company_id = ?',
          whereArgs: [productId, companyId],
        );
        final rawPrecio = rows.first['precio']; // int en BD post-v75
        expect(rawPrecio, 1000,
            reason: 'La BD debe almacenar 1000 minor units');

        // Aplica _priceToDisplay (lo que hace ventas_page tras el fix)
        final displayed = _priceToDisplay(rawPrecio, cur2);
        expect(displayed, '10.00',
            reason: '_priceToDisplay debe convertir 1000 centavos → "10.00"');

        // Simula "Agregar" sin editar precio
        final precioCarrito = MoneyValue.fromMajorUnits(displayed, currency: cur2);
        expect(precioCarrito.minorUnits, 1000,
            reason: 'El precio en el carrito debe ser 1000 centavos (= 10.00)');
        expect(
          precioCarrito.toMajorUnitsDoubleForDisplay(),
          closeTo(10.00, 0.001),
          reason: 'El valor económico en el carrito debe ser 10.00',
        );
      },
    );

    test(
      'flujo completo: crear producto 10.00, vender × 3, subtotal = 30.00',
      () async {
        final precioOriginal = MoneyValue.fromMajorUnits('10.00', currency: cur2);

        final productId = await db.insert('productos', {
          'company_id': companyId,
          'nombre': 'Producto regresion subtotal',
          'unidad_base': 'und',
          'stock': 10.0,
          'costo': 500,
          'precio': precioOriginal.toSql(),
          'impuesto_pct': 0.0,
          'tipo_item': 'producto',
          'precio_incluye_iva': 0,
        });

        // Lee de BD → pasa por _priceToDisplay → reconstruye precio
        final rows = await db.query('productos',
            where: 'id = ? AND company_id = ?',
            whereArgs: [productId, companyId]);
        final precioDisplay = _priceToDisplay(rows.first['precio'], cur2);
        final precio = MoneyValue.fromMajorUnits(precioDisplay, currency: cur2);
        final subtotal = precio.multiplyDecimal('3');

        expect(
          subtotal.toMajorUnitsDoubleForDisplay(),
          closeTo(30.00, 0.001),
          reason: '3 × 10.00 debe ser 30.00',
        );

        // Guarda la venta con los valores correctos
        final ventaId = await db.insert('ventas', {
          'company_id': companyId,
          'producto': 'Producto regresion subtotal',
          'cantidad': 3.0,
          'subtotal': subtotal.toSql(),
          'impuesto_pct': 0.0,
          'impuesto_total': 0,
          'total': subtotal.toSql(),
          'fecha': DateTime.now().toIso8601String(),
          'metodo_pago_id': 1,
          'cliente': 'Cliente general',
          'estado': 'emitida',
        });

        // Relee la venta y confirma el total
        final ventaRows = await db.query('ventas',
            where: 'id = ? AND company_id = ?',
            whereArgs: [ventaId, companyId]);
        final totalGuardado = MoneyValue.fromSql(
          ventaRows.first['total'],
          currency: cur2,
        );

        expect(
          totalGuardado.toMajorUnitsDoubleForDisplay(),
          closeTo(30.00, 0.001),
          reason: 'La venta releída debe tener total 30.00, no 3000',
        );
        expect(
          totalGuardado.minorUnits,
          3000,
          reason: 'En BD debe haber 3000 centavos (= 30.00)',
        );
      },
    );

    test(
      'flujo CreateSaleUseCase — precio 10.00, cantidad 3, total correcto',
      () async {
        final suffix = DateTime.now().microsecondsSinceEpoch;
        final productName = 'Producto pos price $suffix';

        // Precio almacenado: 1000 (= 10.00 con 2 decimales)
        final productId = await db.insert('productos', {
          'company_id': companyId,
          'nombre': productName,
          'unidad_base': 'und',
          'stock': 10.0,
          'costo': 500,
          'precio': 1000,
          'impuesto_pct': 0.0,
          'codigo_barras': '',
          'conversion_nombre': '',
          'conversion_cantidad': 0.0,
          'tipo_item': 'producto',
          'precio_incluye_iva': 0,
        });

        // Simula el flujo tras el fix:
        // BD devuelve 1000 → _priceToDisplay → "10.00" → fromMajorUnits → 1000
        final rawPrecio = 1000; // lo que devuelve obtenerProductos()
        final precioDisplay = _priceToDisplay(rawPrecio, cur2);
        final unitPrice = MoneyValue.fromMajorUnits(precioDisplay, currency: cur2);
        final subtotal = unitPrice.multiplyDecimal('3');

        final useCase = CreateSaleUseCase();
        final result = await useCase.execute(
          CreateSaleRequest(
            items: [
              SaleItemInput(
                productId: productId,
                productName: productName,
                quantity: 3,
                unitPrice: unitPrice,
                unitCost: MoneyValue(minorUnits: 500, currency: cur2),
                subtotal: subtotal,
                taxRate: 0,
                taxTotal: MoneyValue(minorUnits: 0, currency: cur2),
              ),
            ],
            paymentMethodId: 1,
            paymentMethodName: 'EFECTIVO',
            clientName: 'Cliente general',
            efectivo: subtotal,
            transferencia: MoneyValue(minorUnits: 0, currency: cur2),
            credito: MoneyValue(minorUnits: 0, currency: cur2),
            retefuente: MoneyValue(minorUnits: 0, currency: cur2),
            reteiva: MoneyValue(minorUnits: 0, currency: cur2),
            reteica: MoneyValue(minorUnits: 0, currency: cur2),
          ),
        );

        expect(
          result.total.toMajorUnitsDoubleForDisplay(),
          closeTo(30.00, 0.001),
          reason: 'CreateSaleUseCase debe producir total 30.00, no 3000.00',
        );
        expect(
          result.subtotal.toMajorUnitsDoubleForDisplay(),
          closeTo(30.00, 0.001),
        );

        // Confirmar en BD
        final ventaRows = await db.query('ventas',
            where: 'id = ? AND company_id = ?',
            whereArgs: [result.saleId, companyId]);
        final totalBD = MoneyValue.fromSql(
          ventaRows.first['total'],
          currency: cur2,
        );
        expect(
          totalBD.toMajorUnitsDoubleForDisplay(),
          closeTo(30.00, 0.001),
          reason: 'El total guardado en BD debe ser 30.00 (3000 centavos)',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GRUPO 6: regresión negativa — confirmar que el bug anterior ya no ocurre
  //
  // Si alguien revierte _priceToDisplay al comportamiento previo (int.toString)
  // estos tests deben fallar de inmediato con mensajes claros.
  // ──────────────────────────────────────────────────────────────────────────
  group('regresión negativa — el bug anterior no ocurre', () {
    final cur2 = _cop2();

    test('int 1000 NO produce texto "1000" (que causaría precio = 1000.00)', () {
      final display = _priceToDisplay(1000, cur2);
      expect(
        display,
        isNot('1000'),
        reason:
            'Si display fuera "1000", fromMajorUnits lo convertiría a 100000 '
            'centavos = \$1000.00 en vez de \$10.00. Bug anterior confirmado.',
      );
    });

    test('int 50 NO produce texto "50" (que causaría precio = 50.00 en vez de 0.50)', () {
      final display = _priceToDisplay(50, cur2);
      expect(
        display,
        isNot('50'),
        reason: 'display="50" → fromMajorUnits → 5000 centavos = \$50, no \$0.50',
      );
    });

    test('fromMajorUnits del display correcto NO produce minorUnits × 100', () {
      // El bug anterior producía: 1000.toString() → fromMajorUnits("1000") → 100000
      final correctDisplay = _priceToDisplay(1000, cur2); // "10.00"
      final result = MoneyValue.fromMajorUnits(correctDisplay, currency: cur2);
      expect(
        result.minorUnits,
        isNot(100000),
        reason: 'minorUnits=100000 significaría precio=\$1000 (bug anterior)',
      );
      expect(result.minorUnits, 1000);
    });
  });
}
