import 'package:sqflite/sqflite.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../database/schema_impact.dart';
import '../domain/impact_scenario.dart';

class ImpactSimulatorService {
  ImpactSimulatorService({
    DatabaseExecutor? executor,
    int? companyId,
    Currency? currency,
    DateTime Function()? clock,
  }) : _executor = executor,
       _companyId = companyId,
       _currency = currency,
       _clock = clock ?? DateTime.now;

  final DatabaseExecutor? _executor;
  final int? _companyId;
  final Currency? _currency;
  final DateTime Function() _clock;

  Future<DatabaseExecutor> _db() async =>
      _executor ?? await DatabaseHelper.instance.database;

  Future<int> _company(DatabaseExecutor db) async =>
      _companyId ?? await DatabaseHelper.instance.obtenerEmpresaActivaId(db);

  Future<Currency> _resolvedCurrency(
    DatabaseExecutor db,
    int companyId,
  ) async =>
      _currency ?? MoneyCurrencyResolver.resolve(db, companyId: companyId);

  Future<ImpactSnapshot> snapshot() async {
    final db = await _db();
    final companyId = await _company(db);
    final currency = await _resolvedCurrency(db, companyId);
    final opportunities = await db.rawQuery(
      '''
      SELECT id,
             COALESCE(amount, value, 0) AS amount_minor_units,
             COALESCE(NULLIF(sales_stage, ''), stage, 'prospecting') AS sales_stage,
             probability
      FROM crm_opportunities
      WHERE company_id = ?
    ''',
      [companyId],
    );
    final won = opportunities.where(
      (row) => row['sales_stage']?.toString() == 'closed_won',
    );
    final closedWonValue = won.fold<int>(
      0,
      (sum, row) => sum + _integer(row['amount_minor_units']),
    );
    final productColumns = await db.rawQuery('PRAGMA table_info(productos)');
    final hasItemType = productColumns.any(
      (column) => column['name']?.toString() == 'tipo_item',
    );
    final itemTypeSql = hasItemType
        ? "COALESCE(p.tipo_item, 'producto')"
        : "'producto'";
    final itemRows = await db.rawQuery(
      '''
      SELECT oi.product_id, oi.quantity, oi.uom,
             o.id AS opportunity_id, o.sales_stage, o.probability,
             p.nombre AS product_name, $itemTypeSql AS tipo_item
      FROM crm_opportunity_items oi
      JOIN crm_opportunities o ON o.id = oi.opportunity_id
      LEFT JOIN productos p ON p.id = oi.product_id
      WHERE oi.company_id = ? AND o.company_id = ?
      ORDER BY oi.id ASC
      ''',
      [companyId, companyId],
    );
    final demandLines = <ImpactDemandLine>[];
    for (final row in itemRows) {
      final stage = row['sales_stage']?.toString() ?? 'prospecting';
      final probability =
          (row['probability'] as num?)?.toInt() ?? _stageProbability(stage);
      final quantity = (row['quantity'] as num).toDouble();
      final productId = (row['product_id'] as num).toInt();
      final tipoItem = row['tipo_item']?.toString() ?? 'producto';

      double hoursPerUnit = 0.0;
      if (tipoItem == 'servicio') {
        // Para servicios intangibles, la demanda se traduce en horas de personal (HRM)
        hoursPerUnit = 1.0;
      } else {
        final bom = await db.rawQuery(
          '''
          SELECT b.quantity, b.routing_id,
                 COALESCE(SUM(op.time_minutes), 0) AS operation_minutes
          FROM mrp_boms b
          LEFT JOIN mrp_operations op ON op.routing_id = b.routing_id
          WHERE b.company_id = ? AND b.item_id = ? AND b.is_active = 1
          GROUP BY b.id
          ORDER BY b.is_default DESC, b.id ASC
          LIMIT 1
          ''',
          [companyId, productId],
        );
        final bomQuantity = bom.isEmpty
            ? 1
            : (bom.first['quantity'] as num?)?.toDouble() ?? 1;
        final operationMinutes = bom.isEmpty
            ? 0
            : (bom.first['operation_minutes'] as num?)?.toDouble() ?? 0;
        hoursPerUnit = bomQuantity > 0
            ? (operationMinutes / 60 / bomQuantity).toDouble()
            : 0.0;
      }

      final weightedQuantity = quantity * probability / 100;
      demandLines.add(
        ImpactDemandLine(
          productId: productId,
          productName: row['product_name']?.toString() ?? 'Producto $productId',
          uom: row['uom']?.toString() ?? (tipoItem == 'servicio' ? 'SERV' : 'UND'),
          quantity: quantity,
          probability: probability,
          weightedQuantity: weightedQuantity,
          estimatedHoursPerUnit: hoursPerUnit,
          weightedHours: weightedQuantity * hoursPerUnit,
        ),
      );
    }
    final employees = await db.rawQuery(
      '''
      SELECT e.id, e.cargo, e.salario_base,
             jt.mrp_workstation_id, jt.contractual_hours_per_day
      FROM empleados e
      LEFT JOIN hrm_job_titles jt
        ON jt.id = e.job_title_id
       AND jt.company_id = e.company_id
       AND jt.is_deleted = 0
      WHERE e.company_id = ? AND e.activo = 1
    ''',
      [companyId],
    );
    final linkedEmployees = employees
        .where((row) => row['mrp_workstation_id'] != null)
        .toList();
    final configuredLinkedEmployees = linkedEmployees.where((row) {
      final hours = (row['contractual_hours_per_day'] as num?)?.toDouble();
      return hours != null && hours > 0;
    }).toList();
    final productiveEmployeeHoursPerDay = configuredLinkedEmployees
        .fold<double>(
          0,
          (sum, row) =>
              sum +
              ((row['contractual_hours_per_day'] as num?)?.toDouble() ?? 0),
        );
    final personnelCapacityConfigured =
        linkedEmployees.isNotEmpty &&
        linkedEmployees.length == configuredLinkedEmployees.length;
    final workstations = await db.query(
      'mrp_workstations',
      columns: [
        'id',
        'name',
        'production_capacity',
        'available_hours_per_day',
        'status',
      ],
      where: 'company_id = ?',
      whereArgs: [companyId],
    );
    final productionWorkstations = workstations
        .where((row) => row['status']?.toString() == 'produccion')
        .toList();
    final configuredWorkstations = productionWorkstations.where((row) {
      final hours = (row['available_hours_per_day'] as num?)?.toDouble();
      return hours != null && hours > 0;
    }).toList();
    final availableHoursPerDay = configuredWorkstations.fold<double>(
      0,
      (sum, row) =>
          sum + ((row['available_hours_per_day'] as num?)?.toDouble() ?? 0),
    );
    final capacityConfigured =
        productionWorkstations.isNotEmpty &&
        configuredWorkstations.length == productionWorkstations.length;
    return ImpactSnapshot(
      companyId: companyId,
      currency: currency,
      closedWonValue: MoneyValue(
        minorUnits: closedWonValue,
        currency: currency,
      ),
      closedWonCount: won.length,
      activeHeadcount: employees.length,
      activeBasePayroll: MoneyValue(
        minorUnits: employees.fold<int>(
          0,
          (sum, row) => sum + _integer(row['salario_base']),
        ),
        currency: currency,
      ),
      workstationCount: workstations.length,
      configuredWorkstationCount: configuredWorkstations.length,
      availableHoursPerDay: availableHoursPerDay,
      capacityConfigured: capacityConfigured,
      capacityNote: capacityConfigured
          ? 'Capacidad configurada: ${availableHoursPerDay.toStringAsFixed(2)} horas por dia '
                'en ${configuredWorkstations.length} workstations de produccion.'
          : configuredWorkstations.isEmpty
          ? 'Capacidad temporal no configurada. production_capacity no representa horas disponibles.'
          : 'Capacidad parcial: ${availableHoursPerDay.toStringAsFixed(2)} horas por dia '
                'en ${configuredWorkstations.length} de ${productionWorkstations.length} workstations de produccion.',
      productiveEmployeeCount: linkedEmployees.length,
      productiveEmployeeHoursPerDay: productiveEmployeeHoursPerDay,
      personnelCapacityConfigured: personnelCapacityConfigured,
      personnelCapacityNote: linkedEmployees.isEmpty
          ? 'No hay empleados vinculados a una workstation; se conserva el headcount general.'
          : personnelCapacityConfigured
          ? 'Capacidad contractual: ${productiveEmployeeHoursPerDay.toStringAsFixed(2)} horas por dia en ${linkedEmployees.length} empleados vinculados.'
          : 'Hay empleados vinculados a produccion sin horas contractuales configuradas.',
      demandLines: demandLines,
    );
  }

  ImpactResult calculate({
    required ImpactSnapshot snapshot,
    required int upliftPercent,
  }) => ImpactCalculator.calculate(
    snapshot: snapshot,
    upliftPercent: upliftPercent,
  );

  Future<ImpactScenario> saveScenario({
    required String name,
    required ImpactSnapshot snapshot,
    required ImpactResult result,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('El escenario requiere un nombre.');
    }
    final db = await _db();
    await SchemaImpact.crearTablas(db);
    final scenario = ImpactScenario.create(
      companyId: snapshot.companyId,
      name: name.trim(),
      createdAt: _clock(),
      snapshot: snapshot,
      result: result,
    );
    final id = await db.insert('impact_scenarios', scenario.toInsertMap());
    return ImpactScenario(
      id: id,
      companyId: scenario.companyId,
      name: scenario.name,
      createdAt: scenario.createdAt,
      upliftPercent: scenario.upliftPercent,
      snapshot: scenario.snapshot,
      result: scenario.result,
      integritySha256: scenario.integritySha256,
    );
  }

  Future<List<ImpactScenario>> listScenarios() async {
    final db = await _db();
    final companyId = await _company(db);
    final currency = await _resolvedCurrency(db, companyId);
    await SchemaImpact.crearTablas(db);
    final rows = await db.query(
      'impact_scenarios',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows
        .map((row) => ImpactScenario.fromRow(row, currency: currency))
        .toList();
  }

  int _integer(Object? value) => (value as num?)?.toInt() ?? 0;

  int _stageProbability(String stage) {
    switch (stage) {
      case 'qualification':
        return 25;
      case 'needs_analysis':
        return 40;
      case 'value_proposition':
        return 55;
      case 'negotiation_review':
        return 75;
      case 'closed_won':
        return 100;
      case 'closed_lost':
        return 0;
      default:
        return 10;
    }
  }
}
