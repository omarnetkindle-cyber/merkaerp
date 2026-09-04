import 'package:sqflite/sqflite.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../db_helper.dart';
import '../domain/mrp_bom.dart';
import '../domain/mrp_bom_item.dart';
import '../domain/mrp_operation.dart';
import '../domain/mrp_routing.dart';
import '../domain/mrp_work_order.dart';
import '../domain/mrp_work_order_item.dart';
import '../domain/mrp_workstation.dart';
import '../domain/mrp_workstation_shift.dart';

class MrpRepositoryContext {
  MrpRepositoryContext({DatabaseHelper? database})
    : database = database ?? DatabaseHelper.instance;
  final DatabaseHelper database;
  Future<Database> get db => database.database;
  Future<int> get companyId => database.obtenerEmpresaActivaId();
  Future<Currency> get currency async =>
      MoneyCurrencyResolver.resolve(await db, companyId: await companyId);
}

class MrpWorkstationRepository {
  MrpWorkstationRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;
  Future<int> save(MrpWorkstation value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_workstations', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_workstations',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<List<MrpWorkstation>> list() async {
    final db = await _context.db;
    final c = await _context.currency;
    return (await db.query(
      'mrp_workstations',
      where: 'company_id = ?',
      whereArgs: [await _context.companyId],
      orderBy: 'name',
    )).map((r) => MrpWorkstation.fromMap(r, c)).toList();
  }
}

class MrpRoutingRepository {
  MrpRoutingRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;
  Future<int> save(MrpRouting value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_routings', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_routings',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<List<MrpRouting>> list() async {
    final db = await _context.db;
    return (await db.query(
      'mrp_routings',
      where: 'company_id = ?',
      whereArgs: [await _context.companyId],
      orderBy: 'name',
    )).map(MrpRouting.fromMap).toList();
  }

  Future<List<MrpRouting>> listForProduct(int itemId) async {
    final db = await _context.db;
    return (await db.query(
      'mrp_routings',
      where: 'company_id = ? AND item_id = ? AND is_active = 1',
      whereArgs: [await _context.companyId, itemId],
      orderBy: 'is_default DESC, priority ASC, name ASC',
    )).map(MrpRouting.fromMap).toList();
  }

  Future<MrpRouting?> defaultForProduct(int itemId) async {
    final rows = await listForProduct(itemId);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearDefaultForProduct(int itemId, int exceptId) async {
    final db = await _context.db;
    await db.update(
      'mrp_routings',
      {'is_default': 0},
      where: 'company_id = ? AND item_id = ? AND id <> ?',
      whereArgs: [await _context.companyId, itemId, exceptId],
    );
  }
}

class MrpOperationRepository {
  MrpOperationRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;
  Future<int> save(MrpOperation value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_operations', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_operations',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<List<MrpOperation>> listForRouting(int routingId) async {
    final db = await _context.db;
    final c = await _context.currency;
    return (await db.query(
      'mrp_operations',
      where: 'company_id = ? AND routing_id = ?',
      whereArgs: [await _context.companyId, routingId],
      orderBy: 'sequence_order',
    )).map((r) => MrpOperation.fromMap(r, c)).toList();
  }
}

class MrpWorkstationShiftRepository {
  MrpWorkstationShiftRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;

  Future<int> save(MrpWorkstationShift value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_workstation_shifts', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_workstation_shifts',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<List<MrpWorkstationShift>> listForWorkstation(
    int workstationId,
  ) async {
    final db = await _context.db;
    return (await db.query(
      'mrp_workstation_shifts',
      where: 'company_id = ? AND workstation_id = ?',
      whereArgs: [await _context.companyId, workstationId],
      orderBy: 'weekday ASC, start_time ASC',
    )).map(MrpWorkstationShift.fromMap).toList();
  }

  Future<List<MrpWorkstationShift>> listForWorkstationAndWeekday(
    int workstationId,
    int weekday,
  ) async {
    final db = await _context.db;
    return (await db.query(
      'mrp_workstation_shifts',
      where: 'company_id = ? AND workstation_id = ? AND weekday = ?',
      whereArgs: [await _context.companyId, workstationId, weekday],
      orderBy: 'start_time ASC',
    )).map(MrpWorkstationShift.fromMap).toList();
  }
}

class MrpBomRepository {
  MrpBomRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;
  Future<int> save(MrpBom value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_boms', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_boms',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<MrpBom?> findById(int id) async {
    final db = await _context.db;
    final rows = await db.query(
      'mrp_boms',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, await _context.companyId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : MrpBom.fromMap(rows.single, await _context.currency);
  }

  Future<List<MrpBom>> list() async {
    final db = await _context.db;
    final c = await _context.currency;
    return (await db.query(
      'mrp_boms',
      where: 'company_id = ?',
      whereArgs: [await _context.companyId],
      orderBy: 'id DESC',
    )).map((r) => MrpBom.fromMap(r, c)).toList();
  }
}

class MrpBomItemRepository {
  MrpBomItemRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;
  Future<int> save(MrpBomItem value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_bom_items', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_bom_items',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<List<MrpBomItem>> listForBom(int bomId) async {
    final db = await _context.db;
    final c = await _context.currency;
    return (await db.query(
      'mrp_bom_items',
      where: 'company_id = ? AND bom_id = ?',
      whereArgs: [await _context.companyId, bomId],
      orderBy: 'id',
    )).map((r) => MrpBomItem.fromMap(r, c)).toList();
  }
}

class MrpWorkOrderRepository {
  MrpWorkOrderRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;
  Future<int> save(MrpWorkOrder value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_work_orders', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_work_orders',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<MrpWorkOrder?> findById(int id) async {
    final db = await _context.db;
    final rows = await db.query(
      'mrp_work_orders',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, await _context.companyId],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : MrpWorkOrder.fromMap(rows.single, await _context.currency);
  }

  Future<List<MrpWorkOrder>> list() async {
    final db = await _context.db;
    final c = await _context.currency;
    return (await db.query(
      'mrp_work_orders',
      where: 'company_id = ?',
      whereArgs: [await _context.companyId],
      orderBy: 'id DESC',
    )).map((r) => MrpWorkOrder.fromMap(r, c)).toList();
  }
}

class MrpWorkOrderItemRepository {
  MrpWorkOrderItemRepository({MrpRepositoryContext? context})
    : _context = context ?? MrpRepositoryContext();
  final MrpRepositoryContext _context;
  Future<int> save(MrpWorkOrderItem value) async {
    final db = await _context.db;
    final data = value.toMap()..remove('company_id');
    if (value.id == null) {
      return db.insert('mrp_work_order_items', {
        'company_id': await _context.companyId,
        ...data,
      });
    }
    data.remove('id');
    return db.update(
      'mrp_work_order_items',
      data,
      where: 'id = ? AND company_id = ?',
      whereArgs: [value.id, await _context.companyId],
    );
  }

  Future<List<MrpWorkOrderItem>> listForOrder(int workOrderId) async {
    final db = await _context.db;
    return (await db.query(
      'mrp_work_order_items',
      where: 'company_id = ? AND work_order_id = ?',
      whereArgs: [await _context.companyId, workOrderId],
      orderBy: 'id',
    )).map(MrpWorkOrderItem.fromMap).toList();
  }
}
