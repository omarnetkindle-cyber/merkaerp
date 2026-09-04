import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/impact/application/impact_simulator_service.dart';
import 'package:merka_erp/impact/database/schema_impact.dart';
import 'package:merka_erp/impact/domain/impact_scenario.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const companyId = 7;
  final currency = Currency(
    code: 'COP',
    name: 'Peso colombiano',
    symbol: r'$',
    decimalPlaces: 2,
  );
  late Database db;
  late ImpactSimulatorService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE crm_opportunities (
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        value INTEGER NOT NULL DEFAULT 0,
        amount INTEGER,
        stage TEXT,
        sales_stage TEXT,
        probability INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        nombre TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE crm_opportunity_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        opportunity_id TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        uom TEXT NOT NULL,
        unit_price INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        modified_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE empleados (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        cargo TEXT,
        salario_base INTEGER,
        job_title_id INTEGER,
        activo INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE hrm_job_titles (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        contractual_hours_per_day REAL,
        mrp_workstation_id INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE mrp_workstations (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        production_capacity INTEGER NOT NULL,
        available_hours_per_day REAL,
        status TEXT NOT NULL DEFAULT 'produccion',
        hour_rate INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE mrp_boms (
        id INTEGER PRIMARY KEY,
        company_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        routing_id INTEGER,
        is_active INTEGER NOT NULL,
        is_default INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE mrp_operations (
        id INTEGER PRIMARY KEY,
        routing_id INTEGER NOT NULL,
        time_minutes REAL NOT NULL
      )
    ''');
    await SchemaImpact.crearTablas(db);
    await db.insert('crm_opportunities', {
      'id': 'OP-WON',
      'company_id': companyId,
      'value': 100000,
      'amount': 100000,
      'stage': 'closed_won',
      'sales_stage': 'closed_won',
    });
    await db.insert('crm_opportunities', {
      'id': 'OP-OPEN',
      'company_id': companyId,
      'value': 50000,
      'amount': 50000,
      'stage': 'prospecting',
      'sales_stage': 'prospecting',
      'probability': 25,
    });
    await db.insert('productos', {
      'id': 10,
      'company_id': companyId,
      'nombre': 'Producto CRM-MRP',
    });
    await db.insert('crm_opportunity_items', {
      'company_id': companyId,
      'opportunity_id': 'OP-WON',
      'product_id': 10,
      'quantity': 10,
      'uom': 'UND',
      'unit_price': 1000,
      'amount': 10000,
      'created_at': DateTime.utc(2026, 8, 9).toIso8601String(),
    });
    await db.insert('crm_opportunity_items', {
      'company_id': companyId,
      'opportunity_id': 'OP-OPEN',
      'product_id': 10,
      'quantity': 4,
      'uom': 'UND',
      'unit_price': 1000,
      'amount': 4000,
      'created_at': DateTime.utc(2026, 8, 9).toIso8601String(),
    });
    await db.insert('empleados', {
      'id': 1,
      'company_id': companyId,
      'cargo': 'Operario',
      'salario_base': 200000,
      'activo': 1,
    });
    await db.insert('empleados', {
      'id': 2,
      'company_id': companyId,
      'cargo': 'Retirado',
      'salario_base': 900000,
      'activo': 0,
    });
    await db.insert('mrp_workstations', {
      'id': 1,
      'company_id': companyId,
      'name': 'Linea A',
      'production_capacity': 4,
      'available_hours_per_day': 8,
      'hour_rate': 5000,
    });
    service = ImpactSimulatorService(
      executor: db,
      companyId: companyId,
      currency: currency,
      clock: () => DateTime.utc(2026, 8, 9, 12),
    );
  });

  tearDown(() => db.close());

  test('calcula el impacto con unidades menores y formula explicita', () async {
    final snapshot = await service.snapshot();
    final result = service.calculate(snapshot: snapshot, upliftPercent: 20);

    expect(snapshot.closedWonValue.minorUnits, 100000);
    expect(snapshot.closedWonCount, 1);
    expect(snapshot.activeHeadcount, 1);
    expect(snapshot.productiveEmployeeCount, 0);
    expect(snapshot.productiveEmployeeHoursPerDay, 0);
    expect(snapshot.activeBasePayroll.minorUnits, 200000);
    expect(snapshot.workstationCount, 1);
    expect(snapshot.configuredWorkstationCount, 1);
    expect(snapshot.availableHoursPerDay, 8);
    expect(result.projectedClosedWonValue.minorUnits, 120000);
    expect(result.incrementalDemandProxy.minorUnits, 20000);
    expect(result.capacityStatus, 'demanda_sin_bom');
    expect(result.formula, contains('valor_ganado_actual'));
    expect(result.warnings, contains(contains('sin BOM/ruta')));
    expect(snapshot.demandLines, hasLength(2));
    expect(snapshot.demandLines[0].weightedQuantity, 10);
    expect(snapshot.demandLines[1].weightedQuantity, 1);
    expect(result.projectedDemandLines[0].weightedQuantity, 12);
    expect(result.projectedDemandLines[1].weightedQuantity, 1.2);
  });

  test('usa horas contractuales del personal vinculado a produccion', () async {
    await db.insert('hrm_job_titles', {
      'id': 1,
      'company_id': companyId,
      'title': 'Operario',
      'contractual_hours_per_day': 6,
      'mrp_workstation_id': 1,
    });
    await db.update(
      'empleados',
      {'job_title_id': 1},
      where: 'id = ?',
      whereArgs: [1],
    );
    await db.insert('mrp_boms', {
      'id': 1,
      'company_id': companyId,
      'item_id': 10,
      'quantity': 1,
      'routing_id': 1,
      'is_active': 1,
      'is_default': 1,
    });
    await db.insert('mrp_operations', {
      'id': 1,
      'routing_id': 1,
      'time_minutes': 60,
    });

    final snapshot = await service.snapshot();
    expect(snapshot.productiveEmployeeCount, 1);
    expect(snapshot.productiveEmployeeHoursPerDay, 6);
    expect(snapshot.personnelCapacityConfigured, isTrue);
    expect(snapshot.personnelCapacityNote, contains('6.00'));

    final result = service.calculate(snapshot: snapshot, upliftPercent: 20);
    expect(result.projectedProductionHours, 13.2);
    expect(result.capacityStatus, 'capacidad_insuficiente');
  });

  test('guardar escenario no modifica tablas operativas', () async {
    final beforeOpportunities = await db.query(
      'crm_opportunities',
      orderBy: 'id',
    );
    final beforeEmployees = await db.query('empleados', orderBy: 'id');
    final beforeWorkstations = await db.query(
      'mrp_workstations',
      orderBy: 'id',
    );
    final beforeItems = await db.query('crm_opportunity_items', orderBy: 'id');
    final snapshot = await service.snapshot();
    final result = service.calculate(snapshot: snapshot, upliftPercent: 20);

    final saved = await service.saveScenario(
      name: 'Demanda de agosto',
      snapshot: snapshot,
      result: result,
    );

    expect(saved.id, isNotNull);
    expect(
      await db.query('crm_opportunities', orderBy: 'id'),
      beforeOpportunities,
    );
    expect(await db.query('empleados', orderBy: 'id'), beforeEmployees);
    expect(
      await db.query('mrp_workstations', orderBy: 'id'),
      beforeWorkstations,
    );
    expect(await db.query('crm_opportunity_items', orderBy: 'id'), beforeItems);
    expect((await db.query('impact_scenarios')).length, 1);
  });

  test('el libro conserva formula, snapshot y hash de integridad', () async {
    final snapshot = await service.snapshot();
    final result = service.calculate(snapshot: snapshot, upliftPercent: 20);
    final saved = await service.saveScenario(
      name: 'Escenario reproducible',
      snapshot: snapshot,
      result: result,
    );

    final listed = await service.listScenarios();
    expect(listed, hasLength(1));
    expect(listed.single.id, saved.id);
    expect(listed.single.snapshot.closedWonValue.minorUnits, 100000);
    expect(listed.single.result.projectedClosedWonValue.minorUnits, 120000);
    expect(listed.single.result.formula, saved.result.formula);
    expect(listed.single.integritySha256, hasLength(64));
  });

  test(
    'dos escenarios con el mismo instante y snapshot tienen el mismo hash',
    () async {
      final snapshot = await service.snapshot();
      final result = service.calculate(snapshot: snapshot, upliftPercent: 20);
      final first = ImpactScenario.create(
        companyId: companyId,
        name: 'Mismo escenario',
        createdAt: DateTime.utc(2026, 8, 9, 12),
        snapshot: snapshot,
        result: result,
      );
      final second = ImpactScenario.create(
        companyId: companyId,
        name: 'Mismo escenario',
        createdAt: DateTime.utc(2026, 8, 9, 12),
        snapshot: snapshot,
        result: result,
      );

      expect(second.integritySha256, first.integritySha256);
    },
  );

  test('el calculador rechaza incrementos fuera del rango del control', () {
    final snapshot = ImpactSnapshot(
      companyId: companyId,
      currency: currency,
      closedWonValue: MoneyValue(minorUnits: 100000, currency: currency),
      closedWonCount: 1,
      activeHeadcount: 1,
      activeBasePayroll: MoneyValue(minorUnits: 200000, currency: currency),
      workstationCount: 1,
      configuredWorkstationCount: 1,
      availableHoursPerDay: 8,
      capacityConfigured: false,
      capacityNote: 'No configurada',
    );

    expect(
      () => ImpactCalculator.calculate(snapshot: snapshot, upliftPercent: 101),
      throwsArgumentError,
    );
  });
}
