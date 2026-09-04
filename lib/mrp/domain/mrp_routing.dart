class MrpRouting {
  const MrpRouting({
    this.id,
    required this.companyId,
    this.itemId,
    required this.name,
    this.description,
    this.priority = 1,
    this.isActive = true,
    this.isDefault = false,
    this.selectionCriteria,
  });
  final int? id;
  final int companyId;
  final int? itemId;
  final String name;
  final String? description;
  final int priority;
  final bool isActive;
  final bool isDefault;
  final String? selectionCriteria;
  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'item_id': itemId,
    'name': name,
    'description': description,
    'priority': priority,
    'is_active': isActive ? 1 : 0,
    'is_default': isDefault ? 1 : 0,
    'selection_criteria': selectionCriteria,
  };
  factory MrpRouting.fromMap(Map<String, dynamic> m) => MrpRouting(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    itemId: (m['item_id'] as num?)?.toInt(),
    name: m['name'].toString(),
    description: m['description']?.toString(),
    priority: (m['priority'] as num?)?.toInt() ?? 1,
    isActive: (m['is_active'] as num?)?.toInt() != 0,
    isDefault: (m['is_default'] as num?)?.toInt() == 1,
    selectionCriteria: m['selection_criteria']?.toString(),
  );
}
