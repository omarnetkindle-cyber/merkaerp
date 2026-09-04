// ============================================================
// advanced_inventory_service.dart
// Servicio de inventario avanzado con lotes, FIFO y vencimientos.
//
// Compatibilidad: desde el Bloque D del cierre general, la escritura canonica
// de movimientos vive en InventoryMovementService + kardex_inventario. Esta
// fachada queda para consultas/reservas historicas sobre inventory_lots, no
// como fuente primaria de stock operativo.
// ============================================================

import 'package:sqflite/sqflite.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../domain/inventory_lot.dart';
import '../domain/inventory_reservation.dart';

class AdvancedInventoryService {
  static final AdvancedInventoryService instance =
      AdvancedInventoryService._internal();

  AdvancedInventoryService._internal();

  Future<Currency> _currencyFor(Database db, int companyId) {
    return MoneyCurrencyResolver.resolve(db, companyId: companyId);
  }

  /// Crea las tablas necesarias para inventario avanzado
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_lots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        lot_number TEXT NOT NULL,
        manufacturing_date TEXT NOT NULL,
        expiration_date TEXT NOT NULL,
        initial_quantity REAL NOT NULL,
        current_quantity REAL NOT NULL,
        unit_cost INTEGER NOT NULL,
        supplier_id TEXT,
        purchase_document_id TEXT,
        warehouse_id TEXT,
        status TEXT DEFAULT 'active',
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (product_id) REFERENCES productos(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_reservations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        lot_id TEXT,
        document_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        reserved_quantity REAL NOT NULL,
        fulfilled_quantity REAL DEFAULT 0,
        status TEXT DEFAULT 'pending',
        reserved_at TEXT NOT NULL,
        fulfilled_at TEXT,
        cancelled_at TEXT,
        notes TEXT,
        FOREIGN KEY (product_id) REFERENCES productos(id)
      )
    ''');

    // Índices para optimización
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_lots_product ON inventory_lots(product_id)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_lots_expiration ON inventory_lots(expiration_date)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_lots_status ON inventory_lots(status)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reservations_product ON inventory_reservations(product_id)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reservations_document ON inventory_reservations(document_id)',
      );
    } catch (_) {}
  }

  /// Crea un nuevo lote de inventario
  Future<int> createLot(Database db, InventoryLot lot) async {
    final id = await db.insert('inventory_lots', lot.toMap());
    return id;
  }

  /// Obtiene lotes por producto ordenados por fecha de vencimiento (FIFO)
  Future<List<InventoryLot>> getLotsByProduct(
    Database db,
    int productId,
    int companyId,
  ) async {
    final maps = await db.query(
      'inventory_lots',
      where: 'product_id = ? AND company_id = ? AND status = ?',
      whereArgs: [productId, companyId, 'active'],
      orderBy: 'expiration_date ASC',
    );

    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => InventoryLot.fromMap(map, currency: currency))
        .toList();
  }

  /// Obtiene lotes próximos a vencer (dentro de X días)
  Future<List<InventoryLot>> getLotsNearExpiry(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final expiryDate = DateTime.now().add(Duration(days: days));
    final maps = await db.query(
      'inventory_lots',
      where:
          'company_id = ? AND status = ? AND expiration_date <= ? AND expiration_date > ?',
      whereArgs: [
        companyId,
        'active',
        expiryDate.toIso8601String(),
        DateTime.now().toIso8601String(),
      ],
      orderBy: 'expiration_date ASC',
    );

    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => InventoryLot.fromMap(map, currency: currency))
        .toList();
  }

  /// Obtiene lotes vencidos
  Future<List<InventoryLot>> getExpiredLots(Database db, int companyId) async {
    final maps = await db.query(
      'inventory_lots',
      where: 'company_id = ? AND expiration_date < ? AND status != ?',
      whereArgs: [companyId, DateTime.now().toIso8601String(), 'depleted'],
      orderBy: 'expiration_date ASC',
    );

    final currency = await _currencyFor(db, companyId);
    return maps
        .map((map) => InventoryLot.fromMap(map, currency: currency))
        .toList();
  }

  /// Reserva inventario usando FIFO
  Future<bool> reserveInventoryFIFO(
    Database db,
    int companyId,
    int productId,
    double quantity,
    String documentType,
    String documentId,
  ) async {
    final lots = await getLotsByProduct(db, productId, companyId);

    double remainingQuantity = quantity;

    for (final lot in lots) {
      if (remainingQuantity <= 0) break;

      final availableQuantity = lot.currentQuantity;

      if (availableQuantity > 0) {
        final quantityToReserve = availableQuantity < remainingQuantity
            ? availableQuantity
            : remainingQuantity;

        // Crear reserva
        final reservation = InventoryReservation(
          companyId: companyId,
          productId: productId,
          lotId: lot.id.toString(),
          documentType: documentType,
          documentId: documentId,
          reservedQuantity: quantityToReserve,
          reservedAt: DateTime.now(),
        );

        await db.insert('inventory_reservations', reservation.toMap());

        remainingQuantity -= quantityToReserve;
      }
    }

    return remainingQuantity <= 0;
  }

  /// Consume inventario de lotes específicos (FIFO)
  Future<bool> consumeInventoryFIFO(
    Database db,
    int companyId,
    int productId,
    double quantity,
    String documentType,
    String documentId,
  ) async {
    // Primero reservar
    final reserved = await reserveInventoryFIFO(
      db,
      companyId,
      productId,
      quantity,
      documentType,
      documentId,
    );

    if (!reserved) return false;

    // Obtener reservas pendientes
    final reservations = await db.query(
      'inventory_reservations',
      where:
          'company_id = ? AND product_id = ? AND document_id = ? AND status = ?',
      whereArgs: [companyId, productId, documentId, 'pending'],
    );

    for (final map in reservations) {
      final reservation = InventoryReservation.fromMap(map);

      if (reservation.lotId != null) {
        // Actualizar cantidad del lote
        final lotMaps = await db.query(
          'inventory_lots',
          where: 'id = ?',
          whereArgs: [int.tryParse(reservation.lotId!)],
        );

        if (lotMaps.isNotEmpty) {
          final currency = await _currencyFor(db, companyId);
          final lot = InventoryLot.fromMap(lotMaps.first, currency: currency);
          final newQuantity =
              lot.currentQuantity - reservation.reservedQuantity;

          await db.update(
            'inventory_lots',
            {
              'current_quantity': newQuantity,
              'status': newQuantity <= 0 ? 'depleted' : 'active',
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [lot.id],
          );
        }
      }

      // Actualizar reserva
      await db.update(
        'inventory_reservations',
        {
          'status': 'fulfilled',
          'fulfilled_quantity': reservation.reservedQuantity,
          'fulfilled_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [reservation.id],
      );
    }

    return true;
  }

  /// Actualiza el estado de lotes vencidos
  Future<void> updateExpiredLotsStatus(Database db, int companyId) async {
    await db.update(
      'inventory_lots',
      {'status': 'expired', 'updated_at': DateTime.now().toIso8601String()},
      where: 'company_id = ? AND expiration_date < ? AND status = ?',
      whereArgs: [companyId, DateTime.now().toIso8601String(), 'active'],
    );
  }

  /// Obtiene alertas de stock bajo por lote
  Future<List<Map<String, dynamic>>> getLowStockAlertsByLot(
    Database db,
    int companyId,
    double threshold,
  ) async {
    final maps = await db.rawQuery(
      '''
      SELECT 
        p.id as product_id,
        p.nombre as product_name,
        p.stock as total_stock,
        COUNT(l.id) as lot_count,
        SUM(CASE WHEN l.status = 'active' THEN l.current_quantity ELSE 0 END) as active_lot_stock
      FROM productos p
      LEFT JOIN inventory_lots l ON p.id = l.product_id AND l.company_id = p.company_id
      WHERE p.company_id = ?
      GROUP BY p.id
      HAVING total_stock < ?
    ''',
      [companyId, threshold],
    );

    return maps;
  }

  /// Obtiene reporte de rotación por lote
  Future<List<Map<String, dynamic>>> getLotRotationReport(
    Database db,
    int companyId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final maps = await db.rawQuery(
      '''
      SELECT 
        l.lot_number,
        p.nombre as product_name,
        l.initial_quantity,
        l.current_quantity,
        l.expiration_date,
        (l.initial_quantity - l.current_quantity) as consumed_quantity,
        CASE 
          WHEN l.initial_quantity > 0 
          THEN ((l.initial_quantity - l.current_quantity) / l.initial_quantity) * 100 
          ELSE 0 
        END as rotation_percentage
      FROM inventory_lots l
      JOIN productos p ON l.product_id = p.id
      WHERE l.company_id = ? 
        AND l.created_at >= ? 
        AND l.created_at <= ?
      ORDER BY rotation_percentage DESC
    ''',
      [companyId, startDate.toIso8601String(), endDate.toIso8601String()],
    );

    return maps;
  }

  /// Cancela una reserva de inventario
  Future<void> cancelReservation(Database db, int reservationId) async {
    await db.update(
      'inventory_reservations',
      {'status': 'cancelled', 'cancelled_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [reservationId],
    );
  }

  /// Obtiene reservas pendientes por documento
  Future<List<InventoryReservation>> getPendingReservationsByDocument(
    Database db,
    String documentId,
  ) async {
    final maps = await db.query(
      'inventory_reservations',
      where: 'document_id = ? AND status = ?',
      whereArgs: [documentId, 'pending'],
    );

    return maps.map((map) => InventoryReservation.fromMap(map)).toList();
  }
}
