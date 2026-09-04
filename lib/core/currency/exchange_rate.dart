// ============================================================
// exchange_rate.dart
// Modelo para tasas de cambio
// ============================================================

class ExchangeRate {
  final int? id;
  final int companyId;
  final String fromCurrency;
  final String toCurrency;
  final double rate;
  final DateTime effectiveDate;
  final DateTime? expiryDate;
  final String? source; // manual, api, bank
  final DateTime createdAt;
  final DateTime? updatedAt;

  ExchangeRate({
    this.id,
    required this.companyId,
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    required this.effectiveDate,
    this.expiryDate,
    this.source,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isValid {
    if (expiryDate == null) return true;
    return DateTime.now().isBefore(expiryDate!);
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return DateTime.now().isAfter(expiryDate!);
  }

  /// Convierte un monto de la moneda origen a destino
  double convert(double amount) {
    return amount * rate;
  }

  /// Convierte inversamente (de destino a origen)
  double convertInverse(double amount) {
    return amount / rate;
  }

  ExchangeRate copyWith({
    int? id,
    int? companyId,
    String? fromCurrency,
    String? toCurrency,
    double? rate,
    DateTime? effectiveDate,
    DateTime? expiryDate,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExchangeRate(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      fromCurrency: fromCurrency ?? this.fromCurrency,
      toCurrency: toCurrency ?? this.toCurrency,
      rate: rate ?? this.rate,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      expiryDate: expiryDate ?? this.expiryDate,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'from_currency': fromCurrency,
      'to_currency': toCurrency,
      'rate': rate,
      'effective_date': effectiveDate.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'source': source,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ExchangeRate.fromMap(Map<String, dynamic> map) {
    return ExchangeRate(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      fromCurrency: map['from_currency'] as String,
      toCurrency: map['to_currency'] as String,
      rate: (map['rate'] as num).toDouble(),
      effectiveDate: DateTime.parse(map['effective_date'] as String),
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'] as String)
          : null,
      source: map['source'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
