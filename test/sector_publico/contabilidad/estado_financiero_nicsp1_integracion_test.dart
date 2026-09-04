import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/cierre_vigencia_service.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/contabilidad_nicsp_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _entidadId = 'ENT-NICSP1-001';
const _vigencia = '2026';

late Database db;
late CierreVigenciaService cierreService;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaContabilidad.crearTablas(db);
    final auditoria = AuditoriaService(db);
    cierreService = CierreVigenciaService(
      db: db,
      contabilidadService: ContabilidadNICSPService(
        db: db,
        auditoriaService: auditoria,
      ),
      auditoriaService: auditoria,
    );
  });

  tearDown(() async => db.close());

  test(
    'NICSP 1 presenta creditos positivos e integra resultado al patrimonio',
    () async {
      await _insertarSaldo('1110', 'Efectivo', deudor: 1000, acreedor: 0);
      await _insertarSaldo(
        '2401',
        'Cuentas por pagar',
        deudor: 0,
        acreedor: 400,
      );
      await _insertarSaldo('3105', 'Capital fiscal', deudor: 0, acreedor: 300);
      await _insertarSaldo(
        '4111',
        'Ingresos tributarios',
        deudor: 0,
        acreedor: 500,
      );
      await _insertarSaldo(
        '5111',
        'Gastos generales',
        deudor: 200,
        acreedor: 0,
      );

      final situacion = await cierreService.generarEstadoSituacionFinanciera(
        entidadId: _entidadId,
        vigencia: _vigencia,
        fechaCorte: DateTime(2026, 12, 31),
      );
      final resultado = await cierreService.generarEstadoResultado(
        entidadId: _entidadId,
        vigencia: _vigencia,
        fechaInicio: DateTime(2026, 1, 1),
        fechaFin: DateTime(2026, 12, 31),
      );

      expect(situacion.totalActivo, _m(1000));
      expect(situacion.totalPasivo, _m(400));
      expect(situacion.totalPatrimonio, _m(600));
      expect(situacion.totalPasivoPatrimonio, _m(1000));
      expect(situacion.estaCuadrado(), isTrue);
      expect(resultado.totalIngresos, _m(500));
      expect(resultado.totalGastos, _m(200));
      expect(resultado.resultadoOperacional, _m(300));
      expect(
        situacion.patrimonio
            .where((r) => r.codigoCuenta == 'RESULTADO-PERIODO')
            .single
            .valor,
        _m(300),
      );
    },
  );
}

Future<void> _insertarSaldo(
  String codigo,
  String nombre, {
  required num deudor,
  required num acreedor,
}) {
  final deudorMinor = _m(deudor).toSql();
  final acreedorMinor = _m(acreedor).toSql();
  return db.insert('saldos_cuentas', {
    'id': 'SALDO-$codigo',
    'entidad_id': _entidadId,
    'cuenta_codigo': codigo,
    'cuenta_nombre': nombre,
    'saldo_deudor': deudorMinor,
    'saldo_acreedor': acreedorMinor,
    'saldo_neto': deudorMinor - acreedorMinor,
    'fecha_ultimo_movimiento': DateTime(2026, 12, 31).toIso8601String(),
    'vigencia': _vigencia,
  });
}

MoneyValue _m(num pesos) => publicMoneyFromMajor(pesos.toString());
