import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/crm/application/crm_account_service.dart';
import 'package:merka_erp/crm/application/crm_campaign_service.dart';
import 'package:merka_erp/crm/application/crm_lead_service.dart';
import 'package:merka_erp/crm/application/crm_opportunity_service.dart';
import 'package:merka_erp/crm/application/crm_sales_analytics_service.dart';
import 'package:merka_erp/crm/application/crm_territory_service.dart';
import 'package:merka_erp/crm/domain/crm_account.dart';
import 'package:merka_erp/crm/domain/crm_campaign.dart';
import 'package:merka_erp/crm/domain/crm_lead.dart';
import 'package:merka_erp/crm/domain/crm_opportunity.dart';
import 'package:merka_erp/crm/domain/crm_territory.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late int companyId;
  late Currency cop;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_crm_backlog_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await DatabaseHelper.instance.guardarCompanySettings(companyId, {
      'onboarding_completed': '1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
      'crm_enabled': '1',
    });
    cop = Currency(
      code: 'COP',
      name: 'Colombian Peso',
      symbol: r'$',
      decimalPlaces: 2,
    );
  });

  tearDownAll(() async {
    await DatabaseHelper.resetForTests();
    await dbDir.delete(recursive: true);
  });

  test(
    'campanas, territorios, forecasting y embudo usan datos reales',
    () async {
      final campaignId = await CrmCampaignService().create(
        CrmCampaign(
          companyId: companyId,
          name: 'Feria agroindustrial',
          campaignType: 'evento',
          status: 'active',
          startDate: DateTime(2026, 8, 1),
          budget: MoneyValue.fromMajorUnits('250.00', currency: cop),
          expectedRevenue: MoneyValue.fromMajorUnits('5000.00', currency: cop),
          assignedUserId: 7,
        ),
      );
      final territoryId = await CrmTerritoryService().create(
        CrmTerritory(
          companyId: companyId,
          name: 'Antioquia alimentos',
          country: 'Colombia',
          department: 'Antioquia',
          sector: 'Alimentos',
          assignedUserId: 7,
        ),
      );
      final accountId = await CrmAccountService().create(
        CrmAccount(companyId: companyId, name: 'Cliente territorial'),
      );
      await CrmTerritoryService().assignAccount(
        territoryId: territoryId,
        accountId: accountId,
      );
      final leadUno = await CrmLeadService().create(
        CrmLead(
          companyId: companyId,
          accountName: 'Lead convertido',
          leadSource: 'Feria',
          opportunityAmount: MoneyValue.fromMajorUnits(
            '1000.00',
            currency: cop,
          ),
        ),
      );
      final leadDos = await CrmLeadService().create(
        CrmLead(
          companyId: companyId,
          accountName: 'Lead abierto',
          leadSource: 'Feria',
          opportunityAmount: MoneyValue.fromMajorUnits('500.00', currency: cop),
        ),
      );

      await CrmCampaignService().attachLead(
        campaignId: campaignId,
        leadId: leadUno,
      );
      await CrmCampaignService().attachLead(
        campaignId: campaignId,
        leadId: leadDos,
      );
      await CrmTerritoryService().assignLead(
        territoryId: territoryId,
        leadId: leadUno,
      );
      await CrmTerritoryService().assignLead(
        territoryId: territoryId,
        leadId: leadDos,
      );

      final openOpportunityId = await CrmOpportunityService().create(
        CrmOpportunity(
          id: 'crm-forecast-open',
          companyId: companyId,
          accountId: accountId,
          accountName: 'Cliente territorial',
          name: 'Linea abierta',
          amount: MoneyValue.fromMajorUnits('1000.00', currency: cop),
          salesStage: CrmSalesStage.negotiationReview,
          nextFollowUpAt: DateTime(2026, 8, 20),
        ),
      );
      final wonOpportunityId = await CrmOpportunityService().create(
        CrmOpportunity(
          id: 'crm-forecast-won',
          companyId: companyId,
          accountId: accountId,
          accountName: 'Cliente territorial',
          name: 'Linea ganada',
          amount: MoneyValue.fromMajorUnits('500.00', currency: cop),
          salesStage: CrmSalesStage.closedWon,
          nextFollowUpAt: DateTime(2026, 8, 21),
        ),
      );
      for (final opportunityId in [openOpportunityId, wonOpportunityId]) {
        await CrmCampaignService().attachOpportunity(
          campaignId: campaignId,
          opportunityId: opportunityId,
        );
        await CrmTerritoryService().assignOpportunity(
          territoryId: territoryId,
          opportunityId: opportunityId,
        );
      }
      await db.update(
        'crm_leads',
        {
          'converted': 1,
          'converted_opportunity_id': wonOpportunityId,
          'converted_account_id': accountId,
          'status': 'convertido',
        },
        where: 'id = ?',
        whereArgs: [leadUno],
      );

      final accountRow = (await db.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [accountId],
      )).single;
      expect(accountRow['territory_id'], territoryId);
      expect(accountRow['assigned_user_id'], 7);

      final forecast = await CrmSalesAnalyticsService().forecast(
        campaignId: campaignId,
        territoryId: territoryId,
      );
      expect(forecast.totalOpenPipeline.minorUnits, 100000);
      expect(forecast.weightedOpenPipeline.minorUnits, 75000);
      expect(forecast.closedWon.minorUnits, 50000);
      expect(
        forecast.byStage[CrmSalesStage.negotiationReview]?.minorUnits,
        100000,
      );
      expect(forecast.byStage[CrmSalesStage.closedWon]?.minorUnits, 50000);

      final funnel = await CrmSalesAnalyticsService().funnel(
        campaignId: campaignId,
        territoryId: territoryId,
      );
      expect(funnel.leads, 2);
      expect(funnel.convertedLeads, 1);
      expect(funnel.opportunities, 2);
      expect(funnel.closedWonOpportunities, 1);
      expect(funnel.leadToOpportunityRate, 50);
      expect(funnel.opportunityToWonRate, 50);
    },
  );

  test(
    'CRM backlog bloquea datos invalidos con mensajes especificos',
    () async {
      await expectLater(
        () => CrmCampaignService().create(
          CrmCampaign(
            companyId: companyId,
            name: '',
            campaignType: 'evento',
            startDate: DateTime(2026, 8, 1),
            budget: MoneyValue(minorUnits: 0, currency: cop),
            expectedRevenue: MoneyValue(minorUnits: 0, currency: cop),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => CrmTerritoryService().create(
          CrmTerritory(companyId: companyId, name: ''),
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => CrmTerritoryService().assignOpportunity(
          territoryId: 999999,
          opportunityId: 'no-existe',
        ),
        throwsStateError,
      );
    },
  );
}
