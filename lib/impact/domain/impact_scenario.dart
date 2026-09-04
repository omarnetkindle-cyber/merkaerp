import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class ImpactSnapshot {
  const ImpactSnapshot({
    required this.companyId,
    required this.currency,
    required this.closedWonValue,
    required this.closedWonCount,
    required this.activeHeadcount,
    required this.activeBasePayroll,
    required this.workstationCount,
    required this.configuredWorkstationCount,
    required this.availableHoursPerDay,
    required this.capacityConfigured,
    required this.capacityNote,
    this.productiveEmployeeCount = 0,
    this.productiveEmployeeHoursPerDay = 0,
    this.personnelCapacityConfigured = false,
    this.personnelCapacityNote = 'No hay empleados vinculados a produccion.',
    this.demandLines = const [],
  });

  final int companyId;
  final Currency currency;
  final MoneyValue closedWonValue;
  final int closedWonCount;
  final int activeHeadcount;
  final MoneyValue activeBasePayroll;
  final int workstationCount;
  final int configuredWorkstationCount;
  final double availableHoursPerDay;
  final bool capacityConfigured;
  final String capacityNote;
  final int productiveEmployeeCount;
  final double productiveEmployeeHoursPerDay;
  final bool personnelCapacityConfigured;
  final String personnelCapacityNote;
  final List<ImpactDemandLine> demandLines;

  Map<String, dynamic> toJson() => {
    'company_id': companyId,
    'currency': currency.code,
    'closed_won_value': closedWonValue.toWireMap(),
    'closed_won_count': closedWonCount,
    'active_headcount': activeHeadcount,
    'active_base_payroll': activeBasePayroll.toWireMap(),
    'workstation_count': workstationCount,
    'configured_workstation_count': configuredWorkstationCount,
    'available_hours_per_day': availableHoursPerDay,
    'capacity_configured': capacityConfigured,
    'capacity_note': capacityNote,
    'productive_employee_count': productiveEmployeeCount,
    'productive_employee_hours_per_day': productiveEmployeeHoursPerDay,
    'personnel_capacity_configured': personnelCapacityConfigured,
    'personnel_capacity_note': personnelCapacityNote,
    'demand_lines': demandLines.map((line) => line.toJson()).toList(),
  };
}

class ImpactDemandLine {
  const ImpactDemandLine({
    required this.productId,
    required this.productName,
    required this.uom,
    required this.quantity,
    required this.probability,
    required this.weightedQuantity,
    required this.estimatedHoursPerUnit,
    required this.weightedHours,
  });

  final int productId;
  final String productName;
  final String uom;
  final double quantity;
  final int probability;
  final double weightedQuantity;
  final double estimatedHoursPerUnit;
  final double weightedHours;

  ImpactDemandLine scale(int upliftPercent) {
    final factor = (100 + upliftPercent) / 100;
    return ImpactDemandLine(
      productId: productId,
      productName: productName,
      uom: uom,
      quantity: quantity * factor,
      probability: probability,
      weightedQuantity: weightedQuantity * factor,
      estimatedHoursPerUnit: estimatedHoursPerUnit,
      weightedHours: weightedHours * factor,
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'product_name': productName,
    'uom': uom,
    'quantity': quantity,
    'probability': probability,
    'weighted_quantity': weightedQuantity,
    'estimated_hours_per_unit': estimatedHoursPerUnit,
    'weighted_hours': weightedHours,
  };

  factory ImpactDemandLine.fromJson(Map<String, dynamic> json) =>
      ImpactDemandLine(
        productId: (json['product_id'] as num).toInt(),
        productName: json['product_name']?.toString() ?? 'Producto',
        uom: json['uom']?.toString() ?? 'UND',
        quantity: (json['quantity'] as num).toDouble(),
        probability: (json['probability'] as num).toInt(),
        weightedQuantity: (json['weighted_quantity'] as num).toDouble(),
        estimatedHoursPerUnit:
            (json['estimated_hours_per_unit'] as num?)?.toDouble() ?? 0,
        weightedHours: (json['weighted_hours'] as num?)?.toDouble() ?? 0,
      );
}

class ImpactResult {
  const ImpactResult({
    required this.upliftPercent,
    required this.baselineClosedWonValue,
    required this.projectedClosedWonValue,
    required this.incrementalDemandProxy,
    required this.capacityStatus,
    required this.formula,
    required this.warnings,
    this.baselineDemandLines = const [],
    this.projectedDemandLines = const [],
    this.baselineProductionHours = 0,
    this.projectedProductionHours = 0,
  });

  final int upliftPercent;
  final MoneyValue baselineClosedWonValue;
  final MoneyValue projectedClosedWonValue;
  final MoneyValue incrementalDemandProxy;
  final String capacityStatus;
  final String formula;
  final List<String> warnings;
  final List<ImpactDemandLine> baselineDemandLines;
  final List<ImpactDemandLine> projectedDemandLines;
  final double baselineProductionHours;
  final double projectedProductionHours;

  Map<String, dynamic> toJson() => {
    'uplift_percent': upliftPercent,
    'baseline_closed_won_value': baselineClosedWonValue.toWireMap(),
    'projected_closed_won_value': projectedClosedWonValue.toWireMap(),
    'incremental_demand_proxy': incrementalDemandProxy.toWireMap(),
    'capacity_status': capacityStatus,
    'formula': formula,
    'warnings': warnings,
    'baseline_demand_lines': baselineDemandLines
        .map((line) => line.toJson())
        .toList(),
    'projected_demand_lines': projectedDemandLines
        .map((line) => line.toJson())
        .toList(),
    'baseline_production_hours': baselineProductionHours,
    'projected_production_hours': projectedProductionHours,
  };
}

class ImpactCalculator {
  const ImpactCalculator._();

  static ImpactResult calculate({
    required ImpactSnapshot snapshot,
    required int upliftPercent,
  }) {
    if (upliftPercent < 0 || upliftPercent > 100) {
      throw ArgumentError('El incremento debe estar entre 0% y 100%.');
    }
    final projected = snapshot.closedWonValue.multiplyRatio(
      numerator: 100 + upliftPercent,
      denominator: 100,
    );
    final projectedDemandLines = snapshot.demandLines
        .map((line) => line.scale(upliftPercent))
        .toList();
    final baselineHours = snapshot.demandLines.fold<double>(
      0,
      (sum, line) => sum + line.weightedHours,
    );
    final projectedHours = projectedDemandLines.fold<double>(
      0,
      (sum, line) => sum + line.weightedHours,
    );
    final hasDemand = snapshot.demandLines.isNotEmpty;
    final hasCapacityHours = snapshot.demandLines.any(
      (line) => line.estimatedHoursPerUnit > 0,
    );
    final personnelIsRelevant = snapshot.productiveEmployeeCount > 0;
    final effectiveCapacityHours =
        personnelIsRelevant && snapshot.personnelCapacityConfigured
        ? _minimum(
            snapshot.availableHoursPerDay,
            snapshot.productiveEmployeeHoursPerDay,
          )
        : snapshot.availableHoursPerDay;
    final status = !hasDemand
        ? 'sin_demanda_de_productos'
        : !hasCapacityHours
        ? 'demanda_sin_bom'
        : !snapshot.capacityConfigured
        ? 'capacidad_no_configurada'
        : personnelIsRelevant && !snapshot.personnelCapacityConfigured
        ? 'capacidad_personal_no_configurada'
        : projectedHours > effectiveCapacityHours
        ? 'capacidad_insuficiente'
        : 'capacidad_suficiente';
    return ImpactResult(
      upliftPercent: upliftPercent,
      baselineClosedWonValue: snapshot.closedWonValue,
      projectedClosedWonValue: projected,
      incrementalDemandProxy: projected - snapshot.closedWonValue,
      capacityStatus: status,
      formula:
          'valor_ganado_proyectado = valor_ganado_actual * '
          '(1 + uplift_percent / 100); demanda_ponderada_producto = suma(cantidad_linea * '
          'probabilidad / 100); demanda_escenario = demanda_ponderada_producto '
          '* (1 + uplift_percent / 100); horas_MRP = suma(demanda_escenario '
          '* horas_BOM_por_unidad); capacidad_efectiva_diaria = min('
          'horas_workstations, horas_contractuales_personal_vinculado) '
          'cuando existen vinculos productivos.',
      warnings: [
        if (!snapshot.capacityConfigured &&
            snapshot.configuredWorkstationCount > 0)
          'Solo hay capacidad configurada para '
              '${snapshot.configuredWorkstationCount} de '
              '${snapshot.workstationCount} workstations.',
        if (!snapshot.capacityConfigured &&
            snapshot.configuredWorkstationCount == 0)
          'Capacidad no configurada: production_capacity no representa horas disponibles.',
        if (hasDemand && !hasCapacityHours)
          'Hay productos CRM sin BOM/ruta con tiempo: se informa demanda en unidades, sin convertirla a horas.',
        if (personnelIsRelevant && !snapshot.personnelCapacityConfigured)
          snapshot.personnelCapacityNote,
      ],
      baselineDemandLines: snapshot.demandLines,
      projectedDemandLines: projectedDemandLines,
      baselineProductionHours: baselineHours,
      projectedProductionHours: projectedHours,
    );
  }

  static double _minimum(double first, double second) =>
      first < second ? first : second;
}

class ImpactScenario {
  const ImpactScenario({
    this.id,
    required this.companyId,
    required this.name,
    required this.createdAt,
    required this.upliftPercent,
    required this.snapshot,
    required this.result,
    required this.integritySha256,
  });

  final int? id;
  final int companyId;
  final String name;
  final DateTime createdAt;
  final int upliftPercent;
  final ImpactSnapshot snapshot;
  final ImpactResult result;
  final String integritySha256;

  factory ImpactScenario.create({
    required int companyId,
    required String name,
    required DateTime createdAt,
    required ImpactSnapshot snapshot,
    required ImpactResult result,
  }) {
    final base = {
      'company_id': companyId,
      'name': name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'uplift_percent': result.upliftPercent,
      'snapshot': snapshot.toJson(),
      'result': result.toJson(),
      'formula': result.formula,
    };
    final hash = sha256.convert(utf8.encode(jsonEncode(base))).toString();
    return ImpactScenario(
      companyId: companyId,
      name: name,
      createdAt: createdAt,
      upliftPercent: result.upliftPercent,
      snapshot: snapshot,
      result: result,
      integritySha256: hash,
    );
  }

  Map<String, Object?> toInsertMap() => {
    'company_id': companyId,
    'name': name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'uplift_percent': upliftPercent,
    'input_json': jsonEncode({'uplift_percent': upliftPercent}),
    'snapshot_json': jsonEncode(snapshot.toJson()),
    'result_json': jsonEncode(result.toJson()),
    'formula': result.formula,
    'integrity_sha256': integritySha256,
  };

  factory ImpactScenario.fromRow(
    Map<String, dynamic> row, {
    required Currency currency,
  }) {
    final snapshot = jsonDecode(row['snapshot_json'].toString());
    final result = jsonDecode(row['result_json'].toString());
    return ImpactScenario(
      id: (row['id'] as num?)?.toInt(),
      companyId: (row['company_id'] as num).toInt(),
      name: row['name'].toString(),
      createdAt: DateTime.parse(row['created_at'].toString()),
      upliftPercent: (row['uplift_percent'] as num).toInt(),
      snapshot: _snapshotFromJson(snapshot, currency),
      result: _resultFromJson(result, currency),
      integritySha256: row['integrity_sha256'].toString(),
    );
  }
}

ImpactSnapshot _snapshotFromJson(
  Map<String, dynamic> json,
  Currency currency,
) => ImpactSnapshot(
  companyId: (json['company_id'] as num).toInt(),
  currency: currency,
  closedWonValue: MoneyValue.fromSql(
    (json['closed_won_value']['minor_units'] as num).toInt(),
    currency: currency,
  ),
  closedWonCount: (json['closed_won_count'] as num).toInt(),
  activeHeadcount: (json['active_headcount'] as num).toInt(),
  activeBasePayroll: MoneyValue.fromSql(
    (json['active_base_payroll']['minor_units'] as num).toInt(),
    currency: currency,
  ),
  workstationCount: (json['workstation_count'] as num).toInt(),
  configuredWorkstationCount:
      (json['configured_workstation_count'] as num?)?.toInt() ?? 0,
  availableHoursPerDay:
      (json['available_hours_per_day'] as num?)?.toDouble() ?? 0,
  capacityConfigured: json['capacity_configured'] == true,
  capacityNote: json['capacity_note'].toString(),
  productiveEmployeeCount:
      (json['productive_employee_count'] as num?)?.toInt() ?? 0,
  productiveEmployeeHoursPerDay:
      (json['productive_employee_hours_per_day'] as num?)?.toDouble() ?? 0,
  personnelCapacityConfigured: json['personnel_capacity_configured'] == true,
  personnelCapacityNote:
      json['personnel_capacity_note']?.toString() ??
      'No hay empleados vinculados a produccion.',
  demandLines: ((json['demand_lines'] as List?) ?? const [])
      .map((item) => ImpactDemandLine.fromJson(item as Map<String, dynamic>))
      .toList(),
);

ImpactResult _resultFromJson(
  Map<String, dynamic> json,
  Currency currency,
) => ImpactResult(
  upliftPercent: (json['uplift_percent'] as num).toInt(),
  baselineClosedWonValue: MoneyValue.fromSql(
    (json['baseline_closed_won_value']['minor_units'] as num).toInt(),
    currency: currency,
  ),
  projectedClosedWonValue: MoneyValue.fromSql(
    (json['projected_closed_won_value']['minor_units'] as num).toInt(),
    currency: currency,
  ),
  incrementalDemandProxy: MoneyValue.fromSql(
    (json['incremental_demand_proxy']['minor_units'] as num).toInt(),
    currency: currency,
  ),
  capacityStatus: json['capacity_status'].toString(),
  formula: json['formula'].toString(),
  warnings: (json['warnings'] as List).cast<String>(),
  baselineDemandLines: ((json['baseline_demand_lines'] as List?) ?? const [])
      .map((item) => ImpactDemandLine.fromJson(item as Map<String, dynamic>))
      .toList(),
  projectedDemandLines: ((json['projected_demand_lines'] as List?) ?? const [])
      .map((item) => ImpactDemandLine.fromJson(item as Map<String, dynamic>))
      .toList(),
  baselineProductionHours:
      (json['baseline_production_hours'] as num?)?.toDouble() ?? 0,
  projectedProductionHours:
      (json['projected_production_hours'] as num?)?.toDouble() ?? 0,
);
