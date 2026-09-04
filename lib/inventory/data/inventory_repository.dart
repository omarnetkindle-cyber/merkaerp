import '../../db_helper.dart';

abstract class InventoryRepository {
  Future<List<Map<String, dynamic>>> findAll();
  Future<Map<String, dynamic>?> findById(int id);
  Future<void> updateStock(int id, double newStock);
}

class SqliteInventoryRepository implements InventoryRepository {
  final DatabaseHelper _db;

  SqliteInventoryRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper.instance;

  @override
  Future<List<Map<String, dynamic>>> findAll() async {
    final database = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    return await database.query(
      'productos',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre ASC',
    );
  }

  @override
  Future<Map<String, dynamic>?> findById(int id) async {
    final database = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    final results = await database.query(
      'productos',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  @override
  Future<void> updateStock(int id, double newStock) async {
    if (newStock < 0) {
      throw Exception('El stock no puede quedar negativo.');
    }
    final database = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    await database.update(
      'productos',
      {'stock': newStock},
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );
  }
}
