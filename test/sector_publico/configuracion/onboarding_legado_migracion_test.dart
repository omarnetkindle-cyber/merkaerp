import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/configuracion/services/matriz_visibilidad_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'migra onboarding publico legado de municipio al esquema sectorial',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await SchemaMultiTenant.crearTablas(db);
      await db.insert('entidades_territoriales', {
        'id': '2',
        'nit': '900000002-1',
        'razon_social': 'Municipio legado de prueba',
        'tipo_entidad': 'municipio',
        'fecha_creacion': '2026-07-31T00:00:00.000',
        'plan_cuentas_cgc': '{}',
        'configuracion_normativa': '{}',
      });
      await db.execute('''
      CREATE TABLE company_settings (
        company_id INTEGER NOT NULL,
        setting_key TEXT NOT NULL,
        setting_value TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (company_id, setting_key)
      )
    ''');
      await db.insert('company_settings', {
        'company_id': 2,
        'setting_key': 'tipo_entidad',
        'setting_value': 'publica',
        'updated_at': '2026-07-31T00:00:00.000',
      });
      await db.insert('company_settings', {
        'company_id': 2,
        'setting_key': 'subtipo_entidad_publica',
        'setting_value': 'municipio',
        'updated_at': '2026-07-31T00:00:00.000',
      });

      await SchemaMultiTenant.migrarOnboardingLegado(db);

      final configuracion = await db.query(
        'configuracion_entidad',
        where: 'entidad_id = ? AND parametro = ? AND vigente = 1',
        whereArgs: ['2', 'tipo_entidad'],
      );
      final matriz = MatrizVisibilidadService(
        db: db,
        auditoriaService: AuditoriaService(db),
      );
      final modulosMunicipales = await db.query(
        'modulos_por_tipo_entidad',
        where: 'tipo = ?',
        whereArgs: ['municipio'],
      );

      expect(configuracion.single['tipo'], 'municipio');
      expect(configuracion.single['valor'], 'municipio');
      expect(
        configuracion.single['configurado_por'],
        'migracion_onboarding_legado',
      );
      expect(modulosMunicipales, isNotEmpty);
      expect(
        await matriz.obtenerModulosVisibles(
          tipo: 'municipio',
          subtipo: 'categoriaSegunda',
        ),
        contains(Modulo.presupuesto),
      );
    },
  );
}
