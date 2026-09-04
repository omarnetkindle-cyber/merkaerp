import 'package:sqflite/sqflite.dart';

import '../../core/currency/money_currency_resolver.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../domain/crm_campaign.dart';

class CrmCampaignService {
  Future<int> create(CrmCampaign campaign) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    if (campaign.name.trim().isEmpty) {
      throw ArgumentError('El nombre de la campana CRM es obligatorio.');
    }
    if (campaign.campaignType.trim().isEmpty) {
      throw ArgumentError('El tipo de campana CRM es obligatorio.');
    }
    if (campaign.budget.minorUnits < 0 ||
        campaign.expectedRevenue.minorUnits < 0) {
      throw ArgumentError(
        'Presupuesto e ingreso esperado no pueden ser negativos.',
      );
    }
    final db = await DatabaseHelper.instance.database;
    return db.insert(
      'crm_campaigns',
      campaign.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }


  Future<int> createForCustomers(CrmCampaign campaign, List<int> customerIds) async {
    if (customerIds.isEmpty) throw ArgumentError('La campaña debe tener al menos un cliente objetivo.');
    final db = await DatabaseHelper.instance.database;
    await db.execute("""
      CREATE TABLE IF NOT EXISTS crm_campaign_customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        campaign_id INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'target',
        contacted_at TEXT,
        result TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(company_id, campaign_id, customer_id)
      )
    """);
    final campaignId = await create(campaign);
    await db.transaction((txn) async {
      for (final customerId in customerIds.toSet()) {
        await txn.insert('crm_campaign_customers', {
          'company_id': campaign.companyId,
          'campaign_id': campaignId,
          'customer_id': customerId,
          'status': 'target',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CREAR_CAMPANA_CRM_SEGMENTO',
      entidad: 'crm_campaigns',
      entidadId: campaignId,
      detalle: '${campaign.name} · ${customerIds.toSet().length} cliente(s) objetivo. Ningún mensaje fue enviado automáticamente.',
    );
    return campaignId;
  }

  Future<List<CrmCampaign>> list() async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final rows = await db.query(
      'crm_campaigns',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'start_date DESC',
    );
    return rows.map((row) => CrmCampaign.fromMap(row, currency)).toList();
  }

  Future<void> attachLead({
    required int campaignId,
    required int leadId,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await _requireCampaign(db, companyId, campaignId);
    final updated = await db.update(
      'crm_leads',
      {
        'campaign_id': campaignId,
        'modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [leadId, companyId],
    );
    if (updated == 0) throw StateError('Lead CRM no encontrado para campana.');
  }

  Future<void> attachOpportunity({
    required int campaignId,
    required String opportunityId,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await _requireCampaign(db, companyId, campaignId);
    final updated = await db.update(
      'crm_opportunities',
      {
        'campaign_id': campaignId,
        'modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [opportunityId, companyId],
    );
    if (updated == 0) {
      throw StateError('Oportunidad CRM no encontrada para campana.');
    }
  }

  Future<void> _requireCampaign(
    Database db,
    int companyId,
    int campaignId,
  ) async {
    final rows = await db.query(
      'crm_campaigns',
      where: 'id = ? AND company_id = ?',
      whereArgs: [campaignId, companyId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Campana CRM no encontrada.');
  }
}
