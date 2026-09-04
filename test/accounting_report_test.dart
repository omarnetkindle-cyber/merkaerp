import 'package:merka_erp/accounting/data/accounting_report_repository.dart';
import 'package:merka_erp/accounting/domain/journal_entry.dart';
import 'package:merka_erp/accounting/domain/trial_balance.dart';
import 'package:merka_erp/core/company/company_context.dart';
import 'package:merka_erp/core/database/database_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'support/test_money.dart';

class _Context implements CompanyContextProvider {
  const _Context(this.companyId);

  final int companyId;

  @override
  Future<CompanyContext> current({bool force = false}) async {
    return CompanyContext(companyId: companyId, companyName: 'Empresa demo');
  }
}

class _Gateway implements DatabaseGateway {
  _Gateway(this.rows);

  final List<Map<String, dynamic>> rows;
  String? lastSql;
  List<Object?>? lastArgs;

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    throw UnimplementedError();
  }

  @override
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
    throw UnimplementedError();
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    lastSql = sql;
    lastArgs = arguments;
    return rows;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    throw UnimplementedError();
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  group('JournalEntry con MoneyValue', () {
    test('rechaza un descuadre de un centavo sin tolerancia double', () {
      final entry = JournalEntry(
        id: 'entry-1',
        consecutive: '1',
        date: DateTime(2026, 8, 8),
        concept: 'Prueba de partida doble',
        reference: 'TEST-1',
        origin: 'test',
        lines: [
          JournalLine(
            accountCode: '1105',
            description: 'Debito',
            debit: testMoney('100.01'),
            credit: zeroTestMoney,
          ),
          JournalLine(
            accountCode: '2408',
            description: 'Credito',
            debit: zeroTestMoney,
            credit: testMoney('100.00'),
          ),
        ],
      );

      expect(() => entry.post(), throwsStateError);
    });
  });

  group('TrialBalance', () {
    test('calcula totales y estado balanceado', () {
      final balance = TrialBalance(
        accounts: [
          TrialBalanceAccount(
            accountId: 1,
            code: '1105',
            name: 'Caja',
            type: 'activo',
            nature: 'debito',
            debit: testMoney('100'),
            credit: zeroTestMoney,
            balance: testMoney('100'),
          ),
          TrialBalanceAccount(
            accountId: 2,
            code: '4135',
            name: 'Ingresos',
            type: 'ingreso',
            nature: 'credito',
            debit: zeroTestMoney,
            credit: testMoney('100'),
            balance: testMoney('100'),
          ),
        ],
      );

      expect(balance.totalDebit, testMoney('100'));
      expect(balance.totalCredit, testMoney('100'));
      expect(balance.balanced, isTrue);
      expect((balance.toMap()['summary'] as Map)['balanced'], isTrue);
    });
  });

  group('SqliteAccountingReportRepository', () {
    test('consulta balance por empresa activa', () async {
      final gateway = _Gateway([
        {
          'id': 1,
          'codigo': '1105',
          'nombre': 'Caja',
          'tipo': 'activo',
          'naturaleza': 'debito',
          'debito': 50,
          'credito': 0,
          'saldo': 50,
        },
      ]);
      final repository = SqliteAccountingReportRepository(
        gateway: gateway,
        companyContext: const _Context(6),
        resolveCurrency: (_) async => testCop,
      );

      final balance = await repository.trialBalance();

      expect(balance.accounts.single.code, '1105');
      expect(gateway.lastArgs, [6]);
      expect(gateway.lastSql, contains('l.company_id = ?'));
    });
  });
}
