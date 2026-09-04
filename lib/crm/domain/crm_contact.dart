class CrmContact {
  const CrmContact({
    this.id,
    required this.companyId,
    required this.accountId,
    required this.firstName,
    this.lastName = '',
    this.birthdate,
    this.email,
    this.phoneWork,
    this.phoneMobile,
    this.reportsToId,
    this.leadSource,
    this.opportunityRole,
    this.assignedUserId,
    this.entityType = 'comercial',
    this.createdAt,
    this.modifiedAt,
  });

  final int? id;
  final int? companyId;
  final int accountId;
  final String firstName;
  final String lastName;
  final DateTime? birthdate;
  final String? email;
  final String? phoneWork;
  final String? phoneMobile;
  final int? reportsToId;
  final String? leadSource;
  final String? opportunityRole;
  final int? assignedUserId;
  final String entityType;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  Map<String, Object?> toPersistenceMap({
    int? companyIdOverride,
    int? accountIdOverride,
  }) {
    return {
      if (id != null) 'id': id,
      'company_id': companyIdOverride ?? companyId,
      'account_id': accountIdOverride ?? accountId,
      'first_name': firstName,
      'last_name': lastName,
      'birthdate': birthdate?.toIso8601String(),
      'email': email,
      'phone_work': phoneWork,
      'phone_mobile': phoneMobile,
      'reports_to_id': reportsToId,
      'lead_source': leadSource,
      'opportunity_role': opportunityRole,
      'assigned_user_id': assignedUserId,
      'entity_type': entityType,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'modified_at': modifiedAt?.toIso8601String(),
    };
  }

  factory CrmContact.fromMap(Map<String, dynamic> map) {
    return CrmContact(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num?)?.toInt(),
      accountId: (map['account_id'] as num?)?.toInt() ?? 0,
      firstName: map['first_name']?.toString() ?? '',
      lastName: map['last_name']?.toString() ?? '',
      birthdate: _parseDate(map['birthdate']),
      email: map['email']?.toString(),
      phoneWork: map['phone_work']?.toString(),
      phoneMobile: map['phone_mobile']?.toString(),
      reportsToId: (map['reports_to_id'] as num?)?.toInt(),
      leadSource: map['lead_source']?.toString(),
      opportunityRole: map['opportunity_role']?.toString(),
      assignedUserId: (map['assigned_user_id'] as num?)?.toInt(),
      entityType: map['entity_type']?.toString() ?? 'comercial',
      createdAt: _parseDate(map['created_at']),
      modifiedAt: _parseDate(map['modified_at']),
    );
  }
}

DateTime? _parseDate(Object? value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text);
}
