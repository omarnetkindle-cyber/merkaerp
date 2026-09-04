// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/rentas/pages/predial_ica_page.dart';
import 'package:merka_erp/sector_publico/rentas/database/schema_rentas.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('PredialICAPage renders Predial and ICA tabs and TODO banner', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE IF NOT EXISTS entidades_territoriales (
            id TEXT PRIMARY KEY,
            nit TEXT NOT NULL,
            razon_social TEXT NOT NULL,
            tipo_entidad TEXT NOT NULL,
            fecha_creacion TEXT NOT NULL,
            plan_cuentas_cgc TEXT NOT NULL,
            configuracion_normativa TEXT NOT NULL
          )
        ''');
          await SchemaRentas.crearTablas(db);
        },
      );
      DatabaseHelper.setTestDatabase(db);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: PredialICAPage(
          entidadId: 'ENT-TEST-RENTAS',
          usuarioId: 'USR-TEST-02',
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Verify AppBar
    expect(
      find.text('Rentas - Predial e Industria y Comercio (ICA)'),
      findsOneWidget,
    );

    // Verify Main Tabs
    expect(find.text('Impuesto Predial'), findsWidgets);
    expect(find.text('Industria y Comercio (ICA)'), findsWidgets);

    // Switch to ICA tab
    await tester.tap(find.text('Industria y Comercio (ICA)'));
    await tester.pumpAndSettle();

    // Verify ICA elements and active export banner
    expect(
      find.textContaining('Exportacion ICA PDF/XML activa'),
      findsOneWidget,
    );
    expect(find.text('Censo de Contribuyentes ICA'), findsOneWidget);
  });
}
