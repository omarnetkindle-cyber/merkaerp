// ============================================================
// customer_interaction.dart
// Modelo para interacciones con clientes (CRM)
// ============================================================

class CustomerInteraction {
  final int? id;
  final int companyId;
  final int customerId;
  final String customerName;
  final String interactionType; // call, email, meeting, visit, note
  final String subject;
  final String? description;
  final DateTime interactionDate;
  final String? outcome;
  final String? nextAction;
  final DateTime? followUpDate;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CustomerInteraction({
    this.id,
    required this.companyId,
    required this.customerId,
    required this.customerName,
    required this.interactionType,
    required this.subject,
    this.description,
    required this.interactionDate,
    this.outcome,
    this.nextAction,
    this.followUpDate,
    this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  bool get hasFollowUp => followUpDate != null;
  bool get isFollowUpOverdue {
    if (followUpDate == null) return false;
    return DateTime.now().isAfter(followUpDate!);
  }

  CustomerInteraction copyWith({
    int? id,
    int? companyId,
    int? customerId,
    String? customerName,
    String? interactionType,
    String? subject,
    String? description,
    DateTime? interactionDate,
    String? outcome,
    String? nextAction,
    DateTime? followUpDate,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerInteraction(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      interactionType: interactionType ?? this.interactionType,
      subject: subject ?? this.subject,
      description: description ?? this.description,
      interactionDate: interactionDate ?? this.interactionDate,
      outcome: outcome ?? this.outcome,
      nextAction: nextAction ?? this.nextAction,
      followUpDate: followUpDate ?? this.followUpDate,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'customer_id': customerId,
      'customer_name': customerName,
      'interaction_type': interactionType,
      'subject': subject,
      'description': description,
      'interaction_date': interactionDate.toIso8601String(),
      'outcome': outcome,
      'next_action': nextAction,
      'follow_up_date': followUpDate?.toIso8601String(),
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory CustomerInteraction.fromMap(Map<String, dynamic> map) {
    return CustomerInteraction(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      customerId: map['customer_id'] as int,
      customerName: map['customer_name'] as String,
      interactionType: map['interaction_type'] as String,
      subject: map['subject'] as String,
      description: map['description'] as String?,
      interactionDate: DateTime.parse(map['interaction_date'] as String),
      outcome: map['outcome'] as String?,
      nextAction: map['next_action'] as String?,
      followUpDate: map['follow_up_date'] != null
          ? DateTime.parse(map['follow_up_date'] as String)
          : null,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
