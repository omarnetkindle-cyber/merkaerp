import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaContabilidad.crearTablas(db);
    await db.execute('''
      CREATE TABLE asientos_contables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        fecha TEXT NOT NULL,
        concepto TEXT NOT NULL,
        referencia TEXT,
        origen TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'registrado'
      )
    ''');
    await db.execute('''
      CREATE TABLE asiento_lineas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        asiento_id INTEGER NOT NULL,
        cuenta_id INTEGER NOT NULL,
        descripcion TEXT,
        debito INTEGER NOT NULL DEFAULT 0,
        credito INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (asiento_id) REFERENCES asientos_contables(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE accounting_journal_entries (
        id TEXT PRIMARY KEY,
        status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE accounting_journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id TEXT NOT NULL,
        debit INTEGER NOT NULL DEFAULT 0,
        credit INTEGER NOT NULL DEFAULT 0,
        local_debit INTEGER NOT NULL DEFAULT 0,
        local_credit INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await SchemaContabilidad.crearTriggersPartidaDoble(db);
  });

  tearDown(() => db.close());

  test(
    'SQLite acepta un asiento publico balanceado y rechaza una linea directa extra',
    () async {
      await db.insert('asientos_contables_sp', {
        'id': 'SP-BAL',
        'entidad_id': 'ENT-1',
        'numero_asiento': 'SP-1',
        'fecha_asiento': '2026-08-08',
        'descripcion': 'Asiento SQL balanceado',
        'tipo_asiento': 'manual',
        'estado': 'borrador',
        'total_debito': 100,
        'total_credito': 100,
        'usuario_creo': 'USR-1',
      });
      await db.insert('detalles_asientos', {
        'id': 'SP-D1',
        'asiento_id': 'SP-BAL',
        'cuenta_codigo': '1105',
        'cuenta_nombre': 'Caja',
        'debito': 100,
        'credito': 0,
      });
      await db.insert('detalles_asientos', {
        'id': 'SP-D2',
        'asiento_id': 'SP-BAL',
        'cuenta_codigo': '4135',
        'cuenta_nombre': 'Ingresos',
        'debito': 0,
        'credito': 100,
      });

      await db.update(
        'asientos_contables_sp',
        {'estado': 'registrado'},
        where: 'id = ?',
        whereArgs: ['SP-BAL'],
      );
      expect(
        (await db.query(
          'asientos_contables_sp',
          where: 'id = ?',
          whereArgs: ['SP-BAL'],
        )).single['estado'],
        'registrado',
      );

      expect(
        () => db.insert('detalles_asientos', {
          'id': 'SP-D3',
          'asiento_id': 'SP-BAL',
          'cuenta_codigo': '5135',
          'cuenta_nombre': 'Gasto',
          'debito': 1,
          'credito': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'SQLite rechaza al cerrar un asiento publico desbalanceado por SQL directo',
    () async {
      await db.insert('asientos_contables_sp', {
        'id': 'SP-UNBAL',
        'entidad_id': 'ENT-1',
        'numero_asiento': 'SP-2',
        'fecha_asiento': '2026-08-08',
        'descripcion': 'Asiento SQL desbalanceado',
        'tipo_asiento': 'manual',
        'estado': 'borrador',
        'total_debito': 100,
        'total_credito': 100,
        'usuario_creo': 'USR-1',
      });
      await db.insert('detalles_asientos', {
        'id': 'SP-U1',
        'asiento_id': 'SP-UNBAL',
        'cuenta_codigo': '1105',
        'cuenta_nombre': 'Caja',
        'debito': 100,
        'credito': 0,
      });

      expect(
        () => db.update(
          'asientos_contables_sp',
          {'estado': 'registrado'},
          where: 'id = ?',
          whereArgs: ['SP-UNBAL'],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query(
          'asientos_contables_sp',
          where: 'id = ?',
          whereArgs: ['SP-UNBAL'],
        )).single['estado'],
        'borrador',
      );
    },
  );

  test(
    'La ruta comercial normal registra el asiento balanceado con la proteccion activa',
    () async {
      final fullPath =
          '${Directory.systemTemp.path}/phase4_partida_${DateTime.now().microsecondsSinceEpoch}.db';
      final fullDb = await databaseFactory.openDatabase(fullPath);
      await DatabaseHelper.instance.crearDBForTesting(fullDb, 76);
      DatabaseHelper.setTestDatabase(fullDb);
      addTearDown(() async {
        await DatabaseHelper.resetForTests();
        await File(fullPath).delete();
      });

      final cuentas = await fullDb.query('cuentas_contables', limit: 2);
      expect(cuentas.length, 2);
      final asientoId = await DatabaseHelper.instance.registrarAsientoContable(
        concepto: 'Prueba de flujo comercial',
        lineas: [
          {'cuenta_id': cuentas[0]['id'], 'debito': 100, 'credito': 0},
          {'cuenta_id': cuentas[1]['id'], 'debito': 0, 'credito': 100},
        ],
      );

      final asiento = (await fullDb.query(
        'asientos_contables',
        where: 'id = ?',
        whereArgs: [asientoId],
      )).single;
      expect(asiento['estado'], 'registrado');
      final totales = await fullDb.rawQuery(
        '''
      SELECT SUM(debito) AS debito, SUM(credito) AS credito
      FROM asiento_lineas WHERE asiento_id = ?
    ''',
        [asientoId],
      );
      expect(totales.single['debito'], totales.single['credito']);
    },
  );

  test(
    'La ruta accounting journal cierra el borrador solo despues de validar el balance',
    () async {
      await db.insert('accounting_journal_entries', {
        'id': 'J-1',
        'status': 'draft',
      });
      await db.insert('accounting_journal_lines', {
        'entry_id': 'J-1',
        'local_debit': 100,
        'local_credit': 0,
      });
      await db.insert('accounting_journal_lines', {
        'entry_id': 'J-1',
        'local_debit': 0,
        'local_credit': 100,
      });
      await db.update(
        'accounting_journal_entries',
        {'status': 'posted'},
        where: 'id = ?',
        whereArgs: ['J-1'],
      );
      expect(
        (await db.query(
          'accounting_journal_entries',
          where: 'id = ?',
          whereArgs: ['J-1'],
        )).single['status'],
        'posted',
      );
    },
  );

  test(
    'La migracion v76 conserva asientos existentes y activa la validacion SQL',
    () async {
      final legacyPath =
          '${Directory.systemTemp.path}/phase4_legacy_${DateTime.now().microsecondsSinceEpoch}.db';
      final legacyDb = await databaseFactory.openDatabase(legacyPath);
      addTearDown(() async {
        await legacyDb.close();
        await File(legacyPath).delete();
      });
      await legacyDb.execute('''
        CREATE TABLE asientos_contables_sp (
          id TEXT PRIMARY KEY,
          entidad_id TEXT NOT NULL,
          numero_asiento TEXT NOT NULL,
          fecha_asiento TEXT NOT NULL,
          descripcion TEXT NOT NULL,
          tipo_asiento TEXT NOT NULL,
          estado TEXT NOT NULL,
          total_debito INTEGER NOT NULL,
          total_credito INTEGER NOT NULL,
          usuario_creo TEXT NOT NULL
        )
      ''');
      await legacyDb.execute('''
        CREATE TABLE detalles_asientos (
          id TEXT PRIMARY KEY,
          asiento_id TEXT NOT NULL,
          cuenta_codigo TEXT NOT NULL,
          cuenta_nombre TEXT NOT NULL,
          debito INTEGER NOT NULL,
          credito INTEGER NOT NULL
        )
      ''');
      await legacyDb.insert('asientos_contables_sp', {
        'id': 'LEGACY-1',
        'entidad_id': 'ENT-1',
        'numero_asiento': 'LEG-1',
        'fecha_asiento': '2026-08-08',
        'descripcion': 'Asiento existente balanceado',
        'tipo_asiento': 'manual',
        'estado': 'registrado',
        'total_debito': 50,
        'total_credito': 50,
        'usuario_creo': 'USR-1',
      });
      await legacyDb.insert('detalles_asientos', {
        'id': 'LEGACY-D1',
        'asiento_id': 'LEGACY-1',
        'cuenta_codigo': '1105',
        'cuenta_nombre': 'Caja',
        'debito': 50,
        'credito': 0,
      });
      await legacyDb.insert('detalles_asientos', {
        'id': 'LEGACY-D2',
        'asiento_id': 'LEGACY-1',
        'cuenta_codigo': '2401',
        'cuenta_nombre': 'Cuentas por pagar',
        'debito': 0,
        'credito': 50,
      });

      await DatabaseHelper.instance.migrarDBForTesting(legacyDb, 75, 76);

      expect(await legacyDb.query('asientos_contables_sp'), hasLength(1));
      expect(await legacyDb.query('detalles_asientos'), hasLength(2));
      expect(
        () => legacyDb.insert('detalles_asientos', {
          'id': 'LEGACY-D3',
          'asiento_id': 'LEGACY-1',
          'cuenta_codigo': '5135',
          'cuenta_nombre': 'Gasto',
          'debito': 1,
          'credito': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}
