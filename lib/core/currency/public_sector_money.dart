import 'currency.dart';
import 'money_value.dart';

/// Moneda normativa del sector publico colombiano.
///
/// A diferencia del dominio comercial, este valor no depende de la moneda de
/// una empresa: los modulos publicos operan en COP con escala fija 2.
final Currency publicSectorCurrency = Currency(
  code: 'COP',
  name: 'Peso colombiano',
  symbol: r'$',
  decimalPlaces: 2,
);

MoneyValue publicMoneyFromSql(
  Object? value, {
  bool nullableAsZero = false,
}) => MoneyValue.fromSql(
  value,
  currency: publicSectorCurrency,
  nullableAsZero: nullableAsZero,
);

MoneyValue publicMoneyFromMajor(String value) => MoneyValue.fromMajorUnits(
  value,
  currency: publicSectorCurrency,
);

MoneyValue publicMoneyZero() => MoneyValue(
  minorUnits: 0,
  currency: publicSectorCurrency,
);

double publicMoneyForDisplay(MoneyValue value) =>
    value.toMajorUnitsDoubleForDisplay();
