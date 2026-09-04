import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/contratacion/database/schema_contratacion.dart';
import 'package:merka_erp/sector_publico/contratacion/models/contrato.dart';
import 'package:merka_erp/sector_publico/contratacion/models/poliza.dart';
import 'package:merka_erp/sector_publico/contratacion/services/contratacion_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/planeacion/database/schema_planeacion.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _entidadId = 'ENT-CONTRATACION-001';
const _usuarioPresupuesto = 'USR-JEFE-PRESUPUESTO';

late Database db;
late PresupuestoService presupuestoService;
late ContratacionService contratacionService;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaPlaneacion.crearTablas(db);
    await SchemaContratacion.crearTablas(db);

    final auditoria = AuditoriaService(db);
    presupuestoService = PresupuestoService(
      db: db,
      auditoriaService: auditoria,
    );
    contratacionService = ContratacionService(
      db: db,
      presupuestoService: presupuestoService,
      auditoriaService: auditoria,
    );

    await db.insert('entidades_territoriales', {
      'id': _entidadId,
      'nit': '901000001-1',
      'razon_social': 'Municipio de Prueba',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    await db.insert('funcionarios_entidad', {
      'id': 'FUNC-PRESUPUESTO',
      'entidad_id': _entidadId,
      'usuario_id': _usuarioPresupuesto,
      'cargo_clave': 'jefePresupuesto',
      'nombre_completo': 'Jefe de Presupuesto',
      'identificacion': '100000001',
      'telefono': '3000000000',
      'email': 'presupuesto@prueba.gov.co',
      'direccion': 'Direccion de prueba',
    });
  });

  tearDown(() async => db.close());

  test(
    'proceso adjudicado, contrato firmado, RP, poliza y legalizacion',
    () async {
      final flujo = await _crearContratoFirmado('FELIZ');

      expect(flujo.contrato.estado, EstadoContrato.firmado);
      expect(flujo.contrato.rpId, isNull);

      final asociado = await contratacionService.asociarRPAContrato(
        entidadId: _entidadId,
        usuarioId: _usuarioPresupuesto,
        contratoId: flujo.contrato.id,
        valorRP: publicMoneyFromMajor('600'),
        funcionarioExpedidor: 'Jefe de Presupuesto',
        funcionarioSolicitante: 'Secretaria de Obras',
        objetoGasto: 'Mantenimiento vial',
      );
      expect(asociado.rpId, isNotNull);
      expect((await db.query('rps')), hasLength(1));

      await contratacionService.registrarPoliza(
        entidadId: _entidadId,
        usuarioId: _usuarioPresupuesto,
        contratoId: asociado.id,
        numeroContrato: asociado.numeroContrato,
        tipoPoliza: TipoPoliza.cumplimiento,
        aseguradora: 'Aseguradora de Prueba',
        valorAsegurado: publicMoneyFromMajor('600'),
        fechaInicioVigencia: DateTime.now().subtract(const Duration(days: 1)),
        fechaFinVigencia: DateTime.now().add(const Duration(days: 365)),
      );
      final legalizado = await contratacionService.legalizarContrato(
        entidadId: _entidadId,
        usuarioId: _usuarioPresupuesto,
        contratoId: asociado.id,
      );

      expect(legalizado.estado, EstadoContrato.legalizado);
      expect(legalizado.fechaLegalizacion, isNotNull);
    },
  );

  test('bloquea asociar RP sin contrato firmado', () async {
    final sinFirmar = await _crearContratoFirmado('SIN-FIRMA');
    await db.update(
      'contratos',
      {'estado': 'enFirma'},
      where: 'id = ?',
      whereArgs: [sinFirmar.contrato.id],
    );
    await expectLater(
      contratacionService.asociarRPAContrato(
        entidadId: _entidadId,
        usuarioId: _usuarioPresupuesto,
        contratoId: sinFirmar.contrato.id,
        valorRP: publicMoneyFromMajor('100'),
        funcionarioExpedidor: 'Jefe de Presupuesto',
        funcionarioSolicitante: 'Solicitante',
        objetoGasto: 'Servicio',
      ),
      throwsException,
    );
  });

  test('bloquea RP ajeno al proceso de contratacion', () async {
    final origenRP = await _crearContratoFirmado('RP-AJENO');
    final conRP = await contratacionService.asociarRPAContrato(
      entidadId: _entidadId,
      usuarioId: _usuarioPresupuesto,
      contratoId: origenRP.contrato.id,
      valorRP: publicMoneyFromMajor('100'),
      funcionarioExpedidor: 'Jefe de Presupuesto',
      funcionarioSolicitante: 'Solicitante',
      objetoGasto: 'Servicio',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final destino = await _crearContratoFirmado('OTRO-PROCESO');
    await expectLater(
      contratacionService.crearContrato(
        entidadId: _entidadId,
        usuarioId: _usuarioPresupuesto,
        procesoId: destino.procesoId,
        contratistaId: 'TERCERO-OTRO',
        contratistaNombre: 'Proveedor Otro',
        contratistaIdentificacion: '900000002',
        cdpId: destino.cdpId,
        numeroCDP: destino.numeroCDP,
        rpId: conRP.rpId,
        numeroRP: conRP.numeroRP,
        fechaFirma: DateTime.now(),
        fechaInicioEjecucion: DateTime.now(),
        fechaFinEjecucion: DateTime.now().add(const Duration(days: 30)),
      ),
      throwsException,
    );
  });

  test('bloquea legalizacion sin poliza vigente', () async {
    final sinPoliza = await _crearContratoFirmado('SIN-POLIZA');
    final conRPSinPoliza = await contratacionService.asociarRPAContrato(
      entidadId: _entidadId,
      usuarioId: _usuarioPresupuesto,
      contratoId: sinPoliza.contrato.id,
      valorRP: publicMoneyFromMajor('100'),
      funcionarioExpedidor: 'Jefe de Presupuesto',
      funcionarioSolicitante: 'Solicitante',
      objetoGasto: 'Servicio',
    );
    await expectLater(
      contratacionService.legalizarContrato(
        entidadId: _entidadId,
        usuarioId: _usuarioPresupuesto,
        contratoId: conRPSinPoliza.id,
      ),
      throwsException,
    );
  });
}

Future<_ContratoCreado> _crearContratoFirmado(String sufijo) async {
  final apropiacion = await presupuestoService.crearApropiacion(
    entidadId: _entidadId,
    usuarioId: _usuarioPresupuesto,
    vigencia: '2026',
    codigoRubro: '2210101-$sufijo',
    nombreRubro: 'Mantenimiento $sufijo',
    valorApropiado: publicMoneyFromMajor('1000'),
    fuenteFinanciacion: 'Recursos propios',
    sector: 'Infraestructura',
    programa: 'Mantenimiento',
    subprograma: 'Vias',
    proyecto: 'Proyecto $sufijo',
    actividad: 'Actividad $sufijo',
    objetoGasto: 'Mantenimiento vial',
    fechaAprobacionConcejo: DateTime(2026, 1, 1),
    actoAdministrativo: 'ACUERDO-$sufijo',
  );
  final cdp = await presupuestoService.expedirCDP(
    entidadId: _entidadId,
    usuarioId: _usuarioPresupuesto,
    apropiacionId: apropiacion.id,
    valorCDP: publicMoneyFromMajor('800'),
    funcionarioExpedidor: 'Jefe de Presupuesto',
    funcionarioSolicitante: 'Secretaria de Obras',
    objetoGasto: 'Mantenimiento vial',
    contratoNumero: null,
  );
  final procesoId = 'PROCESO-$sufijo';
  final numeroProceso = 'PC-2026-$sufijo';
  await db.insert('procesos_contratacion', {
    'id': procesoId,
    'entidad_id': _entidadId,
    'numero_proceso': numeroProceso,
    'objeto_contrato': 'Mantenimiento vial $sufijo',
    'modalidad': 'licitacionPublica',
    'valor_estimado': 600.0,
    'tipo_contrato': 'obra',
    'dependencia_solicitante': 'Secretaria de Obras',
    'responsable_proceso': 'Responsable de Prueba',
    'fecha_inicio': DateTime.now().toIso8601String(),
    'fecha_publicacion': DateTime.now().toIso8601String(),
    'estado': 'adjudicado',
    'cdp_id': cdp.id,
    'numero_cdp': cdp.numeroCDP,
    'secop_id': 'SECOP-$sufijo',
  });
  final contrato = await contratacionService.crearContrato(
    entidadId: _entidadId,
    usuarioId: _usuarioPresupuesto,
    procesoId: procesoId,
    contratistaId: 'TERCERO-$sufijo',
    contratistaNombre: 'Proveedor $sufijo',
    contratistaIdentificacion: '900000001',
    cdpId: cdp.id,
    numeroCDP: cdp.numeroCDP,
    fechaFirma: DateTime.now(),
    fechaInicioEjecucion: DateTime.now(),
    fechaFinEjecucion: DateTime.now().add(const Duration(days: 30)),
  );
  return _ContratoCreado(
    contrato: contrato,
    procesoId: procesoId,
    cdpId: cdp.id,
    numeroCDP: cdp.numeroCDP,
  );
}

class _ContratoCreado {
  final Contrato contrato;
  final String procesoId;
  final String cdpId;
  final String numeroCDP;

  const _ContratoCreado({
    required this.contrato,
    required this.procesoId,
    required this.cdpId,
    required this.numeroCDP,
  });
}
