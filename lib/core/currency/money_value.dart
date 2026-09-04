import 'currency.dart';

/// Monetary amount stored in the smallest unit defined by [currency].
class MoneyValue implements Comparable<MoneyValue> {
  factory MoneyValue({required int minorUnits, required Currency? currency}) {
    final resolvedCurrency = _requireCurrency(currency);
    _checkInt64(BigInt.from(minorUnits));
    return MoneyValue._(minorUnits, resolvedCurrency);
  }

  factory MoneyValue.fromMajorUnits(
    String value, {
    required Currency? currency,
  }) {
    final resolvedCurrency = _requireCurrency(currency);
    final input = value.trim();
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(input);
    if (match == null) {
      throw FormatException('Invalid monetary value: $value');
    }

    final fraction = match.group(3) ?? '';
    if (fraction.length > resolvedCurrency.decimalPlaces) {
      throw FormatException(
        'Value $value exceeds ${resolvedCurrency.decimalPlaces} decimal places '
        'for ${resolvedCurrency.code}',
      );
    }

    final factor = _pow10(resolvedCurrency.decimalPlaces);
    final whole = BigInt.parse(match.group(2)!);
    final paddedFraction = fraction.padRight(
      resolvedCurrency.decimalPlaces,
      '0',
    );
    final fractionUnits = paddedFraction.isEmpty
        ? BigInt.zero
        : BigInt.parse(paddedFraction);
    var units = whole * factor + fractionUnits;
    if (match.group(1) == '-') units = -units;
    _checkInt64(units);

    return MoneyValue._(units.toInt(), resolvedCurrency);
  }

  /// Rehydrates an amount read from an INTEGER money column in SQLite.
  factory MoneyValue.fromSql(
    Object? value, {
    required Currency? currency,
    bool nullableAsZero = false,
  }) {
    if (value == null) {
      if (!nullableAsZero) {
        throw StateError('A NULL SQLite value cannot become MoneyValue');
      }
      return MoneyValue(minorUnits: 0, currency: currency);
    }
    if (value is! int) {
      throw StateError(
        'Expected INTEGER minor units from SQLite, got ${value.runtimeType}',
      );
    }
    return MoneyValue(minorUnits: value, currency: currency);
  }

  const MoneyValue._(this.minorUnits, this.currency);

  static final BigInt _minInt64 = BigInt.from(-9223372036854775808);
  static final BigInt _maxInt64 = BigInt.from(9223372036854775807);

  final int minorUnits;
  final Currency currency;

  String get currencyCode => currency.code;
  int get decimalPlaces => currency.decimalPlaces;

  MoneyValue operator +(MoneyValue other) {
    _requireCompatible(other);
    return _fromBigInt(BigInt.from(minorUnits) + BigInt.from(other.minorUnits));
  }

  MoneyValue operator -(MoneyValue other) {
    _requireCompatible(other);
    return _fromBigInt(BigInt.from(minorUnits) - BigInt.from(other.minorUnits));
  }

  MoneyValue operator -() => _fromBigInt(-BigInt.from(minorUnits));

  MoneyValue abs() => minorUnits < 0 ? -this : this;

  MoneyValue operator *(int multiplier) {
    return _fromBigInt(BigInt.from(minorUnits) * BigInt.from(multiplier));
  }

  MoneyValue operator /(int divisor) {
    return multiplyRatio(numerator: 1, denominator: divisor);
  }

  /// Applies an exact rational factor and rounds half away from zero.
  MoneyValue multiplyRatio({required int numerator, required int denominator}) {
    if (denominator == 0) {
      throw UnsupportedError('MoneyValue cannot be divided by zero');
    }
    final product = BigInt.from(minorUnits) * BigInt.from(numerator);
    final rounded = _divideRounded(product, BigInt.from(denominator));
    return _fromBigInt(rounded);
  }

  /// Multiplies by an exact decimal factor without binary floating point.
  MoneyValue multiplyDecimal(String factor) {
    final parsed = _parseDecimalRatio(factor);
    return multiplyRatio(numerator: parsed.$1, denominator: parsed.$2);
  }

  /// Divides by an exact decimal factor without binary floating point.
  MoneyValue divideDecimal(String divisor) {
    final parsed = _parseDecimalRatio(divisor);
    if (parsed.$1 == 0) {
      throw UnsupportedError('MoneyValue cannot be divided by zero');
    }
    return multiplyRatio(numerator: parsed.$2, denominator: parsed.$1);
  }

  /// Applies a percentage expressed as decimal text (for example `12.5`).
  MoneyValue percent(String percentage) {
    final parsed = _parseDecimalRatio(percentage);
    return multiplyRatio(numerator: parsed.$1, denominator: parsed.$2 * 100);
  }

  /// INTEGER value persisted in a v75 monetary column.
  int toSql() => minorUnits;

  /// Explicit representation for APIs, audit payloads and persisted JSON.
  Map<String, Object> toWireMap() => {
    'minor_units': minorUnits,
    'currency': currencyCode,
    'scale': decimalPlaces,
  };

  String toMajorUnitsString() {
    final factor = _pow10(decimalPlaces);
    final absolute = BigInt.from(minorUnits).abs();
    final whole = absolute ~/ factor;
    final fraction = (absolute % factor).toString().padLeft(decimalPlaces, '0');
    final sign = minorUnits < 0 ? '-' : '';
    if (decimalPlaces == 0) return '$sign$whole';
    return '$sign$whole.$fraction';
  }

  /// Numeric adapter reserved for charting/legacy presentation libraries.
  /// Domain calculations must keep using MoneyValue operators.
  double toMajorUnitsDoubleForDisplay() => double.parse(toMajorUnitsString());

  String format({bool includeSymbol = true}) {
    final amount = toMajorUnitsString();
    return includeSymbol ? '${currency.symbol}$amount' : amount;
  }

  @override
  int compareTo(MoneyValue other) {
    _requireCompatible(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  bool operator <(MoneyValue other) => compareTo(other) < 0;
  bool operator <=(MoneyValue other) => compareTo(other) <= 0;
  bool operator >(MoneyValue other) => compareTo(other) > 0;
  bool operator >=(MoneyValue other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) {
    return other is MoneyValue &&
        minorUnits == other.minorUnits &&
        currencyCode == other.currencyCode &&
        decimalPlaces == other.decimalPlaces;
  }

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode, decimalPlaces);

  @override
  String toString() => '${toMajorUnitsString()} $currencyCode';

  MoneyValue _fromBigInt(BigInt value) {
    _checkInt64(value);
    return MoneyValue._(value.toInt(), currency);
  }

  void _requireCompatible(MoneyValue other) {
    if (currencyCode != other.currencyCode ||
        decimalPlaces != other.decimalPlaces) {
      throw StateError(
        'Cannot combine $currencyCode/$decimalPlaces with '
        '${other.currencyCode}/${other.decimalPlaces}',
      );
    }
  }

  static Currency _requireCurrency(Currency? currency) {
    if (currency == null || currency.code.trim().isEmpty) {
      throw StateError('A resolved currency is required for MoneyValue');
    }
    if (currency.decimalPlaces < 0 || currency.decimalPlaces > 18) {
      throw StateError(
        'Invalid decimal scale ${currency.decimalPlaces} for ${currency.code}',
      );
    }
    return currency;
  }

  static BigInt _pow10(int exponent) => BigInt.from(10).pow(exponent);

  static (int, int) _parseDecimalRatio(String value) {
    final input = value.trim();
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(input);
    if (match == null) {
      throw FormatException('Invalid decimal factor: $value');
    }
    final fraction = match.group(3) ?? '';
    final denominator = _pow10(fraction.length);
    var numerator = BigInt.parse('${match.group(2)}$fraction');
    if (match.group(1) == '-') numerator = -numerator;
    _checkInt64(numerator);
    _checkInt64(denominator);
    return (numerator.toInt(), denominator.toInt());
  }

  static BigInt _divideRounded(BigInt numerator, BigInt denominator) {
    var normalizedNumerator = numerator;
    var normalizedDenominator = denominator;
    if (normalizedDenominator.isNegative) {
      normalizedNumerator = -normalizedNumerator;
      normalizedDenominator = -normalizedDenominator;
    }

    final quotient = normalizedNumerator ~/ normalizedDenominator;
    final remainder = normalizedNumerator.remainder(normalizedDenominator);
    if (remainder == BigInt.zero) return quotient;

    final roundAway = remainder.abs() * BigInt.two >= normalizedDenominator;
    if (!roundAway) return quotient;
    return normalizedNumerator.isNegative
        ? quotient - BigInt.one
        : quotient + BigInt.one;
  }

  static void _checkInt64(BigInt value) {
    if (value < _minInt64 || value > _maxInt64) {
      throw RangeError('Monetary value exceeds SQLite INTEGER range');
    }
  }
}
