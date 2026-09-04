import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/planeacion/database/schema_planeacion.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/presupuesto/models/pago.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/pac_service.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:merka_erp/sector_publico/contratacion/database/schema_contratacion.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

const entidadId = 'ENT-PAGO-001';
const vigencia = '2026';
const codigoRubro = '2210101';
const usuarioPresupuesto = 'USR-PRESUPUESTO';
const usuarioOrdenador = 'USR-ORDENADOR';
const usuarioAlcalde = 'USR-ALCALDE';
const usuarioTesorero = 'USR-TESORERO';

late Database db;
late PresupuestoService presupuestoService;
late PACService pacService;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaContratacion.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaPlaneacion.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);

    final auditoriaService = AuditoriaService(db);
    presupuestoService = PresupuestoService(
      db: db,
      auditoriaService: auditoriaService,
    );
    pacService = PACService(db: db, auditoriaService: auditoriaService);

    await db.insert('entidades_territoriales', {
      'id': entidadId,
      'nit': '901000001-1',
      'razon_social': 'Municipio de Prueba',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    await _crearFuncionario(usuarioPresupuesto, 'jefePresupuesto');
    await _crearFuncionario(usuarioOrdenador, 'ordenadorGasto');
    await _crearFuncionario(usuarioAlcalde, 'alcaldeRepresentanteLegal');
    await _crearFuncionario(usuarioTesorero, 'tesorero');
    await db.insert('terceros_sector_publico', {
      'id': 'TERCERO-001',
      'entidad_id': entidadId,
      'tipo_identificacion': 'NIT',
      'numero_identificacion': '900123456',
      'razon_social': 'Proveedor de Prueba S.A.S.',
      'tipo_tercero': 'juridica',
      'fecha_creacion': DateTime.now().toIso8601String(),
    });
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'flujo completo descuenta PAC, actualiza saldos y genera asiento NICSP',
    () async {
      final flujo = await _crearFlujo(
        pacProgramado: _m(300),
        valorPago: _m(200),
      );

      final pagoAprobado = await presupuestoService.aprobarPago(
        entidadId: entidadId,
        usuarioId: usuarioAlcalde,
        pagoId: flujo.pago.id,
        usuarioIdCreador: usuarioOrdenador,
      );
      final pagoEjecutado = await presupuestoService.ejecutarPago(
        entidadId: entidadId,
        usuarioId: usuarioTesorero,
        pagoId: pagoAprobado.id,
        usuarioIdAprobador: usuarioAlcalde,
      );

      expect(pagoEjecutado.estado, EstadoPago.pagado);
      expect(pagoEjecutado.fechaEjecucion, isNotNull);

      final apropiacion = (await db.query('apropiaciones')).single;
      expect(apropiacion['valor_cdp'], 50000);
      expect(apropiacion['valor_rp'], 50000);
      expect(apropiacion['saldo_disponible'], 0);
      expect(apropiacion['valor_pagado'], 20000);

      final obligacion = (await db.query('obligaciones')).single;
      expect(obligacion['valor_pagado'], 20000);
      expect(obligacion['saldo_pendiente'], 10000);
      expect(obligacion['estado'], 'pagadaParcialmente');

      final pac = (await db.query('pac')).single;
      expect(pac['valor_ejecutado'], 20000);
      expect(pac['saldo_disponible'], 10000);

      final asiento = await db.query(
        'asientos_contables_sp',
        where: 'referencia_origen = ? AND tipo_documento_origen = ?',
        whereArgs: [pagoEjecutado.id, 'PAGO'],
      );
      expect(asiento, hasLength(1));
      expect(asiento.single['tipo_asiento'], 'automaticoPresupuestal');
      expect(asiento.single['estado'], 'registrado');
    },
  );

  test(
    'bloquea saltos de cadena, cupo PAC insuficiente y pago no aprobado',
    () async {
      await expectLater(
        presupuestoService.expedirRP(
          entidadId: entidadId,
          usuarioId: usuarioPresupuesto,
          cdpId: 'CDP-INEXISTENTE',
          contratoId: 'CONTRATO-001',
          contratoNumero: 'CT-001',
          valorRP: _m(100),
          funcionarioExpedidor: 'Jefe de Presupuesto',
          funcionarioSolicitante: 'Solicitante',
          objetoGasto: 'Servicios',
        ),
        throwsException,
      );
      await expectLater(
        presupuestoService.registrarObligacion(
          entidadId: entidadId,
          usuarioId: usuarioOrdenador,
          rpId: 'RP-INEXISTENTE',
          contratoId: 'CONTRATO-001',
          contratoNumero: 'CT-001',
          terceroId: 'TERCERO-001',
          terceroNombre: 'Proveedor de Prueba S.A.S.',
          valorObligacion: _m(100),
          funcionarioReconocio: 'Ordenador del Gasto',
          objetoGasto: 'Servicios',
          facturaNumero: 'FAC-001',
        ),
        throwsException,
      );
      await expectLater(
        presupuestoService.programarPago(
          entidadId: entidadId,
          usuarioId: usuarioOrdenador,
          obligacionId: 'OBLIGACION-INEXISTENTE',
          terceroId: 'TERCERO-001',
          terceroNombre: 'Proveedor de Prueba S.A.S.',
          bancoDestino: 'Banco de Prueba',
          cuentaDestino: '123456789',
          tipoCuenta: 'Corriente',
          valorPago: _m(100),
          funcionarioProgramo: 'Ordenador del Gasto',
          tipoPago: TipoPago.transferenciaBancaria,
          mesPAC: 1,
        ),
        throwsException,
      );

      final excedido = await _crearFlujo(
        pacProgramado: _m(100),
        valorPago: _m(200),
      );
      final pagoExcedido = await presupuestoService.aprobarPago(
        entidadId: entidadId,
        usuarioId: usuarioAlcalde,
        pagoId: excedido.pago.id,
        usuarioIdCreador: usuarioOrdenador,
      );
      await expectLater(
        presupuestoService.ejecutarPago(
          entidadId: entidadId,
          usuarioId: usuarioTesorero,
          pagoId: pagoExcedido.id,
          usuarioIdAprobador: usuarioAlcalde,
        ),
        throwsException,
      );

      final sinAprobacion = await _crearFlujo(
        pacProgramado: _m(300),
        valorPago: _m(200),
        sufijo: 'SIN-APROBACION',
      );
      await expectLater(
        presupuestoService.ejecutarPago(
          entidadId: entidadId,
          usuarioId: usuarioTesorero,
          pagoId: sinAprobacion.pago.id,
          usuarioIdAprobador: usuarioAlcalde,
        ),
        throwsException,
      );
    },
  );
}

Future<void> _crearFuncionario(String usuarioId, String cargoClave) {
  return db.insert('funcionarios_entidad', {
    'id': 'FUNC-$cargoClave',
    'entidad_id': entidadId,
    'usuario_id': usuarioId,
    'cargo_clave': cargoClave,
    'nombre_completo': cargoClave,
    'identificacion': 'ID-$cargoClave',
    'telefono': '3000000000',
    'email': '$cargoClave@prueba.gov.co',
    'direccion': 'Direccion de prueba',
  });
}

Future<_FlujoCreado> _crearFlujo({
  required MoneyValue pacProgramado,
  required MoneyValue valorPago,
  String sufijo = '',
}) async {
  final apropiacion = await presupuestoService.crearApropiacion(
    entidadId: entidadId,
    usuarioId: usuarioPresupuesto,
    vigencia: vigencia,
    codigoRubro: '$codigoRubro$sufijo',
    nombreRubro: 'Servicios generales $sufijo',
    valorApropiado: _m(1000),
    fuenteFinanciacion: 'Recursos propios',
    sector: 'Administracion',
    programa: 'Funcionamiento',
    subprograma: 'Gestion administrativa',
    proyecto: 'Proyecto de prueba',
    actividad: 'Actividad de prueba',
    objetoGasto: 'Servicios',
    fechaAprobacionConcejo: DateTime(2026, 1, 1),
    actoAdministrativo: 'ACUERDO-$sufijo',
  );
  final cdp = await presupuestoService.expedirCDP(
    entidadId: entidadId,
    usuarioId: usuarioPresupuesto,
    apropiacionId: apropiacion.id,
    valorCDP: _m(500),
    funcionarioExpedidor: 'Jefe de Presupuesto',
    funcionarioSolicitante: 'Solicitante',
    objetoGasto: 'Servicios',
    contratoNumero: null,
  );
  final procesoId = 'PROCESO-$sufijo';
  final contratoId = 'CONTRATO-$sufijo';
  final numeroCdp =
      (await db.query(
            'cdps',
            columns: ['numero_cdp'],
            where: 'id = ?',
            whereArgs: [cdp.id],
          )).single['numero_cdp']
          as String;
  await db.insert('procesos_contratacion', {
    'id': procesoId,
    'entidad_id': entidadId,
    'numero_proceso': 'PROC-$sufijo',
    'objeto_contrato': 'Servicios generales',
    'modalidad': 'contratacionDirecta',
    'valor_estimado': 50000,
    'tipo_contrato': 'prestacionServicios',
    'dependencia_solicitante': 'Administracion',
    'responsable_proceso': 'Responsable de prueba',
    'fecha_inicio': '2026-01-01T00:00:00.000',
    'fecha_publicacion': '2026-01-01T00:00:00.000',
    'fecha_cierre': '2026-01-02T00:00:00.000',
    'estado': 'adjudicado',
    'cdp_id': cdp.id,
    'numero_cdp': numeroCdp,
  });
  await db.insert('contratos', {
    'id': contratoId,
    'entidad_id': entidadId,
    'numero_contrato': 'CT-$sufijo',
    'proceso_id': procesoId,
    'numero_proceso': 'PROC-$sufijo',
    'objeto_contrato': 'Servicios generales',
    'tipo_contrato': 'prestacionServicios',
    'valor_contrato': 50000,
    'contratista_id': 'CONTRATISTA-001',
    'contratista_nombre': 'Proveedor de Prueba S.A.S.',
    'contratista_identificacion': '900000001-1',
    'cdp_id': cdp.id,
    'numero_cdp': numeroCdp,
    'rp_id': null,
    'numero_rp': null,
    'fecha_firma': '2026-01-03T00:00:00.000',
    'fecha_inicio_ejecucion': '2026-01-04T00:00:00.000',
    'fecha_fin_ejecucion': '2026-12-31T00:00:00.000',
    'duracion_dias': 362,
    'estado': 'firmado',
  });
  final rp = await presupuestoService.expedirRP(
    entidadId: entidadId,
    usuarioId: usuarioPresupuesto,
    cdpId: cdp.id,
    contratoId: contratoId,
    contratoNumero: 'CT-$sufijo',
    valorRP: _m(500),
    funcionarioExpedidor: 'Jefe de Presupuesto',
    funcionarioSolicitante: 'Solicitante',
    objetoGasto: 'Servicios',
  );
  final obligacion = await presupuestoService.registrarObligacion(
    entidadId: entidadId,
    usuarioId: usuarioOrdenador,
    rpId: rp.id,
    contratoId: 'CONTRATO-$sufijo',
    contratoNumero: 'CT-$sufijo',
    terceroId: 'TERCERO-001',
    terceroNombre: 'Proveedor de Prueba S.A.S.',
    valorObligacion: _m(300),
    funcionarioReconocio: 'Ordenador del Gasto',
    objetoGasto: 'Servicios',
    facturaNumero: 'FACTURA-$sufijo',
    facturaFecha: DateTime(2026, 1, 10),
  );
  final pac = await pacService.programarPAC(
    entidadId: entidadId,
    usuarioId: usuarioTesorero,
    vigencia: vigencia,
    mes: 1,
    codigoRubro: '$codigoRubro$sufijo',
    valorProgramado: pacProgramado,
    funcionarioProgramo: 'Tesorero',
  );
  await pacService.aprobarPAC(
    entidadId: entidadId,
    usuarioId: usuarioTesorero,
    pacId: pac.id,
    funcionarioAprobo: 'Tesorero',
    actoAdministrativo: 'RES-$sufijo',
  );
  final pago = await presupuestoService.programarPago(
    entidadId: entidadId,
    usuarioId: usuarioOrdenador,
    obligacionId: obligacion.id,
    terceroId: 'TERCERO-001',
    terceroNombre: 'Proveedor de Prueba S.A.S.',
    bancoDestino: 'Banco de Prueba',
    cuentaDestino: '123456789',
    tipoCuenta: 'Corriente',
    valorPago: valorPago,
    funcionarioProgramo: 'Ordenador del Gasto',
    tipoPago: TipoPago.transferenciaBancaria,
    mesPAC: 1,
  );

  return _FlujoCreado(pago);
}

class _FlujoCreado {
  final Pago pago;

  const _FlujoCreado(this.pago);
}

MoneyValue _m(num value) => publicMoneyFromMajor(value.toString());
