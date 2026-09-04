class HrmEmployee {
  const HrmEmployee({
    this.id,
    required this.companyId,
    required this.name,
    this.employeeCode,
    this.document,
    this.birthdate,
    this.gender,
    this.maritalStatus,
    this.jobTitleId,
    this.jobTitle,
    this.status = 'activo',
    this.joinedDate,
    this.terminationDate,
    this.email,
    this.phone,
    this.address,
    this.entityType = 'comercial',
    this.salaryGrade,
    this.managerId,
    this.terminationId,
  });
  final int? id;
  final int companyId;
  final String name;
  final String? employeeCode;
  final String? document;
  final DateTime? birthdate;
  final String? gender;
  final String? maritalStatus;
  final int? jobTitleId;
  final String? jobTitle;
  final String status;
  final DateTime? joinedDate;
  final DateTime? terminationDate;
  final String? email;
  final String? phone;
  final String? address;
  final String entityType;
  final String? salaryGrade;
  final int? managerId;
  final int? terminationId;

  Map<String, Object?> toMap() => {
    'nombre': name,
    'employee_code': employeeCode,
    'documento': document,
    'fecha_nacimiento': birthdate?.toIso8601String(),
    'genero': gender,
    'estado_civil': maritalStatus,
    'job_title_id': jobTitleId,
    'cargo': jobTitle,
    'activo': status == 'activo' ? 1 : 0,
    'fecha_contratacion':
        joinedDate?.toIso8601String() ?? DateTime.now().toIso8601String(),
    'fecha': joinedDate?.toIso8601String() ?? DateTime.now().toIso8601String(),
    'fecha_terminacion': terminationDate?.toIso8601String(),
    'email': email,
    'telefono': phone,
    'direccion': address,
    'salary_grade': salaryGrade,
    'manager_id': managerId,
    'termination_id': terminationId,
  };
  factory HrmEmployee.fromMap(Map<String, dynamic> m) => HrmEmployee(
    id: (m['id'] as num?)?.toInt(),
    companyId: (m['company_id'] as num?)?.toInt() ?? 0,
    name: m['nombre']?.toString() ?? '',
    employeeCode: m['employee_code']?.toString(),
    document: m['documento']?.toString(),
    birthdate: DateTime.tryParse(m['fecha_nacimiento']?.toString() ?? ''),
    gender: m['genero']?.toString(),
    maritalStatus: m['estado_civil']?.toString(),
    jobTitleId: (m['job_title_id'] as num?)?.toInt(),
    jobTitle: m['cargo']?.toString(),
    status: m['activo'] == 1 ? 'activo' : 'retirado',
    joinedDate: DateTime.tryParse(m['fecha_contratacion']?.toString() ?? ''),
    terminationDate: DateTime.tryParse(
      m['fecha_terminacion']?.toString() ?? '',
    ),
    email: m['email']?.toString(),
    phone: m['telefono']?.toString(),
    address: m['direccion']?.toString(),
    entityType: m['entity_type']?.toString() ?? 'comercial',
    salaryGrade: m['salary_grade']?.toString(),
    managerId: (m['manager_id'] as num?)?.toInt(),
    terminationId: (m['termination_id'] as num?)?.toInt(),
  );

  HrmEmployee copyWith({String? status, DateTime? terminationDate}) {
    return HrmEmployee(
      id: id,
      companyId: companyId,
      name: name,
      employeeCode: employeeCode,
      document: document,
      birthdate: birthdate,
      gender: gender,
      maritalStatus: maritalStatus,
      jobTitleId: jobTitleId,
      jobTitle: jobTitle,
      status: status ?? this.status,
      joinedDate: joinedDate,
      terminationDate: terminationDate ?? this.terminationDate,
      email: email,
      phone: phone,
      address: address,
      entityType: entityType,
      salaryGrade: salaryGrade,
      managerId: managerId,
      terminationId: terminationId,
    );
  }
}
