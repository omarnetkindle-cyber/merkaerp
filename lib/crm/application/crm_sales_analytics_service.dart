import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../domain/crm_opportunity.dart';

class CrmForecastSummary {
  const CrmForecastSummary({
    required this.totalOpenPipeline,
    required this.weightedOpenPipeline,
    required this.closedWon,
    required this.byStage,
  });

  final MoneyValue totalOpenPipeline;
  final MoneyValue weightedOpenPipeline;
  final MoneyValue closedWon;
  final Map<CrmSalesStage, MoneyValue> byStage;
}

class CrmFunnelSummary {
  const CrmFunnelSummary({
    required this.leads,
    required this.convertedLeads,
    required this.opportunities,
    required this.closedWonOpportunities,
  });

  final int leads;
  final int convertedLeads;
  final int opportunities;
  final int closedWonOpportunities;

  double get leadToOpportunityRate =>
      leads == 0 ? 0 : convertedLeads / leads * 100;

  double get opportunityToWonRate =>
      opportunities == 0 ? 0 : closedWonOpportunities / opportunities * 100;
}

class CrmSalesAnalyticsService {
  Future<CrmForecastSummary> forecast({
    DateTime? from,
    DateTime? to,
    int? assignedUserId,
    int? territoryId,
    int? campaignId,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    var where = 'company_id = ?';
    final args = <Object?>[companyId];
    if (from != null) {
      where += ' AND date(next_follow_up_at) >= date(?)';
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where += ' AND date(next_follow_up_at) <= date(?)';
      args.add(to.toIso8601String());
    }
    if (assignedUserId != null) {
      where += ' AND assigned_user_id = ?';
      args.add(assignedUserId);
    }
    if (territoryId != null) {
      where += ' AND territory_id = ?';
      args.add(territoryId);
    }
    if (campaignId != null) {
      where += ' AND campaign_id = ?';
      args.add(campaignId);
    }

    final rows = await db.query(
      'crm_opportunities',
      where: where,
      whereArgs: args,
    );

    var totalOpen = zero;
    var weightedOpen = zero;
    var closedWon = zero;
    final byStage = {for (final stage in CrmSalesStage.values) stage: zero};

    for (final row in rows) {
      final stage = crmSalesStageFromValue(
        row['sales_stage']?.toString() ?? row['stage']?.toString(),
      );
      final amount = MoneyValue.fromSql(
        row['amount'] ?? row['value'],
        currency: currency,
        nullableAsZero: true,
      );
      byStage[stage] = byStage[stage]! + amount;
      if (stage == CrmSalesStage.closedWon) {
        closedWon += amount;
        continue;
      }
      if (stage == CrmSalesStage.closedLost) continue;
      final probability =
          (row['probability'] as num?)?.toInt() ?? stage.probability;
      totalOpen += amount;
      weightedOpen += amount.multiplyRatio(
        numerator: probability,
        denominator: 100,
      );
    }

    return CrmForecastSummary(
      totalOpenPipeline: totalOpen,
      weightedOpenPipeline: weightedOpen,
      closedWon: closedWon,
      byStage: byStage,
    );
  }

  Future<CrmFunnelSummary> funnel({
    DateTime? from,
    DateTime? to,
    int? campaignId,
    int? territoryId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    var leadWhere = 'company_id = ?';
    var opportunityWhere = 'company_id = ?';
    final leadArgs = <Object?>[companyId];
    final opportunityArgs = <Object?>[companyId];

    if (from != null) {
      leadWhere += ' AND date(created_at) >= date(?)';
      opportunityWhere += ' AND date(created_at) >= date(?)';
      leadArgs.add(from.toIso8601String());
      opportunityArgs.add(from.toIso8601String());
    }
    if (to != null) {
      leadWhere += ' AND date(created_at) <= date(?)';
      opportunityWhere += ' AND date(created_at) <= date(?)';
      leadArgs.add(to.toIso8601String());
      opportunityArgs.add(to.toIso8601String());
    }
    if (campaignId != null) {
      leadWhere += ' AND campaign_id = ?';
      opportunityWhere += ' AND campaign_id = ?';
      leadArgs.add(campaignId);
      opportunityArgs.add(campaignId);
    }
    if (territoryId != null) {
      leadWhere += ' AND territory_id = ?';
      opportunityWhere += ' AND territory_id = ?';
      leadArgs.add(territoryId);
      opportunityArgs.add(territoryId);
    }

    final leadRows = await db.query(
      'crm_leads',
      columns: ['converted'],
      where: leadWhere,
      whereArgs: leadArgs,
    );
    final opportunityRows = await db.query(
      'crm_opportunities',
      columns: ['sales_stage', 'stage'],
      where: opportunityWhere,
      whereArgs: opportunityArgs,
    );

    final converted = leadRows
        .where((row) => (row['converted'] as num?)?.toInt() == 1)
        .length;
    final closedWon = opportunityRows.where((row) {
      final stage = crmSalesStageFromValue(
        row['sales_stage']?.toString() ?? row['stage']?.toString(),
      );
      return stage == CrmSalesStage.closedWon;
    }).length;

    return CrmFunnelSummary(
      leads: leadRows.length,
      convertedLeads: converted,
      opportunities: opportunityRows.length,
      closedWonOpportunities: closedWon,
    );
  }
}
