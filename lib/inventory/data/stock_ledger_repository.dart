import 'package:sqflite/sqflite.dart';

import '../../core/branch/branch_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../core/database/database_gateway.dart';
import '../../db_helper.dart';
import '../domain/stock_ledger.dart';

abstract class StockLedgerRepository {
  Future<StockLedger> load({
    required int productId,
    required BranchScope scope,
  });

  Future<void> saveLot(StockLot lot, {required BranchScope scope});

  Future<void> replaceLots(
    List<StockLot> lots, {
    required int productId,
    required BranchScope scope,
  });

  Future<void> saveReservation(
    InventoryReservation reservation, {
    required BranchScope scope,
  });

  Future<void> releaseReservation(
    String reservationId, {
    required BranchScope scope,
  });
}

class SqliteStockLedgerRepository implements StockLedgerRepository {
  SqliteStockLedgerRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    DatabaseHelper? db,
  }) : _gateway = gateway,
       _db = db ?? DatabaseHelper.instance;

  final DatabaseGateway _gateway;
  final DatabaseHelper _db;

  @override
  Future<StockLedger> load({
    required int productId,
    required BranchScope scope,
  }) async {
    final currency = await _currencyFor(scope.companyId);
    final lots = await _gateway.query(
      'inventory_lots',
      where:
          'company_id = ? AND branch_id = ? AND warehouse_id = ? AND product_id = ? AND quantity > 0',
      whereArgs: [
        scope.companyId,
        scope.branchId,
        scope.warehouseId,
        productId,
      ],
      orderBy: 'received_at ASC',
    );
    final reservations = await _gateway.query(
      'inventory_reservations',
      where:
          'company_id = ? AND branch_id = ? AND warehouse_id = ? AND product_id = ? AND status = ?',
      whereArgs: [
        scope.companyId,
        scope.branchId,
        scope.warehouseId,
        productId,
        'active',
      ],
      orderBy: 'created_at ASC',
    );
    return StockLedger(
      productId: productId,
      lots: lots.map((row) => _lotFromRow(row, currency)).toList(),
      reservations: reservations.map(_reservationFromRow).toList(),
    );
  }

  @override
  Future<void> saveLot(StockLot lot, {required BranchScope scope}) async {
    await _gateway.insert(
      'inventory_lots',
      _lotToRow(lot, scope),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> replaceLots(
    List<StockLot> lots, {
    required int productId,
    required BranchScope scope,
  }) {
    return _gateway.transaction((txn) async {
      await txn.delete(
        'inventory_lots',
        where:
            'company_id = ? AND branch_id = ? AND warehouse_id = ? AND product_id = ?',
        whereArgs: [
          scope.companyId,
          scope.branchId,
          scope.warehouseId,
          productId,
        ],
      );
      for (final lot in lots.where((lot) => lot.quantity > 0)) {
        await txn.insert(
          'inventory_lots',
          _lotToRow(lot, scope),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> saveReservation(
    InventoryReservation reservation, {
    required BranchScope scope,
  }) async {
    await _gateway.insert(
      'inventory_reservations',
      _reservationToRow(reservation, scope),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> releaseReservation(
    String reservationId, {
    required BranchScope scope,
  }) async {
    await _gateway.update(
      'inventory_reservations',
      {'status': 'released', 'released_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND company_id = ? AND branch_id = ? AND warehouse_id = ?',
      whereArgs: [
        reservationId,
        scope.companyId,
        scope.branchId,
        scope.warehouseId,
      ],
    );
  }

  Map<String, Object?> _lotToRow(StockLot lot, BranchScope scope) => {
    'id': lot.id,
    'company_id': scope.companyId,
    'branch_id': scope.branchId,
    'warehouse_id': scope.warehouseId,
    'product_id': lot.productId,
    'quantity': lot.quantity,
    'unit_cost': lot.unitCost.toSql(),
    'batch_number': lot.batchNumber,
    'serial_number': lot.serialNumber,
    'received_at': lot.receivedAt.toIso8601String(),
    'expires_at': lot.expiresAt?.toIso8601String(),
  };

  Map<String, Object?> _reservationToRow(
    InventoryReservation reservation,
    BranchScope scope,
  ) => {
    'id': reservation.id,
    'company_id': scope.companyId,
    'branch_id': scope.branchId,
    'warehouse_id': scope.warehouseId,
    'product_id': reservation.productId,
    'quantity': reservation.quantity,
    'document_type': reservation.documentType,
    'document_id': reservation.documentId,
    'status': 'active',
    'created_at': reservation.createdAt.toIso8601String(),
  };

  StockLot _lotFromRow(Map<String, Object?> row, Currency currency) {
    return StockLot(
      id: row['id']?.toString() ?? '',
      productId: (row['product_id'] as num?)?.toInt() ?? 0,
      quantity: (row['quantity'] as num?)?.toDouble() ?? 0,
      unitCost: MoneyValue.fromSql(
        row['unit_cost'],
        currency: currency,
        nullableAsZero: true,
      ),
      receivedAt:
          DateTime.tryParse(row['received_at']?.toString() ?? '') ??
          DateTime.now(),
      batchNumber: row['batch_number']?.toString(),
      serialNumber: row['serial_number']?.toString(),
      expiresAt: DateTime.tryParse(row['expires_at']?.toString() ?? ''),
    );
  }

  InventoryReservation _reservationFromRow(Map<String, Object?> row) {
    return InventoryReservation(
      id: row['id']?.toString() ?? '',
      productId: (row['product_id'] as num?)?.toInt() ?? 0,
      quantity: (row['quantity'] as num?)?.toDouble() ?? 0,
      documentType: row['document_type']?.toString() ?? '',
      documentId: row['document_id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Future<Currency> _currencyFor(int companyId) async {
    final database = await _db.database;
    return MoneyCurrencyResolver.resolve(database, companyId: companyId);
  }
}
