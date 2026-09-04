class MrpWorkstationShift {
  const MrpWorkstationShift({
    this.id,
    required this.companyId,
    required this.workstationId,
    required this.weekday,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.availableHours,
  });

  final int? id;
  final int companyId;
  final int workstationId;
  final int weekday;
  final String shiftName;
  final String startTime;
  final String endTime;
  final double availableHours;

  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'workstation_id': workstationId,
    'weekday': weekday,
    'shift_name': shiftName,
    'start_time': startTime,
    'end_time': endTime,
    'available_hours': availableHours,
  };

  factory MrpWorkstationShift.fromMap(Map<String, dynamic> m) =>
      MrpWorkstationShift(
        id: (m['id'] as num?)?.toInt(),
        companyId: (m['company_id'] as num).toInt(),
        workstationId: (m['workstation_id'] as num).toInt(),
        weekday: (m['weekday'] as num).toInt(),
        shiftName: m['shift_name'].toString(),
        startTime: m['start_time'].toString(),
        endTime: m['end_time'].toString(),
        availableHours: (m['available_hours'] as num).toDouble(),
      );
}
