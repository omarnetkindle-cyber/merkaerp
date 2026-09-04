// ============================================================
// commission.dart
// Modelo para gestión de comisiones
// ============================================================

class Commission {
  final int? id;
  final int companyId;
  final int salespersonId;
  final String salespersonName;
  final int? saleId;
  final String? saleNumber;
  final double saleAmount;
  final double commissionRate;
  final double commissionAmount;
  final String status; // pending, paid, cancelled
  final DateTime? paidDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Commission({
    this.id,
    required this.companyId,
    required this.salespersonId,
    required this.salespersonName,
    this.saleId,
    this.saleNumber,
    required this.saleAmount,
    required this.commissionRate,
    required this.commissionAmount,
    this.status = 'pending',
    this.paidDate,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';

  Commission copyWith({
    int? id,
    int? companyId,
    int? salespersonId,
    String? salespersonName,
    int? saleId,
    String? saleNumber,
    double? saleAmount,
    double? commissionRate,
    double? commissionAmount,
    String? status,
    DateTime? paidDate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Commission(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      salespersonId: salespersonId ?? this.salespersonId,
      salespersonName: salespersonName ?? this.salespersonName,
      saleId: saleId ?? this.saleId,
      saleNumber: saleNumber ?? this.saleNumber,
      saleAmount: saleAmount ?? this.saleAmount,
      commissionRate: commissionRate ?? this.commissionRate,
      commissionAmount: commissionAmount ?? this.commissionAmount,
      status: status ?? this.status,
      paidDate: paidDate ?? this.paidDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'salesperson_id': salespersonId,
      'salesperson_name': salespersonName,
      'sale_id': saleId,
      'sale_number': saleNumber,
      'sale_amount': saleAmount,
      'commission_rate': commissionRate,
      'commission_amount': commissionAmount,
      'status': status,
      'paid_date': paidDate?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Commission.fromMap(Map<String, dynamic> map) {
    return Commission(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      salespersonId: map['salesperson_id'] as int,
      salespersonName: map['salesperson_name'] as String,
      saleId: map['sale_id'] as int?,
      saleNumber: map['sale_number'] as String?,
      saleAmount: (map['sale_amount'] as num).toDouble(),
      commissionRate: (map['commission_rate'] as num).toDouble(),
      commissionAmount: (map['commission_amount'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending',
      paidDate: map['paid_date'] != null
          ? DateTime.parse(map['paid_date'] as String)
          : null,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
