import '../domain/journal_entry.dart';
import '../../core/currency/money_value.dart';

class LedgerAccountBalance {
  const LedgerAccountBalance({
    required this.accountCode,
    required this.debit,
    required this.credit,
  });

  final String accountCode;
  final MoneyValue debit;
  final MoneyValue credit;

  MoneyValue get balance => debit - credit;

  Map<String, Object?> toMap() => {
    'account_code': accountCode,
    'debit': debit.toSql(),
    'credit': credit.toSql(),
    'balance': balance.toSql(),
  };
}

class LedgerTrialBalance {
  const LedgerTrialBalance(this.accounts);

  final List<LedgerAccountBalance> accounts;

  MoneyValue get totalDebit => _sum((account) => account.debit);

  MoneyValue get totalCredit => _sum((account) => account.credit);

  MoneyValue _sum(MoneyValue Function(LedgerAccountBalance account) selector) {
    if (accounts.isEmpty) {
      throw StateError('El libro mayor requiere cuentas.');
    }
    final zero = MoneyValue(
      minorUnits: 0,
      currency: accounts.first.debit.currency,
    );
    return accounts.fold(zero, (sum, account) => sum + selector(account));
  }

  bool get balanced => totalDebit == totalCredit;

  Map<String, Object?> toMap() => {
    'accounts': accounts.map((account) => account.toMap()).toList(),
    'summary': {
      'total_debit': totalDebit.toSql(),
      'total_credit': totalCredit.toSql(),
      'balanced': balanced,
    },
  };
}

class LedgerEngine {
  const LedgerEngine();

  JournalEntry post(JournalEntry entry) => entry.post();

  JournalEntry reverse(
    JournalEntry entry, {
    required String reversalId,
    required String reversalConsecutive,
    required DateTime date,
  }) {
    return entry.reverse(
      reversalId: reversalId,
      reversalConsecutive: reversalConsecutive,
      date: date,
    );
  }

  LedgerTrialBalance trialBalance(List<JournalEntry> entries) {
    final totals = <String, ({MoneyValue debit, MoneyValue credit})>{};
    for (final entry in entries.where(
      (entry) => entry.status == JournalEntryStatus.posted,
    )) {
      for (final line in entry.lines) {
        final zero = MoneyValue(minorUnits: 0, currency: line.debit.currency);
        final current = totals[line.accountCode] ?? (debit: zero, credit: zero);
        totals[line.accountCode] = (
          debit: current.debit + line.localDebit,
          credit: current.credit + line.localCredit,
        );
      }
    }

    final accounts = [
      for (final entry in totals.entries)
        LedgerAccountBalance(
          accountCode: entry.key,
          debit: entry.value.debit,
          credit: entry.value.credit,
        ),
    ]..sort((a, b) => a.accountCode.compareTo(b.accountCode));
    return LedgerTrialBalance(accounts);
  }
}
