import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/contratacion/database/schema_contratacion.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v68 conserva contratos y polizas legacy y permite contrato firmado sin RP',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
      CREATE TABLE contratos (
        id TEXT PRIMARY KEY, entidad_id TEXT NOT NULL,
        numero_contrato TEXT NOT NULL UNIQUE, proceso_id TEXT NOT NULL,
        numero_proceso TEXT NOT NULL, objeto_contrato TEXT NOT NULL,
        tipo_contrato TEXT NOT NULL, valor_contrato REAL NOT NULL,
        contratista_id TEXT NOT NULL, contratista_nombre TEXT NOT NULL,
        contratista_identificacion TEXT NOT NULL, cdp_id TEXT NOT NULL,
        numero_cdp TEXT NOT NULL, rp_id TEXT NOT NULL, numero_rp TEXT NOT NULL,
        fecha_firma TEXT NOT NULL, fecha_inicio_ejecucion TEXT NOT NULL,
        fecha_fin_ejecucion TEXT NOT NULL, duracion_dias INTEGER NOT NULL,
        estado TEXT NOT NULL, fecha_legalizacion TEXT, fecha_terminacion TEXT,
        fecha_liquidacion TEXT, supervisor_id TEXT, supervisor_nombre TEXT,
        interventor_id TEXT, interventor_nombre TEXT, observaciones TEXT
      )
    ''');
      await db.execute('''
      CREATE TABLE polizas (
        id TEXT PRIMARY KEY, entidad_id TEXT NOT NULL, contrato_id TEXT NOT NULL,
        numero_contrato TEXT NOT NULL, numero_poliza TEXT NOT NULL UNIQUE,
        tipo_poliza TEXT NOT NULL, aseguradora TEXT NOT NULL,
        valor_asegurado REAL NOT NULL, fecha_emision TEXT NOT NULL,
        fecha_inicio_vigencia TEXT NOT NULL, fecha_fin_vigencia TEXT NOT NULL,
        estado TEXT NOT NULL, fecha_reclamacion TEXT, fecha_pago TEXT,
        observaciones TEXT, FOREIGN KEY (contrato_id) REFERENCES contratos(id)
      )
    ''');
      final ahora = DateTime.now().toIso8601String();
      await _insertarContrato(
        db,
        id: 'CT-LEGACY',
        numero: 'CT-LEGACY',
        rpId: 'RP-LEGACY',
        numeroRp: 'RP-LEGACY',
        fecha: ahora,
      );
      await db.insert('polizas', {
        'id': 'POL-LEGACY',
        'entidad_id': 'ENT-1',
        'contrato_id': 'CT-LEGACY',
        'numero_contrato': 'CT-LEGACY',
        'numero_poliza': 'POL-LEGACY',
        'tipo_poliza': 'cumplimiento',
        'aseguradora': 'Aseguradora',
        'valor_asegurado': 100.0,
        'fecha_emision': ahora,
        'fecha_inicio_vigencia': ahora,
        'fecha_fin_vigencia': ahora,
        'estado': 'vigente',
      });

      await SchemaContratacion.migrarContratosConRPOpcional(db);

      final columnas = await db.rawQuery('PRAGMA table_info(contratos)');
      expect(
        columnas.firstWhere((columna) => columna['name'] == 'rp_id')['notnull'],
        0,
      );
      expect(
        columnas.firstWhere(
          (columna) => columna['name'] == 'numero_rp',
        )['notnull'],
        0,
      );
      final legacy = await db.query(
        'contratos',
        where: 'id = ?',
        whereArgs: ['CT-LEGACY'],
      );
      expect(legacy.single['rp_id'], 'RP-LEGACY');
      expect((await db.query('polizas')).single['contrato_id'], 'CT-LEGACY');

      await _insertarContrato(
        db,
        id: 'CT-SIN-RP',
        numero: 'CT-SIN-RP',
        rpId: null,
        numeroRp: null,
        fecha: ahora,
      );
      expect(
        (await db.query(
          'contratos',
          where: 'id = ?',
          whereArgs: ['CT-SIN-RP'],
        )),
        hasLength(1),
      );
    },
  );
}

Future<void> _insertarContrato(
  Database db, {
  required String id,
  required String numero,
  required String? rpId,
  required String? numeroRp,
  required String fecha,
}) {
  return db.insert('contratos', {
    'id': id,
    'entidad_id': 'ENT-1',
    'numero_contrato': numero,
    'proceso_id': 'PROC-1',
    'numero_proceso': 'PROC-1',
    'objeto_contrato': 'Objeto',
    'tipo_contrato': 'obra',
    'valor_contrato': 100.0,
    'contratista_id': 'TERCERO-1',
    'contratista_nombre': 'Proveedor',
    'contratista_identificacion': '900000001',
    'cdp_id': 'CDP-1',
    'numero_cdp': 'CDP-1',
    'rp_id': rpId,
    'numero_rp': numeroRp,
    'fecha_firma': fecha,
    'fecha_inicio_ejecucion': fecha,
    'fecha_fin_ejecucion': fecha,
    'duracion_dias': 1,
    'estado': 'firmado',
  });
}
