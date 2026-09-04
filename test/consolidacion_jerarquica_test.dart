import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/consolidacion_jerarquica_service.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ConsolidacionJerarquicaService consolidationService;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Crear tablas del esquema multi-tenant y contable
    await db.execute('''
      CREATE TABLE entidades_territoriales (
        id TEXT PRIMARY KEY,
        nit TEXT NOT NULL UNIQUE,
        razon_social TEXT NOT NULL,
        tipo_entidad TEXT NOT NULL,
        gobernacion_id TEXT,
        activo INTEGER NOT NULL DEFAULT 1,
        plan_cuentas_cgc TEXT NOT NULL,
        configuracion_normativa TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE saldos_cuentas (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        cuenta_codigo TEXT NOT NULL,
        cuenta_nombre TEXT NOT NULL,
        saldo_deudor INTEGER NOT NULL DEFAULT 0,
        saldo_acreedor INTEGER NOT NULL DEFAULT 0,
        saldo_neto INTEGER NOT NULL DEFAULT 0,
        fecha_ultimo_movimiento TEXT NOT NULL,
        vigencia TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE asientos_contables_sp (
        id TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE detalles_asientos (
        id TEXT PRIMARY KEY,
        cuenta_codigo TEXT NOT NULL
      )
    ''');
    await SchemaContabilidad.crearTablasConciliacionesReciprocas(db);

    await db.execute('''
      CREATE TABLE apropiaciones (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        valor_apropiado INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cdps (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        valor_cdp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE rps (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        valor_rp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pagos (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        valor_pagado INTEGER NOT NULL
      )
    ''');

    consolidationService = ConsolidacionJerarquicaService(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('1. Agregación contable correcta de Entidad Padre + 2 Hijas', () async {
    // Insertar Entidad Padre (Gobernación)
    await db.insert('entidades_territoriales', {
      'id': 'GOB-01',
      'nit': '800111222-1',
      'razon_social': 'Gobernación del Valle',
      'tipo_entidad': 'gobernacion',
      'gobernacion_id': null,
      'activo': 1,
      'plan_cuentas_cgc': 'CGN_2015',
      'configuracion_normativa': '{}',
    });

    // Insertar 2 Entidades Hijas (Municipios adscritos)
    await db.insert('entidades_territoriales', {
      'id': 'MUN-01',
      'nit': '890300111-2',
      'razon_social': 'Alcaldía de Jamundí',
      'tipo_entidad': 'municipio',
      'gobernacion_id': 'GOB-01',
      'activo': 1,
      'plan_cuentas_cgc': 'CGN_2015',
      'configuracion_normativa': '{}',
    });

    await db.insert('entidades_territoriales', {
      'id': 'MUN-02',
      'nit': '890300222-3',
      'razon_social': 'Alcaldía de Yumbo',
      'tipo_entidad': 'municipio',
      'gobernacion_id': 'GOB-01',
      'activo': 1,
      'plan_cuentas_cgc': 'CGN_2015',
      'configuracion_normativa': '{}',
    });

    // Insertar saldos contables (Clase 1 Activos: $100k Padre, $50k Hija1, $30k Hija2 = $180k)
    final now = DateTime.now().toIso8601String();
    await db.insert('saldos_cuentas', {
      'id': 's1',
      'entidad_id': 'GOB-01',
      'cuenta_codigo': '111005',
      'cuenta_nombre': 'Bancos',
      'saldo_deudor': 10000000,
      'saldo_acreedor': 0,
      'saldo_neto': 10000000,
      'fecha_ultimo_movimiento': now,
      'vigencia': '2026',
    });

    await db.insert('saldos_cuentas', {
      'id': 's2',
      'entidad_id': 'MUN-01',
      'cuenta_codigo': '111005',
      'cuenta_nombre': 'Bancos',
      'saldo_deudor': 5000000,
      'saldo_acreedor': 0,
      'saldo_neto': 5000000,
      'fecha_ultimo_movimiento': now,
      'vigencia': '2026',
    });

    await db.insert('saldos_cuentas', {
      'id': 's3',
      'entidad_id': 'MUN-02',
      'cuenta_codigo': '111005',
      'cuenta_nombre': 'Bancos',
      'saldo_deudor': 3000000,
      'saldo_acreedor': 0,
      'saldo_neto': 3000000,
      'fecha_ultimo_movimiento': now,
      'vigencia': '2026',
    });

    final res = await consolidationService.obtenerConsolidadoContable(
      entidadIdPadre: 'GOB-01',
      vigencia: '2026',
    );

    expect(res['total_entidades_consolidadas'], equals(3));
    expect(res['resumen']['activos'], equals(publicMoneyFromMajor('180000')));
  });

  test(
    '2. Fail-Closed se dispara si la entidad no existe o no tiene hijas',
    () async {
      // Probar con ID inexistente
      expect(
        () => consolidationService.obtenerConsolidadoContable(
          entidadIdPadre: 'INEXISTENTE',
          vigencia: '2026',
        ),
        throwsA(isA<StateError>()),
      );

      // Insertar Entidad sin hijas
      await db.insert('entidades_territoriales', {
        'id': 'MUN-SOLO',
        'nit': '900000000-1',
        'razon_social': 'Municipio Aislado',
        'tipo_entidad': 'municipio',
        'gobernacion_id': null,
        'activo': 1,
        'plan_cuentas_cgc': 'CGN_2015',
        'configuracion_normativa': '{}',
      });

      // Probar con entidad sin hijas (debe fallar de forma segura)
      expect(
        () => consolidationService.obtenerConsolidadoContable(
          entidadIdPadre: 'MUN-SOLO',
          vigencia: '2026',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
