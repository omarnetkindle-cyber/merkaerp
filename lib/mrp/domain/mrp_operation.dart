import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class MrpOperation {
  const MrpOperation({
    this.id,
    required this.companyId,
    required this.routingId,
    required this.workstationId,
    required this.operationName,
    this.sequenceOrder = 1,
    this.timeMinutes = 0,
    this.isSubcontracted = false,
    this.supplierId,
    this.subcontractCost,
    this.leadTimeDays = 0,
  });
  final int? id;
  final int companyId;
  final int routingId;
  final int workstationId;
  final String operationName;
  final int sequenceOrder;
  final double timeMinutes;
  final bool isSubcontracted;
  final int? supplierId;
  final MoneyValue? subcontractCost;
  final int leadTimeDays;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'routing_id': routingId,
    'workstation_id': workstationId,
    'operation_name': operationName,
    'sequence_order': sequenceOrder,
    'time_minutes': timeMinutes,
    'is_subcontracted': isSubcontracted ? 1 : 0,
    'supplier_id': supplierId,
    'subcontract_cost': subcontractCost?.toSql() ?? 0,
    'lead_time_days': leadTimeDays,
  };
  factory MrpOperation.fromMap(Map<String, dynamic> m, Currency c) =>
      MrpOperation(
        id: (m['id'] as num?)?.toInt(),
        companyId: (m['company_id'] as num).toInt(),
        routingId: (m['routing_id'] as num).toInt(),
        workstationId: (m['workstation_id'] as num).toInt(),
        operationName: m['operation_name'].toString(),
        sequenceOrder: (m['sequence_order'] as num?)?.toInt() ?? 1,
        timeMinutes: (m['time_minutes'] as num?)?.toDouble() ?? 0,
        isSubcontracted: (m['is_subcontracted'] as num?)?.toInt() == 1,
        supplierId: (m['supplier_id'] as num?)?.toInt(),
        subcontractCost: MoneyValue.fromSql(
          m['subcontract_cost'],
          currency: c,
          nullableAsZero: true,
        ),
        leadTimeDays: (m['lead_time_days'] as num?)?.toInt() ?? 0,
      );
}
