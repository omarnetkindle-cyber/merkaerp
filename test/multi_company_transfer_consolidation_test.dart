import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/multi_company/company_transfer.dart';
import 'package:merka_erp/core/multi_company/financial_consolidation.dart';
import 'package:merka_erp/core/multi_company/transfer_service.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.instance.crearDBForTesting(
      db,
      DatabaseHelper.schemaVersion,
    );
    await CompanyTransferService.instance.createTables(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'transferencia de fondos exige aprobado y completa atomica con asientos',
    () async {
      final companyA = await _company(db, 'A');
      final companyB = await _company(db, 'B');
      final number = await CompanyTransferService.instance
          .generateTransferNumber(db);
      final transferId = await CompanyTransferService.instance.createTransfer(
        db,
        CompanyTransfer(
          fromCompanyId: companyA,
          toCompanyId: companyB,
          transferNumber: number,
          transferType: 'funds',
          items: const {},
          totalValue: 150000,
          requestedBy: 'tester',
          requestedAt: DateTime(2026, 8, 13),
          createdAt: DateTime(2026, 8, 13),
        ),
      );

      expect(
        () => CompanyTransferService.instance.completeTransfer(db, transferId),
        throwsA(isA<StateError>()),
      );
      expect(
        (await db.query(
          'company_transfers',
          where: 'id = ?',
          whereArgs: [transferId],
        )).single['status'],
        'pending',
      );
      expect(await db.query('asientos_contables'), isEmpty);

      await CompanyTransferService.instance.approveTransfer(
        db,
        transferId,
        'contador',
      );
      await CompanyTransferService.instance.completeTransfer(db, transferId);

      final row = (await db.query(
        'company_transfers',
        where: 'id = ?',
        whereArgs: [transferId],
      )).single;
      expect(row['status'], 'completed');
      expect(row['from_accounting_entry_id'], isNotNull);
      expect(row['to_accounting_entry_id'], isNotNull);
      expect(await db.query('asientos_contables'), hasLength(2));
      expect(await db.query('intercompany_eliminations'), hasLength(1));
    },
  );

  test('consolidacion elimina operaciones intercompania aprobadas', () async {
    final companyA = await _company(db, 'A');
    final companyB = await _company(db, 'B');
    await db.execute('''
      CREATE TABLE gastos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        concepto TEXT NOT NULL,
        monto INTEGER NOT NULL,
        fecha TEXT NOT NULL,
        categoria TEXT
      )
    ''');
    await db.insert('ventas', {
      'company_id': companyA,
      'producto': 'Servicio intercompania',
      'cantidad': 1,
      'subtotal': 100000,
      'impuesto_total': 0,
      'total': 100000,
      'fecha': DateTime(2026, 8, 13).toIso8601String(),
      'estado': 'emitida',
    });
    await db.insert('gastos', {
      'company_id': companyB,
      'concepto': 'Compra intercompania',
      'monto': 100000,
      'fecha': DateTime(2026, 8, 13).toIso8601String(),
      'categoria': 'operativo',
    });

    final sinEliminar = await FinancialConsolidationService.instance
        .getConsolidatedFinancials(
          db,
          [companyA, companyB],
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 31),
        );
    expect((sinEliminar['sales'] as Map)['total']['minor_units'], 100000);
    expect((sinEliminar['expenses'] as Map)['total']['minor_units'], 100000);

    await CompanyTransferService.instance.registerIntercompanyElimination(
      db,
      companyAId: companyA,
      companyBId: companyB,
      metric: 'sales_expenses',
      amount: 100000,
      reference: 'ELIM-1',
      approvedBy: 'contador',
    );

    final eliminado = await FinancialConsolidationService.instance
        .getConsolidatedFinancials(
          db,
          [companyA, companyB],
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 31),
        );
    expect((eliminado['sales'] as Map)['total']['minor_units'], 0);
    expect((eliminado['expenses'] as Map)['total']['minor_units'], 0);
    expect(
      (eliminado['sales'] as Map)['eliminated_intercompany']['minor_units'],
      100000,
    );
  });
}

Future<int> _company(Database db, String name) {
  return db.insert('companies', {
    'name': name,
    'tax_id': name,
    'currency': 'COP',
    'created_at': DateTime(2026, 8, 13).toIso8601String(),
  });
}
