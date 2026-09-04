import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class MrpWorkstation {
  const MrpWorkstation({
    this.id,
    required this.companyId,
    required this.name,
    required this.hourRate,
    this.productionCapacity = 1,
    this.availableHoursPerDay,
    this.status = 'produccion',
    this.warehouseId,
  });
  final int? id;
  final int companyId;
  final String name;
  final MoneyValue hourRate;
  final int productionCapacity;
  final double? availableHoursPerDay;
  final String status;
  final int? warehouseId;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'name': name,
    'hour_rate': hourRate.toSql(),
    'production_capacity': productionCapacity,
    'available_hours_per_day': availableHoursPerDay,
    'status': status,
    'warehouse_id': warehouseId,
  };
  factory MrpWorkstation.fromMap(Map<String, dynamic> m, Currency c) =>
      MrpWorkstation(
        id: (m['id'] as num?)?.toInt(),
        companyId: (m['company_id'] as num).toInt(),
        name: m['name'].toString(),
        hourRate: MoneyValue.fromSql(
          m['hour_rate'],
          currency: c,
          nullableAsZero: true,
        ),
        productionCapacity: (m['production_capacity'] as num?)?.toInt() ?? 1,
        availableHoursPerDay: (m['available_hours_per_day'] as num?)
            ?.toDouble(),
        status: m['status']?.toString() ?? 'produccion',
        warehouseId: (m['warehouse_id'] as num?)?.toInt(),
      );
}
