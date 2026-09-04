import '../../core/currency/money_value.dart';

class PaymentAllocation {
  const PaymentAllocation({
    required this.cash,
    required this.bank,
    required this.credit,
  });

  final MoneyValue cash;
  final MoneyValue bank;
  final MoneyValue credit;

  MoneyValue get total => cash + bank + credit;
}

class PaymentPolicy {
  const PaymentPolicy._();

  static bool isBankMethod(String method) {
    final normalized = method.toUpperCase().trim();
    return normalized == 'TRANSFERENCIA' ||
        normalized == 'TARJETA' ||
        normalized == 'NEQUI' ||
        normalized == 'DAVIPLATA';
  }

  static bool isCreditMethod(String method) {
    return method.toUpperCase().trim() == 'CREDITO';
  }

  static String cashOriginForSale(String method) {
    final normalized = method.toUpperCase().trim();
    if (isBankMethod(normalized)) return 'banco';
    if (isCreditMethod(normalized)) return 'cartera';
    return 'caja';
  }

  static PaymentAllocation allocatePurchase({
    required MoneyValue total,
    required String method,
    required MoneyValue manualCash,
    required MoneyValue manualBank,
    required MoneyValue manualCredit,
  }) {
    final normalized = method.toUpperCase().trim();
    final zero = MoneyValue(minorUnits: 0, currency: total.currency);
    if (total.minorUnits < 0) {
      throw Exception('El total no puede ser negativo.');
    }

    if (normalized == 'PAGO MIXTO') {
      final distributed = manualCash + manualBank + manualCredit;
      if (distributed > total) {
        throw Exception('La distribucion del pago supera el total.');
      }
      return PaymentAllocation(
        cash: manualCash,
        bank: manualBank,
        credit:
            manualCredit + (distributed < total ? total - distributed : zero),
      );
    }

    if (normalized == 'EFECTIVO') {
      return PaymentAllocation(cash: total, bank: zero, credit: zero);
    }

    if (isCreditMethod(normalized)) {
      return PaymentAllocation(cash: zero, bank: zero, credit: total);
    }

    return PaymentAllocation(cash: zero, bank: total, credit: zero);
  }
}
