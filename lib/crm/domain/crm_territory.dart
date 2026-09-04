class CrmTerritory {
  const CrmTerritory({
    this.id,
    required this.companyId,
    required this.name,
    this.country,
    this.department,
    this.city,
    this.sector,
    this.assignedUserId,
    this.active = true,
    this.entityType = 'comercial',
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final int companyId;
  final String name;
  final String? country;
  final String? department;
  final String? city;
  final String? sector;
  final int? assignedUserId;
  final bool active;
  final String entityType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, Object?> toMap() {
    final created = createdAt ?? DateTime.now();
    return {
      if (id != null) 'id': id,
      'company_id': companyId,
      'name': name,
      'country': country,
      'department': department,
      'city': city,
      'sector': sector,
      'assigned_user_id': assignedUserId,
      'active': active ? 1 : 0,
      'entity_type': entityType,
      'created_at': created.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory CrmTerritory.fromMap(Map<String, Object?> map) {
    return CrmTerritory(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num).toInt(),
      name: map['name'].toString(),
      country: map['country']?.toString(),
      department: map['department']?.toString(),
      city: map['city']?.toString(),
      sector: map['sector']?.toString(),
      assignedUserId: (map['assigned_user_id'] as num?)?.toInt(),
      active: (map['active'] as num?)?.toInt() != 0,
      entityType: map['entity_type']?.toString() ?? 'comercial',
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }
}

DateTime? _date(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}
