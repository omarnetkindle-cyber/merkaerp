import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../data/crm_account_repository.dart';
import '../data/crm_contact_repository.dart';
import '../domain/crm_contact.dart';

class CrmContactService {
  CrmContactService({
    CrmContactRepository? repository,
    CrmAccountRepository? accountRepository,
  }) : _repository = repository ?? SqliteCrmContactRepository(),
       _accountRepository = accountRepository ?? SqliteCrmAccountRepository();

  final CrmContactRepository _repository;
  final CrmAccountRepository _accountRepository;

  Future<int> create(CrmContact contact) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    _validate(contact);
    await _requireAccount(contact.accountId);
    await _requireReportsTo(contact);
    if (contact.reportsToId == contact.id && contact.id != null) {
      throw ArgumentError('Un contacto no puede reportarse a si mismo.');
    }
    return _repository.save(contact);
  }

  Future<void> update(CrmContact contact) async {
    if (contact.id == null) {
      throw ArgumentError('El contacto debe tener id para actualizarse.');
    }
    await DatabaseHelper.instance.validarFeatureHabilitada(FeatureKey.crm);
    _validate(contact);
    await _requireAccount(contact.accountId);
    await _requireReportsTo(contact);
    await _repository.save(contact);
  }

  Future<List<CrmContact>> listForAccount(int accountId) =>
      _repository.findByAccount(accountId);

  Future<void> _requireAccount(int accountId) async {
    if (await _accountRepository.findById(accountId) == null) {
      throw StateError('La cuenta CRM no existe en la empresa activa.');
    }
  }

  void _validate(CrmContact contact) {
    if (contact.firstName.trim().isEmpty) {
      throw ArgumentError('El contacto CRM requiere nombre.');
    }
    if (contact.accountId <= 0) {
      throw ArgumentError('El contacto CRM requiere una cuenta valida.');
    }
  }

  Future<void> _requireReportsTo(CrmContact contact) async {
    final reportsToId = contact.reportsToId;
    if (reportsToId == null) return;
    if (contact.id != null && reportsToId == contact.id) {
      throw ArgumentError('Un contacto no puede reportarse a si mismo.');
    }
    final manager = await _repository.findById(reportsToId);
    if (manager == null || manager.accountId != contact.accountId) {
      throw StateError(
        'El contacto supervisor no existe en la misma cuenta CRM.',
      );
    }
  }
}
