import '../../core/company/company_context.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import 'crm_account_service.dart';
import '../data/crm_opportunity_repository.dart';
import '../domain/crm_opportunity.dart';

class CrmOpportunityService {
  CrmOpportunityService({
    CrmOpportunityRepository? repository,
    CompanyContextProvider? companyContext,
  }) : _repository = repository ?? SqliteCrmOpportunityRepository(),
       _companyContext = companyContext ?? CompanyContextService.instance;

  final CrmOpportunityRepository _repository;
  final CompanyContextProvider _companyContext;

  Future<String> create(CrmOpportunity opportunity) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    if (opportunity.accountId <= 0) {
      throw ArgumentError('La oportunidad requiere una cuenta CRM.');
    }
    if (opportunity.name.trim().isEmpty) {
      throw ArgumentError('La oportunidad requiere un nombre.');
    }
    if (opportunity.amount.minorUnits < 0) {
      throw ArgumentError('El monto de la oportunidad no puede ser negativo.');
    }
    if (await CrmAccountService().findById(opportunity.accountId) == null) {
      throw StateError('La cuenta CRM no existe en la empresa activa.');
    }
    return _repository.save(
      opportunity.copyWith(probability: opportunity.salesStage.probability),
    );
  }

  Future<List<CrmOpportunity>> list() => _repository.findAll();

  Future<List<CrmOpportunity>> listForAccount(int accountId) {
    if (accountId <= 0) {
      throw ArgumentError('La cuenta CRM debe tener un identificador valido.');
    }
    return _repository.findByAccount(accountId);
  }

  Future<CrmOpportunity?> findById(String id) => _repository.findById(id);

  Future<void> moveToStage(String id, CrmSalesStage next) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final current = await _repository.findById(id);
    if (current == null) {
      throw StateError('La oportunidad no existe en la empresa activa.');
    }
    if (current.salesStage == CrmSalesStage.closedWon ||
        current.salesStage == CrmSalesStage.closedLost) {
      throw StateError('Una oportunidad cerrada no puede cambiar de etapa.');
    }
    if (next != CrmSalesStage.closedLost &&
        next.index < current.salesStage.index) {
      throw StateError('La etapa de oportunidad no puede retroceder.');
    }
    await _repository.update(
      current.copyWith(
        salesStage: next,
        probability: next.probability,
        modifiedAt: DateTime.now(),
      ),
    );
  }

  Future<void> linkClosedWonToSale({
    required String opportunityId,
    required int saleId,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final opportunity = await _repository.findById(opportunityId);
    if (opportunity == null) {
      throw StateError('La oportunidad no existe en la empresa activa.');
    }
    if (opportunity.salesStage != CrmSalesStage.closedWon) {
      throw StateError(
        'Solo una oportunidad Closed Won puede enlazar una venta.',
      );
    }
    final db = await DatabaseHelper.instance.database;
    final companyId = (await _companyContext.current()).companyId;
    final sale = await db.query(
      'ventas',
      columns: ['id'],
      where: 'id = ? AND company_id = ?',
      whereArgs: [saleId, companyId],
      limit: 1,
    );
    if (sale.isEmpty) {
      throw StateError('La venta no existe en la empresa activa.');
    }
    await _repository.update(
      opportunity.copyWith(linkedSaleId: saleId, modifiedAt: DateTime.now()),
    );
  }
}
