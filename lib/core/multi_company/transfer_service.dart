// ============================================================
// transfer_service.dart
// Servicio de gestion de transferencias entre empresas
// ============================================================

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'company_transfer.dart';

class CompanyTransferService {
  static final CompanyTransferService instance =
      CompanyTransferService._internal();

  CompanyTransferService._internal();

  Future<void> createTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_transfers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_company_id INTEGER NOT NULL,
        to_company_id INTEGER NOT NULL,
        transfer_number TEXT NOT NULL UNIQUE,
        transfer_type TEXT NOT NULL,
        items TEXT NOT NULL,
        total_value INTEGER NOT NULL,
        status TEXT DEFAULT 'pending',
        notes TEXT,
        requested_by TEXT,
        approved_by TEXT,
        requested_at TEXT NOT NULL,
        approved_at TEXT,
        completed_at TEXT,
        from_accounting_entry_id INTEGER,
        to_accounting_entry_id INTEGER,
        intercompany_reference TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await _addColumnIfMissing(
      db,
      'company_transfers',
      'from_accounting_entry_id',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'company_transfers',
      'to_accounting_entry_id',
      'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'company_transfers',
      'intercompany_reference',
      'TEXT',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS intercompany_eliminations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_a_id INTEGER NOT NULL,
        company_b_id INTEGER NOT NULL,
        metric TEXT NOT NULL,
        amount INTEGER NOT NULL,
        reference TEXT NOT NULL,
        source_table TEXT,
        source_id INTEGER,
        approved_by TEXT NOT NULL,
        approved_at TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfers_from ON company_transfers(from_company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfers_to ON company_transfers(to_company_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfers_status ON company_transfers(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_intercompany_metric ON intercompany_eliminations(metric)',
    );
  }

  Future<String> generateTransferNumber(Database db) async {
    final year = DateTime.now().year;
    final prefix = 'TRF-$year-';

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count
      FROM company_transfers
      WHERE transfer_number LIKE ?
    ''',
      ['$prefix%'],
    );

    final count = Sqflite.firstIntValue(result) ?? 0;
    final sequence = (count + 1).toString().padLeft(5, '0');

    return '$prefix$sequence';
  }

  Future<int> createTransfer(Database db, CompanyTransfer transfer) async {
    if (transfer.fromCompanyId == transfer.toCompanyId) {
      throw ArgumentError('La empresa origen y destino deben ser diferentes.');
    }
    return db.insert('company_transfers', {
      'from_company_id': transfer.fromCompanyId,
      'to_company_id': transfer.toCompanyId,
      'transfer_number': transfer.transferNumber,
      'transfer_type': transfer.transferType,
      'items': jsonEncode(transfer.items),
      'total_value': transfer.totalValue.round(),
      'status': transfer.status,
      'notes': transfer.notes,
      'requested_by': transfer.requestedBy,
      'requested_at': transfer.requestedAt.toIso8601String(),
      'created_at': transfer.createdAt.toIso8601String(),
    });
  }

  Future<void> approveTransfer(
    Database db,
    int transferId,
    String approvedBy,
  ) async {
    final updated = await db.update(
      'company_transfers',
      {
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND status = ?',
      whereArgs: [transferId, 'pending'],
    );
    if (updated == 0) {
      throw StateError('Solo se pueden aprobar transferencias pendientes.');
    }
  }

  Future<void> rejectTransfer(
    Database db,
    int transferId,
    String reason,
  ) async {
    final updated = await db.update(
      'company_transfers',
      {'status': 'rejected', 'notes': reason},
      where: 'id = ? AND status = ?',
      whereArgs: [transferId, 'pending'],
    );
    if (updated == 0) {
      throw StateError('Solo se pueden rechazar transferencias pendientes.');
    }
  }

  Future<void> completeTransfer(Database db, int transferId) async {
    await db.transaction((txn) async {
      final transfer = await getTransferById(txn, transferId);
      if (transfer == null) {
        throw StateError('La transferencia no existe.');
      }
      if (!transfer.isApproved) {
        throw StateError(
          'La transferencia debe estar aprobada antes de completarse.',
        );
      }

      int? fromEntryId;
      int? toEntryId;
      switch (transfer.transferType) {
        case 'inventory':
        case 'products':
          await _executeInventoryTransfer(txn, transfer);
          break;
        case 'funds':
          fromEntryId = await _executeFundsTransferFrom(txn, transfer);
          toEntryId = await _executeFundsTransferTo(txn, transfer);
          await registerIntercompanyElimination(
            txn,
            companyAId: transfer.fromCompanyId,
            companyBId: transfer.toCompanyId,
            metric: 'receivable_payable',
            amount: transfer.totalValue,
            reference: transfer.transferNumber,
            sourceTable: 'company_transfers',
            sourceId: transfer.id,
            approvedBy: transfer.approvedBy ?? 'sistema',
            notes:
                'Eliminacion de cuenta reciproca por transferencia de fondos.',
          );
          break;
        default:
          throw StateError(
            'Tipo de transferencia no soportado: ${transfer.transferType}',
          );
      }

      await txn.update(
        'company_transfers',
        {
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
          'from_accounting_entry_id': fromEntryId,
          'to_accounting_entry_id': toEntryId,
          'intercompany_reference': transfer.transferNumber,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [transferId, 'approved'],
      );
    });
  }

  Future<void> registerIntercompanyElimination(
    DatabaseExecutor db, {
    required int companyAId,
    required int companyBId,
    required String metric,
    required double amount,
    required String reference,
    required String approvedBy,
    String? sourceTable,
    int? sourceId,
    String? notes,
  }) async {
    if (companyAId == companyBId) {
      throw ArgumentError('La eliminacion requiere dos empresas diferentes.');
    }
    if (amount <= 0) {
      throw ArgumentError('El monto de eliminacion debe ser mayor a cero.');
    }
    await db.insert('intercompany_eliminations', {
      'company_a_id': companyAId,
      'company_b_id': companyBId,
      'metric': metric,
      'amount': amount.round(),
      'reference': reference,
      'source_table': sourceTable,
      'source_id': sourceId,
      'approved_by': approvedBy,
      'approved_at': DateTime.now().toIso8601String(),
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> cancelTransfer(Database db, int transferId) async {
    final updated = await db.update(
      'company_transfers',
      {'status': 'cancelled'},
      where: 'id = ? AND status IN (?, ?)',
      whereArgs: [transferId, 'pending', 'approved'],
    );
    if (updated == 0) {
      throw StateError(
        'No se puede cancelar una transferencia completada o inexistente.',
      );
    }
  }

  Future<CompanyTransfer?> getTransferById(
    DatabaseExecutor db,
    int transferId,
  ) async {
    final maps = await db.query(
      'company_transfers',
      where: 'id = ?',
      whereArgs: [transferId],
    );

    if (maps.isEmpty) return null;

    final map = maps.first;
    return CompanyTransfer.fromMap({
      ...map,
      'items': jsonDecode(map['items'] as String),
    });
  }

  Future<List<CompanyTransfer>> getTransfersFromCompany(
    Database db,
    int companyId,
  ) async {
    final maps = await db.query(
      'company_transfers',
      where: 'from_company_id = ?',
      whereArgs: [companyId],
      orderBy: 'created_at DESC',
    );

    return maps
        .map(
          (map) => CompanyTransfer.fromMap({
            ...map,
            'items': jsonDecode(map['items'] as String),
          }),
        )
        .toList();
  }

  Future<List<CompanyTransfer>> getTransfersToCompany(
    Database db,
    int companyId,
  ) async {
    final maps = await db.query(
      'company_transfers',
      where: 'to_company_id = ?',
      whereArgs: [companyId],
      orderBy: 'created_at DESC',
    );

    return maps
        .map(
          (map) => CompanyTransfer.fromMap({
            ...map,
            'items': jsonDecode(map['items'] as String),
          }),
        )
        .toList();
  }

  Future<List<CompanyTransfer>> getTransfersByStatus(
    Database db,
    String status,
  ) async {
    final maps = await db.query(
      'company_transfers',
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at DESC',
    );

    return maps
        .map(
          (map) => CompanyTransfer.fromMap({
            ...map,
            'items': jsonDecode(map['items'] as String),
          }),
        )
        .toList();
  }

  Future<List<CompanyTransfer>> getPendingTransfers(Database db) async {
    return getTransfersByStatus(db, 'pending');
  }

  Future<Map<String, dynamic>> getTransferStatistics(
    Database db,
    int companyId,
  ) async {
    final totalResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count, SUM(total_value) as total
      FROM company_transfers
      WHERE from_company_id = ? OR to_company_id = ?
    ''',
      [companyId, companyId],
    );

    final pendingResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count, SUM(total_value) as total
      FROM company_transfers
      WHERE (from_company_id = ? OR to_company_id = ?) AND status = 'pending'
    ''',
      [companyId, companyId],
    );

    final completedResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count, SUM(total_value) as total
      FROM company_transfers
      WHERE (from_company_id = ? OR to_company_id = ?) AND status = 'completed'
    ''',
      [companyId, companyId],
    );

    return {
      'total_transfers': Sqflite.firstIntValue(totalResult) ?? 0,
      'total_value': (totalResult.first['total'] as num?)?.toDouble() ?? 0,
      'pending_transfers': Sqflite.firstIntValue(pendingResult) ?? 0,
      'pending_value': (pendingResult.first['total'] as num?)?.toDouble() ?? 0,
      'completed_transfers': Sqflite.firstIntValue(completedResult) ?? 0,
      'completed_value':
          (completedResult.first['total'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<List<CompanyTransfer>> getTransferHistory(
    Database db,
    int companyA,
    int companyB,
  ) async {
    final maps = await db.query(
      'company_transfers',
      where:
          '(from_company_id = ? AND to_company_id = ?) OR (from_company_id = ? AND to_company_id = ?)',
      whereArgs: [companyA, companyB, companyB, companyA],
      orderBy: 'created_at DESC',
    );

    return maps
        .map(
          (map) => CompanyTransfer.fromMap({
            ...map,
            'items': jsonDecode(map['items'] as String),
          }),
        )
        .toList();
  }

  Future<void> _executeInventoryTransfer(
    DatabaseExecutor db,
    CompanyTransfer transfer,
  ) async {
    for (final entry in transfer.items.entries) {
      final productId = int.tryParse(entry.key);
      final quantity = (entry.value as num).toDouble();

      if (productId != null && quantity > 0) {
        final updatedFrom = await db.rawUpdate(
          '''
          UPDATE productos
          SET stock = stock - ?
          WHERE id = ? AND company_id = ? AND stock >= ?
        ''',
          [quantity, productId, transfer.fromCompanyId, quantity],
        );
        if (updatedFrom == 0) {
          throw StateError(
            'Stock insuficiente para transferir producto $productId.',
          );
        }

        final updatedTo = await db.rawUpdate(
          '''
          UPDATE productos
          SET stock = stock + ?
          WHERE id = ? AND company_id = ?
        ''',
          [quantity, productId, transfer.toCompanyId],
        );
        if (updatedTo == 0) {
          throw StateError(
            'Producto $productId no existe en la empresa destino.',
          );
        }
      }
    }
  }

  Future<int> _executeFundsTransferFrom(
    DatabaseExecutor db,
    CompanyTransfer transfer,
  ) async {
    await db.insert('movimientos_caja', {
      'company_id': transfer.fromCompanyId,
      'tipo': 'egreso',
      'monto': transfer.totalValue,
      'concepto': 'Transferencia a empresa ${transfer.toCompanyId}',
      'fecha': DateTime.now().toIso8601String(),
      'origen': 'banco',
    });

    return _createAccountingEntry(
      db,
      companyId: transfer.fromCompanyId,
      concept: 'Transferencia intercompania ${transfer.transferNumber}',
      reference: transfer.transferNumber,
      debitAccountCode: '1365',
      debitDescription: 'Cuenta por cobrar intercompania',
      creditAccountCode: '1110',
      creditDescription: 'Salida de bancos',
      amount: transfer.totalValue,
    );
  }

  Future<int> _executeFundsTransferTo(
    DatabaseExecutor db,
    CompanyTransfer transfer,
  ) async {
    await db.insert('movimientos_caja', {
      'company_id': transfer.toCompanyId,
      'tipo': 'ingreso',
      'monto': transfer.totalValue,
      'concepto': 'Transferencia desde empresa ${transfer.fromCompanyId}',
      'fecha': DateTime.now().toIso8601String(),
      'origen': 'banco',
    });

    return _createAccountingEntry(
      db,
      companyId: transfer.toCompanyId,
      concept: 'Recepcion intercompania ${transfer.transferNumber}',
      reference: transfer.transferNumber,
      debitAccountCode: '1110',
      debitDescription: 'Entrada de bancos',
      creditAccountCode: '2205',
      creditDescription: 'Cuenta por pagar intercompania',
      amount: transfer.totalValue,
    );
  }

  Future<int> _createAccountingEntry(
    DatabaseExecutor db, {
    required int companyId,
    required String concept,
    required String reference,
    required String debitAccountCode,
    required String debitDescription,
    required String creditAccountCode,
    required String creditDescription,
    required double amount,
  }) async {
    final debitAccountId = await _accountId(db, debitAccountCode);
    final creditAccountId = await _accountId(db, creditAccountCode);
    final entryId = await db.insert('asientos_contables', {
      'company_id': companyId,
      'fecha': DateTime.now().toIso8601String(),
      'concepto': concept,
      'referencia': reference,
      'origen': 'multiempresa',
      'estado': 'borrador',
    });
    await db.insert('asiento_lineas', {
      'company_id': companyId,
      'asiento_id': entryId,
      'cuenta_id': debitAccountId,
      'descripcion': debitDescription,
      'debito': amount,
      'credito': 0,
      'tercero': reference,
    });
    await db.insert('asiento_lineas', {
      'company_id': companyId,
      'asiento_id': entryId,
      'cuenta_id': creditAccountId,
      'descripcion': creditDescription,
      'debito': 0,
      'credito': amount,
      'tercero': reference,
    });
    await db.update(
      'asientos_contables',
      {'estado': 'registrado'},
      where: 'id = ?',
      whereArgs: [entryId],
    );
    return entryId;
  }

  Future<int> _accountId(DatabaseExecutor db, String code) async {
    final rows = await db.query(
      'cuentas_contables',
      columns: ['id'],
      where: 'codigo = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    throw StateError('No existe la cuenta contable $code requerida.');
  }

  Future<void> _addColumnIfMissing(
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
