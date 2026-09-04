// ============================================================
// company_transfer.dart
// Modelo para transferencias entre empresas
// ============================================================

class CompanyTransfer {
  final int? id;
  final int fromCompanyId;
  final int toCompanyId;
  final String transferNumber;
  final String transferType; // inventory, funds, products
  final Map<String, dynamic> items;
  final double totalValue;
  final String status; // pending, approved, rejected, completed, cancelled
  final String? notes;
  final String? requestedBy;
  final String? approvedBy;
  final DateTime requestedAt;
  final DateTime? approvedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  CompanyTransfer({
    this.id,
    required this.fromCompanyId,
    required this.toCompanyId,
    required this.transferNumber,
    required this.transferType,
    required this.items,
    required this.totalValue,
    this.status = 'pending',
    this.notes,
    this.requestedBy,
    this.approvedBy,
    required this.requestedAt,
    this.approvedAt,
    this.completedAt,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  CompanyTransfer copyWith({
    int? id,
    int? fromCompanyId,
    int? toCompanyId,
    String? transferNumber,
    String? transferType,
    Map<String, dynamic>? items,
    double? totalValue,
    String? status,
    String? notes,
    String? requestedBy,
    String? approvedBy,
    DateTime? requestedAt,
    DateTime? approvedAt,
    DateTime? completedAt,
    DateTime? createdAt,
  }) {
    return CompanyTransfer(
      id: id ?? this.id,
      fromCompanyId: fromCompanyId ?? this.fromCompanyId,
      toCompanyId: toCompanyId ?? this.toCompanyId,
      transferNumber: transferNumber ?? this.transferNumber,
      transferType: transferType ?? this.transferType,
      items: items ?? this.items,
      totalValue: totalValue ?? this.totalValue,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      requestedBy: requestedBy ?? this.requestedBy,
      approvedBy: approvedBy ?? this.approvedBy,
      requestedAt: requestedAt ?? this.requestedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'from_company_id': fromCompanyId,
      'to_company_id': toCompanyId,
      'transfer_number': transferNumber,
      'transfer_type': transferType,
      'items': items,
      'total_value': totalValue,
      'status': status,
      'notes': notes,
      'requested_by': requestedBy,
      'approved_by': approvedBy,
      'requested_at': requestedAt.toIso8601String(),
      'approved_at': approvedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CompanyTransfer.fromMap(Map<String, dynamic> map) {
    return CompanyTransfer(
      id: map['id'] as int?,
      fromCompanyId: map['from_company_id'] as int,
      toCompanyId: map['to_company_id'] as int,
      transferNumber: map['transfer_number'] as String,
      transferType: map['transfer_type'] as String,
      items: map['items'] as Map<String, dynamic>,
      totalValue: (map['total_value'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending',
      notes: map['notes'] as String?,
      requestedBy: map['requested_by'] as String?,
      approvedBy: map['approved_by'] as String?,
      requestedAt: DateTime.parse(map['requested_at'] as String),
      approvedAt: map['approved_at'] != null
          ? DateTime.parse(map['approved_at'] as String)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
