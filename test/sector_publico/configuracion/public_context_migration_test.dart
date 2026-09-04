import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('repara onboarding público legado y crea el tenant territorial', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await DatabaseHelper.instance.crearDBForTesting(
      db,
      DatabaseHelper.schemaVersion,
    );
    await db.insert('companies', {
      'name': 'Municipio legado',
      'tax_id': '900000000-1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.insert('company_settings', {
      'company_id': 1,
      'setting_key': 'tipo_entidad',
      'setting_value': 'publica',
      'updated_at': DateTime.now().toIso8601String(),
    });
    await db.insert('company_settings', {
      'company_id': 1,
      'setting_key': 'subtipo_entidad_publica',
      'setting_value': 'municipio',
      'updated_at': DateTime.now().toIso8601String(),
    });

    await SchemaMultiTenant.migrarContextoPublicoDesdeCompanySettings(db);

    final entidad = await db.query(
      'entidades_territoriales',
      where: 'company_id = ?',
      whereArgs: [1],
    );
    final config = await db.query(
      'configuracion_entidad',
      where: 'entidad_id = ? AND vigente = 1',
      whereArgs: ['ENT-001'],
    );

    expect(entidad.single['id'], 'ENT-001');
    expect(entidad.single['tipo_entidad'], 'municipio');
    expect(config.single['valor'], 'municipio');
    expect(config.single['subtipo'], 'municipio');

    await SchemaMultiTenant.migrarContextoPublicoDesdeCompanySettings(db);
    expect(
      await db.rawQuery(
        'SELECT COUNT(*) AS total FROM entidades_territoriales WHERE company_id = 1',
      ),
      [
        {'total': 1},
      ],
    );
  });
}
