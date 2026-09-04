import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class CrmCampaign {
  const CrmCampaign({
    this.id,
    required this.companyId,
    required this.name,
    required this.campaignType,
    this.status = 'planned',
    required this.startDate,
    this.endDate,
    required this.budget,
    required this.expectedRevenue,
    this.assignedUserId,
    this.entityType = 'comercial',
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final int companyId;
  final String name;
  final String campaignType;
  final String status;
  final DateTime startDate;
  final DateTime? endDate;
  final MoneyValue budget;
  final MoneyValue expectedRevenue;
  final int? assignedUserId;
  final String entityType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() {
    final created = createdAt ?? DateTime.now();
    return {
      if (id != null) 'id': id,
      'company_id': companyId,
      'name': name,
      'campaign_type': campaignType,
      'status': status,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'budget': budget.toSql(),
      'expected_revenue': expectedRevenue.toSql(),
      'assigned_user_id': assignedUserId,
      'entity_type': entityType,
      'created_at': created.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory CrmCampaign.fromMap(Map<String, Object?> map, Currency currency) {
    return CrmCampaign(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num).toInt(),
      name: map['name'].toString(),
      campaignType: map['campaign_type'].toString(),
      status: map['status'].toString(),
      startDate: DateTime.parse(map['start_date'].toString()),
      endDate: _date(map['end_date']),
      budget: MoneyValue.fromSql(map['budget'], currency: currency),
      expectedRevenue: MoneyValue.fromSql(
        map['expected_revenue'],
        currency: currency,
      ),
      assignedUserId: (map['assigned_user_id'] as num?)?.toInt(),
      entityType: map['entity_type']?.toString() ?? 'comercial',
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }
}

DateTime? _date(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}
