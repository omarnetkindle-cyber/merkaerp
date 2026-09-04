import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/flujo_efectivo_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _entidadId = 'ENT-FLUJOS-001';
const _usuarioId = 'USR-CONTADOR-001';

late Database db;
late FlujoEfectivoService flujoEfectivoService;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    flujoEfectivoService = FlujoEfectivoService(
      db: db,
      auditoriaService: AuditoriaService(db),
    );

    await db.insert('entidades_territoriales', {
      'id': _entidadId,
      'nit': '901000001-1',
      'razon_social': 'Municipio de Flujos de Prueba',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime(2026, 1, 1).toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    await _insertarSaldoInicial();

    await _insertarMovimiento(
      id: 'AS-INGRESO-OPERACION',
      fecha: DateTime(2026, 6, 10),
      cuentaCodigo: '410101',
      cuentaNombre: 'Ingresos tributarios',
      debito: 500,
    );
    await _insertarMovimiento(
      id: 'AS-GASTO-OPERACION',
      fecha: DateTime(2026, 6, 11),
      cuentaCodigo: '510102',
      cuentaNombre: 'Gastos generales',
      credito: 200,
    );
    await _insertarMovimiento(
      id: 'AS-VENTA-ACTIVO',
      fecha: DateTime(2026, 6, 12),
      cuentaCodigo: '120101',
      cuentaNombre: 'Venta de PPE',
      debito: 120,
    );
    await _insertarMovimiento(
      id: 'AS-COMPRA-ACTIVO',
      fecha: DateTime(2026, 6, 13),
      cuentaCodigo: '160101',
      cuentaNombre: 'Adquisicion de PPE',
      credito: 50,
    );
    await _insertarMovimiento(
      id: 'AS-DEUDA',
      fecha: DateTime(2026, 6, 14),
      cuentaCodigo: '210101',
      cuentaNombre: 'Emision de deuda publica',
      debito: 300,
    );
    await _insertarMovimiento(
      id: 'AS-INTERESES',
      fecha: DateTime(2026, 6, 15),
      cuentaCodigo: '210202',
      cuentaNombre: 'Pago de intereses',
      credito: 70,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'genera NICSP 2 directo con movimientos conocidos del periodo',
    () async {
      final estado = await flujoEfectivoService.generarEstadoFlujosEfectivo(
        entidadId: _entidadId,
        usuarioId: _usuarioId,
        periodo: '2026-06',
      );

      expect(estado['metodo'], 'directo');
      expect(estado['efectivo_inicial'], publicMoneyFromMajor('1000'));
      expect(estado['actividades_operacion'], publicMoneyFromMajor('300'));
      expect(estado['actividades_inversion'], publicMoneyFromMajor('70'));
      expect(estado['actividades_financiacion'], publicMoneyFromMajor('230'));
      expect(estado['variacion_neta_efectivo'], publicMoneyFromMajor('600'));
      expect(estado['efectivo_final'], publicMoneyFromMajor('1600'));
      expect(estado['detalles_operacion'], {
        'Ingresos tributarios': publicMoneyFromMajor('500'),
        'Gastos generales': publicMoneyFromMajor('-200'),
      });

      final auditoria = await db.query(
        'auditoria_registros',
        where: 'entidad_id = ? AND accion = ?',
        whereArgs: [_entidadId, 'generacion_estado_flujos_efectivo'],
      );
      expect(auditoria, hasLength(1));
    },
  );
}

Future<void> _insertarSaldoInicial() {
  return db.insert('saldos_cuentas', {
    'id': 'SALDO-EFECTIVO-001',
    'entidad_id': _entidadId,
    'cuenta_codigo': '110501',
    'cuenta_nombre': 'Caja principal',
    'saldo_deudor': publicMoneyFromMajor('1000').toSql(),
    'saldo_acreedor': publicMoneyFromMajor('0').toSql(),
    'saldo_neto': publicMoneyFromMajor('1000').toSql(),
    'fecha_ultimo_movimiento': DateTime(2026, 1, 1).toIso8601String(),
    'vigencia': '2026',
  });
}

Future<void> _insertarMovimiento({
  required String id,
  required DateTime fecha,
  required String cuentaCodigo,
  required String cuentaNombre,
  double debito = 0,
  double credito = 0,
}) async {
  await db.insert('asientos_contables_sp', {
    'id': id,
    'entidad_id': _entidadId,
    'numero_asiento': id,
    'fecha_asiento': fecha.toIso8601String(),
    'descripcion': 'Movimiento de prueba $id',
    'tipo_asiento': 'manual',
    'estado': 'borrador',
    'total_debito': publicMoneyFromMajor(
      (debito > 0 ? debito : credito).toString(),
    ).toSql(),
    'total_credito': publicMoneyFromMajor(
      (debito > 0 ? debito : credito).toString(),
    ).toSql(),
    'usuario_creo': _usuarioId,
  });
  await db.insert('detalles_asientos', {
    'id': 'DET-$id',
    'asiento_id': id,
    'cuenta_codigo': cuentaCodigo,
    'cuenta_nombre': cuentaNombre,
    'debito': publicMoneyFromMajor(debito.toString()).toSql(),
    'credito': publicMoneyFromMajor(credito.toString()).toSql(),
  });
  await db.insert('detalles_asientos', {
    'id': 'DET-$id-CONTRA',
    'asiento_id': id,
    'cuenta_codigo': '110501',
    'cuenta_nombre': 'Contrapartida de movimiento de prueba',
    'debito': publicMoneyFromMajor(credito.toString()).toSql(),
    'credito': publicMoneyFromMajor(debito.toString()).toSql(),
  });
  await db.update(
    'asientos_contables_sp',
    {'estado': 'registrado'},
    where: 'id = ?',
    whereArgs: [id],
  );
}
