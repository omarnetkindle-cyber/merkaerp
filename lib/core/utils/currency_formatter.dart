import 'package:intl/intl.dart';
import '../currency/money_value.dart';

class CurrencyFormatter {
  static final _formatter = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$',
    decimalDigits: 0,
  );

  /// Acepta valores legacy numericos y MoneyValue solo en el borde de UI.
  static String format(Object valor) {
    final majorUnits = valor is MoneyValue
        ? valor.toMajorUnitsDoubleForDisplay()
        : (valor as num).toDouble();
    return _formatter.format(majorUnits);
  }
}
