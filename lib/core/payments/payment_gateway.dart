// ============================================================
// payment_gateway.dart
// Modelo para configuración de pasarelas de pago
// ============================================================

enum PaymentGatewayType {
  stripe,
  paypal,
  mercadopago,
  local,
  custom,
}

class PaymentGateway {
  final int? id;
  final int companyId;
  final PaymentGatewayType type;
  final String name;
  final Map<String, dynamic> config;
  final bool isActive;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PaymentGateway({
    this.id,
    required this.companyId,
    required this.type,
    required this.name,
    required this.config,
    this.isActive = true,
    this.isDefault = false,
    required this.createdAt,
    this.updatedAt,
  });

  PaymentGateway copyWith({
    int? id,
    int? companyId,
    PaymentGatewayType? type,
    String? name,
    Map<String, dynamic>? config,
    bool? isActive,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentGateway(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      type: type ?? this.type,
      name: name ?? this.name,
      config: config ?? this.config,
      isActive: isActive ?? this.isActive,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'type': type.name,
      'name': name,
      'config': config,
      'is_active': isActive ? 1 : 0,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory PaymentGateway.fromMap(Map<String, dynamic> map) {
    return PaymentGateway(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      type: PaymentGatewayType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => PaymentGatewayType.local,
      ),
      name: map['name'] as String,
      config: map['config'] as Map<String, dynamic>,
      isActive: (map['is_active'] as int?) == 1,
      isDefault: (map['is_default'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
