import '../../core/company/company_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../domain/customer_interaction.dart';

abstract class CrmInteractionRepository {
  Future<List<CustomerInteraction>> findByCustomer(int customerId);
  Future<int> save(CustomerInteraction interaction);
}

class SqliteCrmInteractionRepository implements CrmInteractionRepository {
  SqliteCrmInteractionRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenant = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );

  final TenantDatabaseGateway _tenant;

  @override
  Future<List<CustomerInteraction>> findByCustomer(int customerId) async {
    final rows = await _tenant.query(
      'crm_interactions',
      query: TenantQuery(
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'interaction_date DESC',
      ),
    );
    return rows.map(CustomerInteraction.fromMap).toList();
  }

  @override
  Future<int> save(CustomerInteraction interaction) async {
    final values = interaction.toMap()..remove('company_id');
    values.remove('id');
    return _tenant.insert('crm_interactions', values);
  }
}
