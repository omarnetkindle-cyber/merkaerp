import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/nomina/database/schema_nomina.dart';
import 'package:merka_erp/sector_publico/nomina/models/empleado.dart';
import 'package:merka_erp/sector_publico/nomina/services/nomina_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late NominaService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE entidades_territoriales (id TEXT PRIMARY KEY)
    ''');
    await db.execute('''
      CREATE TABLE configuracion_entidad (
        entidad_id TEXT NOT NULL,
        parametro TEXT NOT NULL,
        valor TEXT NOT NULL,
        vigente INTEGER NOT NULL DEFAULT 1
      )
    ''');
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
    await SchemaNomina.crearTablas(db);
    await db.insert('entidades_territoriales', {'id': 'ENT-001'});
    await db.insert('configuracion_entidad', {
      'entidad_id': 'ENT-001',
      'parametro': 'configuracion_legal',
      'valor': '{"smmlv":1750905,"auxilio_transporte":249095}',
    });
    service = NominaService(db: db, auditoriaService: AuditoriaService(db));
  });

  tearDown(() => db.close());

  test(
    'liquida IBC sin auxilio y no descuenta aportes patronales del neto',
    () async {
      await _insertarEmpleado(
        db,
        id: 'CARRERA',
        salario: 2000000,
        regimen: RegimenNominaPublica.carreraAdministrativa,
        arl: 1,
      );

      final liquidacion = await _liquidar(service, 'CARRERA');

      expect(liquidacion.salud, publicMoneyFromMajor('170000'));
      expect(liquidacion.pension, publicMoneyFromMajor('240000'));
      expect(liquidacion.riesgosLaborales, publicMoneyFromMajor('10440'));
      expect(liquidacion.cajaCompensacion, publicMoneyFromMajor('80000'));
      expect(liquidacion.sena, publicMoneyFromMajor('40000'));
      expect(liquidacion.icbf, publicMoneyFromMajor('60000'));
      expect(liquidacion.auxilioTransporte, publicMoneyFromMajor('249095'));
      expect(liquidacion.netoPagar, publicMoneyFromMajor('2089095'));
    },
  );

  test('aplica ARL por clase y solidaridad gradual desde 16 SMMLV', () async {
    final salario = publicMoneyFromMajor('29765385');
    await _insertarEmpleado(
      db,
      id: 'OFICIAL',
      salario: salario,
      regimen: RegimenNominaPublica.trabajadorOficial,
      arl: 5,
    );

    final liquidacion = await _liquidar(service, 'OFICIAL');

    expect(liquidacion.riesgosLaborales, salario.multiplyDecimal('0.0696'));
    expect(liquidacion.fondoSolidaridad, salario.multiplyDecimal('0.012'));
    expect(
      liquidacion.netoPagar,
      salario -
          salario.multiplyDecimal('0.04') -
          salario.multiplyDecimal('0.04') -
          salario.multiplyDecimal('0.012'),
    );
  });

  test(
    'conserva tratamiento trazable para los seis regimenes publicos',
    () async {
      for (final regimen in RegimenNominaPublica.values) {
        await _insertarEmpleado(
          db,
          id: regimen.name,
          salario: publicMoneyFromMajor('4000000'),
          regimen: regimen,
          arl: 2,
        );
        final liquidacion = await _liquidar(service, regimen.name);
        expect(liquidacion.estado.toString(), 'EstadoLiquidacion.generada');
        expect(liquidacion.observaciones, isNotEmpty);
        expect(liquidacion.riesgosLaborales, publicMoneyFromMajor('41760'));
      }
    },
  );
}

Future<void> _insertarEmpleado(
  Database db, {
  required String id,
  required dynamic salario,
  required RegimenNominaPublica regimen,
  required int arl,
}) {
  return db.insert('empleados_sp', {
    'id': id,
    'entidad_id': 'ENT-001',
    'numero_identificacion': id,
    'nombre_completo': 'Empleado $id',
    'cargo': 'Profesional',
    'dependencia': 'Administrativa',
    'tipo_contrato': 'indefinido',
    'tipo_vinculacion': 'carrera',
    'regimen_nomina': regimen.name,
    'clase_riesgo_arl': arl,
    'salario_basico': salario is int
        ? publicMoneyFromMajor(salario.toString()).toSql()
        : (salario as dynamic).toSql(),
    'fecha_ingreso': '2026-01-01',
    'activo': 1,
  });
}

Future<dynamic> _liquidar(NominaService service, String empleadoId) {
  return service.liquidarNomina(
    entidadId: 'ENT-001',
    usuarioId: 'USR-001',
    empleadoId: empleadoId,
    periodo: '2026-08',
    diasTrabajados: 30,
  );
}
