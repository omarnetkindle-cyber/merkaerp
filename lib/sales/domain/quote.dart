import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';

class SalesQuote {
  final int? id;
  final int companyId;
  final String quoteNumber;
  final int? customerId;
  final String customerName;
  final DateTime quoteDate;
  final DateTime? validUntil;
  final DateTime? acceptedDate;
  final DateTime? rejectedDate;
  final MoneyValue subtotal;
  final MoneyValue taxAmount;
  final MoneyValue total;
  final MoneyValue discountAmount;
  final String status;
  final String? notes;
  final String? terms;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  SalesQuote({
    this.id,
    required this.companyId,
    required this.quoteNumber,
    this.customerId,
    required this.customerName,
    required this.quoteDate,
    this.validUntil,
    this.acceptedDate,
    this.rejectedDate,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.discountAmount,
    this.status = 'draft',
    this.notes,
    this.terms,
    this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  bool get isDraft => status == 'draft';
  bool get isSent => status == 'sent';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';

  bool get isValid =>
      validUntil == null || DateTime.now().isBefore(validUntil!);

  bool get isNearExpiration {
    if (validUntil == null) return false;
    final daysUntil = validUntil!.difference(DateTime.now()).inDays;
    return daysUntil >= 0 && daysUntil <= 7;
  }

  int get daysUntilExpiration {
    if (validUntil == null) return -1;
    return validUntil!.difference(DateTime.now()).inDays;
  }

  SalesQuote copyWith({
    int? id,
    int? companyId,
    String? quoteNumber,
    int? customerId,
    String? customerName,
    DateTime? quoteDate,
    DateTime? validUntil,
    DateTime? acceptedDate,
    DateTime? rejectedDate,
    MoneyValue? subtotal,
    MoneyValue? taxAmount,
    MoneyValue? total,
    MoneyValue? discountAmount,
    String? status,
    String? notes,
    String? terms,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SalesQuote(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      quoteNumber: quoteNumber ?? this.quoteNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      quoteDate: quoteDate ?? this.quoteDate,
      validUntil: validUntil ?? this.validUntil,
      acceptedDate: acceptedDate ?? this.acceptedDate,
      rejectedDate: rejectedDate ?? this.rejectedDate,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      total: total ?? this.total,
      discountAmount: discountAmount ?? this.discountAmount,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      terms: terms ?? this.terms,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'company_id': companyId,
    'quote_number': quoteNumber,
    'customer_id': customerId,
    'customer_name': customerName,
    'quote_date': quoteDate.toIso8601String(),
    'valid_until': validUntil?.toIso8601String(),
    'accepted_date': acceptedDate?.toIso8601String(),
    'rejected_date': rejectedDate?.toIso8601String(),
    'subtotal': subtotal.toSql(),
    'tax_amount': taxAmount.toSql(),
    'total': total.toSql(),
    'discount_amount': discountAmount.toSql(),
    'status': status,
    'notes': notes,
    'terms': terms,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  factory SalesQuote.fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    return SalesQuote(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      quoteNumber: map['quote_number'] as String,
      customerId: map['customer_id'] as int?,
      customerName: map['customer_name'] as String,
      quoteDate: DateTime.parse(map['quote_date'] as String),
      validUntil: map['valid_until'] != null
          ? DateTime.parse(map['valid_until'] as String)
          : null,
      acceptedDate: map['accepted_date'] != null
          ? DateTime.parse(map['accepted_date'] as String)
          : null,
      rejectedDate: map['rejected_date'] != null
          ? DateTime.parse(map['rejected_date'] as String)
          : null,
      subtotal: MoneyValue.fromSql(map['subtotal'], currency: currency),
      taxAmount: MoneyValue.fromSql(map['tax_amount'], currency: currency),
      total: MoneyValue.fromSql(map['total'], currency: currency),
      discountAmount: MoneyValue.fromSql(
        map['discount_amount'],
        currency: currency,
        nullableAsZero: true,
      ),
      status: map['status'] as String? ?? 'draft',
      notes: map['notes'] as String?,
      terms: map['terms'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
