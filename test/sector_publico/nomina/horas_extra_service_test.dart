import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/nomina/database/schema_nomina.dart';
import 'package:merka_erp/sector_publico/nomina/services/horas_extra_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('registrarHorasExtra persists the calculated record', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await SchemaNomina.crearTablas(db);
        await db.execute('''
          CREATE TABLE auditoria_registros (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            usuario_id TEXT NOT NULL,
            usuario_nombre TEXT,
            ip_direccion TEXT,
            fecha_hora TEXT NOT NULL,
            tipo_evento TEXT NOT NULL,
            modulo TEXT NOT NULL,
            accion TEXT NOT NULL,
            valor_anterior TEXT NOT NULL,
            valor_nuevo TEXT NOT NULL,
            hash_anterior TEXT,
            hash_actual TEXT NOT NULL,
            referencia_id TEXT,
            observaciones TEXT
          )
        ''');
      },
    );
    addTearDown(db.close);

    final service = HorasExtraService(
      db: db,
      auditoriaService: AuditoriaService(db),
    );

    final result = await service.registrarHorasExtra(
      entidadId: 'entidad-001',
      usuarioId: 'usuario-001',
      empleadoId: 'empleado-001',
      tipo: TipoHoraExtra.diurna,
      fecha: DateTime(2026, 7, 30),
      cantidadHoras: 2,
      salarioHora: publicMoneyFromMajor('10000'),
    );

    final registros = await db.query(
      'horas_extra',
      where: 'id = ?',
      whereArgs: [result['horas_extra_id']],
    );
    final auditorias = await db.query('auditoria_registros');

    expect(registros, hasLength(1));
    expect(registros.single['empleado_id'], 'empleado-001');
    expect(registros.single['tipo_hora'], 'diurna');
    expect(registros.single['cantidad_horas'], 2.0);
    expect(registros.single['salario_hora'], 1000000);
    expect(registros.single['valor_recargo'], 500000);
    expect(registros.single['valor_total'], 2500000);
    expect(auditorias, hasLength(1));
  });
}
