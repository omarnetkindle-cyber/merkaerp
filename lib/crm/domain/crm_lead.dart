import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class CrmLead {
  const CrmLead({
    this.id,
    required this.companyId,
    this.accountName,
    this.contactId,
    this.leadSource,
    this.status = 'nuevo',
    required this.opportunityAmount,
    this.converted = false,
    this.convertedAccountId,
    this.convertedOpportunityId,
    this.campaignId,
    this.territoryId,
    this.assignedUserId,
    this.entityType = 'comercial',
    this.createdAt,
    this.modifiedAt,
  });

  final int? id;
  final int? companyId;
  final String? accountName;
  final int? contactId;
  final String? leadSource;
  final String status;
  final MoneyValue opportunityAmount;
  final bool converted;
  final int? convertedAccountId;
  final String? convertedOpportunityId;
  final int? campaignId;
  final int? territoryId;
  final int? assignedUserId;
  final String entityType;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  Map<String, Object?> toPersistenceMap({
    int? companyIdOverride,
    bool? convertedOverride,
  }) {
    return {
      if (id != null) 'id': id,
      'company_id': companyIdOverride ?? companyId,
      'account_name': accountName,
      'contact_id': contactId,
      'lead_source': leadSource,
      'status': status,
      'opportunity_amount': opportunityAmount.toSql(),
      'converted': (convertedOverride ?? converted) ? 1 : 0,
      'converted_account_id': convertedAccountId,
      'converted_opportunity_id': convertedOpportunityId,
      'campaign_id': campaignId,
      'territory_id': territoryId,
      'assigned_user_id': assignedUserId,
      'entity_type': entityType,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'modified_at': modifiedAt?.toIso8601String(),
    };
  }

  factory CrmLead.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return CrmLead(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num?)?.toInt(),
      accountName: map['account_name']?.toString(),
      contactId: (map['contact_id'] as num?)?.toInt(),
      leadSource: map['lead_source']?.toString(),
      status: map['status']?.toString() ?? 'nuevo',
      opportunityAmount: MoneyValue.fromSql(
        map['opportunity_amount'],
        currency: currency,
        nullableAsZero: true,
      ),
      converted: (map['converted'] as num?)?.toInt() == 1,
      convertedAccountId: (map['converted_account_id'] as num?)?.toInt(),
      convertedOpportunityId: map['converted_opportunity_id']?.toString(),
      campaignId: (map['campaign_id'] as num?)?.toInt(),
      territoryId: (map['territory_id'] as num?)?.toInt(),
      assignedUserId: (map['assigned_user_id'] as num?)?.toInt(),
      entityType: map['entity_type']?.toString() ?? 'comercial',
      createdAt: _leadDate(map['created_at']),
      modifiedAt: _leadDate(map['modified_at']),
    );
  }
}

DateTime? _leadDate(Object? value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text);
}
