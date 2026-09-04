class HrmJobTitle {
  const HrmJobTitle({
    this.id,
    required this.companyId,
    required this.title,
    this.description,
    this.contractualHoursPerDay,
    this.mrpWorkstationId,
    this.isDeleted = false,
  });
  final int? id;
  final int companyId;
  final String title;
  final String? description;
  final double? contractualHoursPerDay;
  final int? mrpWorkstationId;
  final bool isDeleted;

  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'title': title,
    'description': description,
    'contractual_hours_per_day': contractualHoursPerDay,
    'mrp_workstation_id': mrpWorkstationId,
    'is_deleted': isDeleted ? 1 : 0,
  };
  factory HrmJobTitle.fromMap(Map<String, dynamic> m) => HrmJobTitle(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num).toInt(),
    title: m['title'].toString(),
    description: m['description']?.toString(),
    contractualHoursPerDay: (m['contractual_hours_per_day'] as num?)
        ?.toDouble(),
    mrpWorkstationId: (m['mrp_workstation_id'] as num?)?.toInt(),
    isDeleted: m['is_deleted'] == 1,
  );
}
