import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

enum CrmSalesStage {
  prospecting,
  qualification,
  needsAnalysis,
  valueProposition,
  negotiationReview,
  closedWon,
  closedLost,
}

extension CrmSalesStageValue on CrmSalesStage {
  String get value {
    switch (this) {
      case CrmSalesStage.prospecting:
        return 'prospecting';
      case CrmSalesStage.qualification:
        return 'qualification';
      case CrmSalesStage.needsAnalysis:
        return 'needs_analysis';
      case CrmSalesStage.valueProposition:
        return 'value_proposition';
      case CrmSalesStage.negotiationReview:
        return 'negotiation_review';
      case CrmSalesStage.closedWon:
        return 'closed_won';
      case CrmSalesStage.closedLost:
        return 'closed_lost';
    }
  }

  int get probability {
    switch (this) {
      case CrmSalesStage.prospecting:
        return 10;
      case CrmSalesStage.qualification:
        return 25;
      case CrmSalesStage.needsAnalysis:
        return 40;
      case CrmSalesStage.valueProposition:
        return 55;
      case CrmSalesStage.negotiationReview:
        return 75;
      case CrmSalesStage.closedWon:
        return 100;
      case CrmSalesStage.closedLost:
        return 0;
    }
  }
}

CrmSalesStage crmSalesStageFromValue(String? value) {
  return CrmSalesStage.values.firstWhere(
    (stage) => stage.value == value,
    orElse: () => CrmSalesStage.prospecting,
  );
}

class CrmOpportunity {
  const CrmOpportunity({
    required this.id,
    required this.companyId,
    required this.accountId,
    required this.accountName,
    required this.name,
    required this.amount,
    required this.salesStage,
    required this.nextFollowUpAt,
    this.probability,
    this.leadSource,
    this.opportunityType,
    this.nextStep,
    this.dateClosed,
    this.campaignId,
    this.territoryId,
    this.assignedUserId,
    this.linkedSaleId,
    this.entityType = 'comercial',
    this.createdAt,
    this.modifiedAt,
  });

  final String id;
  final int? companyId;
  final int accountId;
  final String accountName;
  final String name;
  final MoneyValue amount;
  final CrmSalesStage salesStage;
  final DateTime nextFollowUpAt;
  final int? probability;
  final String? leadSource;
  final String? opportunityType;
  final String? nextStep;
  final DateTime? dateClosed;
  final int? campaignId;
  final int? territoryId;
  final int? assignedUserId;
  final int? linkedSaleId;
  final String entityType;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  int get effectiveProbability => probability ?? salesStage.probability;

  Map<String, Object?> toPersistenceMap({
    int? companyIdOverride,
    int? accountIdOverride,
    String? accountNameOverride,
  }) {
    final stage = salesStage.value;
    final accountIdValue = accountIdOverride ?? accountId;
    final accountNameValue = accountNameOverride ?? accountName;
    final created = createdAt ?? DateTime.now();
    return {
      'id': id,
      'company_id': companyIdOverride ?? companyId,
      'customer_id': accountIdValue,
      'customer': accountNameValue,
      'value': amount.toSql(),
      'amount': amount.toSql(),
      'stage': stage,
      'next_follow_up_at': nextFollowUpAt.toIso8601String(),
      'owner': assignedUserId?.toString() ?? 'local',
      'name': name,
      'account_id': accountIdValue,
      'sales_stage': stage,
      'probability': effectiveProbability,
      'lead_source': leadSource,
      'opportunity_type': opportunityType,
      'next_step': nextStep,
      'date_closed': dateClosed?.toIso8601String(),
      'campaign_id': campaignId,
      'territory_id': territoryId,
      'assigned_user_id': assignedUserId,
      'linked_sale_id': linkedSaleId,
      'entity_type': entityType,
      'created_at': created.toIso8601String(),
      'modified_at': modifiedAt?.toIso8601String(),
    };
  }

  CrmOpportunity copyWith({
    CrmSalesStage? salesStage,
    int? probability,
    DateTime? dateClosed,
    int? linkedSaleId,
    DateTime? modifiedAt,
    int? campaignId,
    int? territoryId,
  }) {
    return CrmOpportunity(
      id: id,
      companyId: companyId,
      accountId: accountId,
      accountName: accountName,
      name: name,
      amount: amount,
      salesStage: salesStage ?? this.salesStage,
      nextFollowUpAt: nextFollowUpAt,
      probability: probability ?? this.probability,
      leadSource: leadSource,
      opportunityType: opportunityType,
      nextStep: nextStep,
      dateClosed: dateClosed ?? this.dateClosed,
      campaignId: campaignId ?? this.campaignId,
      territoryId: territoryId ?? this.territoryId,
      assignedUserId: assignedUserId,
      linkedSaleId: linkedSaleId ?? this.linkedSaleId,
      entityType: entityType,
      createdAt: createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  factory CrmOpportunity.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return CrmOpportunity(
      id: map['id'].toString(),
      companyId: (map['company_id'] as num?)?.toInt(),
      accountId:
          (map['account_id'] as num?)?.toInt() ??
          (map['customer_id'] as num?)?.toInt() ??
          0,
      accountName:
          map['customer']?.toString() ?? map['account_name']?.toString() ?? '',
      name: map['name']?.toString() ?? map['customer']?.toString() ?? '',
      amount: _opportunityMoney(map['amount'] ?? map['value'], currency),
      salesStage: crmSalesStageFromValue(
        map['sales_stage']?.toString() ?? map['stage']?.toString(),
      ),
      nextFollowUpAt:
          _opportunityDate(map['next_follow_up_at']) ?? DateTime.now(),
      probability: (map['probability'] as num?)?.toInt(),
      leadSource: map['lead_source']?.toString(),
      opportunityType: map['opportunity_type']?.toString(),
      nextStep: map['next_step']?.toString(),
      dateClosed: _opportunityDate(map['date_closed']),
      campaignId: (map['campaign_id'] as num?)?.toInt(),
      territoryId: (map['territory_id'] as num?)?.toInt(),
      assignedUserId: (map['assigned_user_id'] as num?)?.toInt(),
      linkedSaleId: (map['linked_sale_id'] as num?)?.toInt(),
      entityType: map['entity_type']?.toString() ?? 'comercial',
      createdAt: _opportunityDate(map['created_at']),
      modifiedAt: _opportunityDate(map['modified_at']),
    );
  }
}

DateTime? _opportunityDate(Object? value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text);
}

MoneyValue _opportunityMoney(Object? value, Currency currency) {
  if (value == null) {
    return MoneyValue(minorUnits: 0, currency: currency);
  }
  if (value is int) {
    return MoneyValue.fromSql(value, currency: currency);
  }
  if (value is num && value.toDouble() == value.toDouble().truncateToDouble()) {
    return MoneyValue(minorUnits: value.toInt(), currency: currency);
  }
  return MoneyValue.fromMajorUnits(value.toString(), currency: currency);
}
