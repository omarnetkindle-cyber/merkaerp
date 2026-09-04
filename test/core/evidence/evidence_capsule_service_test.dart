import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/evidence/evidence_capsule_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  final fixedNow = DateTime.utc(2026, 8, 9, 15, 30);

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE asientos_contables (
        id INTEGER PRIMARY KEY,
        company_id INTEGER,
        fecha TEXT NOT NULL,
        concepto TEXT NOT NULL,
        estado TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE asiento_lineas (
        id INTEGER PRIMARY KEY,
        asiento_id INTEGER NOT NULL,
        cuenta_id INTEGER NOT NULL,
        debito INTEGER NOT NULL,
        credito INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE nomina_liquidaciones (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        empleado_id INTEGER NOT NULL,
        periodo TEXT NOT NULL,
        total_devengado INTEGER NOT NULL,
        neto_pagar INTEGER NOT NULL,
        estado TEXT NOT NULL,
        novedades_hrm TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE hrm_leave_types (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        requires_entitlement INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE hrm_leaves (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        employee_id INTEGER NOT NULL,
        leave_type_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        length_days INTEGER NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE apropiaciones (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        vigencia TEXT NOT NULL,
        codigo_rubro TEXT NOT NULL,
        valor_apropiado INTEGER NOT NULL,
        valor_cdp INTEGER NOT NULL,
        valor_rp INTEGER NOT NULL,
        valor_pagado INTEGER NOT NULL,
        saldo_disponible INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cdps (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        apropiacion_id TEXT NOT NULL,
        numero_cdp TEXT NOT NULL,
        valor_cdp INTEGER NOT NULL,
        saldo_disponible INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE rps (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        cdp_id TEXT NOT NULL,
        contrato_id TEXT NOT NULL,
        numero_rp TEXT NOT NULL,
        valor_rp INTEGER NOT NULL,
        saldo_disponible INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE auditoria_registros (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        usuario_id TEXT NOT NULL,
        fecha_hora TEXT NOT NULL,
        hash_anterior TEXT,
        hash_actual TEXT NOT NULL,
        referencia_id TEXT
      )
    ''');
  });

  tearDown(() => db.close());

  test(
    'captura un asiento comercial exacto y su validacion de partida doble',
    () async {
      await db.insert('asientos_contables', {
        'id': 1,
        'company_id': 7,
        'fecha': '2026-08-09',
        'concepto': 'Venta de contado',
        'estado': 'registrado',
      });
      await db.insert('asiento_lineas', {
        'id': 11,
        'asiento_id': 1,
        'cuenta_id': 1105,
        'debito': 12500,
        'credito': 0,
      });
      await db.insert('asiento_lineas', {
        'id': 12,
        'asiento_id': 1,
        'cuenta_id': 4135,
        'debito': 0,
        'credito': 12500,
      });
      await db.insert('auditoria_registros', {
        'id': 'AUD-1',
        'entidad_id': 'ENT-001',
        'usuario_id': 'USR-1',
        'fecha_hora': fixedNow.toIso8601String(),
        'hash_actual': 'hash-asiento',
        'referencia_id': '1',
      });

      final service = EvidenceCapsuleService(
        executor: db,
        clock: () => fixedNow,
      );
      final capsule = await service.generate(
        const EvidenceRequest(
          domain: 'contabilidad',
          recordType: 'asiento_contable_comercial',
          recordId: '1',
        ),
      );

      expect(capsule.result['balanced'], isTrue);
      expect(capsule.result['debit_minor_units'], 12500);
      expect(capsule.result['credit_minor_units'], 12500);
      expect(capsule.auditRecords.single['hash_actual'], 'hash-asiento');
      expect(capsule.verifyIntegrity(), isTrue);
    },
  );

  test(
    'captura nomina y ausencias HRM aprobadas con valores exactos',
    () async {
      await db.insert('nomina_liquidaciones', {
        'id': 2,
        'company_id': 7,
        'empleado_id': 42,
        'periodo': '2026-08',
        'total_devengado': 3000000,
        'neto_pagar': 2700000,
        'estado': 'liquidada',
        'novedades_hrm': '[{"code":"permiso_no_remunerado","days":2}]',
      });
      await db.insert('hrm_leave_types', {
        'id': 1,
        'code': 'permiso_no_remunerado',
        'name': 'Permiso no remunerado',
        'requires_entitlement': 0,
      });
      await db.insert('hrm_leaves', {
        'id': 21,
        'company_id': 7,
        'employee_id': 42,
        'leave_type_id': 1,
        'date': '2026-08-04T00:00:00.000Z',
        'length_days': 2,
        'status': 'aprobado',
      });

      final capsule =
          await EvidenceCapsuleService(
            executor: db,
            clock: () => fixedNow,
          ).generate(
            const EvidenceRequest(
              domain: 'nomina',
              recordType: 'nomina_liquidacion_comercial',
              recordId: '2',
            ),
          );

      expect(capsule.result['neto_pagar_minor_units'], 2700000);
      expect(capsule.result['approved_leave_days'], 2);
      expect(
        capsule.sourceRecords.any((row) => row.table == 'hrm_leaves'),
        isTrue,
      );
      expect(capsule.calculations.single['novedades_hrm'], [
        {'code': 'permiso_no_remunerado', 'days': 2},
      ]);
    },
  );

  test(
    'captura la cadena apropiacion a CDP a RP y produce hash estable',
    () async {
      await db.insert('apropiaciones', {
        'id': 'APR-1',
        'entidad_id': 'ENT-001',
        'vigencia': '2026',
        'codigo_rubro': '2.1.1',
        'valor_apropiado': 1000000,
        'valor_cdp': 400000,
        'valor_rp': 250000,
        'valor_pagado': 0,
        'saldo_disponible': 600000,
      });
      await db.insert('cdps', {
        'id': 'CDP-1',
        'entidad_id': 'ENT-001',
        'apropiacion_id': 'APR-1',
        'numero_cdp': '0001',
        'valor_cdp': 400000,
        'saldo_disponible': 150000,
      });
      await db.insert('rps', {
        'id': 'RP-1',
        'entidad_id': 'ENT-001',
        'cdp_id': 'CDP-1',
        'contrato_id': 'CON-1',
        'numero_rp': '0001',
        'valor_rp': 250000,
        'saldo_disponible': 150000,
      });

      final service = EvidenceCapsuleService(
        executor: db,
        clock: () => fixedNow,
      );
      final request = const EvidenceRequest(
        domain: 'presupuesto',
        recordType: 'rp',
        recordId: 'RP-1',
      );
      final first = await service.generate(request);
      final second = await service.generate(request);

      expect(first.result['chain_complete'], isTrue);
      expect(first.calculations.single['cdp_within_appropriation'], isTrue);
      expect(first.calculations.single['rp_within_cdp'], isTrue);
      expect(first.result['saldo_disponible_minor_units'], 600000);
      expect(first.integritySha256, second.integritySha256);
      expect(first.toJson(), second.toJson());
      expect(first.verifyIntegrity(), isTrue);
    },
  );
}
