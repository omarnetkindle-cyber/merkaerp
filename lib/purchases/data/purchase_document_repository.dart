import 'dart:convert';

import '../../core/branch/branch_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../core/database/database_gateway.dart';
import '../../db_helper.dart';
import '../domain/purchase_document.dart';

abstract class PurchaseDocumentRepository {
  Future<int> save(PurchaseDocument document);

  Future<PurchaseDocument?> findById(int id);

  Future<List<PurchaseDocument>> search(PurchaseDocumentQuery query);

  Future<void> update(PurchaseDocument document);

  Future<void> appendAudit({
    required int documentId,
    required String action,
    required String userId,
    required Map<String, Object?> payload,
  });

  Future<void> upsertSupplierBalance({
    required int companyId,
    required int branchId,
    required int supplierId,
    required String supplierName,
    required MoneyValue delta,
  });
}

class PurchaseDocumentQuery {
  const PurchaseDocumentQuery({
    required this.companyId,
    this.branchId,
    this.warehouseId,
    this.supplierId,
    this.state,
    this.type,
    this.limit = 100,
  });

  final int companyId;
  final int? branchId;
  final int? warehouseId;
  final int? supplierId;
  final PurchaseDocumentState? state;
  final PurchaseDocumentType? type;
  final int limit;
}

class SqlitePurchaseDocumentRepository implements PurchaseDocumentRepository {
  SqlitePurchaseDocumentRepository({
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
  Future<int> save(PurchaseDocument document) async {
    document.validate();
    return _gateway.transaction((txn) async {
      final id = await txn.insert('purchase_documents', _documentRow(document));
      for (final line in document.lines) {
        await txn.insert(
          'purchase_document_lines',
          _lineRow(document, id, line),
        );
      }
      for (final step in document.approvals) {
        await txn.insert(
          'purchase_approval_steps',
          _approvalRow(document, id, step),
        );
      }
      return id;
    });
  }

  @override
  Future<PurchaseDocument?> findById(int id) async {
    final scope = await _scope.current();
    final currency = await _currencyFor(scope.companyId);
    final rows = await _gateway.query(
      'purchase_documents',
      where: 'id = ? AND company_id = ? AND branch_id = ?',
      whereArgs: [id, scope.companyId, scope.branchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final lines = await _gateway.query(
      'purchase_document_lines',
      where: 'document_id = ? AND company_id = ?',
      whereArgs: [id, scope.companyId],
      orderBy: 'id ASC',
    );
    final approvals = await _gateway.query(
      'purchase_approval_steps',
      where: 'document_id = ? AND company_id = ?',
      whereArgs: [id, scope.companyId],
      orderBy: 'level ASC',
    );
    return _fromRows(rows.first, lines, approvals, currency: currency);
  }

  @override
  Future<List<PurchaseDocument>> search(PurchaseDocumentQuery query) async {
    final currency = await _currencyFor(query.companyId);
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
    if (query.supplierId != null) {
      clauses.add('supplier_id = ?');
      args.add(query.supplierId);
    }
    if (query.state != null) {
      clauses.add('state = ?');
      args.add(query.state!.name);
    }
    if (query.type != null) {
      clauses.add('type = ?');
      args.add(query.type!.name);
    }
    final rows = await _gateway.query(
      'purchase_documents',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'issue_date DESC, id DESC',
      limit: query.limit,
    );
    final result = <PurchaseDocument>[];
    for (final row in rows) {
      final id = (row['id'] as num).toInt();
      final lines = await _gateway.query(
        'purchase_document_lines',
        where: 'document_id = ? AND company_id = ?',
        whereArgs: [id, query.companyId],
        orderBy: 'id ASC',
      );
      final approvals = await _gateway.query(
        'purchase_approval_steps',
        where: 'document_id = ? AND company_id = ?',
        whereArgs: [id, query.companyId],
        orderBy: 'level ASC',
      );
      result.add(_fromRows(row, lines, approvals, currency: currency));
    }
    return result;
  }

  @override
  Future<void> update(PurchaseDocument document) async {
    final updated = await _gateway.update(
      'purchase_documents',
      {
        'state': document.state.name,
        'subtotal': document.subtotal.toSql(),
        'tax_total': document.taxTotal.toSql(),
        'retention_total': document.retentionTotal.toSql(),
        'total': document.total.toSql(),
        'approved_by': document.approvedBy,
        'posted_at': document.postedAt?.toIso8601String(),
        'reversed_document_id': document.reversedDocumentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ? AND branch_id = ?',
      whereArgs: [document.id, document.companyId, document.branchId],
    );
    if (updated == 0) throw StateError('Documento de compra no encontrado.');
    await _gateway.delete(
      'purchase_document_lines',
      where: 'document_id = ? AND company_id = ?',
      whereArgs: [document.id, document.companyId],
    );
    for (final line in document.lines) {
      await _gateway.insert(
        'purchase_document_lines',
        _lineRow(document, document.id!, line),
      );
    }
    await _gateway.delete(
      'purchase_approval_steps',
      where: 'document_id = ? AND company_id = ?',
      whereArgs: [document.id, document.companyId],
    );
    for (final step in document.approvals) {
      await _gateway.insert(
        'purchase_approval_steps',
        _approvalRow(document, document.id!, step),
      );
    }
  }

  @override
  Future<void> appendAudit({
    required int documentId,
    required String action,
    required String userId,
    required Map<String, Object?> payload,
  }) async {
    final scope = await _scope.current();
    await _gateway.insert('purchase_document_audit', {
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
      entidad: 'purchase_documents',
      entidadId: documentId,
      detalle: jsonEncode(payload),
    );
  }

  @override
  Future<void> upsertSupplierBalance({
    required int companyId,
    required int branchId,
    required int supplierId,
    required String supplierName,
    required MoneyValue delta,
  }) async {
    final rows = await _gateway.query(
      'supplier_balances',
      where: 'company_id = ? AND branch_id = ? AND supplier_id = ?',
      whereArgs: [companyId, branchId, supplierId],
      limit: 1,
    );
    final now = DateTime.now().toIso8601String();
    if (rows.isEmpty) {
      await _gateway.insert('supplier_balances', {
        'company_id': companyId,
        'branch_id': branchId,
        'supplier_id': supplierId,
        'supplier': supplierName,
        'balance': delta.toSql(),
        'updated_at': now,
      });
      return;
    }
    final current = MoneyValue.fromSql(
      rows.first['balance'],
      currency: delta.currency,
      nullableAsZero: true,
    );
    await _gateway.update(
      'supplier_balances',
      {
        'supplier': supplierName,
        'balance': (current + delta).toSql(),
        'updated_at': now,
      },
      where: 'company_id = ? AND branch_id = ? AND supplier_id = ?',
      whereArgs: [companyId, branchId, supplierId],
    );
  }

  Map<String, Object?> _documentRow(PurchaseDocument document) => {
    'company_id': document.companyId,
    'branch_id': document.branchId,
    'warehouse_id': document.warehouseId,
    'cost_center_id': document.costCenterId,
    'type': document.type.name,
    'state': document.state.name,
    'supplier_id': document.supplierId,
    'supplier': document.supplierName,
    'issue_date': document.issueDate.toIso8601String(),
    'due_date': document.dueDate.toIso8601String(),
    'country': document.country,
    'budget_code': document.budgetCode,
    'budget_available': document.budgetAvailable.toSql(),
    'subtotal': document.subtotal.toSql(),
    'tax_total': document.taxTotal.toSql(),
    'retention_total': document.retentionTotal.toSql(),
    'total': document.total.toSql(),
    'approved_by': document.approvedBy,
    'posted_at': document.postedAt?.toIso8601String(),
    'reversed_document_id': document.reversedDocumentId,
    'correlation_id': document.correlationId,
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  };

  Map<String, Object?> _lineRow(
    PurchaseDocument document,
    int documentId,
    PurchaseDocumentLine line,
  ) => {
    'document_id': documentId,
    'company_id': document.companyId,
    'branch_id': document.branchId,
    'warehouse_id': line.warehouseId,
    'cost_center_id': document.costCenterId,
    'product_id': line.productId,
    'product': line.productName,
    'quantity': line.quantity,
    'received_quantity': line.receivedQuantity,
    'unit_cost': line.unitCost.toSql(),
    'tax_code': line.taxCode,
    'tax_rate': line.taxRate,
    'retention_rate': line.retentionRate,
    'tax_total': line.taxTotal.toSql(),
    'retention_total': line.retentionTotal.toSql(),
    'subtotal': line.subtotal.toSql(),
    'total': line.total.toSql(),
  };

  Map<String, Object?> _approvalRow(
    PurchaseDocument document,
    int documentId,
    ApprovalStep step,
  ) => {
    'document_id': documentId,
    'company_id': document.companyId,
    'branch_id': document.branchId,
    'level': step.level,
    'approver_role': step.approverRole,
    'sla_hours': step.slaHours,
    'approved_by': step.approvedBy,
    'approved_at': step.approvedAt?.toIso8601String(),
    'escalated_to': step.escalatedTo,
  };

  PurchaseDocument _fromRows(
    Map<String, Object?> row,
    List<Map<String, Object?>> lineRows,
    List<Map<String, Object?>> approvalRows, {
    required Currency currency,
  }) {
    final issueDate =
        DateTime.tryParse(row['issue_date']?.toString() ?? '') ??
        DateTime.now();
    return PurchaseDocument(
      id: (row['id'] as num?)?.toInt(),
      companyId: (row['company_id'] as num?)?.toInt() ?? 0,
      branchId: (row['branch_id'] as num?)?.toInt() ?? 1,
      warehouseId: (row['warehouse_id'] as num?)?.toInt() ?? 1,
      costCenterId: (row['cost_center_id'] as num?)?.toInt() ?? 1,
      type: PurchaseDocumentType.values.firstWhere(
        (item) => item.name == row['type']?.toString(),
        orElse: () => PurchaseDocumentType.purchaseOrder,
      ),
      state: PurchaseDocumentState.values.firstWhere(
        (item) => item.name == row['state']?.toString(),
        orElse: () => PurchaseDocumentState.draft,
      ),
      supplierId: (row['supplier_id'] as num?)?.toInt() ?? 0,
      supplierName: row['supplier']?.toString() ?? 'Sin proveedor',
      issueDate: issueDate,
      dueDate:
          DateTime.tryParse(row['due_date']?.toString() ?? '') ?? issueDate,
      country: row['country']?.toString() ?? 'Colombia',
      budgetCode: row['budget_code']?.toString(),
      budgetAvailable: MoneyValue.fromSql(
        row['budget_available'],
        currency: currency,
        nullableAsZero: true,
      ),
      approvedBy: row['approved_by']?.toString(),
      postedAt: DateTime.tryParse(row['posted_at']?.toString() ?? ''),
      reversedDocumentId: (row['reversed_document_id'] as num?)?.toInt(),
      correlationId: row['correlation_id']?.toString(),
      lines: lineRows
          .map(
            (line) => PurchaseDocumentLine(
              productId: (line['product_id'] as num?)?.toInt() ?? 0,
              productName: line['product']?.toString() ?? '',
              quantity: (line['quantity'] as num?)?.toDouble() ?? 0,
              unitCost: MoneyValue.fromSql(
                line['unit_cost'],
                currency: currency,
                nullableAsZero: true,
              ),
              receivedQuantity:
                  (line['received_quantity'] as num?)?.toDouble() ?? 0,
              taxCode: line['tax_code']?.toString() ?? 'EXEMPT',
              taxRate: (line['tax_rate'] as num?)?.toDouble() ?? 0,
              retentionRate: (line['retention_rate'] as num?)?.toDouble() ?? 0,
              warehouseId: (line['warehouse_id'] as num?)?.toInt() ?? 1,
            ),
          )
          .toList(),
      approvals: approvalRows
          .map(
            (step) => ApprovalStep(
              level: (step['level'] as num?)?.toInt() ?? 1,
              approverRole:
                  step['approver_role']?.toString() ?? 'administrador',
              slaHours: (step['sla_hours'] as num?)?.toInt() ?? 24,
              approvedBy: step['approved_by']?.toString(),
              approvedAt: DateTime.tryParse(
                step['approved_at']?.toString() ?? '',
              ),
              escalatedTo: step['escalated_to']?.toString(),
            ),
          )
          .toList(),
    );
  }

  Future<Currency> _currencyFor(int companyId) async {
    final database = await _db.database;
    return MoneyCurrencyResolver.resolve(database, companyId: companyId);
  }
}
