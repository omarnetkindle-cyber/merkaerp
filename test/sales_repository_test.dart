import 'package:merka_erp/core/company/company_context.dart';
import 'package:merka_erp/core/database/database_gateway.dart';
import 'package:merka_erp/sales/data/sale_repository.dart';
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
    return 99;
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
  group('SqliteSaleRepository', () {
    test('lista ventas aisladas por empresa activa', () async {
      final gateway = _RecordingGateway()
        ..nextQueryRows = [
          {
            'id': 4,
            'company_id': 7,
            'producto': 'Factura POS #4',
            'cantidad': 1,
            'total': 12000,
            'fecha': '2026-05-20T10:00:00',
            'estado': 'emitida',
          },
        ];
      final repository = SqliteSaleRepository(
        gateway: gateway,
        companyContext: const _FakeCompanyContext(7),
        validateFeature: (_) async {},
        resolveCurrency: (_) async => testCop,
      );

      final sales = await repository.findAll();

      expect(sales.single.id, 4);
      expect(sales.single.companyId, 7);
      expect(gateway.lastTable, 'ventas');
      expect(gateway.lastWhere, 'company_id = ?');
      expect(gateway.lastWhereArgs, [7]);
      expect(gateway.lastOrderBy, 'fecha DESC');
    });

    test('crea cabecera de venta con company_id activo', () async {
      final gateway = _RecordingGateway();
      final repository = SqliteSaleRepository(
        gateway: gateway,
        companyContext: const _FakeCompanyContext(3),
        validateFeature: (_) async {},
        resolveCurrency: (_) async => testCop,
      );

      final id = await repository.createHeader({
        'producto': 'Factura POS',
        'cantidad': 1,
        'total': 5000,
        'fecha': '2026-05-20T11:00:00',
      });

      expect(id, 99);
      expect(gateway.lastTable, 'ventas');
      expect(gateway.lastInsertedValues?['company_id'], 3);
      expect(gateway.lastInsertedValues?['total'], 5000);
    });

    test('calcula total de ventas por empresa excluyendo anuladas', () async {
      final gateway = _RecordingGateway()
        ..nextRawRows = [
          {'total': 42000},
        ];
      final repository = SqliteSaleRepository(
        gateway: gateway,
        companyContext: const _FakeCompanyContext(5),
        validateFeature: (_) async {},
        resolveCurrency: (_) async => testCop,
      );

      final total = await repository.totalSales();

      expect(total, testMoney('420.00'));
      expect(gateway.lastSqlArgs, [5]);
      expect(gateway.lastSql, contains('company_id = ?'));
      expect(gateway.lastSql, contains("COALESCE(estado, 'emitida')"));
    });
  });
}
