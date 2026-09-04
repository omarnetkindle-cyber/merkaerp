import 'package:merka_erp/core/company/company_context.dart';
import 'package:merka_erp/core/database/database_gateway.dart';
import 'package:merka_erp/core/database/tenant_database_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

class _Context implements CompanyContextProvider {
  const _Context(this.companyId);

  final int companyId;

  @override
  Future<CompanyContext> current({bool force = false}) async {
    return CompanyContext(companyId: companyId, companyName: 'Tenant');
  }
}

class _Gateway implements DatabaseGateway {
  String? where;
  List<Object?>? whereArgs;
  Map<String, Object?>? insertedValues;

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    this.where = where;
    this.whereArgs = whereArgs;
    return 1;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    insertedValues = values;
    return 1;
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
    this.where = where;
    this.whereArgs = whereArgs;
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    return const [];
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
    this.where = where;
    this.whereArgs = whereArgs;
    return 1;
  }
}

void main() {
  group('TenantDatabaseGateway', () {
    test(
      'agrega filtro company_id a consultas con condiciones existentes',
      () async {
        final gateway = _Gateway();
        final tenantGateway = TenantDatabaseGateway(
          gateway: gateway,
          companyContext: const _Context(42),
        );

        await tenantGateway.query(
          'ventas',
          query: const TenantQuery(where: 'estado = ?', whereArgs: ['emitida']),
        );

        expect(gateway.where, 'company_id = ? AND (estado = ?)');
        expect(gateway.whereArgs, [42, 'emitida']);
      },
    );

    test('inyecta company_id en inserciones', () async {
      final gateway = _Gateway();
      final tenantGateway = TenantDatabaseGateway(
        gateway: gateway,
        companyContext: const _Context(9),
      );

      await tenantGateway.insert('productos', {'nombre': 'Cafe'});

      expect(gateway.insertedValues, {'nombre': 'Cafe', 'company_id': 9});
    });
  });
}
