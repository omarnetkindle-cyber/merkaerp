// ============================================================
// webhook.dart
// Modelo para configuración de webhooks
// ============================================================

class Webhook {
  final int? id;
  final int companyId;
  final String event; // sale.created, inventory.low, etc.
  final String url;
  final String? secret; // Para verificar firma HMAC
  final bool isActive;
  final int retryCount;
  final int maxRetries;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Webhook({
    this.id,
    required this.companyId,
    required this.event,
    required this.url,
    this.secret,
    this.isActive = true,
    this.retryCount = 0,
    this.maxRetries = 3,
    required this.createdAt,
    this.updatedAt,
  });

  Webhook copyWith({
    int? id,
    int? companyId,
    String? event,
    String? url,
    String? secret,
    bool? isActive,
    int? retryCount,
    int? maxRetries,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Webhook(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      event: event ?? this.event,
      url: url ?? this.url,
      secret: secret ?? this.secret,
      isActive: isActive ?? this.isActive,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'event': event,
      'url': url,
      'secret': secret,
      'is_active': isActive ? 1 : 0,
      'retry_count': retryCount,
      'max_retries': maxRetries,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Webhook.fromMap(Map<String, dynamic> map) {
    return Webhook(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      event: map['event'] as String,
      url: (map['url'] ?? map['target_url'])?.toString() ?? '',
      secret: map['secret'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      retryCount: map['retry_count'] as int? ?? 0,
      maxRetries: map['max_retries'] as int? ?? 3,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
