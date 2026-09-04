import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/conciliacion_reciprocas_service.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/consolidacion_jerarquica_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ConsolidacionJerarquicaService consolidacionService;
  late ConciliacionReciprocasService conciliacionService;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);

    final ahora = DateTime(2026, 7, 31).toIso8601String();
    await db.insert('entidades_territoriales', {
      'id': 'GOB-01',
      'nit': '800111222-1',
      'razon_social': 'Gobernacion de Prueba',
      'tipo_entidad': 'departamento',
      'fecha_creacion': ahora,
      'activo': 1,
      'plan_cuentas_cgc': 'CGN_2015',
      'configuracion_normativa': '{}',
    });
    await db.insert('entidades_territoriales', {
      'id': 'MUN-01',
      'nit': '890300111-2',
      'razon_social': 'Municipio de Prueba',
      'tipo_entidad': 'municipio',
      'gobernacion_id': 'GOB-01',
      'fecha_creacion': ahora,
      'activo': 1,
      'plan_cuentas_cgc': 'CGN_2015',
      'configuracion_normativa': '{}',
    });
    await db.insert('funcionarios_entidad', {
      'id': 'FUN-CONTADOR',
      'entidad_id': 'GOB-01',
      'usuario_id': 'USR-CONTADOR',
      'cargo_clave': 'contador',
      'nombre_completo': 'Contador Consolidador',
      'identificacion': '1001',
      'telefono': '3000000000',
      'email': 'contador@example.test',
      'direccion': 'Sede central',
    });
    await db.insert('funcionarios_entidad', {
      'id': 'FUN-CONTROL',
      'entidad_id': 'GOB-01',
      'usuario_id': 'USR-CONTROL',
      'cargo_clave': 'jefeControlInterno',
      'nombre_completo': 'Jefe Control Interno',
      'identificacion': '1002',
      'telefono': '3000000001',
      'email': 'control@example.test',
      'direccion': 'Sede central',
    });

    await _insertarAsiento(
      db,
      id: 'ASI-GOB',
      entidadId: 'GOB-01',
      numero: 'GOB-2026-001',
      detalles: const [
        _Detalle('DET-GOB-GASTO', '542305', 'Transferencia entregada', 100, 0),
        _Detalle('DET-GOB-BANCO', '111005', 'Bancos', 0, 100),
      ],
    );
    await _insertarAsiento(
      db,
      id: 'ASI-MUN',
      entidadId: 'MUN-01',
      numero: 'MUN-2026-001',
      detalles: const [
        _Detalle('DET-MUN-BANCO', '111005', 'Bancos', 100, 0),
        _Detalle('DET-MUN-INGRESO', '442805', 'Transferencia recibida', 0, 100),
      ],
    );

    await _insertarSaldo(db, 'SAL-GOB-GASTO', 'GOB-01', '542305', 100, 0);
    await _insertarSaldo(db, 'SAL-GOB-BANCO', 'GOB-01', '111005', 0, 100);
    await _insertarSaldo(db, 'SAL-MUN-BANCO', 'MUN-01', '111005', 100, 0);
    await _insertarSaldo(db, 'SAL-MUN-INGRESO', 'MUN-01', '442805', 0, 100);

    consolidacionService = ConsolidacionJerarquicaService(db: db);
    conciliacionService = ConciliacionReciprocasService(db: db);
  });

  tearDown(() async => db.close());

  test(
    'NICSP 40 conserva la reciproca sin conciliar y la elimina solo tras aprobacion contable',
    () async {
      final asientosAntes = await db.query(
        'asientos_contables_sp',
        orderBy: 'id',
      );
      final detallesAntes = await db.query('detalles_asientos', orderBy: 'id');

      final sinConciliar = await consolidacionService
          .obtenerConsolidadoContable(
            entidadIdPadre: 'GOB-01',
            vigencia: '2026',
          );
      expect(sinConciliar['clases']['5']['neto'], _m(100));
      expect(sinConciliar['clases']['4']['neto'], _m(-100));
      expect(
        sinConciliar['eliminaciones_reciprocas']['conciliaciones_aplicadas'],
        0,
      );

      await expectLater(
        conciliacionService.aprobarConciliacion(
          entidadConsolidadoraId: 'GOB-01',
          vigencia: '2026',
          usuarioId: 'USR-CONTROL',
          partidas: [
            PartidaReciprocaInput(
              detalleAsientoId: 'DET-GOB-GASTO',
              montoEliminar: _m(100),
            ),
            PartidaReciprocaInput(
              detalleAsientoId: 'DET-MUN-INGRESO',
              montoEliminar: _m(100),
            ),
          ],
          toleranciaMonto: _m(0),
          toleranciaDias: 0,
        ),
        throwsA(isA<StateError>()),
      );

      final conciliacionId = await conciliacionService.aprobarConciliacion(
        entidadConsolidadoraId: 'GOB-01',
        vigencia: '2026',
        usuarioId: 'USR-CONTADOR',
        partidas: [
          PartidaReciprocaInput(
            detalleAsientoId: 'DET-GOB-GASTO',
            montoEliminar: _m(100),
          ),
          PartidaReciprocaInput(
            detalleAsientoId: 'DET-MUN-INGRESO',
            montoEliminar: _m(100),
          ),
        ],
        toleranciaMonto: _m(0),
        toleranciaDias: 0,
        observaciones: 'Transferencia intragrupo soportada por acto 001.',
      );

      final conciliacion = (await db.query(
        'conciliaciones_reciprocas',
        where: 'id = ?',
        whereArgs: [conciliacionId],
      )).single;
      expect(conciliacion['aprobado_por'], 'USR-CONTADOR');
      expect(conciliacion['tolerancia_monto'], 0);
      expect(conciliacion['tolerancia_dias'], 0);
      expect(conciliacion['diferencia_monto_validada'], 0);
      expect(conciliacion['diferencia_dias_validada'], 0);

      final conciliado = await consolidacionService.obtenerConsolidadoContable(
        entidadIdPadre: 'GOB-01',
        vigencia: '2026',
      );
      expect(conciliado['clases']['5']['neto'], _m(0));
      expect(conciliado['clases']['4']['neto'], _m(0));
      expect(conciliado['clases']['1']['neto'], _m(0));
      expect(
        conciliado['eliminaciones_reciprocas']['conciliaciones_aplicadas'],
        1,
      );
      expect(
        conciliado['eliminaciones_reciprocas']['debito_eliminado'],
        _m(100),
      );
      expect(
        conciliado['eliminaciones_reciprocas']['credito_eliminado'],
        _m(100),
      );

      expect(
        await db.query('asientos_contables_sp', orderBy: 'id'),
        asientosAntes,
      );
      expect(await db.query('detalles_asientos', orderBy: 'id'), detallesAntes);
      expect(
        await db.query(
          'auditoria_registros',
          where: 'accion = ?',
          whereArgs: ['APROBAR_CONCILIACION_RECIPROCA'],
        ),
        hasLength(1),
      );
    },
  );
}

class _Detalle {
  const _Detalle(this.id, this.cuenta, this.nombre, this.debito, this.credito);

  final String id;
  final String cuenta;
  final String nombre;
  final int debito;
  final int credito;
}

Future<void> _insertarAsiento(
  Database db, {
  required String id,
  required String entidadId,
  required String numero,
  required List<_Detalle> detalles,
}) async {
  await db.insert('asientos_contables_sp', {
    'id': id,
    'entidad_id': entidadId,
    'numero_asiento': numero,
    'fecha_asiento': DateTime(2026, 7, 31).toIso8601String(),
    'descripcion': 'Transferencia intragrupo',
    'tipo_asiento': 'manual',
    'estado': 'borrador',
    'total_debito': 10000,
    'total_credito': 10000,
    'usuario_creo': 'USR-CONTADOR',
  });
  for (final detalle in detalles) {
    await db.insert('detalles_asientos', {
      'id': detalle.id,
      'asiento_id': id,
      'cuenta_codigo': detalle.cuenta,
      'cuenta_nombre': detalle.nombre,
      'debito': publicMoneyFromMajor(detalle.debito.toString()).toSql(),
      'credito': publicMoneyFromMajor(detalle.credito.toString()).toSql(),
    });
  }
  await db.update(
    'asientos_contables_sp',
    {'estado': 'registrado'},
    where: 'id = ?',
    whereArgs: [id],
  );
}

Future<void> _insertarSaldo(
  Database db,
  String id,
  String entidadId,
  String cuenta,
  int debito,
  int credito,
) {
  return db.insert('saldos_cuentas', {
    'id': id,
    'entidad_id': entidadId,
    'cuenta_codigo': cuenta,
    'cuenta_nombre': cuenta,
    'saldo_deudor': publicMoneyFromMajor(debito.toString()).toSql(),
    'saldo_acreedor': publicMoneyFromMajor(credito.toString()).toSql(),
    'saldo_neto': publicMoneyFromMajor((debito - credito).toString()).toSql(),
    'fecha_ultimo_movimiento': DateTime(2026, 7, 31).toIso8601String(),
    'vigencia': '2026',
  });
}

MoneyValue _m(num pesos) => publicMoneyFromMajor(pesos.toString());
