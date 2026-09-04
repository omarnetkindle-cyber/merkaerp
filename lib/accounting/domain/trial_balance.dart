import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class TrialBalanceAccount {
  const TrialBalanceAccount({
    required this.accountId,
    required this.code,
    required this.name,
    required this.type,
    required this.nature,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final int accountId;
  final String code;
  final String name;
  final String type;
  final String nature;
  final MoneyValue debit;
  final MoneyValue credit;
  final MoneyValue balance;

  factory TrialBalanceAccount.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return TrialBalanceAccount(
      accountId: (map['id'] as num?)?.toInt() ?? 0,
      code: map['codigo']?.toString() ?? '',
      name: map['nombre']?.toString() ?? '',
      type: map['tipo']?.toString() ?? '',
      nature: map['naturaleza']?.toString() ?? '',
      debit: MoneyValue.fromSql(
        map['debito'],
        currency: currency,
        nullableAsZero: true,
      ),
      credit: MoneyValue.fromSql(
        map['credito'],
        currency: currency,
        nullableAsZero: true,
      ),
      balance: MoneyValue.fromSql(
        map['saldo'],
        currency: currency,
        nullableAsZero: true,
      ),
    );
  }

  Map<String, Object?> toMap() => {
    'account_id': accountId,
    'code': code,
    'name': name,
    'type': type,
    'nature': nature,
    'debit': debit.toSql(),
    'credit': credit.toSql(),
    'balance': balance.toSql(),
  };
}

class TrialBalance {
  const TrialBalance({required this.accounts});

  final List<TrialBalanceAccount> accounts;

  MoneyValue get totalDebit => _sum((account) => account.debit);

  MoneyValue get totalCredit => _sum((account) => account.credit);

  MoneyValue get difference => totalDebit - totalCredit;

  MoneyValue _sum(MoneyValue Function(TrialBalanceAccount account) selector) {
    if (accounts.isEmpty) {
      throw StateError('El balance de prueba requiere cuentas.');
    }
    final zero = MoneyValue(
      minorUnits: 0,
      currency: accounts.first.debit.currency,
    );
    return accounts.fold(zero, (sum, account) => sum + selector(account));
  }

  bool get balanced => difference.minorUnits == 0;

  Map<String, Object?> toMap() => {
    'accounts': accounts.map((account) => account.toMap()).toList(),
    'summary': {
      'total_debit': totalDebit.toSql(),
      'total_credit': totalCredit.toSql(),
      'difference': difference.toSql(),
      'balanced': balanced,
    },
  };
}
