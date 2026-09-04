// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/auditoria/services/chip_reporter_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Pruebas de Integridad de funcionarios_entidad', () {
    test('Guardados consecutivos con IDs determinísticos no duplican registros', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE funcionarios_entidad (
              id TEXT PRIMARY KEY,
              entidad_id TEXT NOT NULL,
              cargo_clave TEXT NOT NULL,
              nombre_completo TEXT NOT NULL,
              identificacion TEXT NOT NULL,
              tarjeta_profesional TEXT,
              telefono TEXT NOT NULL,
              email TEXT NOT NULL,
              direccion TEXT NOT NULL
            )
          ''');
        },
      );

      final auditoriaService = AuditoriaService(db);
      final chipReporterService = CHIPReporterService(
        db: db,
        auditoriaService: auditoriaService,
      );

      final entidadId = 'MUN-SOP-25';

      print('=== PASO 1: Primer guardado con datos iniciales via CHIPReporterService ===');
      await chipReporterService.guardarFuncionariosResponsables(
        entidadId: entidadId,
        representanteNombre: 'Juan Carlos Alcalde',
        representanteId: '80.123.456',
        ordenadorNombre: 'Maria Clara Ordenadora',
        ordenadorId: '1.020.304.050',
        contadorNombre: 'Roberto Ruiz Contador',
        contadorId: '19.456.789',
        contadorTarjeta: '98765-T',
        direccion: 'Calle 5 No. 4-12',
        telefono: '3109876543',
        email: 'hacienda@soporta.gov.co',
      );

      // Consulta del Paso 2
      print('=== PASO 2: Resultado de la consulta después del primer guardado ===');
      final list1 = await db.query(
        'funcionarios_entidad',
        where: 'entidad_id = ?',
        whereArgs: [entidadId],
        orderBy: 'cargo_clave ASC',
      );
      
      for (final row in list1) {
        print('| id: ${row['id']} | cargo_clave: ${row['cargo_clave']} | nombre_completo: ${row['nombre_completo']} |');
      }
      print('Total filas: ${list1.length}');

      expect(list1.length, equals(4));

      print('=== PASO 3: Segundo guardado cambiando el nombre del representante legal via CHIPReporterService ===');
      await chipReporterService.guardarFuncionariosResponsables(
        entidadId: entidadId,
        representanteNombre: 'Carlos Mario Alcalde Nuevo', // Nuevo valor
        representanteId: '80.123.456',
        ordenadorNombre: 'Maria Clara Ordenadora',
        ordenadorId: '1.020.304.050',
        contadorNombre: 'Roberto Ruiz Contador',
        contadorId: '19.456.789',
        contadorTarjeta: '98765-T',
        direccion: 'Calle 5 No. 4-12',
        telefono: '3109876543',
        email: 'hacienda@soporta.gov.co',
      );

      // Consulta del Paso 4
      print('=== PASO 4: Resultado de la consulta después del segundo guardado ===');
      final list2 = await db.query(
        'funcionarios_entidad',
        where: 'entidad_id = ?',
        whereArgs: [entidadId],
        orderBy: 'cargo_clave ASC',
      );
      
      for (final row in list2) {
        print('| id: ${row['id']} | cargo_clave: ${row['cargo_clave']} | nombre_completo: ${row['nombre_completo']} |');
      }
      print('Total filas: ${list2.length}');

      expect(list2.length, equals(4));
      
      final repLegal = list2.firstWhere((r) => r['cargo_clave'] == 'representante_legal');
      expect(repLegal['nombre_completo'], equals('Carlos Mario Alcalde Nuevo'));

      await db.close();
    });
  });
}
