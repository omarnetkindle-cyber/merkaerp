import 'dart:convert';

import '../../core/branch/branch_context.dart';
import '../../core/database/database_gateway.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../domain/sales_document.dart';

abstract class SalesDocumentRepository {
  Future<int> save(SalesDocument document);

  Future<SalesDocument?> findById(int id);

  Future<List<SalesDocument>> search(SalesDocumentQuery query);

  Future<void> updateState(SalesDocument document);

  Future<void> appendAudit({
    required int documentId,
    required String action,
    required String userId,
    required Map<String, Object?> payload,
  });
}

class SalesDocumentQuery {
  const SalesDocumentQuery({
    required this.companyId,
    this.branchId,
    this.warehouseId,
    this.customerId,
    this.state,
    this.type,
    this.limit = 100,
  });

  final int companyId;
  final int? branchId;
  final int? warehouseId;
  final int? customerId;
  final SalesDocumentState? state;
  final SalesDocumentType? type;
  final int limit;
}

class SqliteSalesDocumentRepository implements SalesDocumentRepository {
  SqliteSalesDocumentRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    BranchScopeProvider? scope,
    DatabaseHelper? db,
  }) : _gateway = gateway,
       _scope = scope ?? BranchContextService.instance,
       _db = db ?? DatabaseHelper.instance;

  final DatabaseGateway _gateway;
  final BranchScopeProvider _scope;
  final DatabaseHelper _db;

  @override
  Future<int> save(SalesDocument document) async {
    document.validate();
    return _gateway.transaction((txn) async {
      final id = await txn.insert('sales_documents', _documentRow(document));
      for (final line in document.lines) {
        await txn.insert('sales_document_lines', {
          'document_id': id,
          'company_id': document.companyId,
          'branch_id': document.branchId,
          'warehouse_id': line.warehouseId,
          'cost_center_id': document.costCenterId,
          'product_id': line.productId,
          'product': line.productName,
          'quantity': line.quantity,
          'unit_price': line.unitPrice.toSql(),
          'discount': line.discount.toSql(),
          'tax_rate': line.taxRate,
          'tax_total': line.taxTotal.toSql(),
          'subtotal': line.subtotal.toSql(),
          'total': line.total.toSql(),
        });
      }
      return id;
    });
  }

  @override
  Future<SalesDocument?> findById(int id) async {
    final scope = await _scope.current();
    final rows = await _gateway.query(
      'sales_documents',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, scope.companyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final lines = await _gateway.query(
      'sales_document_lines',
      where: 'document_id = ? AND company_id = ?',
      whereArgs: [id, scope.companyId],
      orderBy: 'id ASC',
    );
    return _fromRows(
      rows.first,
      lines,
      currency: await _currencyForCompany(scope.companyId),
    );
  }

  @override
  Future<List<SalesDocument>> search(SalesDocumentQuery query) async {
    final clauses = ['company_id = ?'];
    final args = <Object?>[query.companyId];
    if (query.branchId != null) {
      clauses.add('branch_id = ?');
      args.add(query.branchId);
    }
    if (query.warehouseId != null) {
      clauses.add('warehouse_id = ?');
      args.add(query.warehouseId);
    }
    if (query.customerId != null) {
      clauses.add('customer_id = ?');
      args.add(query.customerId);
    }
    if (query.state != null) {
      clauses.add('state = ?');
      args.add(query.state!.name);
    }
    if (query.type != null) {
      clauses.add('type = ?');
      args.add(query.type!.name);
    }

    final documents = await _gateway.query(
      'sales_documents',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'issue_date DESC, id DESC',
      limit: query.limit,
    );
    final result = <SalesDocument>[];
    for (final row in documents) {
      final id = (row['id'] as num).toInt();
      final lines = await _gateway.query(
        'sales_document_lines',
        where: 'document_id = ? AND company_id = ?',
        whereArgs: [id, query.companyId],
        orderBy: 'id ASC',
      );
      result.add(
        _fromRows(
          row,
          lines,
          currency: await _currencyForCompany(query.companyId),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> updateState(SalesDocument document) async {
    final updated = await _gateway.update(
      'sales_documents',
      {
        'state': document.state.name,
        'approved_by': document.approvedBy,
        'posted_at': document.postedAt?.toIso8601String(),
        'reversed_document_id': document.reversedDocumentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [document.id, document.companyId],
    );
    if (updated == 0) throw StateError('Documento de venta no encontrado.');
  }

  @override
  Future<void> appendAudit({
    required int documentId,
    required String action,
    required String userId,
    required Map<String, Object?> payload,
  }) async {
    final scope = await _scope.current();
    await _gateway.insert('sales_document_audit', {
      'company_id': scope.companyId,
      'branch_id': scope.branchId,
      'document_id': documentId,
      'action': action,
      'user_id': userId,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
    await _db.registrarEventoAuditoria(
      accion: action,
      entidad: 'sales_documents',
      entidadId: documentId,
      detalle: jsonEncode(payload),
    );
  }

  Map<String, Object?> _documentRow(SalesDocument document) => {
    'company_id': document.companyId,
    'branch_id': document.branchId,
    'warehouse_id': document.warehouseId,
    'cost_center_id': document.costCenterId,
    'type': document.type.name,
    'state': document.state.name,
    'customer_id': document.customerId,
    'customer': document.customerName,
    'issue_date': document.issueDate.toIso8601String(),
    'due_date': document.paymentTerm.dueDate.toIso8601String(),
    'payment_method': document.paymentTerm.method,
    'credit_days': document.paymentTerm.creditDays,
    'subtotal': document.subtotal.toSql(),
    'discount_total': document.discountTotal.toSql(),
    'tax_total': document.taxTotal.toSql(),
    'total': document.total.toSql(),
    'approved_by': document.approvedBy,
    'posted_at': document.postedAt?.toIso8601String(),
    'reversed_document_id': document.reversedDocumentId,
    'correlation_id': document.correlationId,
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  };

  SalesDocument _fromRows(
    Map<String, Object?> row,
    List<Map<String, Object?>> lineRows, {
    required Currency currency,
  }) {
    final issueDate = DateTime.parse(row['issue_date'].toString());
    final dueDate =
        DateTime.tryParse(row['due_date']?.toString() ?? '') ?? issueDate;
    return SalesDocument(
      id: (row['id'] as num?)?.toInt(),
      companyId: (row['company_id'] as num?)?.toInt() ?? 0,
      branchId: (row['branch_id'] as num?)?.toInt() ?? 1,
      warehouseId: (row['warehouse_id'] as num?)?.toInt() ?? 1,
      costCenterId: (row['cost_center_id'] as num?)?.toInt() ?? 1,
      type: SalesDocumentType.values.firstWhere(
        (item) => item.name == row['type']?.toString(),
        orElse: () => SalesDocumentType.invoice,
      ),
      state: SalesDocumentState.values.firstWhere(
        (item) => item.name == row['state']?.toString(),
        orElse: () => SalesDocumentState.draft,
      ),
      customerId: (row['customer_id'] as num?)?.toInt(),
      customerName: row['customer']?.toString() ?? 'Cliente general',
      issueDate: issueDate,
      paymentTerm: SalesPaymentTerm(
        method: row['payment_method']?.toString() ?? 'EFECTIVO',
        dueDate: dueDate,
        creditDays: (row['credit_days'] as num?)?.toInt() ?? 0,
      ),
      lines: lineRows
          .map(
            (line) => SalesDocumentLine(
              productId: (line['product_id'] as num?)?.toInt() ?? 0,
              productName: line['product']?.toString() ?? '',
              quantity: (line['quantity'] as num?)?.toDouble() ?? 0,
              unitPrice: MoneyValue.fromSql(
                line['unit_price'],
                currency: currency,
                nullableAsZero: true,
              ),
              discount: MoneyValue.fromSql(
                line['discount'],
                currency: currency,
                nullableAsZero: true,
              ),
              taxRate: (line['tax_rate'] as num?)?.toDouble() ?? 0,
              taxTotal: MoneyValue.fromSql(
                line['tax_total'],
                currency: currency,
                nullableAsZero: true,
              ),
              warehouseId: (line['warehouse_id'] as num?)?.toInt() ?? 1,
            ),
          )
          .toList(),
      approvedBy: row['approved_by']?.toString(),
      postedAt: DateTime.tryParse(row['posted_at']?.toString() ?? ''),
      reversedDocumentId: (row['reversed_document_id'] as num?)?.toInt(),
      correlationId: row['correlation_id']?.toString(),
    );
  }

  Future<Currency> _currencyForCompany(int companyId) async {
    return MoneyCurrencyResolver.resolve(
      await _db.database,
      companyId: companyId,
    );
  }
}
