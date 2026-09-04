import '../data/accounting_report_repository.dart';
import '../domain/trial_balance.dart';

class AccountingReportService {
  AccountingReportService({AccountingReportRepository? repository})
    : _repository = repository ?? SqliteAccountingReportRepository();

  final AccountingReportRepository _repository;

  Future<TrialBalance> trialBalance() async {
    return _repository.trialBalance();
  }
}
