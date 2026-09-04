import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'postgres_service.dart';
import '../db_helper.dart';

enum HybridSyncStatus {
  idle,
  syncing,
  offline,
  error,
  conflict
}

class HybridSyncService {
  HybridSyncService._();
  
  static final HybridSyncService instance = HybridSyncService._();
  
  HybridSyncStatus _status = HybridSyncStatus.idle;
  Timer? _syncTimer;
  DateTime? _lastSyncTimestamp;
  bool _isPostgresAvailable = false;
  
  HybridSyncStatus get status => _status;
  DateTime? get lastSyncTimestamp => _lastSyncTimestamp;
  bool get isPostgresAvailable => _isPostgresAvailable;
  
  final List<void Function(HybridSyncStatus)> _statusListeners = [];
  
  void addStatusListener(void Function(HybridSyncStatus) listener) {
    _statusListeners.add(listener);
  }
  
  void removeStatusListener(void Function(HybridSyncStatus) listener) {
    _statusListeners.remove(listener);
  }
  
  void _setStatus(HybridSyncStatus newStatus) {
    _status = newStatus;
    for (final listener in _statusListeners) {
      listener(newStatus);
    }
  }
  
  /// Retained only for source compatibility.
  ///
  /// The former hybrid engine called REST endpoints that are not part of the
  /// authenticated Control Center contract and applied operational rows
  /// directly. It is intentionally inert; use [SyncService] instead.
  @Deprecated('Use SyncService; legacy hybrid replication is disabled.')
  Future<void> initialize() async {
    _syncTimer?.cancel();
    _isPostgresAvailable = false;
    _setStatus(HybridSyncStatus.offline);
    await _loadLastSyncTimestamp();
    debugPrint(
      'HybridSyncService legacy deshabilitado; use SyncService autenticado.',
    );
  }

  Future<void> _loadLastSyncTimestamp() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['last_hybrid_sync_timestamp'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      _lastSyncTimestamp = DateTime.tryParse(rows.first['valor']?.toString() ?? '');
    }
  }
  
  void stopAutoSync() {
    _syncTimer?.cancel();
  }
  
  Future<void> sync() async {
    if (_status == HybridSyncStatus.syncing) return;
    if (!_isPostgresAvailable) {
      debugPrint('PostgreSQL not available, skipping sync');
      return;
    }
    
    _setStatus(HybridSyncStatus.syncing);
    
    try {
      // 1. Push cambios locales a PostgreSQL
      await _pushLocalChanges();
      
      // 2. Pull cambios de PostgreSQL
      await _pullRemoteChanges();
      
      // 3. Actualizar timestamp de última sincronización
      _lastSyncTimestamp = DateTime.now();
      await _saveLastSyncTimestamp();
      
      _setStatus(HybridSyncStatus.idle);
      debugPrint('Hybrid sync completed successfully');
    } catch (e) {
      debugPrint('Hybrid sync error: $e');
      _setStatus(HybridSyncStatus.error);
    }
  }
  
  Future<void> _pushLocalChanges() async {
    final db = await DatabaseHelper.instance.database;
    final postgresService = PostgresService();
    
    // Obtener cambios no sincronizados
    final pendingChanges = await db.query(
      'local_changes',
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );
    
    if (pendingChanges.isEmpty) return;
    
    for (final change in pendingChanges) {
      final tableName = change['table_name'] as String;
      final operation = change['operation'] as String;
      final data = jsonDecode(change['data'] as String);
      
      try {
        switch (operation) {
          case 'insert':
            await postgresService.insert(tableName, data);
            break;
          case 'update':
            final id = data['id'];
            await postgresService.update(tableName, data, 'id = ?', [id]);
            break;
          case 'delete':
            final id = data['id'];
            await postgresService.delete(tableName, 'id = ?', [id]);
            break;
        }
        
        // Marcar como sincronizado
        await db.update(
          'local_changes',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [change['id']],
        );
        
        debugPrint('Pushed change: $tableName $operation');
      } catch (e) {
        debugPrint('Error pushing change: $e');
        // Continuar con el siguiente cambio
      }
    }
  }
  
  Future<void> _pullRemoteChanges() async {
    final db = await DatabaseHelper.instance.database;
    final postgresService = PostgresService();
    
    // Desactivar temporalmente los triggers locales durante la descarga para evitar bucles
    await db.execute("UPDATE sync_state SET is_syncing = 1 WHERE rowid = 1");
    
    try {
      // Tablas a sincronizar
      final tables = ['productos', 'clientes', 'ventas', 'venta_items'];
      
      for (final tableName in tables) {
      try {
        // Obtener último timestamp de sincronización para esta tabla
        final metadataRows = await db.query(
          'sync_table_metadata',
          where: 'table_name = ?',
          whereArgs: [tableName],
          limit: 1,
        );
        
        DateTime? lastSync;
        if (metadataRows.isNotEmpty) {
          lastSync = DateTime.tryParse(metadataRows.first['last_sync_timestamp'] as String);
        }
        
        // Obtener cambios de PostgreSQL
        String query = 'SELECT * FROM $tableName';
        Map<String, dynamic>? params;
        
        if (lastSync != null) {
          query += ' WHERE updated_at > @lastSync';
          params = {'lastSync': lastSync.toIso8601String()};
        }
        
        query += ' ORDER BY updated_at ASC LIMIT 100';
        
        final remoteChanges = await postgresService.query(query, params: params);
        
        if (remoteChanges.isEmpty) continue;
        
        final localTableName = tableName == 'venta_items' ? 'ventas_detalle' : tableName;
        
        for (final remoteRecord in remoteChanges) {
          final recordId = remoteRecord['id'].toString();
          
          // Verificar si existe localmente
          final localRecords = await db.query(
            localTableName,
            where: 'id = ?',
            whereArgs: [remoteRecord['id']],
            limit: 1,
          );
          
          if (localRecords.isEmpty) {
            // Insertar nuevo registro
            await db.insert(localTableName, remoteRecord);
          } else {
            // Verificar conflicto
            final localRecord = localRecords.first;
            final localUpdatedAt = DateTime.tryParse(localRecord['updated_at']?.toString() ?? '');
            final remoteUpdatedAt = DateTime.tryParse(remoteRecord['updated_at']?.toString() ?? '');
            
            if (localUpdatedAt != null && remoteUpdatedAt != null) {
              if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
                // Actualizar con datos remotos
                await db.update(localTableName, remoteRecord, where: 'id = ?', whereArgs: [remoteRecord['id']]);
              } else if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
                // Conflicto: local es más reciente
                await _createConflict(tableName, recordId, localRecord, remoteRecord);
              }
            }
          }
        }
        
        // Actualizar metadata de sincronización
        final latestRecord = remoteChanges.last;
        final latestTimestamp = latestRecord['updated_at'] as String;
        
        if (metadataRows.isEmpty) {
          await db.insert('sync_table_metadata', {
            'table_name': tableName,
            'last_sync_timestamp': latestTimestamp,
            'last_sync_record_id': latestRecord['id'],
          });
        } else {
          await db.update(
            'sync_table_metadata',
            {
              'last_sync_timestamp': latestTimestamp,
              'last_sync_record_id': latestRecord['id'],
            },
            where: 'table_name = ?',
            whereArgs: [tableName],
          );
        }
        
        debugPrint('Pulled ${remoteChanges.length} changes from $tableName');
      } catch (e) {
        debugPrint('Error pulling changes for $tableName: $e');
        // Continuar con la siguiente tabla
      }
    }
    } finally {
      // Volver a activar los triggers
      await db.execute("UPDATE sync_state SET is_syncing = 0 WHERE rowid = 1");
    }
  }
  
  Future<void> _createConflict(String tableName, String recordId, Map<String, dynamic> localData, Map<String, dynamic> remoteData) async {
    final db = await DatabaseHelper.instance.database;
    
    // Verificar si ya existe conflicto
    final existing = await db.query(
      'sync_conflicts',
      where: 'table_name = ? AND record_id = ? AND resolved = 0',
      whereArgs: [tableName, recordId],
      limit: 1,
    );
    
    if (existing.isNotEmpty) return;
    
    await db.insert('sync_conflicts', {
      'table_name': tableName,
      'record_id': recordId,
      'local_data': jsonEncode(localData),
      'remote_data': jsonEncode(remoteData),
      'resolved': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    
    _setStatus(HybridSyncStatus.conflict);
    debugPrint('Conflict created for $tableName:$recordId');
  }
  
  Future<void> queueLocalChange(String tableName, String operation, Map<String, dynamic> data) async {
    if (!_isPostgresAvailable) {
      debugPrint('PostgreSQL not available, skipping change queue');
      return;
    }
    
    final db = await DatabaseHelper.instance.database;
    final recordId = data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.insert('local_changes', {
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'data': jsonEncode(data),
      'timestamp': DateTime.now().toIso8601String(),
      'synced': 0,
    });
    
    debugPrint('Queued local change: $tableName $operation');
  }
  
  Future<void> _saveLastSyncTimestamp() async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'app_config',
      {
        'clave': 'last_hybrid_sync_timestamp',
        'valor': _lastSyncTimestamp?.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  Future<List<Map<String, dynamic>>> getConflicts() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sync_conflicts',
      where: 'resolved = 0',
      orderBy: 'created_at DESC',
    );
    
    return rows.map((row) => {
      'id': row['id'],
      'table_name': row['table_name'],
      'record_id': row['record_id'],
      'local_data': jsonDecode(row['local_data']?.toString() ?? '{}'),
      'remote_data': jsonDecode(row['remote_data']?.toString() ?? '{}'),
      'created_at': row['created_at'],
    }).toList();
  }
  
  Future<void> resolveConflict(int conflictId, String resolution, Map<String, dynamic> data) async {
    final db = await DatabaseHelper.instance.database;
    final postgresService = PostgresService();
    
    final conflict = await db.query(
      'sync_conflicts',
      where: 'id = ?',
      whereArgs: [conflictId],
      limit: 1,
    );
    
    if (conflict.isEmpty) return;
    
    final tableName = conflict.first['table_name'] as String;
    final recordId = conflict.first['record_id']?.toString() ?? '';
    
    // Aplicar resolución
    if (resolution == 'remote') {
      // Usar datos remotos
      final remoteData = jsonDecode(conflict.first['remote_data']?.toString() ?? '{}') as Map<String, dynamic>;
      await db.update(tableName, remoteData, where: 'id = ?', whereArgs: [int.tryParse(recordId)]);
      await postgresService.update(tableName, remoteData, 'id = ?', [int.tryParse(recordId)]);
    } else if (resolution == 'local') {
      // Usar datos locales y enviar a PostgreSQL
      await postgresService.update(tableName, data, 'id = ?', [int.tryParse(recordId)]);
    }
    
    // Marcar conflicto como resuelto
    await db.update(
      'sync_conflicts',
      {
        'resolved': 1,
        'resolution': resolution,
        'resolved_data': jsonEncode(data),
      },
      where: 'id = ?',
      whereArgs: [conflictId],
    );
    
    debugPrint('Resolved conflict $conflictId with resolution: $resolution');
  }
  
  Future<void> migrateToPostgres() async {
    if (!_isPostgresAvailable) {
      throw Exception('PostgreSQL not available for migration');
    }
    
    _setStatus(HybridSyncStatus.syncing);
    
    try {
      final db = await DatabaseHelper.instance.database;
      final postgresService = PostgresService();
      
      // Tablas a migrar
      final tables = ['productos', 'clientes', 'ventas', 'venta_items'];
      
      for (final tableName in tables) {
        debugPrint('Migrating table: $tableName');
        
        // Obtener todos los datos locales
        final localData = await db.query(tableName);
        
        for (final record in localData) {
          try {
            // Insertar en PostgreSQL
            await postgresService.insert(tableName, record);
          } catch (e) {
            // Si falla por duplicado, intentar actualizar
            try {
              await postgresService.update(tableName, record, 'id = ?', [record['id']]);
            } catch (updateError) {
              debugPrint('Error migrating record ${record['id']}: $updateError');
            }
          }
        }
        
        debugPrint('Migrated ${localData.length} records from $tableName');
      }
      
      _setStatus(HybridSyncStatus.idle);
      debugPrint('Migration to PostgreSQL completed');
    } catch (e) {
      _setStatus(HybridSyncStatus.error);
      debugPrint('Migration error: $e');
      rethrow;
    }
  }
}
