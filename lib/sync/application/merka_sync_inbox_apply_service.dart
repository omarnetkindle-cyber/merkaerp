import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../inventory/application/inventory_movement_service.dart';
import 'merka_sale_sync_outbox.dart';

class MerkaSyncInboxApplyResult {
  const MerkaSyncInboxApplyResult({
    required this.applied,
    required this.skipped,
    required this.failed,
    required this.terminalErrors,
  });

  final int applied;
  final int skipped;
  final int failed;
  final int terminalErrors;

  int get processed => applied + skipped + failed + terminalErrors;

  Map<String, Object?> toMap() => {
    'applied': applied,
    'skipped': skipped,
    'failed': failed,
    'terminal_errors': terminalErrors,
    'processed': processed,
  };
}

class MerkaSyncInboxApplyService {
  MerkaSyncInboxApplyService({DateTime Function()? now, this.maxAttempts = 5})
    : _now = now ?? (() => DateTime.now().toUtc());

  final DateTime Function() _now;
  final int maxAttempts;

  Future<MerkaSyncInboxApplyResult> applyPending({
    required Database db,
    int limit = 50,
  }) async {
    await MerkaSyncLocalSchema.ensure(db);
    final current = _now().toUtc();
    final rows = await db.query(
      'merka_sync_inbox',
      where: '''
        status IN (?, ?)
        AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
      ''',
      whereArgs: ['pending', 'retry', current.toIso8601String()],
      orderBy: 'id ASC',
      limit: limit,
    );

    var applied = 0;
    var skipped = 0;
    var failed = 0;
    var terminalErrors = 0;

    for (final row in rows) {
      try {
        final eventName = row['event_name']?.toString();
        switch (eventName) {
          case 'product.upserted':
            await db.transaction((txn) async {
              await _withSyncState(txn, () => _applyProductUpserted(txn, row));
            });
            applied++;
          case 'customer.upserted':
            await db.transaction((txn) async {
              await _withSyncState(txn, () => _applyCustomerUpserted(txn, row));
            });
            applied++;
          case 'sale.confirmed':
            await db.transaction((txn) async {
              await _withSyncState(txn, () => _applySaleConfirmed(txn, row));
            });
            applied++;
          default:
            await _markUnsupported(db, row, 'Evento no soportado: $eventName');
            skipped++;
        }
      } catch (error) {
        final terminal = await _markFailed(db, row, error);
        if (terminal) {
          terminalErrors++;
        } else {
          failed++;
        }
      }
    }

    return MerkaSyncInboxApplyResult(
      applied: applied,
      skipped: skipped,
      failed: failed,
      terminalErrors: terminalErrors,
    );
  }

  Future<void> _applySaleConfirmed(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow,
  ) async {
    final tenantKind = inboxRow['tenant_kind'].toString();
    final tenantId = inboxRow['tenant_id'].toString();
    final aggregateType = inboxRow['aggregate_type'].toString();
    final aggregateId = inboxRow['aggregate_id'].toString();
    final idempotencyKey = inboxRow['idempotency_key'].toString();
    final remoteEventId = inboxRow['remote_event_id'].toString();
    final sourceDeviceId = inboxRow['source_device_id'].toString();

    final existingMap = await db.query(
      'merka_sync_entity_map',
      where: '''
        tenant_kind = ?
        AND tenant_id = ?
        AND (
          (remote_aggregate_type = ? AND remote_aggregate_id = ?)
          OR idempotency_key = ?
        )
      ''',
      whereArgs: [
        tenantKind,
        tenantId,
        aggregateType,
        aggregateId,
        idempotencyKey,
      ],
      limit: 1,
    );
    if (existingMap.isNotEmpty) {
      await _markApplied(db, inboxRow);
      return;
    }

    final payload = _decodeMap(inboxRow['payload_json']);
    final sale = _mapValue(payload['sale'], 'payload.sale');
    final details = _listOfMaps(payload['details'], 'payload.details');
    if (details.isEmpty) {
      throw const FormatException('payload.details requerido para venta.');
    }

    final companyId =
        _intValue(inboxRow['company_id']) ?? _intValue(sale['company_id']) ?? 0;
    if (companyId <= 0) {
      throw const FormatException('company_id requerido para venta remota.');
    }
    final saleDate =
        _stringValue(sale['fecha']) ?? _stringValue(payload['occurred_at']);
    if (saleDate == null) {
      throw const FormatException('fecha requerida para venta remota.');
    }
    final localCustomerId = await _resolveRemoteCustomerId(
      db: db,
      inboxRow: inboxRow,
      companyId: companyId,
      remoteCustomerId: _intValue(sale['cliente_id']),
    );

    for (final detail in details) {
      final remoteProductId = _intValue(detail['producto_id']);
      if (remoteProductId == null || remoteProductId <= 0) {
        throw const FormatException('producto_id inválido en detalle remoto.');
      }
      final productId = await _resolveRemoteProductId(
        db: db,
        inboxRow: inboxRow,
        companyId: companyId,
        remoteProductId: remoteProductId,
      );
      final productRows = await db.query(
        'productos',
        where: 'id = ? AND company_id = ?',
        whereArgs: [productId, companyId],
        limit: 1,
      );
      if (productRows.isEmpty) {
        throw StateError(
          'Producto $productId no existe localmente para aplicar venta remota.',
        );
      }
    }

    final localSaleId = await _insertFiltered(db, 'ventas', {
      'company_id': companyId,
      'producto_id': _intValue(sale['producto_id']) ?? 0,
      'producto': 'Factura POS sincronizada',
      'cantidad': _numValue(sale['cantidad']) ?? details.length,
      'precio_unitario': _numValue(sale['precio_unitario']) ?? 0,
      'costo_unitario': _numValue(sale['costo_unitario']) ?? 0,
      'subtotal': _numValue(sale['subtotal']) ?? 0,
      'impuesto_pct': _numValue(sale['impuesto_pct']) ?? 0,
      'impuesto_total': _numValue(sale['impuesto_total']) ?? 0,
      'total': _numValue(sale['total']) ?? 0,
      'fecha': saleDate,
      'metodo_pago_id': _intValue(sale['metodo_pago_id']) ?? 1,
      'estado': _stringValue(sale['estado']) ?? 'emitida',
      'cliente_id': localCustomerId,
      'cliente': _stringValue(sale['cliente']),
      'efectivo': _numValue(sale['efectivo']) ?? 0,
      'transferencia': _numValue(sale['transferencia']) ?? 0,
      'credito': _numValue(sale['credito']) ?? 0,
      'retefuente': _numValue(sale['retefuente']) ?? 0,
      'retefuente_concepto':
          _stringValue(sale['retefuente_concepto']) ?? 'otros_ingresos',
      'retefuente_base': _numValue(sale['retefuente_base']) ?? 0,
      'retefuente_tasa': _numValue(sale['retefuente_tasa']) ?? 0,
      'reteiva': _numValue(sale['reteiva']) ?? 0,
      'reteica': _numValue(sale['reteica']) ?? 0,
      'created_by': 'sync:$sourceDeviceId',
    });

    await db.update(
      'ventas',
      {'producto': 'Factura POS #$localSaleId'},
      where: 'id = ? AND company_id = ?',
      whereArgs: [localSaleId, companyId],
    );

    for (final detail in details) {
      final productId = await _resolveRemoteProductId(
        db: db,
        inboxRow: inboxRow,
        companyId: companyId,
        remoteProductId: _intValue(detail['producto_id'])!,
      );
      final quantity = (_numValue(detail['cantidad']) ?? 0).toDouble();
      if (quantity <= 0) {
        throw const FormatException('cantidad inválida en detalle remoto.');
      }
      final productRows = await db.query(
        'productos',
        where: 'id = ? AND company_id = ?',
        whereArgs: [productId, companyId],
        limit: 1,
      );
      final product = productRows.single;
      final currentStock = (_numValue(product['stock']) ?? 0).toDouble();
      final currentCost = (_numValue(product['costo']) ?? 0).toInt();
      final newStock = currentStock - quantity;
      await db.update(
        'productos',
        {'stock': newStock},
        where: 'id = ? AND company_id = ?',
        whereArgs: [productId, companyId],
      );
      await _insertFiltered(db, 'ventas_detalle', {
        'company_id': companyId,
        'venta_id': localSaleId,
        'producto_id': productId,
        'producto':
            _stringValue(detail['producto']) ?? product['nombre'].toString(),
        'cantidad': quantity,
        'precio_unitario': _numValue(detail['precio_unitario']) ?? 0,
        'subtotal': _numValue(detail['subtotal']) ?? 0,
        'impuesto_pct': _numValue(detail['impuesto_pct']) ?? 0,
        'impuesto_total': _numValue(detail['impuesto_total']) ?? 0,
      });
      await InventoryMovementService.record(
        db: db,
        companyId: companyId,
        productId: productId,
        type: 'salida',
        quantity: quantity,
        stockBefore: currentStock,
        stockAfter: newStock,
        costBeforeMinor: currentCost,
        costAfterMinor: currentCost,
        costTotalMinor: (currentCost * quantity).round(),
        reason: 'SYNC VENTA $remoteEventId',
        date: saleDate,
        documentType: 'venta',
        documentId: localSaleId,
        createdBy: 'sync:$sourceDeviceId',
      );
    }

    final now = _now().toUtc().toIso8601String();
    await db.insert('merka_sync_entity_map', {
      'tenant_kind': tenantKind,
      'tenant_id': tenantId,
      'remote_aggregate_type': aggregateType,
      'remote_aggregate_id': aggregateId,
      'remote_event_id': remoteEventId,
      'idempotency_key': idempotencyKey,
      'source_device_id': sourceDeviceId,
      'local_table': 'ventas',
      'local_id': localSaleId,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await _markApplied(db, inboxRow);
  }

  Future<void> _applyProductUpserted(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow,
  ) async {
    final payload = _decodeMap(inboxRow['payload_json']);
    final entity = _mapValue(payload['entity'], 'payload.entity');
    final companyId =
        _intValue(inboxRow['company_id']) ??
        _intValue(entity['company_id']) ??
        0;
    if (companyId <= 0) {
      throw const FormatException('company_id requerido para producto remoto.');
    }
    final remoteId = _intValue(entity['id']);
    if (remoteId == null || remoteId <= 0) {
      throw const FormatException('id requerido para producto remoto.');
    }

    final values = <String, Object?>{
      'company_id': companyId,
      'codigo': _stringValue(entity['codigo']) ?? '',
      'nombre': _stringValue(entity['nombre']),
      'unidad_base': _stringValue(entity['unidad_base']) ?? 'unid.',
      'stock': _numValue(entity['stock']) ?? 0,
      'stock_minimo': _numValue(entity['stock_minimo']) ?? 5,
      'stock_maximo': _numValue(entity['stock_maximo']) ?? 0,
      'lead_time_days': _intValue(entity['lead_time_days']) ?? 7,
      'costo': _numValue(entity['costo']) ?? 0,
      'precio': _numValue(entity['precio']) ?? 0,
      'impuesto_pct': _numValue(entity['impuesto_pct']) ?? 0,
      'codigo_barras': _stringValue(entity['codigo_barras']) ?? '',
      'conversion_nombre': _stringValue(entity['conversion_nombre']) ?? '',
      'conversion_cantidad': _numValue(entity['conversion_cantidad']) ?? 0,
      'tipo_item': _stringValue(entity['tipo_item']) ?? 'producto',
      'precio_incluye_iva': _intValue(entity['precio_incluye_iva']) ?? 0,
    };
    if (_stringValue(values['nombre']) == null) {
      throw const FormatException('nombre requerido para producto remoto.');
    }

    final mappedLocalId = await _mappedLocalId(db, inboxRow);
    final updateValues = Map<String, Object?>.from(values)..remove('stock');
    final localId = await _upsertMappedRow(
      db,
      table: 'productos',
      values: values,
      updateValues: updateValues,
      companyId: companyId,
      mappedLocalId: mappedLocalId,
      naturalKeyFinder: () => _findProductByNaturalKey(db, values, companyId),
    );

    await _rememberEntityMap(
      db,
      inboxRow,
      localTable: 'productos',
      localId: localId,
    );
    await _markApplied(db, inboxRow);
  }

  Future<void> _applyCustomerUpserted(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow,
  ) async {
    final payload = _decodeMap(inboxRow['payload_json']);
    final entity = _mapValue(payload['entity'], 'payload.entity');
    final companyId =
        _intValue(inboxRow['company_id']) ??
        _intValue(entity['company_id']) ??
        0;
    if (companyId <= 0) {
      throw const FormatException('company_id requerido para cliente remoto.');
    }
    final remoteId = _intValue(entity['id']);
    if (remoteId == null || remoteId <= 0) {
      throw const FormatException('id requerido para cliente remoto.');
    }

    final values = <String, Object?>{
      'company_id': companyId,
      'nombre': _stringValue(entity['nombre']),
      'documento': _stringValue(entity['documento']) ?? '',
      'telefono': _stringValue(entity['telefono']) ?? '',
      'direccion': _stringValue(entity['direccion']) ?? '',
      'email': _stringValue(entity['email']) ?? '',
      'estado': _stringValue(entity['estado']) ?? 'activo',
      'fecha':
          _stringValue(entity['fecha']) ?? _stringValue(payload['occurred_at']),
      'gran_contribuyente': _intValue(entity['gran_contribuyente']) ?? 0,
      'autorretenedor': _intValue(entity['autorretenedor']) ?? 0,
      'declarante': _intValue(entity['declarante']) ?? 1,
      'regimen_tributario':
          _stringValue(entity['regimen_tributario']) ?? 'ordinario',
    };
    if (_stringValue(values['nombre']) == null) {
      throw const FormatException('nombre requerido para cliente remoto.');
    }

    final mappedLocalId = await _mappedLocalId(db, inboxRow);
    final localId = await _upsertMappedRow(
      db,
      table: 'clientes',
      values: values,
      companyId: companyId,
      mappedLocalId: mappedLocalId,
      naturalKeyFinder: () => _findCustomerByNaturalKey(db, values, companyId),
    );

    await _rememberEntityMap(
      db,
      inboxRow,
      localTable: 'clientes',
      localId: localId,
    );
    await _markApplied(db, inboxRow);
  }

  Future<void> _withSyncState(
    DatabaseExecutor db,
    Future<void> Function() action,
  ) async {
    if (!await _tableExists(db, 'sync_state')) {
      await action();
      return;
    }
    await db.update('sync_state', {'is_syncing': 1}, where: 'rowid = 1');
    try {
      await action();
    } finally {
      await db.update('sync_state', {'is_syncing': 0}, where: 'rowid = 1');
    }
  }

  Future<void> _markApplied(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow,
  ) async {
    final now = _now().toUtc().toIso8601String();
    await db.update(
      'merka_sync_inbox',
      {
        'status': 'applied',
        'applied_at': now,
        'updated_at': now,
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [inboxRow['id']],
    );
  }

  Future<void> _markUnsupported(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow,
    String reason,
  ) async {
    final now = _now().toUtc().toIso8601String();
    await db.update(
      'merka_sync_inbox',
      {'status': 'unsupported', 'updated_at': now, 'last_error': reason},
      where: 'id = ?',
      whereArgs: [inboxRow['id']],
    );
  }

  Future<bool> _markFailed(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow,
    Object error,
  ) async {
    final failedAt = _now().toUtc();
    final nextAttempts = (_intValue(inboxRow['attempts']) ?? 0) + 1;
    final isTerminal = nextAttempts >= maxAttempts;
    await db.update(
      'merka_sync_inbox',
      {
        'status': isTerminal ? 'error' : 'retry',
        'attempts': nextAttempts,
        'updated_at': failedAt.toIso8601String(),
        'next_attempt_at': isTerminal
            ? null
            : failedAt.add(_retryDelay(nextAttempts)).toIso8601String(),
        'last_error': error.toString(),
      },
      where: 'id = ?',
      whereArgs: [inboxRow['id']],
    );
    return isTerminal;
  }

  Duration _retryDelay(int attempts) {
    final boundedAttempts = attempts.clamp(1, 6);
    return Duration(seconds: 5 * boundedAttempts * boundedAttempts);
  }

  Future<int> _insertFiltered(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> values,
  ) async {
    final columns = await _columns(db, table);
    final filtered = <String, Object?>{};
    for (final entry in values.entries) {
      if (columns.contains(entry.key)) filtered[entry.key] = entry.value;
    }
    return db.insert(table, filtered);
  }

  Future<int> _upsertMappedRow(
    DatabaseExecutor db, {
    required String table,
    required Map<String, Object?> values,
    Map<String, Object?>? updateValues,
    required int companyId,
    required int? mappedLocalId,
    required Future<int?> Function() naturalKeyFinder,
  }) async {
    final safeUpdateValues = updateValues ?? values;
    if (mappedLocalId != null &&
        await _rowExists(db, table, mappedLocalId, companyId)) {
      await _updateFiltered(
        db,
        table,
        safeUpdateValues,
        id: mappedLocalId,
        companyId: companyId,
      );
      return mappedLocalId;
    }

    final naturalKeyId = await naturalKeyFinder();
    if (naturalKeyId != null) {
      await _updateFiltered(
        db,
        table,
        safeUpdateValues,
        id: naturalKeyId,
        companyId: companyId,
      );
      return naturalKeyId;
    }

    return _insertFiltered(db, table, values);
  }

  Future<int> _updateFiltered(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> values, {
    required int id,
    required int companyId,
  }) async {
    final columns = await _columns(db, table);
    final filtered = <String, Object?>{};
    for (final entry in values.entries) {
      if (entry.key == 'id') continue;
      if (columns.contains(entry.key)) filtered[entry.key] = entry.value;
    }
    if (filtered.isEmpty) return 0;
    return db.update(
      table,
      filtered,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }

  Future<int?> _mappedLocalId(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow,
  ) async {
    final rows = await db.query(
      'merka_sync_entity_map',
      columns: ['local_id'],
      where: '''
        tenant_kind = ?
        AND tenant_id = ?
        AND (
          (remote_aggregate_type = ? AND remote_aggregate_id = ?)
          OR idempotency_key = ?
        )
      ''',
      whereArgs: [
        inboxRow['tenant_kind'],
        inboxRow['tenant_id'],
        inboxRow['aggregate_type'],
        inboxRow['aggregate_id'],
        inboxRow['idempotency_key'],
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _intValue(rows.single['local_id']);
  }

  Future<void> _rememberEntityMap(
    DatabaseExecutor db,
    Map<String, Object?> inboxRow, {
    required String localTable,
    required int localId,
  }) async {
    final now = _now().toUtc().toIso8601String();
    await db.insert('merka_sync_entity_map', {
      'tenant_kind': inboxRow['tenant_kind'],
      'tenant_id': inboxRow['tenant_id'],
      'remote_aggregate_type': inboxRow['aggregate_type'],
      'remote_aggregate_id': inboxRow['aggregate_id'],
      'remote_event_id': inboxRow['remote_event_id'],
      'idempotency_key': inboxRow['idempotency_key'],
      'source_device_id': inboxRow['source_device_id'],
      'local_table': localTable,
      'local_id': localId,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> _resolveRemoteProductId({
    required DatabaseExecutor db,
    required Map<String, Object?> inboxRow,
    required int companyId,
    required int remoteProductId,
  }) async {
    final sourceDeviceId = inboxRow['source_device_id'].toString();
    final remoteAggregateId =
        'product:$companyId:$sourceDeviceId:$remoteProductId';
    final rows = await db.query(
      'merka_sync_entity_map',
      columns: ['local_id'],
      where: '''
        tenant_kind = ?
        AND tenant_id = ?
        AND remote_aggregate_type = ?
        AND remote_aggregate_id = ?
        AND local_table = ?
      ''',
      whereArgs: [
        inboxRow['tenant_kind'],
        inboxRow['tenant_id'],
        'product',
        remoteAggregateId,
        'productos',
      ],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return _intValue(rows.single['local_id']) ?? remoteProductId;
    }
    return remoteProductId;
  }

  Future<int?> _resolveRemoteCustomerId({
    required DatabaseExecutor db,
    required Map<String, Object?> inboxRow,
    required int companyId,
    required int? remoteCustomerId,
  }) async {
    if (remoteCustomerId == null || remoteCustomerId <= 0) return null;
    final sourceDeviceId = inboxRow['source_device_id'].toString();
    final remoteAggregateId =
        'customer:$companyId:$sourceDeviceId:$remoteCustomerId';
    final rows = await db.query(
      'merka_sync_entity_map',
      columns: ['local_id'],
      where: '''
        tenant_kind = ?
        AND tenant_id = ?
        AND remote_aggregate_type = ?
        AND remote_aggregate_id = ?
        AND local_table = ?
      ''',
      whereArgs: [
        inboxRow['tenant_kind'],
        inboxRow['tenant_id'],
        'customer',
        remoteAggregateId,
        'clientes',
      ],
      limit: 1,
    );
    if (rows.isEmpty) return remoteCustomerId;
    return _intValue(rows.single['local_id']) ?? remoteCustomerId;
  }

  Future<int?> _findProductByNaturalKey(
    DatabaseExecutor db,
    Map<String, Object?> values,
    int companyId,
  ) async {
    final barcode = _stringValue(values['codigo_barras']);
    if (barcode != null) {
      final rows = await db.query(
        'productos',
        columns: ['id'],
        where: 'company_id = ? AND codigo_barras = ?',
        whereArgs: [companyId, barcode],
        limit: 1,
      );
      if (rows.isNotEmpty) return _intValue(rows.single['id']);
    }

    final code = _stringValue(values['codigo']);
    if (code != null) {
      final rows = await db.query(
        'productos',
        columns: ['id'],
        where: 'company_id = ? AND codigo = ?',
        whereArgs: [companyId, code],
        limit: 1,
      );
      if (rows.isNotEmpty) return _intValue(rows.single['id']);
    }

    return null;
  }

  Future<int?> _findCustomerByNaturalKey(
    DatabaseExecutor db,
    Map<String, Object?> values,
    int companyId,
  ) async {
    final document = _stringValue(values['documento']);
    if (document == null) return null;
    final rows = await db.query(
      'clientes',
      columns: ['id'],
      where: 'company_id = ? AND documento = ?',
      whereArgs: [companyId, document],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _intValue(rows.single['id']);
  }

  Future<bool> _rowExists(
    DatabaseExecutor db,
    String table,
    int id,
    int companyId,
  ) async {
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
      limit: 1,
    );
    return rows.isNotEmpty;
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

  Map<String, Object?> _decodeMap(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return {};
    final decoded = jsonDecode(value.toString());
    return _mapValue(decoded, 'json');
  }

  Map<String, Object?> _mapValue(Object? value, String label) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw FormatException('$label debe ser objeto JSON.');
  }

  List<Map<String, Object?>> _listOfMaps(Object? value, String label) {
    if (value is! List) throw FormatException('$label debe ser lista.');
    return value.map((item) => _mapValue(item, label)).toList();
  }

  String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  int? _intValue(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  num? _numValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }
}
