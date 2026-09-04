import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/accounting/accounting_period_schema_migration.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late DatabaseHelper helper;
  late int companyId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_close_block4_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    helper = DatabaseHelper.instance;
    db = await helper.database;
    companyId = await helper.obtenerEmpresaActivaId();
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('v89 separa periodos por empresa y migra el esquema legacy', () async {
    await helper.abrirPeriodoContable(anio: 2026, mes: 1);
    await db.insert('companies', {
      'name': 'Empresa secundaria bloque4',
      'created_at': DateTime.now().toIso8601String(),
    });
    final secondCompany =
        (await db.query(
              'companies',
              where: 'name = ?',
              whereArgs: ['Empresa secundaria bloque4'],
            )).single['id']
            as int;

    await db.insert('periodos_contables', {
      'company_id': secondCompany,
      'anio': 2026,
      'mes': 1,
      'estado': 'abierto',
      'fecha_apertura': DateTime.now().toIso8601String(),
    });
    final rows = await db.query(
      'periodos_contables',
      where: 'anio = ? AND mes = ?',
      whereArgs: [2026, 1],
    );
    expect(rows, hasLength(2));
    expect(await helper.obtenerPeriodosContables(), hasLength(1));

    final legacy = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await legacy.execute('''
      CREATE TABLE app_config(clave TEXT PRIMARY KEY, valor TEXT)
    ''');
    await legacy.execute('''
      CREATE TABLE companies(id INTEGER PRIMARY KEY, name TEXT, created_at TEXT)
    ''');
    await legacy.execute('''
      CREATE TABLE cuentas_contables(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        codigo TEXT NOT NULL UNIQUE,
        nombre TEXT NOT NULL,
        tipo TEXT NOT NULL,
        naturaleza TEXT NOT NULL,
        activa INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await legacy.execute('''
      CREATE TABLE periodos_contables(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        anio INTEGER NOT NULL,
        mes INTEGER NOT NULL,
        estado TEXT NOT NULL,
        fecha_apertura TEXT NOT NULL,
        fecha_cierre TEXT,
        observacion TEXT,
        UNIQUE(anio, mes)
      )
    ''');
    await legacy.insert('companies', {
      'id': 7,
      'name': 'Legacy',
      'created_at': DateTime.now().toIso8601String(),
    });
    await legacy.insert('app_config', {
      'clave': 'company_active_id',
      'valor': '7',
    });
    await legacy.insert('periodos_contables', {
      'anio': 2025,
      'mes': 12,
      'estado': 'cerrado',
      'fecha_apertura': '2025-12-01T00:00:00.000',
    });
    await AccountingPeriodSchemaMigration.migrateV89(legacy);
    final columns = await legacy.rawQuery(
      'PRAGMA table_info(periodos_contables)',
    );
    expect(columns.any((row) => row['name'] == 'company_id'), isTrue);
    final migrated = await legacy.query('periodos_contables');
    expect(migrated.single['company_id'], 7);
    await legacy.close();
  });

  test('cierre anual transfiere resultado a utilidades acumuladas', () async {
    final income =
        (await db.query(
              'cuentas_contables',
              where: 'codigo = ?',
              whereArgs: ['4135'],
              limit: 1,
            )).single['id']
            as int;
    final expense =
        (await db.query(
              'cuentas_contables',
              where: 'codigo = ?',
              whereArgs: ['5135'],
              limit: 1,
            )).single['id']
            as int;
    final cash =
        (await db.query(
              'cuentas_contables',
              where: 'codigo = ?',
              whereArgs: ['1105'],
              limit: 1,
            )).single['id']
            as int;
    final payable =
        (await db.query(
              'cuentas_contables',
              where: 'codigo = ?',
              whereArgs: ['2205'],
              limit: 1,
            )).single['id']
            as int;

    await helper.registrarAsientoContable(
      concepto: 'Ingreso base cierre bloque4',
      referencia: 'B4-INGRESO',
      fecha: DateTime(2026, 6, 10),
      lineas: [
        {'cuenta_id': cash, 'debito': 100000, 'credito': 0},
        {'cuenta_id': income, 'debito': 0, 'credito': 100000},
      ],
    );
    await helper.registrarAsientoContable(
      concepto: 'Gasto base cierre bloque4',
      referencia: 'B4-GASTO',
      fecha: DateTime(2026, 6, 11),
      lineas: [
        {'cuenta_id': expense, 'debito': 30000, 'credito': 0},
        {'cuenta_id': payable, 'debito': 0, 'credito': 30000},
      ],
    );

    final result = await helper.cerrarEjercicioContable(anio: 2026);
    expect(result['tipo_resultado'], 'utilidad');
    expect(result['resultado_minor_units'], 70000);

    final closure = await db.query(
      'asientos_contables',
      where: 'company_id = ? AND referencia LIKE ?',
      whereArgs: [companyId, 'CIERRE_EJERCICIO:2026:%'],
    );
    expect(closure, hasLength(2));

    final retained = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(l.debito), 0) AS debito,
             COALESCE(SUM(l.credito), 0) AS credito
      FROM asiento_lineas l
      INNER JOIN cuentas_contables c ON c.id = l.cuenta_id
      WHERE l.company_id = ? AND c.codigo = '3705'
    ''',
      [companyId],
    );
    expect(retained.single['debito'], 0);
    expect(retained.single['credito'], 70000);

    final resultAccount = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(l.debito), 0) AS debito,
             COALESCE(SUM(l.credito), 0) AS credito
      FROM asiento_lineas l
      INNER JOIN cuentas_contables c ON c.id = l.cuenta_id
      WHERE l.company_id = ? AND c.codigo = '3605'
    ''',
      [companyId],
    );
    expect(resultAccount.single['debito'], resultAccount.single['credito']);
  });
}
