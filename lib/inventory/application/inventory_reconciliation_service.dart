import 'package:sqflite/sqflite.dart';

class InventoryReconciliationReport {
  const InventoryReconciliationReport({
    required this.companyId,
    required this.productId,
    required this.productStock,
    required this.kardexStock,
    required this.legacyLotStock,
    required this.advancedLotStock,
  });

  final int companyId;
  final int productId;
  final double productStock;
  final double kardexStock;
  final double legacyLotStock;
  final double advancedLotStock;

  bool get productMatchesKardex => _same(productStock, kardexStock);

  bool get legacyLotsMatchProduct =>
      legacyLotStock == 0 || _same(productStock, legacyLotStock);

  bool get advancedLotsMatchProduct =>
      advancedLotStock == 0 || _same(productStock, advancedLotStock);

  bool get isReconciled =>
      productMatchesKardex &&
      legacyLotsMatchProduct &&
      advancedLotsMatchProduct;

  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'product_id': productId,
    'productos_stock': productStock,
    'kardex_stock': kardexStock,
    'lotes_stock': legacyLotStock,
    'inventory_lots_stock': advancedLotStock,
    'reconciliado': isReconciled,
  };

  static bool _same(double a, double b) => (a - b).abs() < 0.000001;
}

/// Reconciles the operational stock projection against the canonical movement
/// ledger. `kardex_inventario` is the auditable ledger; `productos.stock` is
/// the read projection; `lotes` and `inventory_lots` are compatibility lot
/// projections that must be synchronized by `InventoryMovementService`.
class InventoryReconciliationService {
  const InventoryReconciliationService();

  Future<InventoryReconciliationReport> forProduct({
    required DatabaseExecutor db,
    required int companyId,
    required int productId,
  }) async {
    final product = await db.query(
      'productos',
      columns: ['stock'],
      where: 'id = ? AND company_id = ?',
      whereArgs: [productId, companyId],
      limit: 1,
    );
    if (product.isEmpty) {
      throw StateError('Producto $productId no existe en empresa $companyId.');
    }
    return InventoryReconciliationReport(
      companyId: companyId,
      productId: productId,
      productStock: (product.single['stock'] as num?)?.toDouble() ?? 0,
      kardexStock: await _kardexStock(db, companyId, productId),
      legacyLotStock: await _legacyLotStock(db, companyId, productId),
      advancedLotStock: await _advancedLotStock(db, companyId, productId),
    );
  }

  Future<double> _kardexStock(
    DatabaseExecutor db,
    int companyId,
    int productId,
  ) async {
    if (!await _tableExists(db, 'kardex_inventario')) return 0;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(
        CASE
          WHEN lower(tipo) LIKE '%salida%' THEN -cantidad
          ELSE cantidad
        END
      ), 0) AS total
      FROM kardex_inventario
      WHERE company_id = ? AND producto_id = ?
      ''',
      [companyId, productId],
    );
    return (rows.single['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> _legacyLotStock(
    DatabaseExecutor db,
    int companyId,
    int productId,
  ) async {
    if (!await _tableExists(db, 'lotes')) return 0;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(cantidad), 0) AS total
      FROM lotes
      WHERE company_id = ? AND producto_id = ?
        AND (status IS NULL OR status != 'depleted')
      ''',
      [companyId, productId],
    );
    return (rows.single['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> _advancedLotStock(
    DatabaseExecutor db,
    int companyId,
    int productId,
  ) async {
    if (!await _tableExists(db, 'inventory_lots')) return 0;
    final columns = await _columns(db, 'inventory_lots');
    final quantityColumn = columns.contains('quantity')
        ? 'quantity'
        : 'current_quantity';
    if (!columns.contains(quantityColumn)) return 0;
    final statusPredicate = columns.contains('status')
        ? "AND (status IS NULL OR status != 'depleted')"
        : '';
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM($quantityColumn), 0) AS total
      FROM inventory_lots
      WHERE company_id = ? AND product_id = ? $statusPredicate
      ''',
      [companyId, productId],
    );
    return (rows.single['total'] as num?)?.toDouble() ?? 0;
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'].toString()).toSet();
  }
}
