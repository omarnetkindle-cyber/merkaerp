import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../domain/crm_territory.dart';

class CrmTerritoryService {
  Future<int> create(CrmTerritory territory) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    if (territory.name.trim().isEmpty) {
      throw ArgumentError('El nombre del territorio CRM es obligatorio.');
    }
    final db = await DatabaseHelper.instance.database;
    return db.insert(
      'crm_territories',
      territory.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<CrmTerritory>> list() async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final rows = await db.query(
      'crm_territories',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'name ASC',
    );
    return rows.map(CrmTerritory.fromMap).toList();
  }

  Future<void> assignAccount({
    required int territoryId,
    required int accountId,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final territory = await _requireTerritory(db, companyId, territoryId);
    final values = <String, Object?>{
      'territory_id': territoryId,
      'modified_at': DateTime.now().toIso8601String(),
    };
    if (territory.assignedUserId != null) {
      values['assigned_user_id'] = territory.assignedUserId;
    }
    final updated = await db.update(
      'clientes',
      values,
      where: 'id = ? AND company_id = ?',
      whereArgs: [accountId, companyId],
    );
    if (updated == 0) throw StateError('Cuenta CRM no encontrada.');
  }

  Future<void> assignLead({
    required int territoryId,
    required int leadId,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await _requireTerritory(db, companyId, territoryId);
    final updated = await db.update(
      'crm_leads',
      {
        'territory_id': territoryId,
        'modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [leadId, companyId],
    );
    if (updated == 0) throw StateError('Lead CRM no encontrado.');
  }

  Future<void> assignOpportunity({
    required int territoryId,
    required String opportunityId,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await _requireTerritory(db, companyId, territoryId);
    final updated = await db.update(
      'crm_opportunities',
      {
        'territory_id': territoryId,
        'modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [opportunityId, companyId],
    );
    if (updated == 0) throw StateError('Oportunidad CRM no encontrada.');
  }

  Future<CrmTerritory> _requireTerritory(
    Database db,
    int companyId,
    int territoryId,
  ) async {
    final rows = await db.query(
      'crm_territories',
      where: 'id = ? AND company_id = ? AND active = 1',
      whereArgs: [territoryId, companyId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Territorio CRM no encontrado.');
    return CrmTerritory.fromMap(rows.single);
  }
}
