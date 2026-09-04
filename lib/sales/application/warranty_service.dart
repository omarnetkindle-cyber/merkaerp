// ============================================================
// warranty_service.dart
// Servicio de gestión de garantías
// ============================================================

import 'package:sqflite/sqflite.dart';
import '../domain/warranty.dart';

class WarrantyService {
  static final WarrantyService instance = WarrantyService._internal();

  WarrantyService._internal();

  /// Crea las tablas necesarias para garantías
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS warranties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        sale_id INTEGER,
        sale_number TEXT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        duration_months INTEGER NOT NULL,
        warranty_type TEXT NOT NULL,
        status TEXT DEFAULT 'active',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS warranty_claims (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        warranty_id INTEGER NOT NULL,
        claim_date TEXT NOT NULL,
        issue_description TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        resolution TEXT,
        resolved_date TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (warranty_id) REFERENCES warranties(id)
      )
    ''');

    // Las instalaciones nuevas pueden llegar con la tabla legacy creada
    // antes que este servicio. Mantener esta defensa idempotente evita que
    // una accion de mantenimiento falle por una columna moderna ausente.
    final warrantyColumns = await db.rawQuery('PRAGMA table_info(warranties)');
    const compatibilityColumns = {
      'sale_id': 'INTEGER',
      'sale_number': 'TEXT',
      'product_id': 'INTEGER',
      'product_name': 'TEXT',
      'customer_id': 'INTEGER',
      'customer_name': 'TEXT',
      'start_date': 'TEXT',
      'end_date': 'TEXT',
      'duration_months': 'INTEGER',
      'warranty_type': 'TEXT',
      'notes': 'TEXT',
      'created_at': 'TEXT',
      'updated_at': 'TEXT',
    };
    for (final entry in compatibilityColumns.entries) {
      if (!warrantyColumns.any((row) => row['name'] == entry.key)) {
        await db.execute(
          'ALTER TABLE warranties ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }

    // Índices - Comentados temporalmente por errores de esquema
    // await db.execute('CREATE INDEX IF NOT EXISTS idx_warranties_company ON warranties(company_id)');
    // await db.execute('CREATE INDEX IF NOT EXISTS idx_warranties_product ON warranties(product_id)');
    // await db.execute('CREATE INDEX IF NOT EXISTS idx_warranties_customer ON warranties(customer_id)');
    // await db.execute('CREATE INDEX IF NOT EXISTS idx_warranties_status ON warranties(status)');
    // await db.execute('CREATE INDEX IF NOT EXISTS idx_warranty_claims_warranty ON warranty_claims(warranty_id)');
  }

  /// Crea una garantía
  Future<int> createWarranty(Database db, Warranty warranty) async {
    final id = await db.insert('warranties', warranty.toMap());
    return id;
  }

  /// Genera automáticamente una garantía para una venta
  Future<int> generateWarrantyForSale(
    Database db,
    int companyId,
    int saleId,
    String saleNumber,
    int productId,
    String productName,
    int customerId,
    String customerName, {
    int durationMonths = 12,
    String warrantyType = 'manufacturer',
  }) async {
    final startDate = DateTime.now();
    final endDate = DateTime(
      startDate.year,
      startDate.month + durationMonths,
      startDate.day,
    );

    final warranty = Warranty(
      companyId: companyId,
      saleId: saleId,
      saleNumber: saleNumber,
      productId: productId,
      productName: productName,
      customerId: customerId,
      customerName: customerName,
      startDate: startDate,
      endDate: endDate,
      durationMonths: durationMonths,
      warrantyType: warrantyType,
      createdAt: DateTime.now(),
    );

    return await createWarranty(db, warranty);
  }

  /// Obtiene una garantía por ID
  Future<Warranty?> getWarrantyById(Database db, int warrantyId) async {
    final maps = await db.query(
      'warranties',
      where: 'id = ?',
      whereArgs: [warrantyId],
    );

    if (maps.isEmpty) return null;
    return Warranty.fromMap(maps.first);
  }

  /// Obtiene garantías por producto
  Future<List<Warranty>> getWarrantiesByProduct(
    Database db,
    int productId,
  ) async {
    final maps = await db.query(
      'warranties',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => Warranty.fromMap(map)).toList();
  }

  /// Obtiene garantías por cliente
  Future<List<Warranty>> getWarrantiesByCustomer(
    Database db,
    int customerId,
  ) async {
    final maps = await db.query(
      'warranties',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => Warranty.fromMap(map)).toList();
  }

  /// Obtiene garantías activas de una empresa
  Future<List<Warranty>> getActiveWarranties(Database db, int companyId) async {
    final maps = await db.query(
      'warranties',
      where: 'company_id = ? AND status = ?',
      whereArgs: [companyId, 'active'],
      orderBy: 'end_date ASC',
    );

    return maps.map((map) => Warranty.fromMap(map)).toList();
  }

  /// Obtiene garantías próximas a vencer
  Future<List<Warranty>> getExpiringSoonWarranties(
    Database db,
    int companyId, {
    int days = 30,
  }) async {
    final futureDate = DateTime.now().add(Duration(days: days));

    final maps = await db.query(
      'warranties',
      where: 'company_id = ? AND status = ? AND end_date <= ?',
      whereArgs: [companyId, 'active', futureDate.toIso8601String()],
      orderBy: 'end_date ASC',
    );

    return maps.map((map) => Warranty.fromMap(map)).toList();
  }

  /// Obtiene garantías vencidas
  Future<List<Warranty>> getExpiredWarranties(
    Database db,
    int companyId,
  ) async {
    final now = DateTime.now().toIso8601String();

    final maps = await db.query(
      'warranties',
      where: 'company_id = ? AND end_date < ? AND status = ?',
      whereArgs: [companyId, now, 'active'],
      orderBy: 'end_date DESC',
    );

    return maps.map((map) => Warranty.fromMap(map)).toList();
  }

  /// Actualiza el estado de una garantía
  Future<void> updateWarrantyStatus(
    Database db,
    int warrantyId,
    String status,
  ) async {
    await db.update(
      'warranties',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [warrantyId],
    );
  }

  /// Marca garantías vencidas automáticamente
  Future<int> markExpiredWarranties(Database db, int companyId) async {
    final now = DateTime.now().toIso8601String();

    final result = await db.update(
      'warranties',
      {'status': 'expired', 'updated_at': DateTime.now().toIso8601String()},
      where: 'company_id = ? AND end_date < ? AND status = ?',
      whereArgs: [companyId, now, 'active'],
    );

    return result;
  }

  /// Crea un reclamo de garantía
  Future<int> createWarrantyClaim(
    Database db,
    int warrantyId,
    String issueDescription,
  ) async {
    final id = await db.insert('warranty_claims', {
      'warranty_id': warrantyId,
      'claim_date': DateTime.now().toIso8601String(),
      'issue_description': issueDescription,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });

    // Actualizar estado de la garantía
    await updateWarrantyStatus(db, warrantyId, 'claimed');

    return id;
  }

  /// Resuelve un reclamo de garantía
  Future<void> resolveWarrantyClaim(
    Database db,
    int claimId,
    String resolution,
  ) async {
    await db.update(
      'warranty_claims',
      {
        'status': 'resolved',
        'resolution': resolution,
        'resolved_date': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [claimId],
    );
  }

  /// Obtiene reclamos de una garantía
  Future<List<Map<String, dynamic>>> getWarrantyClaims(
    Database db,
    int warrantyId,
  ) async {
    final maps = await db.query(
      'warranty_claims',
      where: 'warranty_id = ?',
      whereArgs: [warrantyId],
      orderBy: 'claim_date DESC',
    );

    return maps;
  }

  /// Obtiene reclamos pendientes
  Future<List<Map<String, dynamic>>> getPendingClaims(
    Database db,
    int companyId,
  ) async {
    final maps = await db.rawQuery(
      '''
      SELECT wc.*, w.product_name, w.customer_name
      FROM warranty_claims wc
      INNER JOIN warranties w ON wc.warranty_id = w.id
      WHERE w.company_id = ? AND wc.status = 'pending'
      ORDER BY wc.claim_date ASC
    ''',
      [companyId],
    );

    return maps;
  }

  /// Obtiene estadísticas de garantías
  Future<Map<String, dynamic>> getWarrantyStatistics(
    Database db,
    int companyId,
  ) async {
    final totalResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM warranties
      WHERE company_id = ?
    ''',
      [companyId],
    );

    final activeResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM warranties
      WHERE company_id = ? AND status = 'active'
    ''',
      [companyId],
    );

    final expiredResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM warranties
      WHERE company_id = ? AND status = 'expired'
    ''',
      [companyId],
    );

    final claimedResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM warranties
      WHERE company_id = ? AND status = 'claimed'
    ''',
      [companyId],
    );

    final expiringSoonResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM warranties
      WHERE company_id = ? AND status = 'active' AND end_date <= datetime('now', '+30 days')
    ''',
      [companyId],
    );

    final pendingClaimsResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM warranty_claims wc
      INNER JOIN warranties w ON wc.warranty_id = w.id
      WHERE w.company_id = ? AND wc.status = 'pending'
    ''',
      [companyId],
    );

    return {
      'total_warranties': Sqflite.firstIntValue(totalResult) ?? 0,
      'active_warranties': Sqflite.firstIntValue(activeResult) ?? 0,
      'expired_warranties': Sqflite.firstIntValue(expiredResult) ?? 0,
      'claimed_warranties': Sqflite.firstIntValue(claimedResult) ?? 0,
      'expiring_soon': Sqflite.firstIntValue(expiringSoonResult) ?? 0,
      'pending_claims': Sqflite.firstIntValue(pendingClaimsResult) ?? 0,
    };
  }

  /// Busca garantías por número de venta
  Future<Warranty?> getWarrantyBySaleNumber(
    Database db,
    String saleNumber,
  ) async {
    final maps = await db.query(
      'warranties',
      where: 'sale_number = ?',
      whereArgs: [saleNumber],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Warranty.fromMap(maps.first);
  }

  /// Extiende una garantía
  Future<void> extendWarranty(
    Database db,
    int warrantyId,
    int additionalMonths,
  ) async {
    final warranty = await getWarrantyById(db, warrantyId);
    if (warranty == null) return;

    final newEndDate = warranty.endDate.add(
      Duration(days: 30 * additionalMonths),
    );

    await db.update(
      'warranties',
      {
        'end_date': newEndDate.toIso8601String(),
        'duration_months': warranty.durationMonths + additionalMonths,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [warrantyId],
    );
  }
}
