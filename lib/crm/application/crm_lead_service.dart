import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../data/crm_lead_repository.dart';
import '../domain/crm_account.dart';
import '../domain/crm_contact.dart';
import '../domain/crm_lead.dart';
import '../domain/crm_opportunity.dart';

class CrmLeadConversionResult {
  const CrmLeadConversionResult({
    required this.accountId,
    required this.contactId,
    required this.opportunityId,
  });

  final int accountId;
  final int contactId;
  final String opportunityId;
}

class CrmLeadService {
  CrmLeadService({
    CrmLeadRepository? repository,
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _repository = repository ?? SqliteCrmLeadRepository(),
       _gateway = gateway,
       _companyContext = companyContext ?? CompanyContextService.instance;

  final CrmLeadRepository _repository;
  final DatabaseGateway _gateway;
  final CompanyContextProvider _companyContext;

  Future<int> create(CrmLead lead) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    if ((lead.accountName ?? '').trim().isEmpty) {
      throw ArgumentError('El lead requiere nombre de cuenta.');
    }
    if (lead.opportunityAmount.minorUnits < 0) {
      throw ArgumentError('El monto estimado del lead no puede ser negativo.');
    }
    return _repository.save(lead);
  }

  Future<List<CrmLead>> list() => _repository.findAll();

  Future<CrmLead?> findById(int id) => _repository.findById(id);

  Future<CrmLeadConversionResult> convert({
    required int leadId,
    required CrmAccount account,
    required CrmContact contact,
    required CrmOpportunity opportunity,
  }) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    final companyId = (await _companyContext.current()).companyId;
    if (account.id != null || contact.id != null) {
      throw ArgumentError(
        'La conversion crea una cuenta y un contacto nuevos.',
      );
    }
    if (account.name.trim().isEmpty) {
      throw ArgumentError('La cuenta resultante requiere un nombre.');
    }
    if (contact.firstName.trim().isEmpty) {
      throw ArgumentError('El contacto resultante requiere nombre.');
    }
    if (opportunity.name.trim().isEmpty) {
      throw ArgumentError('La oportunidad resultante requiere un nombre.');
    }
    if (opportunity.amount.minorUnits < 0) {
      throw ArgumentError('El monto de la oportunidad no puede ser negativo.');
    }

    return _gateway.transaction((txn) async {
      final leadRows = await txn.query(
        'crm_leads',
        where: 'id = ? AND company_id = ?',
        whereArgs: [leadId, companyId],
        limit: 1,
      );
      if (leadRows.isEmpty) {
        throw StateError('El lead no existe en la empresa activa.');
      }
      if ((leadRows.first['converted'] as num?)?.toInt() == 1) {
        throw StateError('El lead ya fue convertido.');
      }
      final status = leadRows.first['status']?.toString().toLowerCase();
      if (const {
        'no_convertible',
        'descartado',
        'rechazado',
      }.contains(status)) {
        throw StateError('El lead esta marcado como no convertible.');
      }

      final accountId = await txn.insert(
        'clientes',
        account.toPersistenceMap(companyIdOverride: companyId)..remove('id'),
      );
      final contactId = await txn.insert(
        'crm_contacts',
        contact.toPersistenceMap(
          companyIdOverride: companyId,
          accountIdOverride: accountId,
        )..remove('id'),
      );
      final opportunityId = opportunity.id.isEmpty
          ? 'CRM-${DateTime.now().microsecondsSinceEpoch}'
          : opportunity.id;
      final opportunityValues = opportunity.toPersistenceMap(
        companyIdOverride: companyId,
        accountIdOverride: accountId,
        accountNameOverride: account.name,
      )..['id'] = opportunityId;
      await txn.insert('crm_opportunities', opportunityValues);
      await txn.update(
        'crm_leads',
        {
          'converted': 1,
          'converted_account_id': accountId,
          'converted_opportunity_id': opportunityId,
          'contact_id': contactId,
          'status': 'convertido',
          'modified_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND company_id = ?',
        whereArgs: [leadId, companyId],
      );

      return CrmLeadConversionResult(
        accountId: accountId,
        contactId: contactId,
        opportunityId: opportunityId,
      );
    });
  }
}
