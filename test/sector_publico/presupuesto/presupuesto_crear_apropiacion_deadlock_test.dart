import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('crear apropiacion en servicio puro no bloquea FFI', () async {
    final path =
        '${Directory.systemTemp.path}/presupuesto_deadlock_${DateTime.now().microsecondsSinceEpoch}.db';
    final db = await databaseFactory.openDatabase(path);
    await SchemaPresupuesto.crearTablas(db);
    final service = PresupuestoService(db: db);

    await service.crearApropiacion(
      entidadId: 'entidad-prueba',
      usuarioId: 'usuario-prueba',
      vigencia: '2026',
      codigoRubro: '01-01',
      nombreRubro: 'Prueba',
      valorApropiado: publicMoneyFromMajor('1000'),
      fuenteFinanciacion: 'Recursos propios',
      sector: 'Educacion',
      programa: 'Programa',
      subprograma: 'Subprograma',
      proyecto: 'Proyecto',
      actividad: 'Actividad',
      objetoGasto: 'Objeto',
      fechaAprobacionConcejo: DateTime(2026),
      actoAdministrativo: 'ACT-1',
    );

    expect(await db.query('apropiaciones'), hasLength(1));
    await db.close();
    await File(path).delete();
  });
}
