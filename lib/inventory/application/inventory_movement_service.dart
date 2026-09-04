import 'package:sqflite/sqflite.dart';

/// Persists the legacy movement row and the canonical historical Kardex row
/// in the same transaction.
class InventoryMovementService {
  const InventoryMovementService._();

  static Future<void> record({
    required DatabaseExecutor db,
    required int companyId,
    required int productId,
    required String type,
    required double quantity,
    required double stockBefore,
    required double stockAfter,
    required String reason,
    required String date,
    int? warehouseId,
    int costBeforeMinor = 0,
    int costAfterMinor = 0,
    int? costTotalMinor,
    String? documentType,
    int? documentId,
    String createdBy = 'local',
    bool syncLots = true,
  }) async {
    await db.insert('movimientos_inventario', {
      'company_id': companyId,
      'producto_id': productId,
      'tipo': type,
      'cantidad': quantity,
      'stock_anterior': stockBefore,
      'stock_nuevo': stockAfter,
      'costo_anterior': costBeforeMinor,
      'costo_nuevo': costAfterMinor,
      'motivo': reason,
      'fecha': date,
    });
    await db.insert('kardex_inventario', {
      'company_id': companyId,
      'producto_id': productId,
      'bodega_id': warehouseId,
      'tipo': type,
      'cantidad': quantity,
      'costo_unitario': costAfterMinor,
      'costo_total': costTotalMinor ?? 0,
      'stock_anterior': stockBefore,
      'stock_nuevo': stockAfter,
      'referencia': reason,
      'documento_tipo': documentType,
      'documento_id': documentId,
      'fecha': date,
      'created_by': createdBy,
    });
    if (syncLots) {
      await _syncLots(
        db: db,
        companyId: companyId,
        productId: productId,
        type: type,
        quantity: quantity,
        warehouseId: warehouseId,
        costMinor: costAfterMinor,
        reference: _lotReference(
          type: type,
          productId: productId,
          documentType: documentType,
          documentId: documentId,
          warehouseId: warehouseId,
        ),
        date: date,
      );
    }
  }

  static bool _isInbound(String type) {
    final normalized = type.toLowerCase();
    return normalized.contains('entrada') ||
        normalized == 'compra' ||
        normalized == 'in';
  }

  static bool _isOutbound(String type) {
    final normalized = type.toLowerCase();
    return normalized.contains('salida') ||
        normalized == 'venta' ||
        normalized == 'out';
  }

  static String _lotReference({
    required String type,
    required int productId,
    required String? documentType,
    required int? documentId,
    required int? warehouseId,
  }) {
    final doc = documentType == null || documentId == null
        ? type
        : '$documentType-$documentId';
    return 'AUTO-$doc-P$productId-W${warehouseId ?? 1}';
  }

  static Future<void> _syncLots({
    required DatabaseExecutor db,
    required int companyId,
    required int productId,
    required String type,
    required double quantity,
    required int? warehouseId,
    required int costMinor,
    required String reference,
    required String date,
  }) async {
    if (quantity <= 0) return;
    if (_isInbound(type)) {
      await _addLegacyLot(
        db,
        companyId: companyId,
        productId: productId,
        quantity: quantity,
        costMinor: costMinor,
        reference: reference,
        date: date,
      );
      await _addAdvancedLot(
        db,
        companyId: companyId,
        productId: productId,
        quantity: quantity,
        costMinor: costMinor,
        warehouseId: warehouseId,
        reference: reference,
        date: date,
      );
      return;
    }
    if (_isOutbound(type)) {
      await _consumeLegacyLots(
        db,
        companyId: companyId,
        productId: productId,
        quantity: quantity,
      );
      await _consumeAdvancedLots(
        db,
        companyId: companyId,
        productId: productId,
        quantity: quantity,
        warehouseId: warehouseId,
      );
    }
  }

  static Future<void> _addLegacyLot(
    DatabaseExecutor db, {
    required int companyId,
    required int productId,
    required double quantity,
    required int costMinor,
    required String reference,
    required String date,
  }) async {
    if (!await _tableExists(db, 'lotes')) return;
    final existing = await db.query(
      'lotes',
      columns: ['id', 'cantidad'],
      where: 'company_id = ? AND producto_id = ? AND codigo_lote = ?',
      whereArgs: [companyId, productId, reference],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('lotes', {
        'company_id': companyId,
        'producto_id': productId,
        'codigo_lote': reference,
        'fecha_vencimiento': null,
        'cantidad': quantity,
        'costo': costMinor,
        'status': 'active',
        'created_at': date,
      });
      return;
    }
    final current = (existing.single['cantidad'] as num?)?.toDouble() ?? 0;
    await db.update(
      'lotes',
      {'cantidad': current + quantity, 'status': 'active'},
      where: 'id = ? AND company_id = ?',
      whereArgs: [existing.single['id'], companyId],
    );
  }

  static Future<void> _consumeLegacyLots(
    DatabaseExecutor db, {
    required int companyId,
    required int productId,
    required double quantity,
  }) async {
    if (!await _tableExists(db, 'lotes')) return;
    var remaining = quantity;
    final rows = await db.query(
      'lotes',
      where:
          'company_id = ? AND producto_id = ? AND status = ? AND cantidad > 0',
      whereArgs: [companyId, productId, 'active'],
      orderBy: 'fecha_vencimiento IS NULL, fecha_vencimiento ASC, id ASC',
    );
    for (final row in rows) {
      if (remaining <= 0) break;
      final current = (row['cantidad'] as num?)?.toDouble() ?? 0;
      final take = current < remaining ? current : remaining;
      final left = current - take;
      await db.update(
        'lotes',
        {'cantidad': left, 'status': left <= 0 ? 'depleted' : 'active'},
        where: 'id = ? AND company_id = ?',
        whereArgs: [row['id'], companyId],
      );
      remaining -= take;
    }
  }

  static Future<void> _addAdvancedLot(
    DatabaseExecutor db, {
    required int companyId,
    required int productId,
    required double quantity,
    required int costMinor,
    required int? warehouseId,
    required String reference,
    required String date,
  }) async {
    if (!await _tableExists(db, 'inventory_lots')) return;
    final columns = await _columns(db, 'inventory_lots');
    final usesLedgerSchema = columns.contains('quantity');
    final qtyColumn = usesLedgerSchema ? 'quantity' : 'current_quantity';
    final idValue = usesLedgerSchema ? reference : null;
    final existing = await db.query(
      'inventory_lots',
      columns: ['id', qtyColumn],
      where: usesLedgerSchema
          ? 'company_id = ? AND product_id = ? AND id = ?'
          : 'company_id = ? AND product_id = ? AND lot_number = ?',
      whereArgs: [companyId, productId, reference],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final current = (existing.single[qtyColumn] as num?)?.toDouble() ?? 0;
      await db.update(
        'inventory_lots',
        {
          qtyColumn: current + quantity,
          if (columns.contains('status')) 'status': 'active',
        },
        where: 'id = ?',
        whereArgs: [existing.single['id']],
      );
      return;
    }

    if (usesLedgerSchema) {
      await db.insert('inventory_lots', {
        'id': idValue,
        'company_id': companyId,
        'branch_id': 1,
        'warehouse_id': warehouseId ?? 1,
        'product_id': productId,
        'quantity': quantity,
        'unit_cost': costMinor,
        'batch_number': reference,
        'received_at': date,
        'expires_at': null,
      });
      return;
    }

    await db.insert('inventory_lots', {
      'company_id': companyId,
      'product_id': productId,
      'lot_number': reference,
      'manufacturing_date': date,
      // El esquema legacy obliga un vencimiento no nulo aunque el movimiento
      // no lo conoce. Usamos un sentinel de 'sin vencimiento informado' en vez
      // de declarar falsamente que vence el mismo día de recepción.
      'expiration_date': '9999-12-31T23:59:59.999Z',
      'initial_quantity': quantity,
      'current_quantity': quantity,
      'unit_cost': costMinor,
      'warehouse_id': (warehouseId ?? 1).toString(),
      'status': 'active',
      'created_at': date,
    });
  }

  static Future<void> _consumeAdvancedLots(
    DatabaseExecutor db, {
    required int companyId,
    required int productId,
    required double quantity,
    required int? warehouseId,
  }) async {
    if (!await _tableExists(db, 'inventory_lots')) return;
    final columns = await _columns(db, 'inventory_lots');
    final qtyColumn = columns.contains('quantity')
        ? 'quantity'
        : 'current_quantity';
    final statusFilter = columns.contains('status') ? ' AND status = ?' : '';
    final statusArgs = columns.contains('status')
        ? <Object?>['active']
        : const <Object?>[];
    final warehouseFilter =
        columns.contains('warehouse_id') && warehouseId != null
        ? ' AND warehouse_id = ?'
        : '';
    final warehouseArgs =
        columns.contains('warehouse_id') && warehouseId != null
        ? <Object?>[warehouseId]
        : const <Object?>[];
    var remaining = quantity;
    final rows = await db.query(
      'inventory_lots',
      where:
          'company_id = ? AND product_id = ? AND $qtyColumn > 0$statusFilter$warehouseFilter',
      whereArgs: [companyId, productId, ...statusArgs, ...warehouseArgs],
      orderBy: columns.contains('expires_at')
          ? 'expires_at IS NULL, expires_at ASC, received_at ASC'
          : 'expiration_date IS NULL, expiration_date ASC, id ASC',
    );
    for (final row in rows) {
      if (remaining <= 0) break;
      final current = (row[qtyColumn] as num?)?.toDouble() ?? 0;
      final take = current < remaining ? current : remaining;
      final left = current - take;
      await db.update(
        'inventory_lots',
        {
          qtyColumn: left,
          if (columns.contains('status'))
            'status': left <= 0 ? 'depleted' : 'active',
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      remaining -= take;
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'].toString()).toSet();
  }
}
