import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/money_schema_manifest.g.dart';
import 'package:merka_erp/core/currency/money_schema_migration.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.instance.crearDBForTesting(db, 74);
    for (final id in [1, 2]) {
      await db.insert('companies', {
        'id': id,
        'name': 'Company $id',
        'currency': 'COP',
        'created_at': '2026-08-02T00:00:00.000',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });

  tearDown(() async {
    await db.close();
    await DatabaseHelper.resetForTests();
  });

  test('migra las 355 columnas y conserva filas y valores COP', () async {
    await db.insert('movimientos_caja', {
      'company_id': 1,
      'tipo': 'ingreso',
      'concepto': 'precision',
      'monto': 99.99,
      'fecha': '2026-08-02',
      'origen': 'test',
    });
    await db.insert('entidades_territoriales', {
      'id': 'ENT-TEST',
      'nit': '900000001',
      'razon_social': 'Entidad de prueba',
      'tipo_entidad': 'municipio',
      'fecha_creacion': '2026-08-02T00:00:00.000',
      'plan_cuentas_cgc': 'CGC',
      'configuracion_normativa': '{}',
    });
    await db.insert('pac', {
      'id': 'pac-money-test',
      'entidad_id': 'ENT-TEST',
      'vigencia': '2026',
      'mes': 8,
      'codigo_rubro': '2.1.1',
      'valor_programado': 1000000,
      'valor_ejecutado': 9999,
      'saldo_disponible': 990001,
      'estado': 'activo',
      'fecha_creacion': '2026-08-02T00:00:00.000',
    });

    final countsBefore = await _rowCounts(db);
    final result = await db.transaction(MoneySchemaMigration.migrateV75);
    final countsAfter = await _rowCounts(db);

    expect(result.tables, hasLength(125));
    expect(result.columnCount, moneySchemaColumnCount);
    expect(countsAfter, countsBefore);
    await _expectAllMoneyColumnsAreInteger(db);

    final cash = await db.query(
      'movimientos_caja',
      where: 'concepto = ?',
      whereArgs: ['precision'],
    );
    expect(cash.single['monto'], 9999);

    final pac = await db.query(
      'pac',
      where: 'id = ?',
      whereArgs: ['pac-money-test'],
    );
    expect(pac.single['valor_programado'], 1000000);
    expect(pac.single['valor_ejecutado'], 9999);
    expect(pac.single['saldo_disponible'], 990001);
  });

  test('respeta la escala configurada de una moneda comercial', () async {
    await db.update(
      'app_currencies',
      {'decimal_places': 0},
      where: 'code = ?',
      whereArgs: ['JPY'],
    );
    await db.update(
      'companies',
      {'currency': 'JPY'},
      where: 'id = ?',
      whereArgs: [1],
    );
    await db.update(
      'companies',
      {'currency': 'JPY'},
      where: 'id = ?',
      whereArgs: [2],
    );
    await db.update(
      'empresa_config',
      {'moneda': 'JPY'},
      where: 'id = ?',
      whereArgs: [1],
    );
    await db.insert('movimientos_caja', {
      'company_id': 1,
      'tipo': 'ingreso',
      'concepto': 'yen',
      'monto': 99.6,
      'fecha': '2026-08-02',
      'origen': 'test',
    });

    await db.transaction(MoneySchemaMigration.migrateV75);

    final row = await db.query(
      'movimientos_caja',
      where: 'concepto = ?',
      whereArgs: ['yen'],
    );
    expect(row.single['monto'], 100);
  });

  test('es idempotente y no vuelve a escalar una base v75', () async {
    await db.insert('movimientos_caja', {
      'company_id': 1,
      'tipo': 'ingreso',
      'concepto': 'idempotencia',
      'monto': 12.34,
      'fecha': '2026-08-02',
      'origen': 'test',
    });

    await db.transaction(MoneySchemaMigration.migrateV75);
    final second = await db.transaction(MoneySchemaMigration.migrateV75);

    expect(second.tables.every((table) => table.alreadyMigrated), isTrue);
    final row = await db.query(
      'movimientos_caja',
      where: 'concepto = ?',
      whereArgs: ['idempotencia'],
    );
    expect(row.single['monto'], 1234);
  });

  test('una instalacion nueva v75 termina con esquema INTEGER', () async {
    await db.close();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    await DatabaseHelper.instance.crearDBForTesting(db, 75);

    await _expectAllMoneyColumnsAreInteger(db);
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    expect(integrity.single.values.single, 'ok');
  });
}

Future<Map<String, int>> _rowCounts(Database db) async {
  final result = <String, int>{};
  for (final table in moneySchemaColumns.keys) {
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM "$table"');
    result[table] = (rows.single['count']! as num).toInt();
  }
  return result;
}

Future<void> _expectAllMoneyColumnsAreInteger(Database db) async {
  var count = 0;
  for (final entry in moneySchemaColumns.entries) {
    final info = await db.rawQuery('PRAGMA table_info("${entry.key}")');
    final types = <String, String>{
      for (final column in info)
        column['name']! as String: column['type'].toString().toUpperCase(),
    };
    for (final column in entry.value) {
      expect(types[column], 'INTEGER', reason: '${entry.key}.$column');
      count++;
    }
  }
  expect(count, moneySchemaColumnCount);
}
