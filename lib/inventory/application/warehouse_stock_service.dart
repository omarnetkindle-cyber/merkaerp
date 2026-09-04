import '../../db_helper.dart';
import 'inventory_movement_service.dart';

/// Operaciones de stock por bodega compartidas por produccion y otros modulos.
/// MRP solo coordina estas operaciones; no modifica `stock_bodega` directamente.
class WarehouseStockService {
  WarehouseStockService({DatabaseHelper? database})
    : _database = database ?? DatabaseHelper.instance;
  final DatabaseHelper _database;

  Future<double> availableQuantity({
    required int productId,
    required int warehouseId,
  }) async {
    final db = await _database.database;
    final companyId = await _database.obtenerEmpresaActivaId();
    final rows = await db.query(
      'stock_bodega',
      columns: ['cantidad'],
      where: 'company_id = ? AND producto_id = ? AND bodega_id = ?',
      whereArgs: [companyId, productId, warehouseId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.single['cantidad'] as num).toDouble();
  }

  Future<int> transfer({
    required int productId,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double quantity,
    String reason = 'traslado',
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('La cantidad transferida debe ser positiva.');
    }
    final db = await _database.database;
    final companyId = await _database.obtenerEmpresaActivaId();
    final id = await db.insert('traslados_bodega', {
      'company_id': companyId,
      'producto_id': productId,
      'bodega_origen_id': fromWarehouseId,
      'bodega_destino_id': toWarehouseId,
      'cantidad': quantity,
      'estado': 'registrado',
      'observacion': reason,
      'fecha': DateTime.now().toIso8601String(),
    });
    await _database.procesarTrasladoBodega(trasladoId: id, usuario: 'mrp');
    return id;
  }

  Future<void> receiveProduction({
    required int productId,
    required int warehouseId,
    required double quantity,
    String reason = 'recepcion de produccion',
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('La cantidad recibida debe ser positiva.');
    }
    final db = await _database.database;
    final companyId = await _database.obtenerEmpresaActivaId();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_bodega',
        where: 'company_id = ? AND producto_id = ? AND bodega_id = ?',
        whereArgs: [companyId, productId, warehouseId],
        limit: 1,
      );
      final previous = rows.isEmpty
          ? 0.0
          : (rows.single['cantidad'] as num).toDouble();
      final next = previous + quantity;
      if (rows.isEmpty) {
        await txn.insert('stock_bodega', {
          'company_id': companyId,
          'producto_id': productId,
          'bodega_id': warehouseId,
          'cantidad': next,
          'costo': 0,
          'actualizado_en': DateTime.now().toIso8601String(),
        });
      } else {
        await txn.update(
          'stock_bodega',
          {
            'cantidad': next,
            'actualizado_en': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [rows.single['id']],
        );
      }
      await InventoryMovementService.record(
        db: txn,
        companyId: companyId,
        productId: productId,
        type: 'entrada',
        quantity: quantity,
        stockBefore: previous,
        stockAfter: next,
        warehouseId: warehouseId,
        reason: reason,
        date: DateTime.now().toIso8601String(),
        documentType: 'stock_bodega',
      );
    });
  }

  Future<void> consume({
    required int productId,
    required int warehouseId,
    required double quantity,
    String reason = 'consumo de produccion',
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('La cantidad consumida debe ser positiva.');
    }
    final db = await _database.database;
    final companyId = await _database.obtenerEmpresaActivaId();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_bodega',
        where: 'company_id = ? AND producto_id = ? AND bodega_id = ?',
        whereArgs: [companyId, productId, warehouseId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError(
          'No existe stock del producto #$productId en la bodega $warehouseId.',
        );
      }
      final previous = (rows.single['cantidad'] as num).toDouble();
      if (previous < quantity) {
        throw StateError(
          'Stock insuficiente para consumir el producto #$productId: '
          'requiere $quantity y hay $previous.',
        );
      }
      final next = previous - quantity;
      await txn.update(
        'stock_bodega',
        {'cantidad': next, 'actualizado_en': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [rows.single['id']],
      );
      await InventoryMovementService.record(
        db: txn,
        companyId: companyId,
        productId: productId,
        type: 'salida',
        quantity: quantity,
        stockBefore: previous,
        stockAfter: next,
        warehouseId: warehouseId,
        reason: reason,
        date: DateTime.now().toIso8601String(),
        documentType: 'stock_bodega',
      );
    });
  }
}
