// ============================================================
// commission_service.dart
// Servicio de gestión de comisiones
// ============================================================

import 'package:sqflite/sqflite.dart';
import '../domain/commission.dart';

class CommissionService {
  static final CommissionService instance = CommissionService._internal();
  
  CommissionService._internal();
  
  /// Crea las tablas necesarias para comisiones
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS commissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        salesperson_id INTEGER NOT NULL,
        salesperson_name TEXT NOT NULL,
        sale_id INTEGER,
        sale_number TEXT,
        sale_amount REAL NOT NULL,
        commission_rate REAL NOT NULL,
        commission_amount REAL NOT NULL,
        status TEXT DEFAULT 'pending',
        paid_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS commission_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        salesperson_id INTEGER,
        commission_rate REAL NOT NULL,
        min_amount REAL DEFAULT 0,
        max_amount REAL,
        product_category TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    
    // Índices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_commissions_company ON commissions(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_commissions_salesperson ON commissions(salesperson_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_commissions_status ON commissions(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_commission_rules_company ON commission_rules(company_id)');
  }
  
  /// Calcula la **tasa** de comisión aplicable (en porcentaje, ej. 5.0 para el 5%).
  ///
  /// Este método devuelve la tasa, NO el monto ya calculado.
  /// Para obtener el monto usa [calculateCommissionAmount].
  Future<double> getApplicableRate(
    Database db,
    int companyId,
    int salespersonId,
    double saleAmount, {
    String? productCategory,
  }) async {
    // Regla específica para el vendedor
    final ruleResult = await db.query(
      'commission_rules',
      where: 'company_id = ? AND salesperson_id = ? AND is_active = 1',
      whereArgs: [companyId, salespersonId],
      limit: 1,
    );

    if (ruleResult.isNotEmpty) {
      final rule = ruleResult.first;
      final rate = (rule['commission_rate'] as num).toDouble();
      final minAmount = (rule['min_amount'] as num?)?.toDouble() ?? 0;
      final maxAmount = (rule['max_amount'] as num?)?.toDouble();
      if (saleAmount >= minAmount &&
          (maxAmount == null || saleAmount <= maxAmount)) {
        return rate;
      }
    }

    // Regla general de la empresa
    final generalRuleResult = await db.query(
      'commission_rules',
      where: 'company_id = ? AND salesperson_id IS NULL AND is_active = 1',
      whereArgs: [companyId],
      limit: 1,
    );
    if (generalRuleResult.isNotEmpty) {
      return (generalRuleResult.first['commission_rate'] as num).toDouble();
    }

    // Tasa por defecto: 5%
    return 5.0;
  }

  /// Calcula la comisión para una venta.
  /// Devuelve el MONTO ya calculado (no la tasa).
  /// [saleAmount] debe ser en major units (ej. 10000.0 para $10.000).
  Future<double> calculateCommission(
    Database db,
    int companyId,
    int salespersonId,
    double saleAmount, {
    String? productCategory,
  }) async {
    final rate = await getApplicableRate(
      db, companyId, salespersonId, saleAmount,
      productCategory: productCategory,
    );
    return saleAmount * (rate / 100);
  }
  
  /// Crea una comisión
  Future<int> createCommission(Database db, Commission commission) async {
    final id = await db.insert('commissions', commission.toMap());
    return id;
  }
  
  /// Genera automáticamente la comisión para una venta.
  ///
  /// Corrección: `calculateCommission` devuelve el MONTO directamente.
  /// Ya no se multiplica de nuevo por `saleAmount * (rate / 100)`.
  Future<int> generateCommissionForSale(
    Database db,
    int companyId,
    int saleId,
    String saleNumber,
    double saleAmount,
    int salespersonId,
    String salespersonName,
  ) async {
    // commissionAmount ya es el monto final (calculateCommission lo calcula).
    final commissionAmount = await calculateCommission(
      db, companyId, salespersonId, saleAmount);
    // Derivar la tasa para registrarla en el campo commission_rate.
    final rate = saleAmount > 0 ? (commissionAmount / saleAmount) * 100 : 0.0;

    final commission = Commission(
      companyId: companyId,
      salespersonId: salespersonId,
      salespersonName: salespersonName,
      saleId: saleId,
      saleNumber: saleNumber,
      saleAmount: saleAmount,
      commissionRate: rate,          // tasa real (ej. 5.0)
      commissionAmount: commissionAmount, // monto real (ej. 50000.0)
      createdAt: DateTime.now(),
    );

    return await createCommission(db, commission);
  }
  
  /// Marca una comisión como pagada
  Future<void> markAsPaid(Database db, int commissionId) async {
    await db.update(
      'commissions',
      {
        'status': 'paid',
        'paid_date': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [commissionId],
    );
  }
  
  /// Cancela una comisión
  Future<void> cancelCommission(Database db, int commissionId) async {
    await db.update(
      'commissions',
      {
        'status': 'cancelled',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [commissionId],
    );
  }
  
  /// Obtiene comisiones por vendedor
  Future<List<Commission>> getCommissionsBySalesperson(
    Database db,
    int salespersonId,
  ) async {
    final maps = await db.query(
      'commissions',
      where: 'salesperson_id = ?',
      whereArgs: [salespersonId],
      orderBy: 'created_at DESC',
    );
    
    return maps.map((map) => Commission.fromMap(map)).toList();
  }
  
  /// Obtiene comisiones por estado
  Future<List<Commission>> getCommissionsByStatus(
    Database db,
    int companyId,
    String status,
  ) async {
    final maps = await db.query(
      'commissions',
      where: 'company_id = ? AND status = ?',
      whereArgs: [companyId, status],
      orderBy: 'created_at DESC',
    );
    
    return maps.map((map) => Commission.fromMap(map)).toList();
  }
  
  /// Obtiene comisiones pendientes de pago
  Future<List<Commission>> getPendingCommissions(Database db, int companyId) async {
    return await getCommissionsByStatus(db, companyId, 'pending');
  }
  
  /// Obtiene resumen de comisiones por vendedor
  Future<List<Map<String, dynamic>>> getCommissionsSummaryBySalesperson(
    Database db,
    int companyId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String where = 'company_id = ?';
    final whereArgs = <Object>[companyId];
    
    if (startDate != null) {
      where += ' AND created_at >= ?';
      whereArgs.add(startDate.toIso8601String());
    }
    
    if (endDate != null) {
      where += ' AND created_at <= ?';
      whereArgs.add(endDate.toIso8601String());
    }
    
    final maps = await db.rawQuery('''
      SELECT 
        salesperson_id,
        salesperson_name,
        COUNT(*) as total_commissions,
        SUM(sale_amount) as total_sales,
        SUM(commission_amount) as total_commissions_amount,
        AVG(commission_rate) as avg_commission_rate
      FROM commissions
      WHERE $where
      GROUP BY salesperson_id, salesperson_name
      ORDER BY total_commissions_amount DESC
    ''', whereArgs);
    
    return maps;
  }
  
  /// Registra una regla de comisión
  Future<int> registerCommissionRule(
    Database db,
    int companyId,
    double commissionRate, {
    int? salespersonId,
    double? minAmount,
    double? maxAmount,
    String? productCategory,
  }) async {
    final id = await db.insert('commission_rules', {
      'company_id': companyId,
      'salesperson_id': salespersonId,
      'commission_rate': commissionRate,
      'min_amount': minAmount ?? 0,
      'max_amount': maxAmount,
      'product_category': productCategory,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    return id;
  }
  
  /// Obtiene reglas de comisión de una empresa
  Future<List<Map<String, dynamic>>> getCommissionRules(Database db, int companyId) async {
    final maps = await db.query(
      'commission_rules',
      where: 'company_id = ? AND is_active = 1',
      whereArgs: [companyId],
      orderBy: 'salesperson_id IS NULL, salesperson_id ASC',
    );
    
    return maps;
  }
  
  /// Actualiza una regla de comisión
  Future<void> updateCommissionRule(
    Database db,
    int ruleId,
    double commissionRate, {
    double? minAmount,
    double? maxAmount,
    String? productCategory,
  }) async {
    await db.update(
      'commission_rules',
      {
        'commission_rate': commissionRate,
        'min_amount': minAmount,
        'max_amount': maxAmount,
        'product_category': productCategory,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }
  
  /// Desactiva una regla de comisión
  Future<void> deactivateCommissionRule(Database db, int ruleId) async {
    await db.update(
      'commission_rules',
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [ruleId],
    );
  }
  
  /// Obtiene estadísticas de comisiones
  Future<Map<String, dynamic>> getCommissionStatistics(Database db, int companyId) async {
    final totalResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        SUM(commission_amount) as total_amount
      FROM commissions
      WHERE company_id = ?
    ''', [companyId]);
    
    final pendingResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        SUM(commission_amount) as total_amount
      FROM commissions
      WHERE company_id = ? AND status = 'pending'
    ''', [companyId]);
    
    final paidResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        SUM(commission_amount) as total_amount
      FROM commissions
      WHERE company_id = ? AND status = 'paid'
    ''', [companyId]);
    
    return {
      'total_commissions': Sqflite.firstIntValue(totalResult) ?? 0,
      'total_amount': (totalResult.first['total_amount'] as num?)?.toDouble() ?? 0,
      'pending_commissions': Sqflite.firstIntValue(pendingResult) ?? 0,
      'pending_amount': (pendingResult.first['total_amount'] as num?)?.toDouble() ?? 0,
      'paid_commissions': Sqflite.firstIntValue(paidResult) ?? 0,
      'paid_amount': (paidResult.first['total_amount'] as num?)?.toDouble() ?? 0,
    };
  }
}
