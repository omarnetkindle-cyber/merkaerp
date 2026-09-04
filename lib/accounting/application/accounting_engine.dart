import '../../core/currency/money_value.dart';

class AccountingLineDraft {
  const AccountingLineDraft({
    required this.accountCode,
    required this.debit,
    required this.credit,
    required this.description,
    this.thirdParty,
  });

  final String accountCode;
  final MoneyValue debit;
  final MoneyValue credit;
  final String description;
  final String? thirdParty;

  Map<String, dynamic> toLegacyMap() => {
    'codigo': accountCode,
    'debito': debit.toSql(),
    'credito': credit.toSql(),
    'descripcion': description,
    'tercero': thirdParty,
  };
}

class AccountingEntryDraft {
  const AccountingEntryDraft({
    required this.concept,
    required this.reference,
    required this.origin,
    required this.lines,
  });

  final String concept;
  final String reference;
  final String origin;
  final List<AccountingLineDraft> lines;

  List<Map<String, dynamic>> toLegacyLines() =>
      lines.map((line) => line.toLegacyMap()).toList();
}

class AccountingRuleSet {
  const AccountingRuleSet({
    this.cashAccount = '1105',
    this.bankAccount = '1110',
    this.accountsReceivableAccount = '1305',
    this.inventoryAccount = '1435',
    this.taxDeductibleAccount = '1355',
    this.accountsPayableAccount = '2205',
    this.taxPayableAccount = '2408',
    this.salesRevenueAccount = '4135',
    this.operationalExpenseAccount = '5135',
    this.costOfSalesAccount = '6135',
  });

  final String cashAccount;
  final String bankAccount;
  final String accountsReceivableAccount;
  final String inventoryAccount;
  final String taxDeductibleAccount;
  final String accountsPayableAccount;
  final String taxPayableAccount;
  final String salesRevenueAccount;
  final String operationalExpenseAccount;
  final String costOfSalesAccount;

  String moneyAccountForOrigin(String origin) {
    final normalized = origin.toLowerCase().trim();
    if (normalized == 'banco') return bankAccount;
    if (normalized == 'cartera') return accountsReceivableAccount;
    return cashAccount;
  }

  String moneyAccountForPaymentMethod(String method) {
    final normalized = method.toUpperCase().trim();
    if (normalized == 'TRANSFERENCIA' ||
        normalized == 'TARJETA' ||
        normalized == 'NEQUI' ||
        normalized == 'DAVIPLATA') {
      return bankAccount;
    }
    if (normalized == 'CREDITO') return accountsReceivableAccount;
    return cashAccount;
  }
}

class AccountingEngine {
  const AccountingEngine({this.rules = const AccountingRuleSet()});

  final AccountingRuleSet rules;

  AccountingEntryDraft sale({
    required int saleId,
    required MoneyValue total,
    required MoneyValue cashPayment,
    required MoneyValue bankPayment,
    required MoneyValue credit,
    required MoneyValue costOfSale,
    required MoneyValue tax,
    required MoneyValue retefuente,
    required MoneyValue reteiva,
    required MoneyValue reteica,
    String? client,
  }) {
    final zero = MoneyValue(minorUnits: 0, currency: total.currency);
    final subtotal = total - tax + retefuente + reteiva + reteica;
    final totalPayments = cashPayment + bankPayment + credit;
    if (totalPayments != total) {
      throw StateError('Los medios de pago no coinciden con el total neto.');
    }

    final lines = <AccountingLineDraft>[
      AccountingLineDraft(
        accountCode: rules.salesRevenueAccount,
        debit: zero,
        credit: subtotal,
        description: 'Ingreso por venta #$saleId',
        thirdParty: client,
      ),
    ];

    if (tax.minorUnits > 0) {
      lines.add(
        AccountingLineDraft(
          accountCode: rules.taxPayableAccount,
          debit: zero,
          credit: tax,
          description: 'Impuesto generado venta #$saleId',
          thirdParty: client,
        ),
      );
    }
    _addDebitIfPositive(
      lines,
      amount: retefuente,
      zero: zero,
      account: '135515',
      description: 'Anticipo Retefuente venta #$saleId',
      thirdParty: client,
    );
    _addDebitIfPositive(
      lines,
      amount: reteiva,
      zero: zero,
      account: '135517',
      description: 'Anticipo ReteIVA venta #$saleId',
      thirdParty: client,
    );
    _addDebitIfPositive(
      lines,
      amount: reteica,
      zero: zero,
      account: '135518',
      description: 'Anticipo ReteICA venta #$saleId',
      thirdParty: client,
    );
    _addDebitIfPositive(
      lines,
      amount: cashPayment,
      zero: zero,
      account: rules.cashAccount,
      description: 'Cobro por caja venta #$saleId',
      thirdParty: client,
    );
    _addDebitIfPositive(
      lines,
      amount: bankPayment,
      zero: zero,
      account: rules.bankAccount,
      description: 'Cobro por banco venta #$saleId',
      thirdParty: client,
    );
    _addDebitIfPositive(
      lines,
      amount: credit,
      zero: zero,
      account: rules.accountsReceivableAccount,
      description: 'Cuenta por cobrar venta #$saleId',
      thirdParty: client,
    );

    if (costOfSale.minorUnits > 0) {
      lines.addAll([
        AccountingLineDraft(
          accountCode: rules.costOfSalesAccount,
          debit: costOfSale,
          credit: zero,
          description: 'Costo de venta #$saleId',
          thirdParty: client,
        ),
        AccountingLineDraft(
          accountCode: rules.inventoryAccount,
          debit: zero,
          credit: costOfSale,
          description: 'Salida de inventario por venta #$saleId',
          thirdParty: client,
        ),
      ]);
    }

    return AccountingEntryDraft(
      concept: 'Venta #$saleId',
      reference: 'VENTA-$saleId',
      origin: 'ventas',
      lines: lines,
    );
  }

  AccountingEntryDraft purchase({
    required int purchaseId,
    required MoneyValue total,
    required MoneyValue cashPayment,
    required MoneyValue bankPayment,
    required MoneyValue credit,
    required MoneyValue tax,
    required MoneyValue retefuente,
    required MoneyValue reteiva,
    required MoneyValue reteica,
    String? supplier,
  }) {
    final zero = MoneyValue(minorUnits: 0, currency: total.currency);
    final subtotal = total - tax + retefuente + reteiva + reteica;
    final lines = <AccountingLineDraft>[
      AccountingLineDraft(
        accountCode: rules.inventoryAccount,
        debit: subtotal,
        credit: zero,
        description: 'Compra de inventario #$purchaseId',
        thirdParty: supplier,
      ),
    ];

    _addDebitIfPositive(
      lines,
      amount: tax,
      zero: zero,
      account: rules.taxDeductibleAccount,
      description: 'Impuesto descontable compra #$purchaseId',
      thirdParty: supplier,
    );
    _addCreditIfPositive(
      lines,
      amount: retefuente,
      zero: zero,
      account: '2365',
      description: 'Retefuente practicada compra #$purchaseId',
      thirdParty: supplier,
    );
    _addCreditIfPositive(
      lines,
      amount: reteiva,
      zero: zero,
      account: '2367',
      description: 'ReteIVA practicado compra #$purchaseId',
      thirdParty: supplier,
    );
    _addCreditIfPositive(
      lines,
      amount: reteica,
      zero: zero,
      account: '2368',
      description: 'ReteICA practicado compra #$purchaseId',
      thirdParty: supplier,
    );
    _addCreditIfPositive(
      lines,
      amount: cashPayment,
      zero: zero,
      account: rules.cashAccount,
      description: 'Pago de compra #$purchaseId por caja',
      thirdParty: supplier,
    );
    _addCreditIfPositive(
      lines,
      amount: bankPayment,
      zero: zero,
      account: rules.bankAccount,
      description: 'Pago de compra #$purchaseId por banco',
      thirdParty: supplier,
    );
    _addCreditIfPositive(
      lines,
      amount: credit,
      zero: zero,
      account: rules.accountsPayableAccount,
      description: 'Cuenta por pagar compra #$purchaseId',
      thirdParty: supplier,
    );

    return AccountingEntryDraft(
      concept: 'Compra #$purchaseId',
      reference: 'COMPRA-$purchaseId',
      origin: 'compras',
      lines: lines,
    );
  }

  static void _addDebitIfPositive(
    List<AccountingLineDraft> lines, {
    required MoneyValue amount,
    required MoneyValue zero,
    required String account,
    required String description,
    String? thirdParty,
  }) {
    if (amount.minorUnits <= 0) return;
    lines.add(
      AccountingLineDraft(
        accountCode: account,
        debit: amount,
        credit: zero,
        description: description,
        thirdParty: thirdParty,
      ),
    );
  }

  static void _addCreditIfPositive(
    List<AccountingLineDraft> lines, {
    required MoneyValue amount,
    required MoneyValue zero,
    required String account,
    required String description,
    String? thirdParty,
  }) {
    if (amount.minorUnits <= 0) return;
    lines.add(
      AccountingLineDraft(
        accountCode: account,
        debit: zero,
        credit: amount,
        description: description,
        thirdParty: thirdParty,
      ),
    );
  }
}
