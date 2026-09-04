// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/salud/pages/salud_publica_page.dart';
import 'package:merka_erp/sector_publico/salud/database/schema_salud.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('SaludPublicaPage renders RIPS and Glosas tabs and TODO banner', (
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
          await SchemaSalud.crearTablas(db);
        },
      );
      DatabaseHelper.setTestDatabase(db);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SaludPublicaPage(
          entidadId: 'ENT-TEST-SALUD',
          usuarioId: 'USR-TEST-04',
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Verify AppBar
    expect(find.text('Salud Pública (RIPS / EPS / ADRES)'), findsOneWidget);

    // Verify BottomNavigationBar Tabs
    expect(find.text('RIPS'), findsWidgets);
    expect(find.text('Glosas'), findsWidgets);

    // Verify TODO Banner
    expect(
      find.textContaining('Gestión integral ESE / Salud:'),
      findsOneWidget,
    );
  });
}
