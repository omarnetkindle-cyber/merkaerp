import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/planeacion/database/schema_planeacion.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/presupuesto/models/pago.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/pac_service.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/vigencias_futuras_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late PresupuestoService presupuesto;
  late VigenciasFuturasService vigencias;
  late int anioFuturo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaPlaneacion.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    await db.execute('''
      CREATE TABLE contratos (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_contrato TEXT NOT NULL UNIQUE,
        estado TEXT NOT NULL,
        cdp_id TEXT NOT NULL,
        rp_id TEXT
      )
    ''');

    final auditoria = AuditoriaService(db);
    presupuesto = PresupuestoService(db: db, auditoriaService: auditoria);
    vigencias = VigenciasFuturasService(db: db);
    anioFuturo = DateTime.now().year + 1;

    await _crearEntidad(db, 'MUN-01', 'municipio', 'Municipio Prueba');
    await _crearEntidad(db, 'ESE-01', 'hospitalEse', 'Hospital ESE Prueba');
    await _crearFuncionario(
      db,
      'MUN-01',
      'USR-ALCALDE',
      'alcaldeRepresentanteLegal',
    );
    await _crearFuncionario(db, 'MUN-01', 'USR-JEFE-MUN', 'jefePresupuesto');
    await _crearFuncionario(db, 'MUN-01', 'USR-ORDENADOR', 'ordenadorGasto');
    await _crearFuncionario(db, 'MUN-01', 'USR-TESORERO', 'tesorero');
    await _crearFuncionario(
      db,
      'ESE-01',
      'USR-HACIENDA-ESE',
      'secretarioHacienda',
    );
    await _crearFuncionario(db, 'ESE-01', 'USR-JEFE-ESE', 'jefePresupuesto');
    await _crearTercero(db, 'MUN-01', 'TER-MUN');
    await _crearTercero(db, 'ESE-01', 'TER-ESE');
  });

  tearDown(() async => db.close());

  test(
    'municipio autorizado recorre compromiso obligacion y pago por anualidad',
    () async {
      final autorizacionId = await _registrarAutorizacion(
        service: vigencias,
        entidadId: 'MUN-01',
        usuarioId: 'USR-ALCALDE',
        anio: anioFuturo,
        corporacion: 'concejo',
      );
      final rpId = await _crearRpFuturo(
        db: db,
        presupuesto: presupuesto,
        entidadId: 'MUN-01',
        usuarioJefe: 'USR-JEFE-MUN',
        sufijo: 'MUN',
        anio: anioFuturo,
        valorRP: _m(600),
        autorizacionId: autorizacionId,
      );
      final obligacion = await presupuesto.registrarObligacion(
        entidadId: 'MUN-01',
        usuarioId: 'USR-ORDENADOR',
        rpId: rpId,
        contratoId: 'CT-MUN',
        contratoNumero: 'CONTRATO-MUN',
        terceroId: 'TER-MUN',
        terceroNombre: 'Proveedor futuro municipal',
        valorObligacion: _m(500),
        funcionarioReconocio: 'Ordenador del gasto',
        objetoGasto: 'Proyecto plurianual',
        facturaNumero: 'FAC-MUN',
        facturaFecha: DateTime.now(),
      );
      final pac = PACService(db: db, auditoriaService: AuditoriaService(db));
      final cupo = await pac.programarPAC(
        entidadId: 'MUN-01',
        usuarioId: 'USR-TESORERO',
        vigencia: anioFuturo.toString(),
        mes: 1,
        codigoRubro: 'RUBRO-MUN',
        valorProgramado: _m(500),
        funcionarioProgramo: 'Tesorero',
      );
      await pac.aprobarPAC(
        entidadId: 'MUN-01',
        usuarioId: 'USR-TESORERO',
        pacId: cupo.id,
        funcionarioAprobo: 'Tesorero',
        actoAdministrativo: 'RES-PAC-MUN',
      );
      final pago = await presupuesto.programarPago(
        entidadId: 'MUN-01',
        usuarioId: 'USR-ORDENADOR',
        obligacionId: obligacion.id,
        terceroId: 'TER-MUN',
        terceroNombre: 'Proveedor futuro municipal',
        bancoDestino: 'Banco publico',
        cuentaDestino: '123456',
        tipoCuenta: 'corriente',
        valorPago: _m(400),
        funcionarioProgramo: 'Ordenador del gasto',
        tipoPago: TipoPago.transferenciaBancaria,
        mesPAC: 1,
      );
      final aprobado = await presupuesto.aprobarPago(
        entidadId: 'MUN-01',
        usuarioId: 'USR-ALCALDE',
        pagoId: pago.id,
        usuarioIdCreador: 'USR-ORDENADOR',
      );
      await presupuesto.ejecutarPago(
        entidadId: 'MUN-01',
        usuarioId: 'USR-TESORERO',
        pagoId: aprobado.id,
        usuarioIdAprobador: 'USR-ALCALDE',
      );

      final compromiso = (await db.query(
        'compromisos_vigencias_futuras',
      )).single;
      final distribucion = (await db.query(
        'vigencias_futuras_distribucion',
        where: 'autorizacion_id = ?',
        whereArgs: [autorizacionId],
      )).single;
      expect(compromiso['rp_id'], rpId);
      expect(compromiso['monto_comprometido'], 60000);
      expect(compromiso['monto_obligado'], 50000);
      expect(compromiso['monto_pagado'], 40000);
      expect(distribucion['monto_autorizado'], 100000);
      expect(distribucion['monto_comprometido'], 60000);
      expect(distribucion['monto_obligado'], 50000);
      expect(distribucion['monto_pagado'], 40000);
      expect(distribucion['saldo_disponible'], 40000);
    },
  );

  test(
    'ESE configurada autoriza y compromete; ESE incompleta se deniega fail-closed',
    () async {
      await expectLater(
        _registrarAutorizacion(
          service: vigencias,
          entidadId: 'ESE-01',
          usuarioId: 'USR-HACIENDA-ESE',
          anio: anioFuturo,
          corporacion: 'autoridad_configurada',
        ),
        throwsA(isA<StateError>()),
      );

      final autorizacionId = await _registrarAutorizacion(
        service: vigencias,
        entidadId: 'ESE-01',
        usuarioId: 'USR-HACIENDA-ESE',
        anio: anioFuturo,
        corporacion: 'autoridad_configurada',
        estatutoEse: 'Acuerdo Junta Directiva 010 de 2025',
        autoridadEse: 'CONFIS territorial competente',
        actoDelegacionEse: 'Decreto territorial 020 de 2025',
      );
      await _crearRpFuturo(
        db: db,
        presupuesto: presupuesto,
        entidadId: 'ESE-01',
        usuarioJefe: 'USR-JEFE-ESE',
        sufijo: 'ESE',
        anio: anioFuturo,
        valorRP: _m(300),
        autorizacionId: autorizacionId,
      );

      final autorizacion = (await db.query(
        'autorizaciones_vigencias_futuras',
        where: 'id = ?',
        whereArgs: [autorizacionId],
      )).single;
      expect(autorizacion['estatuto_presupuestal_ese'], isNotEmpty);
      expect(autorizacion['autoridad_competente_ese'], isNotEmpty);
      expect(autorizacion['acto_delegacion_ese'], isNotEmpty);
    },
  );

  test(
    'bloquea falta/exceso de autorizacion, RBAC y pago de recibido irregular',
    () async {
      await expectLater(
        _crearRpFuturo(
          db: db,
          presupuesto: presupuesto,
          entidadId: 'MUN-01',
          usuarioJefe: 'USR-JEFE-MUN',
          sufijo: 'SIN-AUT',
          anio: anioFuturo,
          valorRP: _m(100),
        ),
        throwsA(isA<StateError>()),
      );
      final autorizacionId = await _registrarAutorizacion(
        service: vigencias,
        entidadId: 'MUN-01',
        usuarioId: 'USR-ALCALDE',
        anio: anioFuturo,
        corporacion: 'concejo',
        sufijo: 'BLOQ',
      );
      await expectLater(
        _crearRpFuturo(
          db: db,
          presupuesto: presupuesto,
          entidadId: 'MUN-01',
          usuarioJefe: 'USR-JEFE-MUN',
          sufijo: 'EXCESO',
          anio: anioFuturo,
          valorRP: _m(1001),
          autorizacionId: autorizacionId,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        _registrarAutorizacion(
          service: vigencias,
          entidadId: 'MUN-01',
          usuarioId: 'USR-TESORERO',
          anio: anioFuturo,
          corporacion: 'concejo',
          sufijo: 'RBAC',
        ),
        throwsA(isA<StateError>()),
      );

      final recepcionId = await vigencias.registrarRecepcionSatisfaccion(
        entidadId: 'MUN-01',
        usuarioId: 'USR-ORDENADOR',
        terceroId: 'TER-01',
        terceroNombre: 'Proveedor recibido',
        actaNumero: 'ACTA-REC-01',
        fechaRecepcion: DateTime.now(),
        descripcion: 'Servicios recibidos sin obligacion presupuestal',
        valor: _m(250),
        soporte: 'hash:soporte-recibido',
        contratoId: 'CT-BLOQ',
        motivoSinObligacion: 'Falla excepcional reportada para regularizacion.',
      );
      final recepcion = (await db.query(
        'recepciones_satisfaccion',
        where: 'id = ?',
        whereArgs: [recepcionId],
      )).single;
      expect(recepcion['bloquea_pago'], 1);
      expect(recepcion['asiento_contable_id'], isNotNull);
      expect(
        await db.query('incidentes_recibido_sin_obligacion'),
        hasLength(1),
      );

      await expectLater(
        presupuesto.programarPagoRecepcion(
          entidadId: 'MUN-01',
          usuarioId: 'USR-ORDENADOR',
          recepcionId: recepcionId,
          terceroId: 'TER-01',
          terceroNombre: 'Proveedor recibido',
          bancoDestino: 'Banco',
          cuentaDestino: '123',
          tipoCuenta: 'corriente',
          valorPago: _m(250),
          funcionarioProgramo: 'Ordenador',
          tipoPago: TipoPago.transferenciaBancaria,
          mesPAC: 1,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.query('obligaciones'), isEmpty);
    },
  );
}

Future<void> _crearEntidad(Database db, String id, String tipo, String nombre) {
  return db.insert('entidades_territoriales', {
    'id': id,
    'nit': 'NIT-$id',
    'razon_social': nombre,
    'tipo_entidad': tipo,
    'fecha_creacion': DateTime.now().toIso8601String(),
    'plan_cuentas_cgc': 'CGN_2015',
    'configuracion_normativa': '{}',
  });
}

Future<void> _crearFuncionario(
  Database db,
  String entidadId,
  String usuarioId,
  String cargo,
) {
  return db.insert('funcionarios_entidad', {
    'id': '$entidadId-$cargo',
    'entidad_id': entidadId,
    'usuario_id': usuarioId,
    'cargo_clave': cargo,
    'nombre_completo': cargo,
    'identificacion': 'ID-$usuarioId',
    'telefono': '3000000000',
    'email': '$usuarioId@example.test',
    'direccion': 'Sede',
  });
}

Future<void> _crearTercero(Database db, String entidadId, String id) {
  return db.insert('terceros_sector_publico', {
    'id': id,
    'entidad_id': entidadId,
    'tipo_identificacion': 'NIT',
    'numero_identificacion': 'NIT-$id',
    'razon_social': 'Proveedor $id',
    'tipo_tercero': 'juridica',
    'fecha_creacion': DateTime.now().toIso8601String(),
  });
}

Future<String> _crearRpFuturo({
  required Database db,
  required PresupuestoService presupuesto,
  required String entidadId,
  required String usuarioJefe,
  required String sufijo,
  required int anio,
  required MoneyValue valorRP,
  String? autorizacionId,
}) async {
  final apropiacion = await presupuesto.crearApropiacion(
    entidadId: entidadId,
    usuarioId: usuarioJefe,
    vigencia: anio.toString(),
    codigoRubro: 'RUBRO-$sufijo',
    nombreRubro: 'Proyecto plurianual $sufijo',
    valorApropiado: _m(2000),
    fuenteFinanciacion: 'Recursos propios',
    sector: 'Administracion',
    programa: 'Inversion',
    subprograma: 'Infraestructura',
    proyecto: 'Proyecto $sufijo',
    actividad: 'Ejecucion',
    objetoGasto: 'Servicios',
    fechaAprobacionConcejo: DateTime.now(),
    actoAdministrativo: 'ACTO-APR-$sufijo',
  );
  final cdp = await presupuesto.expedirCDP(
    entidadId: entidadId,
    usuarioId: usuarioJefe,
    apropiacionId: apropiacion.id,
    valorCDP: valorRP,
    funcionarioExpedidor: 'Jefe de Presupuesto',
    funcionarioSolicitante: 'Gobierno local',
    objetoGasto: 'Proyecto plurianual',
    contratoNumero: null,
  );
  await db.insert('contratos', {
    'id': 'CT-$sufijo',
    'entidad_id': entidadId,
    'numero_contrato': 'CONTRATO-$sufijo',
    'estado': 'firmado',
    'cdp_id': cdp.id,
    'rp_id': null,
  });
  final rp = await presupuesto.expedirRP(
    entidadId: entidadId,
    usuarioId: usuarioJefe,
    cdpId: cdp.id,
    contratoId: 'CT-$sufijo',
    contratoNumero: 'CONTRATO-$sufijo',
    valorRP: valorRP,
    funcionarioExpedidor: 'Jefe de Presupuesto',
    funcionarioSolicitante: 'Gobierno local',
    objetoGasto: 'Proyecto plurianual',
    autorizacionVigenciaFuturaId: autorizacionId,
  );
  return rp.id;
}

Future<String> _registrarAutorizacion({
  required VigenciasFuturasService service,
  required String entidadId,
  required String usuarioId,
  required int anio,
  required String corporacion,
  String sufijo = '',
  String? estatutoEse,
  String? autoridadEse,
  String? actoDelegacionEse,
}) {
  return service.registrarAutorizacion(
    entidadId: entidadId,
    usuarioId: usuarioId,
    tipo: 'ordinaria',
    regimenPresupuestal: 'Estatuto territorial vigente',
    causalLegal: 'Ley 819 de 2003, articulo 12',
    objeto: 'Proyecto plurianual $sufijo',
    planDesarrolloReferencia: 'PDT-2024-2027',
    mfmpReferencia: 'MFMP-2026',
    anioInicio: anio,
    anioFin: anio,
    montoTotal: _m(1000),
    apropiacionVigenciaActual: _m(200),
    distribucion: {anio: _m(1000)},
    confisAutoridad: 'CONFIS territorial',
    confisActoNumero: 'CONFIS-$entidadId-$sufijo',
    confisActoFecha: DateTime.now(),
    confisSoporte: 'hash:confis-$entidadId-$sufijo',
    corporacionTipo: corporacion,
    autorizacionAutoridad: corporacion,
    autorizacionActoNumero: 'ACTO-$entidadId-$sufijo',
    autorizacionActoFecha: DateTime.now(),
    autorizacionSoporte: 'hash:acto-$entidadId-$sufijo',
    estatutoPresupuestalEse: estatutoEse,
    autoridadCompetenteEse: autoridadEse,
    actoDelegacionEse: actoDelegacionEse,
  );
}

MoneyValue _m(num value) => publicMoneyFromMajor(value.toString());
