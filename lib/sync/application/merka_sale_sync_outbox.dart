import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../app_session.dart';
import '../../services/licencia_service.dart';
import 'merka_sync_tenant_resolver.dart';

abstract class SaleSyncOutboxWriter {
  Future<void> enqueueSaleConfirmed({
    required DatabaseExecutor db,
    required int companyId,
    required int saleId,
  });
}

class MerkaSaleSyncOutboxWriter implements SaleSyncOutboxWriter {
  const MerkaSaleSyncOutboxWriter({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  @override
  Future<void> enqueueSaleConfirmed({
    required DatabaseExecutor db,
    required int companyId,
    required int saleId,
  }) async {
    await MerkaSyncLocalSchema.ensure(db);

    final license = await LicenciaService.instance.obtenerLicencia();
    final tenantKind = resolveMerkaSyncTenantKind(license);
    final tenantId = resolveMerkaSyncTenantId(license, companyId);
    final sourceDeviceId = await _resolveDeviceId(db, license);
    final sourceUserId = AppSession.usuarioId ?? 'local';
    final occurredAt = DateTime.now().toUtc();
    final saleRows = await db.query(
      'ventas',
      where: 'id = ? AND company_id = ?',
      whereArgs: [saleId, companyId],
      limit: 1,
    );
    if (saleRows.isEmpty) {
      throw StateError('No se encontró la venta $saleId para sincronizar.');
    }

    final sale = Map<String, Object?>.from(saleRows.single);
    final branchId = (sale['branch_id'] as num?)?.toInt() ?? 1;
    final details = await db.query(
      'ventas_detalle',
      where: 'venta_id = ? AND company_id = ?',
      whereArgs: [saleId, companyId],
      orderBy: 'id ASC',
    );
    final inventoryMovements = await db.query(
      'movimientos_inventario',
      where: 'company_id = ? AND motivo = ?',
      whereArgs: [companyId, 'FACTURA POS #$saleId'],
      orderBy: 'id ASC',
    );
    final kardexRows = await _queryIfExists(
      db,
      'kardex_inventario',
      where: 'company_id = ? AND documento_tipo = ? AND documento_id = ?',
      whereArgs: [companyId, 'venta', saleId],
      orderBy: 'id ASC',
    );

    final aggregateId = 'sale:$companyId:$sourceDeviceId:$saleId';
    final idempotencyKey = 'sale.confirmed:$companyId:$sourceDeviceId:$saleId';
    final payload = <String, Object?>{
      'schema_version': 1,
      'event_name': 'sale.confirmed',
      'tenant': {
        'tenant_kind': tenantKind,
        'tenant_id': tenantId,
        'company_id': companyId,
        'branch_id': branchId,
      },
      'source': {'device_id': sourceDeviceId, 'user_id': sourceUserId},
      'sale': sale,
      'details': details.map((row) => Map<String, Object?>.from(row)).toList(),
      'inventory_movements': inventoryMovements
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
      'kardex': kardexRows
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
      'occurred_at': occurredAt.toIso8601String(),
    };
    final payloadJson = jsonEncode(payload);
    final payloadChecksum = sha256.convert(utf8.encode(payloadJson)).toString();

    await db.insert('merka_sync_outbox', {
      'event_id': _uuid.v4(),
      'tenant_kind': tenantKind,
      'tenant_id': tenantId,
      'company_id': companyId,
      'branch_id': branchId,
      'aggregate_type': 'sale',
      'aggregate_id': aggregateId,
      'operation': 'confirmed',
      'event_name': 'sale.confirmed',
      'event_version': 1,
      'payload_json': payloadJson,
      'payload_checksum': payloadChecksum,
      'idempotency_key': idempotencyKey,
      'source_device_id': sourceDeviceId,
      'source_user_id': sourceUserId,
      'status': 'pending',
      'attempts': 0,
      'created_at': occurredAt.toIso8601String(),
      'updated_at': occurredAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<String> _resolveDeviceId(
    DatabaseExecutor db,
    LicenciaInfo? license,
  ) async {
    final licensedInstallation = license?.installationId?.trim();
    if (licensedInstallation != null && licensedInstallation.isNotEmpty) {
      return licensedInstallation;
    }

    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['merka_sync_device_id'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final stored = rows.single['valor']?.toString().trim();
      if (stored != null && stored.isNotEmpty) return stored;
    }

    final generated = 'device-${_uuid.v4()}';
    await db.insert('app_config', {
      'clave': 'merka_sync_device_id',
      'valor': generated,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return generated;
  }

  Future<List<Map<String, Object?>>> _queryIfExists(
    DatabaseExecutor db,
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final exists = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (exists.isEmpty) return const [];
    final rows = await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }
}

class MerkaMasterDataSyncOutboxWriter {
  const MerkaMasterDataSyncOutboxWriter({Uuid uuid = const Uuid()})
    : _uuid = uuid;

  final Uuid _uuid;

  Future<void> enqueueProductUpserted({
    required DatabaseExecutor db,
    required int companyId,
    required int productId,
  }) async {
    await _enqueueRowUpserted(
      db: db,
      companyId: companyId,
      table: 'productos',
      id: productId,
      aggregateType: 'product',
      eventName: 'product.upserted',
      rowLabel: 'producto',
    );
  }

  Future<void> enqueueCustomerUpserted({
    required DatabaseExecutor db,
    required int companyId,
    required int customerId,
  }) async {
    await _enqueueRowUpserted(
      db: db,
      companyId: companyId,
      table: 'clientes',
      id: customerId,
      aggregateType: 'customer',
      eventName: 'customer.upserted',
      rowLabel: 'cliente',
    );
  }

  Future<int> enqueueExistingMasterData({
    required DatabaseExecutor db,
    required int companyId,
  }) async {
    await MerkaSyncLocalSchema.ensure(db);
    if (await _isApplyingRemoteSync(db)) return 0;

    var queued = 0;
    if (await _tableExists(db, 'productos')) {
      final products = await db.query(
        'productos',
        columns: ['id'],
        where: 'company_id = ?',
        whereArgs: [companyId],
        orderBy: 'id ASC',
      );
      for (final product in products) {
        final id = _intValue(product['id']);
        if (id == null) continue;
        final before = await _outboxCount(db);
        await enqueueProductUpserted(
          db: db,
          companyId: companyId,
          productId: id,
        );
        final after = await _outboxCount(db);
        if (after > before) queued++;
      }
    }

    if (await _tableExists(db, 'clientes')) {
      final customers = await db.query(
        'clientes',
        columns: ['id'],
        where: 'company_id = ?',
        whereArgs: [companyId],
        orderBy: 'id ASC',
      );
      for (final customer in customers) {
        final id = _intValue(customer['id']);
        if (id == null) continue;
        final before = await _outboxCount(db);
        await enqueueCustomerUpserted(
          db: db,
          companyId: companyId,
          customerId: id,
        );
        final after = await _outboxCount(db);
        if (after > before) queued++;
      }
    }

    return queued;
  }

  Future<void> _enqueueRowUpserted({
    required DatabaseExecutor db,
    required int companyId,
    required String table,
    required int id,
    required String aggregateType,
    required String eventName,
    required String rowLabel,
  }) async {
    await MerkaSyncLocalSchema.ensure(db);
    if (await _isApplyingRemoteSync(db)) return;

    final rows = await db.query(
      table,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No se encontró el $rowLabel $id para sincronizar.');
    }

    final license = await LicenciaService.instance.obtenerLicencia();
    final tenantKind = resolveMerkaSyncTenantKind(license);
    final tenantId = resolveMerkaSyncTenantId(license, companyId);
    final sourceDeviceId = await _resolveDeviceId(db, license);
    final sourceUserId = AppSession.usuarioId ?? 'local';
    final occurredAt = DateTime.now().toUtc();
    final branchId = _intValue(rows.single['branch_id']) ?? 1;
    final aggregateId = '$aggregateType:$companyId:$sourceDeviceId:$id';
    final row = Map<String, Object?>.from(rows.single);
    final contentChecksum = sha256
        .convert(utf8.encode(jsonEncode({'entity': row})))
        .toString();
    final payload = <String, Object?>{
      'schema_version': 1,
      'event_name': eventName,
      'tenant': {
        'tenant_kind': tenantKind,
        'tenant_id': tenantId,
        'company_id': companyId,
        'branch_id': branchId,
      },
      'source': {'device_id': sourceDeviceId, 'user_id': sourceUserId},
      'entity': row,
      'occurred_at': occurredAt.toIso8601String(),
    };
    final payloadJson = jsonEncode(payload);
    final payloadChecksum = sha256.convert(utf8.encode(payloadJson)).toString();
    final idempotencyKey =
        '$eventName:$companyId:$sourceDeviceId:$id:$contentChecksum';

    await db.insert('merka_sync_outbox', {
      'event_id': _uuid.v4(),
      'tenant_kind': tenantKind,
      'tenant_id': tenantId,
      'company_id': companyId,
      'branch_id': branchId,
      'aggregate_type': aggregateType,
      'aggregate_id': aggregateId,
      'operation': 'upserted',
      'event_name': eventName,
      'event_version': 1,
      'payload_json': payloadJson,
      'payload_checksum': payloadChecksum,
      'idempotency_key': idempotencyKey,
      'source_device_id': sourceDeviceId,
      'source_user_id': sourceUserId,
      'status': 'pending',
      'attempts': 0,
      'created_at': occurredAt.toIso8601String(),
      'updated_at': occurredAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> _isApplyingRemoteSync(DatabaseExecutor db) async {
    if (!await _tableExists(db, 'sync_state')) return false;
    final rows = await db.query('sync_state', limit: 1);
    if (rows.isEmpty) return false;
    return _intValue(rows.single['is_syncing']) == 1;
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<int> _outboxCount(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM merka_sync_outbox',
    );
    return ((rows.single['total'] as num?) ?? 0).toInt();
  }

  Future<String> _resolveDeviceId(
    DatabaseExecutor db,
    LicenciaInfo? license,
  ) async {
    final licensedInstallation = license?.installationId?.trim();
    if (licensedInstallation != null && licensedInstallation.isNotEmpty) {
      return licensedInstallation;
    }

    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['merka_sync_device_id'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final stored = rows.single['valor']?.toString().trim();
      if (stored != null && stored.isNotEmpty) return stored;
    }

    final generated = 'device-${_uuid.v4()}';
    await db.insert('app_config', {
      'clave': 'merka_sync_device_id',
      'valor': generated,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return generated;
  }

  int? _intValue(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class MerkaSyncLocalSchema {
  const MerkaSyncLocalSchema._();

  static Future<void> ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_config(
        clave TEXT PRIMARY KEY,
        valor TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS merka_sync_outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        tenant_kind TEXT NOT NULL DEFAULT 'commercial',
        tenant_id TEXT NOT NULL,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        event_name TEXT NOT NULL,
        event_version INTEGER NOT NULL DEFAULT 1,
        payload_json TEXT NOT NULL,
        payload_checksum TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        source_device_id TEXT NOT NULL,
        source_user_id TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        next_attempt_at TEXT,
        last_error TEXT,
        pushed_at TEXT,
        remote_cursor TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS merka_sync_inbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_event_id TEXT NOT NULL UNIQUE,
        tenant_kind TEXT NOT NULL DEFAULT 'commercial',
        tenant_id TEXT NOT NULL,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        aggregate_type TEXT NOT NULL,
        aggregate_id TEXT NOT NULL,
        event_name TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        payload_checksum TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        source_device_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        received_at TEXT NOT NULL,
        updated_at TEXT,
        applied_at TEXT,
        next_attempt_at TEXT,
        last_error TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS merka_sync_entity_map(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_kind TEXT NOT NULL,
        tenant_id TEXT NOT NULL,
        remote_aggregate_type TEXT NOT NULL,
        remote_aggregate_id TEXT NOT NULL,
        remote_event_id TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        source_device_id TEXT NOT NULL,
        local_table TEXT NOT NULL,
        local_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(tenant_kind, tenant_id, remote_aggregate_type, remote_aggregate_id),
        UNIQUE(tenant_kind, tenant_id, idempotency_key)
      )
    ''');
    await _ensureColumn(
      db,
      'merka_sync_inbox',
      'attempts',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(db, 'merka_sync_inbox', 'updated_at', 'TEXT');
    await _ensureColumn(db, 'merka_sync_inbox', 'next_attempt_at', 'TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS merka_sync_checkpoints(
        tenant_kind TEXT NOT NULL,
        tenant_id TEXT NOT NULL,
        source_device_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        cursor TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(tenant_kind, tenant_id, source_device_id, direction)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_merka_sync_outbox_pending
      ON merka_sync_outbox(status, created_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_merka_sync_outbox_tenant
      ON merka_sync_outbox(tenant_kind, tenant_id, aggregate_type, aggregate_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_merka_sync_inbox_pending
      ON merka_sync_inbox(status, received_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_merka_sync_entity_map_remote
      ON merka_sync_entity_map(
        tenant_kind,
        tenant_id,
        remote_aggregate_type,
        remote_aggregate_id
      )
    ''');
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}
