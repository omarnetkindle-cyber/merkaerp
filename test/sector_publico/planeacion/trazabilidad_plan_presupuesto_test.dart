import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/planeacion/database/schema_planeacion.dart';
import 'package:merka_erp/sector_publico/planeacion/services/trazabilidad_plan_presupuesto_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TrazabilidadPlanPresupuestoService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE entidades_territoriales (id TEXT PRIMARY KEY)',
    );
    await db.execute('''
      CREATE TABLE proyectos_mga (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        codigo_bpin TEXT NOT NULL,
        estado TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE apropiaciones (
        id TEXT PRIMARY KEY, entidad_id TEXT NOT NULL,
        valor_apropiado INTEGER NOT NULL, valor_pagado INTEGER NOT NULL
      )
    ''');
    await SchemaPlaneacion.migrarTrazabilidadPlanPresupuesto(db);
    await db.insert('entidades_territoriales', {'id': 'ent-1'});
    await db.insert('proyectos_mga', {
      'id': 'proy-1',
      'entidad_id': 'ent-1',
      'codigo_bpin': 'BPIN-1',
      'estado': 'viabilizado',
    });
    await db.insert('apropiaciones', {
      'id': 'apr-1',
      'entidad_id': 'ent-1',
      'valor_apropiado': 10000000,
      'valor_pagado': 7000000,
    });
    service = TrazabilidadPlanPresupuestoService(db);
  });

  tearDown(() => db.close());

  test(
    'vincula proyecto, rubro y meta y alerta desviacion mayor a 20 puntos',
    () async {
      await service.vincularRubroAMeta(
        id: 'vinculo-1',
        entidadId: 'ent-1',
        proyectoId: 'proy-1',
        apropiacionId: 'apr-1',
        metaCodigo: 'META-01',
        metaDescripcion: 'Cobertura de acueducto',
        avanceFisicoPorcentaje: 40,
        fechaReporte: DateTime(2026, 8, 1),
      );

      final seguimiento = await service.consultarSeguimiento(
        entidadId: 'ent-1',
        proyectoId: 'proy-1',
      );

      expect(seguimiento, hasLength(1));
      expect(seguimiento.single.ejecucionFinancieraPorcentaje, 70);
      expect(seguimiento.single.avanceFisicoPorcentaje, 40);
      expect(seguimiento.single.alertaDesviacion, isTrue);
    },
  );

  test(
    'no alerta cuando la diferencia financiera-fisica es de 20 puntos o menos',
    () async {
      await service.vincularRubroAMeta(
        id: 'vinculo-2',
        entidadId: 'ent-1',
        proyectoId: 'proy-1',
        apropiacionId: 'apr-1',
        metaCodigo: 'META-02',
        metaDescripcion: 'Conexion rural',
        avanceFisicoPorcentaje: 50,
        fechaReporte: DateTime(2026, 8, 1),
      );

      final seguimiento = await service.consultarSeguimiento(
        entidadId: 'ent-1',
        proyectoId: 'proy-1',
      );

      expect(seguimiento.single.alertaDesviacion, isFalse);
    },
  );
}
