import '../../core/branch/branch_context.dart';
import '../../core/events/domain_event.dart';
import '../data/journal_entry_repository.dart';
import '../domain/journal_entry.dart';
import 'ledger_engine.dart';

class AccountingPostingService {
  AccountingPostingService({
    LedgerEngine ledger = const LedgerEngine(),
    JournalEntryRepository? repository,
    BranchScopeProvider? scopeProvider,
    DomainEventPublisher events = const NoopDomainEventPublisher(),
  }) : _ledger = ledger,
       _repository = repository ?? SqliteJournalEntryRepository(),
       _scopeProvider = scopeProvider ?? BranchContextService.instance,
       _events = events;

  final LedgerEngine _ledger;
  final JournalEntryRepository _repository;
  final BranchScopeProvider _scopeProvider;
  final DomainEventPublisher _events;

  Future<JournalEntry> post(JournalEntry draft) async {
    final scope = await _scopeProvider.current();
    final posted = _ledger.post(draft);
    await _repository.savePosted(posted, scope: scope);
    await _events.publish(
      IntegrationEvent(
        name: 'accounting.journal_posted',
        payload: {
          'aggregate_type': 'journal_entry',
          'aggregate_id': posted.id,
          'journal_entry_id': posted.id,
          'consecutive': posted.consecutive,
          'total_debit': posted.totalDebit.toWireMap(),
          'total_credit': posted.totalCredit.toWireMap(),
          'company_id': scope.companyId,
          'branch_id': scope.branchId,
          'correlation_id': posted.correlationId,
        },
      ),
    );
    return posted;
  }

  Future<JournalEntry> reverse(
    JournalEntry posted, {
    required String reversalId,
    required String reversalConsecutive,
    required DateTime date,
  }) async {
    final scope = await _scopeProvider.current();
    final reversal = _ledger.reverse(
      posted,
      reversalId: reversalId,
      reversalConsecutive: reversalConsecutive,
      date: date,
    );
    await _repository.savePosted(reversal, scope: scope);
    await _events.publish(
      IntegrationEvent(
        name: 'accounting.journal_reversed',
        payload: {
          'aggregate_type': 'journal_entry',
          'aggregate_id': posted.id,
          'journal_entry_id': posted.id,
          'reversal_entry_id': reversal.id,
          'reversal_consecutive': reversal.consecutive,
          'company_id': scope.companyId,
          'branch_id': scope.branchId,
          'correlation_id': posted.correlationId,
        },
      ),
    );
    return reversal;
  }

  Future<LedgerTrialBalance> trialBalance({
    required int companyId,
    required int branchId,
    DateTime? from,
    DateTime? to,
  }) async {
    final entries = await _repository.findPosted(
      companyId: companyId,
      branchId: branchId,
      from: from,
      to: to,
    );
    return _ledger.trialBalance(entries);
  }
}
