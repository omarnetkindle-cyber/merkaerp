// ============================================================
// currency.dart
// Modelo para monedas y tasas de cambio
// ============================================================

class Currency {
  final String code;
  final String name;
  final String symbol;
  final int decimalPlaces;
  final bool isDefault;

  Currency({
    required this.code,
    required this.name,
    required this.symbol,
    this.decimalPlaces = 2,
    this.isDefault = false,
  });

  Currency copyWith({
    String? code,
    String? name,
    String? symbol,
    int? decimalPlaces,
    bool? isDefault,
  }) {
    return Currency(
      code: code ?? this.code,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'symbol': symbol,
      'decimal_places': decimalPlaces,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory Currency.fromMap(Map<String, dynamic> map) {
    return Currency(
      code: map['code'] as String,
      name: map['name'] as String,
      symbol: map['symbol'] as String,
      decimalPlaces: map['decimal_places'] as int? ?? 2,
      isDefault: (map['is_default'] as int?) == 1,
    );
  }

  /// Formatea un monto en esta moneda
  String format(double amount) {
    return '$symbol${amount.toStringAsFixed(decimalPlaces)}';
  }

  /// Monedas comunes predefinidas
  static final List<Currency> commonCurrencies = [
    Currency(code: 'USD', name: 'US Dollar', symbol: '\$', isDefault: true),
    Currency(code: 'EUR', name: 'Euro', symbol: '€'),
    Currency(code: 'GBP', name: 'British Pound', symbol: '£'),
    Currency(code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
    Currency(code: 'COP', name: 'Colombian Peso', symbol: '\$'),
    Currency(code: 'MXN', name: 'Mexican Peso', symbol: '\$'),
    Currency(code: 'ARS', name: 'Argentine Peso', symbol: '\$'),
    Currency(code: 'PEN', name: 'Peruvian Sol', symbol: 'S/'),
    Currency(code: 'CLP', name: 'Chilean Peso', symbol: '\$'),
    Currency(code: 'BRL', name: 'Brazilian Real', symbol: 'R\$'),
  ];
}
