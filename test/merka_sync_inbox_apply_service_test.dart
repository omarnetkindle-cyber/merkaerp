import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/sync/application/merka_sale_sync_outbox.dart';
import 'package:merka_erp/sync/application/merka_sync_inbox_apply_service.dart';

void main() {
  late Database db;
  late DateTime now;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    now = DateTime.utc(2026, 9, 2, 17);
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _createOperationalSchema(db);
    await MerkaSyncLocalSchema.ensure(db);
    await db.insert('productos', {
      'id': 10,
      'company_id': 1,
      'nombre': 'Producto sincronizado',
      'unidad_base': 'unid.',
      'stock': 5,
      'costo': 70000,
      'precio': 150000,
      'impuesto_pct': 0,
    });
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'aplica sale.confirmed remoto a venta local e inventario una vez',
    () async {
      await _insertInboxSaleEvent(db);

      final result = await MerkaSyncInboxApplyService(
        now: () => now,
      ).applyPending(db: db);

      expect(result.applied, 1);
      expect(result.failed, 0);

      final sales = await db.query('ventas');
      expect(sales, hasLength(1));
      expect(sales.single['id'], isNot(99));
      expect(sales.single['producto'], 'Factura POS #${sales.single['id']}');
      expect(sales.single['created_by'], 'sync:device-windows');

      final details = await db.query('ventas_detalle');
      expect(details, hasLength(1));
      expect(details.single['venta_id'], sales.single['id']);
      expect(details.single['producto_id'], 10);

      final products = await db.query(
        'productos',
        where: 'id = ?',
        whereArgs: [10],
      );
      expect((products.single['stock'] as num).toDouble(), 3);

      final movements = await db.query('movimientos_inventario');
      expect(movements, hasLength(1));
      expect(movements.single['motivo'], 'SYNC VENTA remote-event-1');
      expect((movements.single['stock_anterior'] as num).toDouble(), 5);
      expect((movements.single['stock_nuevo'] as num).toDouble(), 3);

      final kardex = await db.query('kardex_inventario');
      expect(kardex, hasLength(1));
      expect(kardex.single['created_by'], 'sync:device-windows');
      expect(kardex.single['documento_id'], sales.single['id']);

      final maps = await db.query('merka_sync_entity_map');
      expect(maps, hasLength(1));
      expect(maps.single['remote_aggregate_id'], 'sale:1:device-windows:99');
      expect(maps.single['local_id'], sales.single['id']);

      final inbox = await db.query('merka_sync_inbox');
      expect(inbox.single['status'], 'applied');
      expect(inbox.single['applied_at'], now.toIso8601String());
    },
  );

  test(
    'outbox maestro registra producto y cliente locales como upsert',
    () async {
      await db.insert('clientes', {
        'id': 20,
        'company_id': 1,
        'nombre': 'Cliente local',
        'documento': '123',
        'estado': 'activo',
      });

      await const MerkaMasterDataSyncOutboxWriter().enqueueProductUpserted(
        db: db,
        companyId: 1,
        productId: 10,
      );
      await const MerkaMasterDataSyncOutboxWriter().enqueueCustomerUpserted(
        db: db,
        companyId: 1,
        customerId: 20,
      );
      await const MerkaMasterDataSyncOutboxWriter().enqueueProductUpserted(
        db: db,
        companyId: 1,
        productId: 10,
      );

      final events = await db.query(
        'merka_sync_outbox',
        orderBy: 'aggregate_type ASC',
      );
      expect(events, hasLength(2));
      expect(
        events.map((row) => row['event_name']),
        contains('product.upserted'),
      );
      expect(
        events.map((row) => row['event_name']),
        contains('customer.upserted'),
      );
      expect(events.every((row) => row['status'] == 'pending'), isTrue);
      expect(events.every((row) => row['payload_checksum'] != null), isTrue);
    },
  );

  test('bootstrap de catálogo existente es idempotente', () async {
    await db.insert('clientes', {
      'id': 20,
      'company_id': 1,
      'nombre': 'Cliente local',
      'documento': '123',
      'estado': 'activo',
    });

    final writer = const MerkaMasterDataSyncOutboxWriter();
    final first = await writer.enqueueExistingMasterData(db: db, companyId: 1);
    final second = await writer.enqueueExistingMasterData(db: db, companyId: 1);

    expect(first, 2);
    expect(second, 0);
    final events = await db.query('merka_sync_outbox');
    expect(events, hasLength(2));
  });

  test('reaplicar mismo evento no duplica venta ni inventario', () async {
    await _insertInboxSaleEvent(db);
    final service = MerkaSyncInboxApplyService(now: () => now);

    await service.applyPending(db: db);
    await db.update(
      'merka_sync_inbox',
      {'status': 'pending', 'applied_at': null},
      where: 'remote_event_id = ?',
      whereArgs: ['remote-event-1'],
    );
    final result = await service.applyPending(db: db);

    expect(result.applied, 1);
    expect(await _count(db, 'ventas'), 1);
    expect(await _count(db, 'ventas_detalle'), 1);
    expect(await _count(db, 'movimientos_inventario'), 1);
    final products = await db.query(
      'productos',
      where: 'id = ?',
      whereArgs: [10],
    );
    expect((products.single['stock'] as num).toDouble(), 3);
  });

  test('aplica product.upserted remoto y guarda mapa de id local', () async {
    await db.delete('productos');
    await _insertInboxEntityEvent(
      db,
      remoteEventId: 'remote-product-1',
      aggregateType: 'product',
      aggregateId: 'product:1:device-android:99',
      eventName: 'product.upserted',
      idempotencyKey: 'product.upserted:1:device-android:99:v1',
      sourceDeviceId: 'device-android',
      entity: {
        'id': 99,
        'company_id': 1,
        'codigo': 'CAF-001',
        'nombre': 'Café remoto',
        'unidad_base': 'unid.',
        'stock': 12,
        'costo': 80000,
        'precio': 150000,
        'impuesto_pct': 19,
        'codigo_barras': '770000000001',
        'tipo_item': 'producto',
      },
    );

    final result = await MerkaSyncInboxApplyService(
      now: () => now,
    ).applyPending(db: db);

    expect(result.applied, 1);
    final products = await db.query('productos');
    expect(products, hasLength(1));
    expect(products.single['id'], isNot(99));
    expect(products.single['nombre'], 'Café remoto');
    expect((products.single['stock'] as num).toDouble(), 12);

    final maps = await db.query(
      'merka_sync_entity_map',
      where: 'remote_aggregate_type = ?',
      whereArgs: ['product'],
    );
    expect(maps, hasLength(1));
    expect(maps.single['remote_aggregate_id'], 'product:1:device-android:99');
    expect(maps.single['local_id'], products.single['id']);
  });

  test(
    'product.upserted no pisa stock de producto existente mapeado',
    () async {
      await db.insert('merka_sync_entity_map', {
        'tenant_kind': 'commercial',
        'tenant_id': 'company:1',
        'remote_aggregate_type': 'product',
        'remote_aggregate_id': 'product:1:device-android:99',
        'remote_event_id': 'remote-product-previous',
        'idempotency_key': 'product.upserted:1:device-android:99:previous',
        'source_device_id': 'device-android',
        'local_table': 'productos',
        'local_id': 10,
        'created_at': now.toIso8601String(),
      });
      await _insertInboxEntityEvent(
        db,
        remoteEventId: 'remote-product-update',
        aggregateType: 'product',
        aggregateId: 'product:1:device-android:99',
        eventName: 'product.upserted',
        idempotencyKey: 'product.upserted:1:device-android:99:v2',
        sourceDeviceId: 'device-android',
        entity: {
          'id': 99,
          'company_id': 1,
          'nombre': 'Producto renombrado',
          'unidad_base': 'unid.',
          'stock': 999,
          'costo': 80000,
          'precio': 160000,
          'impuesto_pct': 0,
        },
      );

      final result = await MerkaSyncInboxApplyService(
        now: () => now,
      ).applyPending(db: db);

      expect(result.applied, 1);
      final products = await db.query(
        'productos',
        where: 'id = ?',
        whereArgs: [10],
      );
      expect(products.single['nombre'], 'Producto renombrado');
      expect((products.single['stock'] as num).toDouble(), 5);
    },
  );

  test(
    'aplica customer.upserted remoto y permite mapear cliente en venta',
    () async {
      await _insertInboxEntityEvent(
        db,
        remoteEventId: 'remote-customer-1',
        aggregateType: 'customer',
        aggregateId: 'customer:1:device-android:88',
        eventName: 'customer.upserted',
        idempotencyKey: 'customer.upserted:1:device-android:88:v1',
        sourceDeviceId: 'device-android',
        entity: {
          'id': 88,
          'company_id': 1,
          'nombre': 'Cliente remoto',
          'documento': '900123',
          'telefono': '3001234567',
          'direccion': 'Calle 1',
          'email': 'cliente@merka.test',
          'estado': 'activo',
          'fecha': '2026-09-02T14:30:00.000Z',
        },
      );
      await _insertInboxSaleEvent(
        db,
        remoteEventId: 'remote-sale-customer',
        idempotencyKey: 'sale.confirmed:1:device-android:100',
        aggregateId: 'sale:1:device-android:100',
        sourceDeviceId: 'device-android',
        remoteSaleId: 100,
        remoteCustomerId: 88,
      );

      final result = await MerkaSyncInboxApplyService(
        now: () => now,
      ).applyPending(db: db);

      expect(result.applied, 2);
      final customers = await db.query('clientes');
      expect(customers, hasLength(1));
      final sales = await db.query('ventas');
      expect(sales.single['cliente_id'], customers.single['id']);
    },
  );

  test(
    'venta remota usa producto mapeado aunque el id local sea distinto',
    () async {
      await db.delete('productos');
      await _insertInboxEntityEvent(
        db,
        remoteEventId: 'remote-product-for-sale',
        aggregateType: 'product',
        aggregateId: 'product:1:device-android:99',
        eventName: 'product.upserted',
        idempotencyKey: 'product.upserted:1:device-android:99:v1',
        sourceDeviceId: 'device-android',
        entity: {
          'id': 99,
          'company_id': 1,
          'nombre': 'Producto con mapa',
          'unidad_base': 'unid.',
          'stock': 6,
          'costo': 70000,
          'precio': 150000,
          'impuesto_pct': 0,
        },
      );
      await _insertInboxSaleEvent(
        db,
        remoteEventId: 'remote-sale-mapped-product',
        idempotencyKey: 'sale.confirmed:1:device-android:99',
        aggregateId: 'sale:1:device-android:99',
        sourceDeviceId: 'device-android',
        remoteSaleId: 99,
        remoteProductId: 99,
      );

      final result = await MerkaSyncInboxApplyService(
        now: () => now,
      ).applyPending(db: db);

      expect(result.applied, 2);
      expect(result.failed, 0);
      final products = await db.query('productos');
      final localProductId = products.single['id'] as int;
      expect(localProductId, isNot(99));
      expect((products.single['stock'] as num).toDouble(), 4);

      final details = await db.query('ventas_detalle');
      expect(details.single['producto_id'], localProductId);
    },
  );

  test('si falta producto deja evento en retry sin tocar ventas', () async {
    await db.delete('productos', where: 'id = ?', whereArgs: [10]);
    await _insertInboxSaleEvent(db);

    final result = await MerkaSyncInboxApplyService(
      now: () => now,
    ).applyPending(db: db);

    expect(result.failed, 1);
    expect(await _count(db, 'ventas'), 0);
    final inbox = await db.query('merka_sync_inbox');
    expect(inbox.single['status'], 'retry');
    expect(inbox.single['attempts'], 1);
    expect(inbox.single['last_error'].toString(), contains('Producto 10'));
  });

  test('evento no soportado queda marcado unsupported', () async {
    await _insertInboxSaleEvent(db, eventName: 'product.updated');

    final result = await MerkaSyncInboxApplyService(
      now: () => now,
    ).applyPending(db: db);

    expect(result.skipped, 1);
    final inbox = await db.query('merka_sync_inbox');
    expect(inbox.single['status'], 'unsupported');
  });
}

Future<void> _createOperationalSchema(Database db) async {
  await db.execute('''
    CREATE TABLE productos(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      codigo TEXT DEFAULT '',
      nombre TEXT NOT NULL,
      unidad_base TEXT NOT NULL,
      stock REAL DEFAULT 0,
      stock_minimo REAL DEFAULT 5,
      stock_maximo REAL DEFAULT 0,
      lead_time_days INTEGER DEFAULT 7,
      costo REAL DEFAULT 0,
      precio REAL DEFAULT 0,
      impuesto_pct REAL DEFAULT 0,
      codigo_barras TEXT DEFAULT '',
      conversion_nombre TEXT DEFAULT '',
      conversion_cantidad REAL DEFAULT 0,
      tipo_item TEXT DEFAULT 'producto',
      precio_incluye_iva INTEGER DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE clientes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      nombre TEXT NOT NULL,
      documento TEXT DEFAULT '',
      telefono TEXT DEFAULT '',
      direccion TEXT DEFAULT '',
      email TEXT DEFAULT '',
      estado TEXT DEFAULT 'activo',
      fecha TEXT,
      gran_contribuyente INTEGER DEFAULT 0,
      autorretenedor INTEGER DEFAULT 0,
      declarante INTEGER DEFAULT 1,
      regimen_tributario TEXT DEFAULT 'ordinario'
    )
  ''');
  await db.execute('''
    CREATE TABLE ventas(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      producto_id INTEGER DEFAULT 0,
      producto TEXT NOT NULL,
      cantidad REAL NOT NULL,
      precio_unitario REAL DEFAULT 0,
      costo_unitario REAL DEFAULT 0,
      subtotal REAL DEFAULT 0,
      impuesto_pct REAL DEFAULT 0,
      impuesto_total REAL DEFAULT 0,
      total REAL NOT NULL,
      fecha TEXT NOT NULL,
      metodo_pago_id INTEGER DEFAULT 1,
      estado TEXT DEFAULT 'emitida',
      cliente_id INTEGER,
      cliente TEXT,
      efectivo REAL DEFAULT 0,
      transferencia REAL DEFAULT 0,
      credito REAL DEFAULT 0,
      retefuente REAL DEFAULT 0,
      retefuente_concepto TEXT DEFAULT 'otros_ingresos',
      retefuente_base REAL DEFAULT 0,
      retefuente_tasa REAL DEFAULT 0,
      reteiva REAL DEFAULT 0,
      reteica REAL DEFAULT 0,
      created_by TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE ventas_detalle(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      venta_id INTEGER NOT NULL,
      producto_id INTEGER NOT NULL,
      producto TEXT NOT NULL,
      cantidad REAL NOT NULL,
      precio_unitario REAL NOT NULL,
      subtotal REAL NOT NULL,
      impuesto_pct REAL DEFAULT 0,
      impuesto_total REAL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE movimientos_inventario(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER,
      producto_id INTEGER,
      tipo TEXT,
      cantidad REAL,
      stock_anterior REAL,
      stock_nuevo REAL,
      costo_anterior REAL DEFAULT 0,
      costo_nuevo REAL DEFAULT 0,
      motivo TEXT,
      fecha TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE kardex_inventario(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id INTEGER NOT NULL,
      producto_id INTEGER NOT NULL,
      bodega_id INTEGER,
      tipo TEXT NOT NULL,
      cantidad REAL NOT NULL,
      costo_unitario REAL NOT NULL DEFAULT 0,
      costo_total REAL NOT NULL DEFAULT 0,
      stock_anterior REAL NOT NULL DEFAULT 0,
      stock_nuevo REAL NOT NULL DEFAULT 0,
      referencia TEXT,
      documento_tipo TEXT,
      documento_id INTEGER,
      fecha TEXT NOT NULL,
      created_by TEXT DEFAULT 'local'
    )
  ''');
  await db.execute('CREATE TABLE sync_state(is_syncing INTEGER DEFAULT 0)');
  await db.insert('sync_state', {'is_syncing': 0});
}

Future<void> _insertInboxSaleEvent(
  Database db, {
  String eventName = 'sale.confirmed',
  String remoteEventId = 'remote-event-1',
  String idempotencyKey = 'sale.confirmed:1:device-windows:99',
  String aggregateId = 'sale:1:device-windows:99',
  String sourceDeviceId = 'device-windows',
  int remoteSaleId = 99,
  int remoteProductId = 10,
  int? remoteCustomerId,
}) async {
  final payload = {
    'schema_version': 1,
    'event_name': eventName,
    'occurred_at': '2026-09-02T15:00:00.000Z',
    'sale': {
      'id': remoteSaleId,
      'company_id': 1,
      'producto_id': 0,
      'producto': 'Factura POS #$remoteSaleId',
      'cantidad': 1,
      'precio_unitario': 0,
      'costo_unitario': 0,
      'subtotal': 300000,
      'impuesto_pct': 0,
      'impuesto_total': 0,
      'total': 300000,
      'fecha': '2026-09-02T15:00:00.000Z',
      'metodo_pago_id': 1,
      'estado': 'emitida',
      ...remoteCustomerId == null ? const {} : {'cliente_id': remoteCustomerId},
      'cliente': 'Cliente remoto',
      'efectivo': 300000,
      'transferencia': 0,
      'credito': 0,
    },
    'details': [
      {
        'id': 100,
        'company_id': 1,
        'venta_id': remoteSaleId,
        'producto_id': remoteProductId,
        'producto': 'Producto sincronizado',
        'cantidad': 2,
        'precio_unitario': 150000,
        'subtotal': 300000,
        'impuesto_pct': 0,
        'impuesto_total': 0,
      },
    ],
  };
  final payloadJson = jsonEncode(payload);
  await db.insert('merka_sync_inbox', {
    'remote_event_id': remoteEventId,
    'tenant_kind': 'commercial',
    'tenant_id': 'company:1',
    'company_id': 1,
    'branch_id': 1,
    'aggregate_type': 'sale',
    'aggregate_id': aggregateId,
    'event_name': eventName,
    'payload_json': payloadJson,
    'payload_checksum': sha256.convert(utf8.encode(payloadJson)).toString(),
    'idempotency_key': idempotencyKey,
    'source_device_id': sourceDeviceId,
    'status': 'pending',
    'received_at': '2026-09-02T15:01:00.000Z',
  });
}

Future<void> _insertInboxEntityEvent(
  Database db, {
  required String remoteEventId,
  required String aggregateType,
  required String aggregateId,
  required String eventName,
  required String idempotencyKey,
  required String sourceDeviceId,
  required Map<String, Object?> entity,
}) async {
  final payload = {
    'schema_version': 1,
    'event_name': eventName,
    'occurred_at': '2026-09-02T14:00:00.000Z',
    'entity': entity,
  };
  final payloadJson = jsonEncode(payload);
  await db.insert('merka_sync_inbox', {
    'remote_event_id': remoteEventId,
    'tenant_kind': 'commercial',
    'tenant_id': 'company:1',
    'company_id': 1,
    'branch_id': 1,
    'aggregate_type': aggregateType,
    'aggregate_id': aggregateId,
    'event_name': eventName,
    'payload_json': payloadJson,
    'payload_checksum': sha256.convert(utf8.encode(payloadJson)).toString(),
    'idempotency_key': idempotencyKey,
    'source_device_id': sourceDeviceId,
    'status': 'pending',
    'received_at': '2026-09-02T14:01:00.000Z',
  });
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM $table');
  return (rows.single['total'] as num).toInt();
}
