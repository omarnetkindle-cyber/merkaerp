import 'package:sqflite/sqflite.dart';

import '../../core/company/company_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/database/database_gateway.dart';
import '../../core/database/tenant_database_gateway.dart';
import '../../db_helper.dart';
import '../../features/feature_key.dart';
import '../../sync/application/merka_sale_sync_outbox.dart';
import '../domain/product.dart';

abstract class ProductRepository {
  Future<List<Product>> findAll();

  Future<Product?> findById(int id);

  Future<int> save(Product product);

  Future<void> delete(int id);

  Future<void> updateStock(int id, double stock);
}

class SqliteProductRepository implements ProductRepository {
  SqliteProductRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _tenantGateway = TenantDatabaseGateway(
         gateway: gateway,
         companyContext: companyContext ?? CompanyContextService.instance,
       );

  final TenantDatabaseGateway _tenantGateway;

  Future<Currency> _currencyFor(int companyId) async {
    final db = await DatabaseHelper.instance.database;
    return MoneyCurrencyResolver.resolve(db, companyId: companyId);
  }

  @override
  Future<void> delete(int id) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(
      FeatureKey.inventory,
    );
    await _tenantGateway.delete(
      'productos',
      query: TenantQuery(where: 'id = ?', whereArgs: [id]),
    );
  }

  @override
  Future<List<Product>> findAll() async {
    final rows = await _tenantGateway.query(
      'productos',
      query: const TenantQuery(orderBy: 'nombre ASC'),
    );
    final currency = await _currencyFor(await _tenantGateway.companyId);
    return rows.map((row) => Product.fromMap(row, currency: currency)).toList();
  }

  @override
  Future<Product?> findById(int id) async {
    final row = await _tenantGateway.findById('productos', id);
    if (row == null) return null;
    final currency = await _currencyFor(await _tenantGateway.companyId);
    return Product.fromMap(row, currency: currency);
  }

  @override
  Future<int> save(Product product) async {
    await DatabaseHelper.instance.validarFeatureHabilitada(
      FeatureKey.inventory,
    );
    final data = product.toPersistenceMap()..remove('company_id');

    final id = product.id;
    if (id == null) {
      final savedId = await _tenantGateway.insert('productos', data);
      await _enqueueProductUpsert(savedId);
      return savedId;
    }

    final updated = await _tenantGateway.update(
      'productos',
      data,
      query: TenantQuery(where: 'id = ?', whereArgs: [id]),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated > 0) {
      await _enqueueProductUpsert(id);
    }
    return updated;
  }

  @override
  Future<void> updateStock(int id, double stock) async {
    if (stock < 0) {
      throw Exception('El stock no puede quedar negativo.');
    }
    await _tenantGateway.update('productos', {
      'stock': stock,
    }, query: TenantQuery(where: 'id = ?', whereArgs: [id]));
  }

  Future<void> _enqueueProductUpsert(int productId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await const MerkaMasterDataSyncOutboxWriter().enqueueProductUpserted(
        db: db,
        companyId: await _tenantGateway.companyId,
        productId: productId,
      );
    } catch (_) {
      // La sincronización nunca debe impedir guardar inventario local/offline.
    }
  }
}
