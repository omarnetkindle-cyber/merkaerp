class CrmAccount {
  const CrmAccount({
    this.id,
    required this.companyId,
    required this.name,
    this.parentId,
    this.email,
    this.phone,
    this.address,
    this.document,
    this.status = 'activo',
    this.entityType = 'comercial',
    this.assignedUserId,
    this.territoryId,
    this.createdAt,
    this.modifiedAt,
  });

  final int? id;
  final int? companyId;
  final String name;
  final int? parentId;
  final String? email;
  final String? phone;
  final String? address;
  final String? document;
  final String status;
  final String entityType;
  final int? assignedUserId;
  final int? territoryId;
  final DateTime? createdAt;
  final DateTime? modifiedAt;

  Map<String, Object?> toPersistenceMap({int? companyIdOverride}) {
    final now = DateTime.now().toIso8601String();
    return {
      if (id != null) 'id': id,
      'company_id': companyIdOverride ?? companyId,
      'nombre': name,
      'documento': document,
      'telefono': phone,
      'direccion': address,
      'email': email,
      'estado': status,
      'parent_id': parentId,
      'assigned_user_id': assignedUserId,
      'territory_id': territoryId,
      'entity_type': entityType,
      'created_at': (createdAt ?? DateTime.tryParse(now))?.toIso8601String(),
      'modified_at': modifiedAt?.toIso8601String(),
      'fecha': (createdAt ?? DateTime.tryParse(now))?.toIso8601String(),
    };
  }

  factory CrmAccount.fromMap(Map<String, dynamic> map) {
    return CrmAccount(
      id: (map['id'] as num?)?.toInt(),
      companyId: (map['company_id'] as num?)?.toInt(),
      name: map['nombre']?.toString() ?? map['name']?.toString() ?? '',
      parentId: (map['parent_id'] as num?)?.toInt(),
      email: map['email']?.toString(),
      phone: map['telefono']?.toString() ?? map['phone']?.toString(),
      address: map['direccion']?.toString() ?? map['address']?.toString(),
      document: map['documento']?.toString() ?? map['document']?.toString(),
      status: map['estado']?.toString() ?? 'activo',
      entityType: map['entity_type']?.toString() ?? 'comercial',
      assignedUserId: (map['assigned_user_id'] as num?)?.toInt(),
      territoryId: (map['territory_id'] as num?)?.toInt(),
      createdAt: _date(map['created_at'] ?? map['fecha']),
      modifiedAt: _date(map['modified_at']),
    );
  }
}

DateTime? _date(Object? value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text);
}
