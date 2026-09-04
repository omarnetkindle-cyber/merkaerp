/// Prueba de widget para Presupuesto Público
/// Verifica la creación de apropiaciones, CDPs, RPs, obligaciones y pagos
/// con validación de base de datos real y bloqueos normativos
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/presupuesto/pages/presupuesto_publico_page.dart';
import 'package:merka_erp/sector_publico/presupuesto/models/apropiacion.dart';
import 'package:merka_erp/sector_publico/presupuesto/models/cdp.dart';
import 'package:merka_erp/sector_publico/presupuesto/models/rp.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:merka_erp/sector_publico/contratacion/database/schema_contratacion.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/planeacion/database/schema_planeacion.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';

Future<void>? _pageReady;

Future<void> _seedSignedContract(
  Database db, {
  required String entidadId,
  required String cdpId,
  required String numeroCdp,
}) async {
  await db.insert('procesos_contratacion', {
    'id': 'process-001',
    'entidad_id': entidadId,
    'numero_proceso': 'PROC-001',
    'objeto_contrato': 'Servicios de prueba',
    'modalidad': 'contratacionDirecta',
    'valor_estimado': 100000000,
    'tipo_contrato': 'prestacionServicios',
    'dependencia_solicitante': 'Presupuesto',
    'responsable_proceso': 'Funcionario de prueba',
    'fecha_inicio': DateTime(2026).toIso8601String(),
    'fecha_publicacion': DateTime(2026).toIso8601String(),
    'fecha_cierre': DateTime(2026).toIso8601String(),
    'estado': 'adjudicado',
    'cdp_id': cdpId,
    'numero_cdp': numeroCdp,
    'secop_id': null,
    'observaciones': null,
  });
  await db.insert('contratos', {
    'id': 'contract-001',
    'entidad_id': entidadId,
    'numero_contrato': 'CT-001-2026',
    'proceso_id': 'process-001',
    'numero_proceso': 'PROC-001',
    'objeto_contrato': 'Servicios de prueba',
    'tipo_contrato': 'prestacionServicios',
    'valor_contrato': 100000000,
    'contratista_id': 'supplier-001',
    'contratista_nombre': 'Proveedor de prueba',
    'contratista_identificacion': '900000001',
    'cdp_id': cdpId,
    'numero_cdp': numeroCdp,
    'rp_id': null,
    'numero_rp': null,
    'fecha_firma': DateTime(2026).toIso8601String(),
    'fecha_inicio_ejecucion': DateTime(2026).toIso8601String(),
    'fecha_fin_ejecucion': DateTime(2027).toIso8601String(),
    'duracion_dias': 365,
    'estado': 'firmado',
    'fecha_legalizacion': null,
    'fecha_terminacion': null,
    'fecha_liquidacion': null,
    'supervisor_id': null,
    'supervisor_nombre': null,
    'interventor_id': null,
    'interventor_nombre': null,
    'observaciones': null,
  });
}

Future<void> _pumpBudgetUi(WidgetTester tester) async {
  final ready = _pageReady;
  if (ready != null) {
    await tester.runAsync(() async {
      await ready;
    });
    _pageReady = null;
  }
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await tester.pump();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es_CO');
    // WidgetTester ya corre en un isolate; usar otro isolate para SQLite
    // deja las respuestas FFI esperando en RawReceivePort bajo fake async.
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Presupuesto Público Page Tests', () {
    late Database db;
    late PresupuestoService presupuestoService;
    late String testEntidadId;
    late String testUsuarioId;
    late String dbPath;

    setUp(() async {
      // Usar una base aislada y el esquema versionado real evita que el
      // singleton de la app compita con la inicializacion del widget.
      dbPath =
          '${Directory.systemTemp.path}/phase4_presupuesto_ui_${DateTime.now().microsecondsSinceEpoch}.db';
      db = await databaseFactory.openDatabase(dbPath);
      DatabaseHelper.setTestDatabase(db);
      await SchemaMultiTenant.crearTablas(db);
      await SchemaContratacion.crearTablas(db);
      // Usa primero el esquema versionado real. Los CREATE locales de abajo
      // quedan como compatibilidad histórica, pero no pueden ocultar columnas
      // obligatorias del contrato de producción.
      await SchemaPresupuesto.crearTablas(db);
      await SchemaPlaneacion.crearTablas(db);

      // Crear tablas necesarias para las pruebas
      await db.execute('''
        CREATE TABLE IF NOT EXISTS apropiaciones (
          id TEXT PRIMARY KEY,
          entidad_id TEXT NOT NULL,
          codigo_rubro TEXT NOT NULL,
          nombre_rubro TEXT NOT NULL,
          valor_inicial REAL NOT NULL,
          valor_apropiado REAL NOT NULL,
          valor_cdp REAL NOT NULL DEFAULT 0,
          valor_rp REAL NOT NULL DEFAULT 0,
          valor_obligado REAL NOT NULL DEFAULT 0,
          valor_pagado REAL NOT NULL DEFAULT 0,
          saldo_disponible REAL NOT NULL,
          fuente_financiacion TEXT NOT NULL,
          sector TEXT NOT NULL,
          programa TEXT NOT NULL,
          subprograma TEXT NOT NULL,
          proyecto TEXT NOT NULL,
          actividad TEXT NOT NULL,
          objeto_gasto TEXT NOT NULL,
          fecha_creacion TEXT NOT NULL,
          fecha_aprobacion_concejo TEXT,
          acto_administrativo TEXT,
          activo INTEGER NOT NULL DEFAULT 1
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS cdps (
          id TEXT PRIMARY KEY,
          entidad_id TEXT NOT NULL,
          numero_cdp TEXT NOT NULL,
          vigencia TEXT NOT NULL,
          apropiacion_id TEXT NOT NULL,
          codigo_rubro TEXT NOT NULL,
          valor_cdp REAL NOT NULL,
          valor_comprometido_rp REAL NOT NULL DEFAULT 0,
          saldo_disponible REAL NOT NULL,
          fecha_expedicion TEXT NOT NULL,
          fecha_vigencia TEXT NOT NULL,
          funcionario_expedidor TEXT NOT NULL,
          funcionario_solicitante TEXT NOT NULL,
          objeto_gasto TEXT NOT NULL,
          contrato_numero TEXT,
          estado TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS rps (
          id TEXT PRIMARY KEY,
          entidad_id TEXT NOT NULL,
          numero_rp TEXT NOT NULL,
          vigencia TEXT NOT NULL,
          cdp_id TEXT NOT NULL,
          numero_cdp TEXT NOT NULL,
          contrato_id TEXT,
          contrato_numero TEXT NOT NULL,
          codigo_rubro TEXT NOT NULL,
          valor_rp REAL NOT NULL,
          valor_obligado REAL NOT NULL DEFAULT 0,
          saldo_disponible REAL NOT NULL,
          fecha_expedicion TEXT NOT NULL,
          fecha_vigencia TEXT NOT NULL,
          funcionario_expedidor TEXT NOT NULL,
          funcionario_solicitante TEXT NOT NULL,
          objeto_gasto TEXT NOT NULL,
          estado TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS obligaciones (
          id TEXT PRIMARY KEY,
          entidad_id TEXT NOT NULL,
          numero_obligacion TEXT NOT NULL,
          vigencia TEXT NOT NULL,
          rp_id TEXT NOT NULL,
          numero_rp TEXT NOT NULL,
          contrato_id TEXT,
          contrato_numero TEXT,
          tercero_id TEXT,
          tercero_nombre TEXT NOT NULL,
          codigo_rubro TEXT NOT NULL,
          valor_obligacion REAL NOT NULL,
          valor_pagado REAL NOT NULL DEFAULT 0,
          saldo_pendiente REAL NOT NULL,
          fecha_reconocimiento TEXT NOT NULL,
          funcionario_reconocio TEXT NOT NULL,
          objeto_gasto TEXT NOT NULL,
          acta_recibo_numero TEXT,
          acta_recibo_fecha TEXT,
          factura_numero TEXT,
          factura_fecha TEXT,
          estado TEXT NOT NULL,
          observaciones TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS pagos (
          id TEXT PRIMARY KEY,
          entidad_id TEXT NOT NULL,
          numero_pago TEXT NOT NULL,
          vigencia TEXT NOT NULL,
          obligacion_id TEXT NOT NULL,
          numero_obligacion TEXT NOT NULL,
          rp_id TEXT NOT NULL,
          numero_rp TEXT NOT NULL,
          tercero_id TEXT,
          tercero_nombre TEXT NOT NULL,
          banco_destino TEXT NOT NULL,
          cuenta_destino TEXT NOT NULL,
          tipo_cuenta TEXT NOT NULL,
          valor_pago REAL NOT NULL,
          fecha_programacion TEXT NOT NULL,
          fecha_aprobacion TEXT,
          fecha_ejecucion TEXT,
          funcionario_aprobo TEXT NOT NULL,
          funcionario_programo TEXT NOT NULL,
          tipo_pago TEXT NOT NULL,
          estado TEXT NOT NULL,
          numero_cheque TEXT,
          numero_referencia TEXT,
          observaciones TEXT,
          rechazo_motivo TEXT
        )
      ''');

      presupuestoService = PresupuestoService(db: db, auditoriaService: null);

      testEntidadId = 'test-entidad-${DateTime.now().millisecondsSinceEpoch}';
      testUsuarioId = 'test-usuario-${DateTime.now().millisecondsSinceEpoch}';
      await db.insert('funcionarios_entidad', {
        'id': 'FUNC-$testUsuarioId',
        'entidad_id': testEntidadId,
        'usuario_id': testUsuarioId,
        'cargo_clave': 'rector',
        'nombre_completo': 'Rector de prueba',
        'identificacion': 'ID-$testUsuarioId',
        'telefono': '3000000000',
        'email': 'presupuesto@prueba.gov.co',
        'direccion': 'Direccion de prueba',
      });

      // Limpiar datos de prueba anteriores
      await db.delete(
        'apropiaciones',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'cdps',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'rps',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'obligaciones',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'pagos',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
    });

    tearDown(() async {
      // Limpiar datos de prueba
      await db.delete(
        'apropiaciones',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'cdps',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'rps',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'obligaciones',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await db.delete(
        'pagos',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );
      await DatabaseHelper.resetForTests();
      await File(dbPath).delete();
    });

    testWidgets('Crear apropiación y verificar en base de datos', (
      WidgetTester tester,
    ) async {
      // Build the page
      await tester.pumpWidget(
        MaterialApp(
          home: PresupuestoPublicoPage(
            entidadId: testEntidadId,
            usuarioId: testUsuarioId,
            onReady: (ready) => _pageReady = ready,
          ),
        ),
      );

      await _pumpBudgetUi(tester);

      // Verificar que estamos en la pestaña de apropiaciones
      expect(find.text('Apropiaciones Presupuestales'), findsOneWidget);

      // Tocar el botón de crear apropiación
      await tester.tap(find.text('Crear Apropiación'));
      await _pumpBudgetUi(tester);

      // Llenar el formulario
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Vigencia (año)'),
        '2026',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código Rubro'),
        '01-01-01-00-000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre Rubro'),
        'Gastos Generales',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor Apropiado'),
        '1000000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Fuente de Financiación'),
        'Recursos Propios',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Sector'),
        'Educación',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Programa'),
        'Educación Básica',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Subprograma'),
        'Primaria',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Proyecto'),
        'PROJ-001',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Actividad'),
        'ACT-001',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Objeto de Gasto'),
        'Servicios Públicos',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Acto Administrativo (Acuerdo/Ordenanza)',
        ),
        'ACU-001-2026',
      );

      // Tocar el botón de crear
      await tester.tap(find.text('Crear'));
      await _pumpBudgetUi(tester);

      // Verificar en base de datos que la apropiación se creó
      final apropiacionesResult = await db.query(
        'apropiaciones',
        where: 'entidad_id = ? AND codigo_rubro = ?',
        whereArgs: [testEntidadId, '01-01-01-00-000'],
      );

      expect(
        apropiacionesResult.length,
        1,
        reason: 'Debe haber una apropiación creada',
      );

      final apropiacionData = apropiacionesResult.first;
      expect(apropiacionData['codigo_rubro'], '01-01-01-00-000');
      expect(apropiacionData['nombre_rubro'], 'Gastos Generales');
      expect(apropiacionData['valor_apropiado'], 100000000);
      expect(apropiacionData['saldo_disponible'], 100000000);
      expect(apropiacionData['vigencia'], '2026');
      expect(apropiacionData['activo'], 1);
    });

    testWidgets('Bloqueo normativo: CDP excede saldo disponible', (
      WidgetTester tester,
    ) async {
      // Primero crear una apropiación
      await presupuestoService.crearApropiacion(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        vigencia: '2026',
        codigoRubro: '01-01-01-00-000',
        nombreRubro: 'Gastos Generales',
        valorApropiado: publicMoneyFromMajor('1000000'),
        fuenteFinanciacion: 'Recursos Propios',
        sector: 'Educación',
        programa: 'Educación Básica',
        subprograma: 'Primaria',
        proyecto: 'PROJ-001',
        actividad: 'ACT-001',
        objetoGasto: 'Servicios Públicos',
        fechaAprobacionConcejo: DateTime.now(),
        actoAdministrativo: 'ACU-001-2026',
      );

      // Build the page
      await tester.pumpWidget(
        MaterialApp(
          home: PresupuestoPublicoPage(
            entidadId: testEntidadId,
            usuarioId: testUsuarioId,
            onReady: (ready) => _pageReady = ready,
          ),
        ),
      );

      await _pumpBudgetUi(tester);

      // Ir a la pestaña de CDPs
      await tester.tap(find.text('CDPs'));
      await _pumpBudgetUi(tester);

      // Tocar el botón de expedir CDP
      await tester.tap(find.text('Expedir CDP'));
      await _pumpBudgetUi(tester);

      // Seleccionar la apropiación
      await tester.tap(find.byType(DropdownButtonFormField<Apropiacion>));
      await _pumpBudgetUi(tester);
      await tester.tap(find.textContaining('01-01-01-00-000'));
      await _pumpBudgetUi(tester);

      // Intentar expedir CDP con valor mayor al saldo disponible
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor CDP'),
        '2000000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Expedidor'),
        'Juan Pérez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Solicitante'),
        'María García',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Objeto de Gasto'),
        'Servicios',
      );

      // Tocar el botón de expedir
      await tester.tap(find.text('Expedir'));
      await _pumpBudgetUi(tester);

      // Verificar que aparece mensaje de error
      expect(find.text('Excede saldo disponible'), findsOneWidget);
    });

    testWidgets('Crear CDP válido y verificar en base de datos', (
      WidgetTester tester,
    ) async {
      // Primero crear una apropiación
      await presupuestoService.crearApropiacion(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        vigencia: '2026',
        codigoRubro: '01-01-01-00-000',
        nombreRubro: 'Gastos Generales',
        valorApropiado: publicMoneyFromMajor('1000000'),
        fuenteFinanciacion: 'Recursos Propios',
        sector: 'Educación',
        programa: 'Educación Básica',
        subprograma: 'Primaria',
        proyecto: 'PROJ-001',
        actividad: 'ACT-001',
        objetoGasto: 'Servicios Públicos',
        fechaAprobacionConcejo: DateTime.now(),
        actoAdministrativo: 'ACU-001-2026',
      );

      // Build the page
      await tester.pumpWidget(
        MaterialApp(
          home: PresupuestoPublicoPage(
            entidadId: testEntidadId,
            usuarioId: testUsuarioId,
            onReady: (ready) => _pageReady = ready,
          ),
        ),
      );

      await _pumpBudgetUi(tester);

      // Ir a la pestaña de CDPs
      await tester.tap(find.text('CDPs'));
      await _pumpBudgetUi(tester);

      // Tocar el botón de expedir CDP
      await tester.tap(find.text('Expedir CDP'));
      await _pumpBudgetUi(tester);

      // Seleccionar la apropiación
      await tester.tap(find.byType(DropdownButtonFormField<Apropiacion>));
      await _pumpBudgetUi(tester);
      await tester.tap(find.textContaining('01-01-01-00-000'));
      await _pumpBudgetUi(tester);

      // Llenar el formulario con valor válido
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor CDP'),
        '500000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Expedidor'),
        'Juan Pérez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Solicitante'),
        'María García',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Objeto de Gasto'),
        'Servicios',
      );

      // Tocar el botón de expedir
      await tester.tap(find.text('Expedir'));
      await _pumpBudgetUi(tester);

      // Verificar en base de datos que el CDP se creó
      final cdpsResult = await db.query(
        'cdps',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );

      expect(cdpsResult.length, 1, reason: 'Debe haber un CDP creado');

      final cdpData = cdpsResult.first;
      expect(cdpData['valor_cdp'], 50000000);
      expect(cdpData['saldo_disponible'], 50000000);
      expect(cdpData['estado'], 'vigente');

      // Verificar que la apropiación se actualizó
      final apropiacionesResult = await db.query(
        'apropiaciones',
        where: 'entidad_id = ? AND codigo_rubro = ?',
        whereArgs: [testEntidadId, '01-01-01-00-000'],
      );

      final apropiacionData = apropiacionesResult.first;
      expect(apropiacionData['valor_cdp'], 50000000);
      expect(apropiacionData['saldo_disponible'], 50000000);
    });

    testWidgets('Bloqueo normativo: RP sin contrato (Ley 80/1993 Art. 41)', (
      WidgetTester tester,
    ) async {
      // Crear apropiación y CDP
      final apropiacion = await presupuestoService.crearApropiacion(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        vigencia: '2026',
        codigoRubro: '01-01-01-00-000',
        nombreRubro: 'Gastos Generales',
        valorApropiado: publicMoneyFromMajor('1000000'),
        fuenteFinanciacion: 'Recursos Propios',
        sector: 'Educación',
        programa: 'Educación Básica',
        subprograma: 'Primaria',
        proyecto: 'PROJ-001',
        actividad: 'ACT-001',
        objetoGasto: 'Servicios Públicos',
        fechaAprobacionConcejo: DateTime.now(),
        actoAdministrativo: 'ACU-001-2026',
      );

      final cdp = await presupuestoService.expedirCDP(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        apropiacionId: apropiacion.id,
        valorCDP: publicMoneyFromMajor('500000'),
        funcionarioExpedidor: 'Juan Pérez',
        funcionarioSolicitante: 'María García',
        objetoGasto: 'Servicios',
        contratoNumero: null,
      );

      // Build the page
      await tester.pumpWidget(
        MaterialApp(
          home: PresupuestoPublicoPage(
            entidadId: testEntidadId,
            usuarioId: testUsuarioId,
            onReady: (ready) => _pageReady = ready,
          ),
        ),
      );

      await _pumpBudgetUi(tester);

      // Ir a la pestaña de RPs
      await tester.tap(find.text('RPs'));
      await _pumpBudgetUi(tester);

      // Tocar el botón de expedir RP
      await tester.tap(find.text('Expedir RP'));
      await _pumpBudgetUi(tester);

      // Seleccionar el CDP
      await tester.tap(find.byType(DropdownButtonFormField<CDP>));
      await _pumpBudgetUi(tester);
      await tester.tap(find.textContaining(cdp.numeroCDP));
      await _pumpBudgetUi(tester);

      // NO llenar el número de contrato (violación normativa)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor RP'),
        '300000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Expedidor'),
        'Juan Pérez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Solicitante'),
        'María García',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Objeto de Gasto'),
        'Servicios',
      );

      // Tocar el botón de expedir
      await tester.tap(find.text('Expedir'));
      await _pumpBudgetUi(tester);

      // Verificar que aparece mensaje de error normativo
      expect(find.text('Requerido (Ley 80/1993 Art. 41)'), findsOneWidget);
    });

    testWidgets('Crear RP válido con contrato y verificar en base de datos', (
      WidgetTester tester,
    ) async {
      // Crear apropiación y CDP
      final apropiacion = await presupuestoService.crearApropiacion(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        vigencia: '2026',
        codigoRubro: '01-01-01-00-000',
        nombreRubro: 'Gastos Generales',
        valorApropiado: publicMoneyFromMajor('1000000'),
        fuenteFinanciacion: 'Recursos Propios',
        sector: 'Educación',
        programa: 'Educación Básica',
        subprograma: 'Primaria',
        proyecto: 'PROJ-001',
        actividad: 'ACT-001',
        objetoGasto: 'Servicios Públicos',
        fechaAprobacionConcejo: DateTime.now(),
        actoAdministrativo: 'ACU-001-2026',
      );

      final cdp = await presupuestoService.expedirCDP(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        apropiacionId: apropiacion.id,
        valorCDP: publicMoneyFromMajor('500000'),
        funcionarioExpedidor: 'Juan Pérez',
        funcionarioSolicitante: 'María García',
        objetoGasto: 'Servicios',
        contratoNumero: null,
      );

      // Build the page
      await tester.pumpWidget(
        MaterialApp(
          home: PresupuestoPublicoPage(
            entidadId: testEntidadId,
            usuarioId: testUsuarioId,
            onReady: (ready) => _pageReady = ready,
          ),
        ),
      );

      await _pumpBudgetUi(tester);

      // Ir a la pestaña de RPs
      await tester.tap(find.text('RPs'));
      await _pumpBudgetUi(tester);

      // Tocar el botón de expedir RP
      await tester.tap(find.text('Expedir RP'));
      await _pumpBudgetUi(tester);

      // Seleccionar el CDP
      await tester.tap(find.byType(DropdownButtonFormField<CDP>));
      await _pumpBudgetUi(tester);
      await tester.tap(find.textContaining(cdp.numeroCDP));
      await _pumpBudgetUi(tester);

      await _seedSignedContract(
        db,
        entidadId: testEntidadId,
        cdpId: cdp.id,
        numeroCdp: cdp.numeroCDP,
      );

      // Llenar el formulario con contrato (cumple normativa)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número Contrato *'),
        'CT-001-2026',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'ID Contrato'),
        'contract-001',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor RP'),
        '300000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Expedidor'),
        'Juan Pérez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Solicitante'),
        'María García',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Objeto de Gasto'),
        'Servicios',
      );

      // Tocar el botón de expedir
      await tester.tap(find.text('Expedir'));
      await _pumpBudgetUi(tester);

      // Verificar en base de datos que el RP se creó
      final rpsResult = await db.query(
        'rps',
        where: 'entidad_id = ?',
        whereArgs: [testEntidadId],
      );

      expect(rpsResult.length, 1, reason: 'Debe haber un RP creado');

      final rpData = rpsResult.first;
      expect(rpData['valor_rp'], 30000000);
      expect(rpData['saldo_disponible'], 30000000);
      expect(rpData['contrato_numero'], 'CT-001-2026');
      expect(rpData['estado'], 'vigente');
    });

    testWidgets('Bloqueo normativo: Obligación sin acta de recibo ni factura', (
      WidgetTester tester,
    ) async {
      // Crear apropiación, CDP y RP
      final apropiacion = await presupuestoService.crearApropiacion(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        vigencia: '2026',
        codigoRubro: '01-01-01-00-000',
        nombreRubro: 'Gastos Generales',
        valorApropiado: publicMoneyFromMajor('1000000'),
        fuenteFinanciacion: 'Recursos Propios',
        sector: 'Educación',
        programa: 'Educación Básica',
        subprograma: 'Primaria',
        proyecto: 'PROJ-001',
        actividad: 'ACT-001',
        objetoGasto: 'Servicios Públicos',
        fechaAprobacionConcejo: DateTime.now(),
        actoAdministrativo: 'ACU-001-2026',
      );

      final cdp = await presupuestoService.expedirCDP(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        apropiacionId: apropiacion.id,
        valorCDP: publicMoneyFromMajor('500000'),
        funcionarioExpedidor: 'Juan Pérez',
        funcionarioSolicitante: 'María García',
        objetoGasto: 'Servicios',
        contratoNumero: null,
      );

      await _seedSignedContract(
        db,
        entidadId: testEntidadId,
        cdpId: cdp.id,
        numeroCdp: cdp.numeroCDP,
      );
      final rp = await presupuestoService.expedirRP(
        entidadId: testEntidadId,
        usuarioId: testUsuarioId,
        cdpId: cdp.id,
        contratoId: 'contract-001',
        contratoNumero: 'CT-001-2026',
        valorRP: publicMoneyFromMajor('300000'),
        funcionarioExpedidor: 'Juan Pérez',
        funcionarioSolicitante: 'María García',
        objetoGasto: 'Servicios',
      );

      // Build the page
      await tester.pumpWidget(
        MaterialApp(
          home: PresupuestoPublicoPage(
            entidadId: testEntidadId,
            usuarioId: testUsuarioId,
            onReady: (ready) => _pageReady = ready,
          ),
        ),
      );

      await _pumpBudgetUi(tester);

      // Ir a la pestaña de obligaciones
      await tester.tap(find.text('Obligaciones'));
      await _pumpBudgetUi(tester);

      // Tocar el botón de registrar obligación
      await tester.tap(find.text('Registrar Obligación'));
      await _pumpBudgetUi(tester);

      // Seleccionar el RP
      await tester.tap(find.byType(DropdownButtonFormField<RP>));
      await _pumpBudgetUi(tester);
      await tester.tap(find.textContaining(rp.numeroRP));
      await _pumpBudgetUi(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Número Contrato'),
        'CT-001-2026',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'ID Contrato'),
        'contract-001',
      );

      // Llenar el formulario SIN acta de recibo ni factura (violación normativa)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre Tercero'),
        'Empresa XYZ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Valor Obligación'),
        '200000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Funcionario Reconoció'),
        'Juan Pérez',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Objeto de Gasto'),
        'Servicios',
      );

      // Tocar el botón de registrar
      await tester.tap(find.text('Registrar'));
      await _pumpBudgetUi(tester);

      // Verificar que aparece mensaje de error normativo
      expect(find.textContaining('acta de recibo'), findsOneWidget);
    });

    testWidgets(
      'Crear obligación válida con acta de recibo y verificar en base de datos',
      (WidgetTester tester) async {
        // Crear apropiación, CDP y RP
        final apropiacion = await presupuestoService.crearApropiacion(
          entidadId: testEntidadId,
          usuarioId: testUsuarioId,
          vigencia: '2026',
          codigoRubro: '01-01-01-00-000',
          nombreRubro: 'Gastos Generales',
          valorApropiado: publicMoneyFromMajor('1000000'),
          fuenteFinanciacion: 'Recursos Propios',
          sector: 'Educación',
          programa: 'Educación Básica',
          subprograma: 'Primaria',
          proyecto: 'PROJ-001',
          actividad: 'ACT-001',
          objetoGasto: 'Servicios Públicos',
          fechaAprobacionConcejo: DateTime.now(),
          actoAdministrativo: 'ACU-001-2026',
        );

        final cdp = await presupuestoService.expedirCDP(
          entidadId: testEntidadId,
          usuarioId: testUsuarioId,
          apropiacionId: apropiacion.id,
          valorCDP: publicMoneyFromMajor('500000'),
          funcionarioExpedidor: 'Juan Pérez',
          funcionarioSolicitante: 'María García',
          objetoGasto: 'Servicios',
          contratoNumero: null,
        );

        await _seedSignedContract(
          db,
          entidadId: testEntidadId,
          cdpId: cdp.id,
          numeroCdp: cdp.numeroCDP,
        );
        final rp = await presupuestoService.expedirRP(
          entidadId: testEntidadId,
          usuarioId: testUsuarioId,
          cdpId: cdp.id,
          contratoId: 'contract-001',
          contratoNumero: 'CT-001-2026',
          valorRP: publicMoneyFromMajor('300000'),
          funcionarioExpedidor: 'Juan Pérez',
          funcionarioSolicitante: 'María García',
          objetoGasto: 'Servicios',
        );

        // Build the page
        await tester.pumpWidget(
          MaterialApp(
            home: PresupuestoPublicoPage(
              entidadId: testEntidadId,
              usuarioId: testUsuarioId,
              onReady: (ready) => _pageReady = ready,
            ),
          ),
        );

        await _pumpBudgetUi(tester);

        // Ir a la pestaña de obligaciones
        await tester.tap(find.text('Obligaciones'));
        await _pumpBudgetUi(tester);

        // Tocar el botón de registrar obligación
        await tester.tap(find.text('Registrar Obligación'));
        await _pumpBudgetUi(tester);

        // Seleccionar el RP
        await tester.tap(find.byType(DropdownButtonFormField<RP>));
        await _pumpBudgetUi(tester);
        await tester.tap(find.textContaining(rp.numeroRP));
        await _pumpBudgetUi(tester);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Número Contrato'),
          'CT-001-2026',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'ID Contrato'),
          'contract-001',
        );

        // Llenar el formulario con acta de recibo (cumple normativa)
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nombre Tercero'),
          'Empresa XYZ',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Valor Obligación'),
          '200000',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Funcionario Reconoció'),
          'Juan Pérez',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Objeto de Gasto'),
          'Servicios',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Número Acta Recibo'),
          'ACTA-001',
        );

        // Tocar el botón de registrar
        await tester.tap(find.text('Registrar'));
        await _pumpBudgetUi(tester);

        // Verificar en base de datos que la obligación se creó
        final obligacionesResult = await db.query(
          'obligaciones',
          where: 'entidad_id = ?',
          whereArgs: [testEntidadId],
        );

        expect(
          obligacionesResult.length,
          1,
          reason: 'Debe haber una obligación creada',
        );

        final obligacionData = obligacionesResult.first;
        expect(obligacionData['valor_obligacion'], 20000000);
        expect(obligacionData['saldo_pendiente'], 20000000);
        expect(obligacionData['tercero_nombre'], 'Empresa XYZ');
        expect(obligacionData['acta_recibo_numero'], 'ACTA-001');
        expect(obligacionData['estado'], 'pendiente');
      },
    );
  });
}
