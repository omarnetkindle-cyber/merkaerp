// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/planeacion/pages/planeacion_page.dart';
import 'package:merka_erp/sector_publico/planeacion/database/schema_planeacion.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets(
    'PlaneacionPage renders tabs, banner TODO and handles empty state',
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
            await SchemaPlaneacion.crearTablas(db);
          },
        );
        DatabaseHelper.setTestDatabase(db);
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: PlaneacionPage(
            entidadId: 'ENT-TEST-PLANEACION',
            usuarioId: 'USR-TEST-01',
          ),
        ),
      );

      // Wait for real async tasks to finish
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Verify AppBar and Banner
      expect(find.text('Planeación Territorial & BPIN (DNP)'), findsOneWidget);
      expect(
        find.textContaining(
          'Pendiente: vincular automaticamente metas PDT/MGA',
        ),
        findsOneWidget,
      );

      // Verify BottomNavigationBar items
      expect(find.text('Proyectos MGA'), findsWidgets);
      expect(find.text('PDT'), findsWidgets);

      // Verify empty state for Proyectos MGA
      expect(find.text('Banco de Proyectos MGA (BPIN)'), findsOneWidget);
      expect(find.text('Registrar Proyecto MGA'), findsWidgets);
    },
  );
}
