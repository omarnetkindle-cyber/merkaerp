import '../core/currency/currency.dart';
import '../core/currency/money_value.dart';

/// Colombian withholding thresholds used by the commercial flows.
///
/// The UVT amount is kept here so tax consumers do not carry a stale
/// hardcoded monetary value. Rates remain configurable at the transaction
/// or company-parameter boundary.
class RetentionPolicy {
  const RetentionPolicy._();

  static const int currentUvtYear = 2026;
  static const int currentUvtMajorUnits = 52374;

  static MoneyValue currentUvt({required Currency currency}) {
    return MoneyValue.fromMajorUnits(
      currentUvtMajorUnits.toString(),
      currency: currency,
    );
  }

  static MoneyValue baseForConcept({
    required String concept,
    required Currency currency,
  }) {
    final normalized = concept.trim().toLowerCase();
    if (normalized == 'servicios') {
      return currentUvt(currency: currency) * 2;
    }
    if (normalized == 'arrendamientos_muebles') {
      return currentUvt(currency: currency) * 2;
    }
    if (normalized == 'arrendamientos' ||
        normalized == 'arrendamientos_inmuebles') {
      return currentUvt(currency: currency) * 10;
    }
    if (normalized == 'rendimientos_financieros') {
      return MoneyValue(minorUnits: 0, currency: currency);
    }
    if (normalized == 'honorarios') {
      return MoneyValue(minorUnits: 0, currency: currency);
    }
    return currentUvt(currency: currency) * 10;
  }
}
