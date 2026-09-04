// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/activos/pages/activos_estado_page.dart';
import 'package:merka_erp/sector_publico/activos/database/schema_activos.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets(
    'ActivosEstadoPage renders Activos and FUT tabs and responsibility banner',
    (WidgetTester tester) async {
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
            await SchemaActivos.crearTablas(db);
          },
        );
        DatabaseHelper.setTestDatabase(db);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ActivosEstadoPage(
            entidadId: 'ENT-TEST-ACTIVOS',
            usuarioId: 'USR-TEST-03',
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Verify AppBar
      expect(
        find.text('Propiedad, Planta y Equipo (NICSP 17)'),
        findsOneWidget,
      );

      // Verify BottomNavigationBar Tabs
      expect(find.text('Activos NICSP 17'), findsWidgets);
      expect(find.text('FUT'), findsWidgets);

      // Verify responsibility banner
      expect(
        find.textContaining(
          'Actas de responsabilidad a cuentadantes activas',
        ),
        findsOneWidget,
      );
    },
  );
}
