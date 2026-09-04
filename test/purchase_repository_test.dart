import 'package:merka_erp/core/company/company_context.dart';
import 'package:merka_erp/core/database/database_gateway.dart';
import 'package:merka_erp/purchases/data/purchase_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'support/test_money.dart';

class _FakeCompanyContext implements CompanyContextProvider {
  const _FakeCompanyContext(this.companyId);

  final int companyId;

  @override
  Future<CompanyContext> current({bool force = false}) async {
    return CompanyContext(companyId: companyId, companyName: 'Empresa demo');
  }
}

class _RecordingGateway implements DatabaseGateway {
  List<Map<String, dynamic>> nextQueryRows = const [];
  List<Map<String, dynamic>> nextRawRows = const [];
  String? lastTable;
  String? lastWhere;
  List<Object?>? lastWhereArgs;
  String? lastOrderBy;
  String? lastSql;
  List<Object?>? lastSqlArgs;
  Map<String, Object?>? lastInsertedValues;

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
    lastTable = table;
    lastInsertedValues = values;
    return 17;
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
    lastTable = table;
    lastWhere = where;
    lastWhereArgs = whereArgs;
    lastOrderBy = orderBy;
    return nextQueryRows;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    lastSql = sql;
    lastSqlArgs = arguments;
    return nextRawRows;
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
  group('SqlitePurchaseRepository', () {
    test('lista compras aisladas por empresa activa', () async {
      final gateway = _RecordingGateway()
        ..nextQueryRows = [
          {
            'id': 8,
            'company_id': 4,
            'proveedor': 'Proveedor demo',
            'total': 9000,
            'fecha': '2026-05-20T12:00:00',
            'estado': 'pagada',
          },
        ];
      final repository = SqlitePurchaseRepository(
        gateway: gateway,
        companyContext: const _FakeCompanyContext(4),
        validateFeature: (_) async {},
        resolveCurrency: (_) async => testCop,
      );

      final purchases = await repository.findAll();

      expect(purchases.single.id, 8);
      expect(purchases.single.companyId, 4);
      expect(gateway.lastTable, 'compras');
      expect(gateway.lastWhere, 'company_id = ?');
      expect(gateway.lastWhereArgs, [4]);
      expect(gateway.lastOrderBy, 'fecha DESC');
    });

    test('crea cabecera de compra con company_id activo', () async {
      final gateway = _RecordingGateway();
      final repository = SqlitePurchaseRepository(
        gateway: gateway,
        companyContext: const _FakeCompanyContext(11),
        validateFeature: (_) async {},
        resolveCurrency: (_) async => testCop,
      );

      final id = await repository.createHeader({
        'proveedor': 'Proveedor demo',
        'total': 50000,
        'fecha': '2026-05-20T13:00:00',
      });

      expect(id, 17);
      expect(gateway.lastTable, 'compras');
      expect(gateway.lastInsertedValues?['company_id'], 11);
      expect(gateway.lastInsertedValues?['total'], 50000);
    });

    test('calcula total de compras excluyendo anuladas', () async {
      final gateway = _RecordingGateway()
        ..nextRawRows = [
          {'total': 77000},
        ];
      final repository = SqlitePurchaseRepository(
        gateway: gateway,
        companyContext: const _FakeCompanyContext(2),
        validateFeature: (_) async {},
        resolveCurrency: (_) async => testCop,
      );

      final total = await repository.totalPurchases();

      expect(total, testMoney('770.00'));
      expect(gateway.lastSqlArgs, [2]);
      expect(gateway.lastSql, contains('company_id = ?'));
      expect(gateway.lastSql, contains("COALESCE(estado, 'pagada')"));
    });
  });
}
