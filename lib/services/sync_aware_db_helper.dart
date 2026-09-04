import 'package:sqflite/sqflite.dart';
import '../db_helper.dart';
import 'hybrid_sync_service.dart';

/// Wrapper del DatabaseHelper que detecta cambios automáticamente
/// y los encola para sincronización con PostgreSQL
class SyncAwareDatabaseHelper {
  static final SyncAwareDatabaseHelper instance = SyncAwareDatabaseHelper._();
  SyncAwareDatabaseHelper._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final HybridSyncService _syncService = HybridSyncService.instance;

  /// Tablas que deben sincronizarse
  static const Set<String> _syncableTables = {
    'productos',
    'clientes',
    'ventas',
    'venta_items',
  };

  Future<Database> get database => _dbHelper.database;

  /// Insert con detección de cambios
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = await database;
    
    // Agregar timestamp de actualización si no existe
    if (!data.containsKey('updated_at')) {
      data['updated_at'] = DateTime.now().toIso8601String();
    }
    
    final result = await db.insert(table, data);
    
    // Encolar cambio para sincronización
    if (_syncableTables.contains(table)) {
      final insertedData = Map<String, dynamic>.from(data);
      insertedData['id'] = result;
      await _syncService.queueLocalChange(table, 'insert', insertedData);
    }
    
    return result;
  }

  /// Insert con conflicto algorithm
  Future<int> insertWithConflict(
    String table,
    Map<String, dynamic> data, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final db = await database;
    
    // Agregar timestamp de actualización si no existe
    if (!data.containsKey('updated_at')) {
      data['updated_at'] = DateTime.now().toIso8601String();
    }
    
    final result = await db.insert(
      table,
      data,
      conflictAlgorithm: conflictAlgorithm ?? ConflictAlgorithm.abort,
    );
    
    // Encolar cambio para sincronización
    if (_syncableTables.contains(table)) {
      final insertedData = Map<String, dynamic>.from(data);
      insertedData['id'] = result;
      await _syncService.queueLocalChange(table, 'insert', insertedData);
    }
    
    return result;
  }

  /// Query (sin detección de cambios - solo lectura)
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Update con detección de cambios
  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    
    // Agregar timestamp de actualización
    values['updated_at'] = DateTime.now().toIso8601String();
    
    final result = await db.update(table, values, where: where, whereArgs: whereArgs);
    
    // Encolar cambio para sincronización
    if (_syncableTables.contains(table) && result > 0) {
      // Obtener los registros actualizados para encolarlos
      final updatedRecords = await db.query(
        table,
        where: where,
        whereArgs: whereArgs,
      );
      
      for (final record in updatedRecords) {
        await _syncService.queueLocalChange(table, 'update', record);
      }
    }
    
    return result;
  }

  /// Delete con detección de cambios
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    
    // Obtener los registros antes de eliminar para encolarlos
    List<Map<String, dynamic>> recordsToDelete = [];
    if (_syncableTables.contains(table)) {
      recordsToDelete = await db.query(
        table,
        where: where,
        whereArgs: whereArgs,
      );
    }
    
    final result = await db.delete(table, where: where, whereArgs: whereArgs);
    
    // Encolar cambios para sincronización
    if (_syncableTables.contains(table)) {
      for (final record in recordsToDelete) {
        await _syncService.queueLocalChange(table, 'delete', record);
      }
    }
    
    return result;
  }

  /// Execute SQL directo (sin detección automática)
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    final db = await database;
    await db.execute(sql, arguments);
  }

  /// Raw query (sin detección automática)
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final db = await database;
    return db.rawQuery(sql, arguments);
  }

  /// Batch operations con detección de cambios
  Future<List<Object?>> batch(Batch batch) async {
    return batch.commit(noResult: false);
  }

  /// Transaction con detección de cambios
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }

  /// Método de conveniencia para operaciones que no deben sincronizarse
  /// (útil para operaciones internas o configuración)
  Future<int> insertWithoutSync(String table, Map<String, dynamic> data) async {
    final db = await database;
    return db.insert(table, data);
  }

  Future<int> updateWithoutSync(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> deleteWithoutSync(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }
}
