import '../../core/company/company_context.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../data/crm_opportunity_item_repository.dart';
import '../domain/crm_opportunity_item.dart';

class CrmOpportunityItemService {
  CrmOpportunityItemService({
    CrmOpportunityItemRepository? repository,
    CompanyContextProvider? companyContext,
  }) : _repository = repository ?? SqliteCrmOpportunityItemRepository(),
       _companyContext = companyContext ?? CompanyContextService.instance;

  final CrmOpportunityItemRepository _repository;
  final CompanyContextProvider _companyContext;

  Future<List<CrmOpportunityItem>> listForOpportunity(String opportunityId) =>
      _repository.findByOpportunity(opportunityId);

  Future<int> save(CrmOpportunityItem item) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    if (item.opportunityId.trim().isEmpty) {
      throw ArgumentError('La linea requiere una oportunidad.');
    }
    if (item.productId <= 0) {
      throw ArgumentError('La linea requiere un producto valido.');
    }
    if (!item.quantity.isFinite || item.quantity <= 0) {
      throw ArgumentError('La cantidad del producto debe ser mayor que cero.');
    }
    if (item.unitPrice.minorUnits < 0) {
      throw ArgumentError('El precio unitario no puede ser negativo.');
    }
    final companyId = (await _companyContext.current()).companyId;
    final db = await DatabaseHelper.instance.database;
    final opportunity = await db.query(
      'crm_opportunities',
      columns: ['id'],
      where: 'id = ? AND company_id = ?',
      whereArgs: [item.opportunityId, companyId],
      limit: 1,
    );
    if (opportunity.isEmpty) {
      throw StateError('La oportunidad no existe en la empresa activa.');
    }
    final product = await db.query(
      'productos',
      columns: ['id'],
      where: 'id = ? AND company_id = ?',
      whereArgs: [item.productId, companyId],
      limit: 1,
    );
    if (product.isEmpty) {
      throw StateError('El producto no existe en la empresa activa.');
    }
    return _repository.save(item);
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    await _repository.delete(id);
  }
}
