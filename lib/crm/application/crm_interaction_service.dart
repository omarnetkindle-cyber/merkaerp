import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../data/crm_interaction_repository.dart';
import '../domain/customer_interaction.dart';

class CrmInteractionService {
  CrmInteractionService({CrmInteractionRepository? repository})
    : _repository = repository ?? SqliteCrmInteractionRepository();

  final CrmInteractionRepository _repository;

  Future<int> create(CustomerInteraction interaction) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    if (interaction.customerId <= 0) {
      throw ArgumentError('La interaccion requiere una cuenta CRM valida.');
    }
    if (interaction.subject.trim().isEmpty) {
      throw ArgumentError('La interaccion requiere un asunto.');
    }
    if (interaction.interactionType.trim().isEmpty) {
      throw ArgumentError('La interaccion requiere un tipo.');
    }
    return _repository.save(interaction);
  }

  Future<List<CustomerInteraction>> listForCustomer(int customerId) =>
      _repository.findByCustomer(customerId);
}
