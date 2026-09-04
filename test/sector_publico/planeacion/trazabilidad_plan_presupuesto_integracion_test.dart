import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/contratacion/database/schema_contratacion.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/planeacion/database/schema_planeacion.dart';
import 'package:merka_erp/sector_publico/planeacion/services/trazabilidad_plan_presupuesto_service.dart';
import 'package:merka_erp/sector_publico/presupuesto/models/apropiacion.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const entidadId = 'ENT-PLAN-001';
  const usuarioPresupuesto = 'USR-PRESUPUESTO';
  const proyectoId = 'PROY-BPIN-001';
  const metaCodigo = 'META-PDT-01';

  late Database db;
  late PresupuestoService presupuesto;
  late TrazabilidadPlanPresupuestoService trazabilidad;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaContratacion.crearTablas(db);
    await SchemaPlaneacion.crearTablas(db);

    presupuesto = PresupuestoService(db: db);
    trazabilidad = TrazabilidadPlanPresupuestoService(db);

    await db.insert('entidades_territoriales', {
      'id': entidadId,
      'nit': '901999001-1',
      'razon_social': 'Municipio Planificado',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime(2026, 1, 1).toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    await db.insert('funcionarios_entidad', {
      'id': 'FUNC-PRESUPUESTO',
      'entidad_id': entidadId,
      'usuario_id': usuarioPresupuesto,
      'cargo_clave': 'jefePresupuesto',
      'nombre_completo': 'Jefe de Presupuesto',
      'identificacion': '10000001',
      'telefono': '3000000001',
      'email': 'presupuesto@plan.gov.co',
      'direccion': 'Palacio Municipal',
    });
  });

  tearDown(() async {
    await db.close();
  });

  Future<Apropiacion> crearApropiacion(PresupuestoService service) {
    return service.crearApropiacion(
      entidadId: entidadId,
      usuarioId: usuarioPresupuesto,
      vigencia: '2026',
      codigoRubro: '231010101',
      nombreRubro: 'Infraestructura educativa',
      valorApropiado: publicMoneyFromMajor('100000000'),
      fuenteFinanciacion: 'SGP Educacion',
      sector: 'Educacion',
      programa: 'Calidad educativa',
      subprograma: 'Infraestructura',
      proyecto: 'Aulas rurales',
      actividad: 'Construccion',
      objetoGasto: 'Obra publica educativa',
      fechaAprobacionConcejo: DateTime(2026, 1, 10),
      actoAdministrativo: 'ACUERDO-001-2026',
    );
  }

  Future<void> crearProyectoMGA() {
    return db.insert('proyectos_mga', {
      'id': proyectoId,
      'entidad_id': entidadId,
      'codigo_bpin': '202600000001',
      'nombre_proyecto': 'Mejoramiento de infraestructura educativa rural',
      'tipo_proyecto': 'inversion',
      'sector': 'Educacion',
      'programa': 'Calidad educativa',
      'subprograma': 'Infraestructura',
      'valor_total': 10000000000,
      'valor_ejecutado': 0,
      'saldo_por_ejecutar': 10000000000,
      'fecha_inicio': DateTime(2026, 1, 1).toIso8601String(),
      'fecha_fin': DateTime(2026, 12, 31).toIso8601String(),
      'responsable': 'Jefe de Planeacion',
      'dependencia': 'Secretaria de Planeacion',
      'estado': 'viabilizado',
      'codigo_cdp': null,
      'codigo_rp': null,
      'observaciones': null,
    });
  }

  Future<void> crearContratoFirmado(String cdpId, String numeroCdp) async {
    await db.insert('procesos_contratacion', {
      'id': 'PROCESO-PLAN-001',
      'entidad_id': entidadId,
      'numero_proceso': 'PC-PLAN-001',
      'objeto_contrato': 'Construccion de aulas rurales',
      'modalidad': 'licitacionPublica',
      'valor_estimado': 5000000000,
      'tipo_contrato': 'obra',
      'dependencia_solicitante': 'Secretaria de Educacion',
      'responsable_proceso': 'Responsable contractual',
      'fecha_inicio': DateTime(2026, 3, 1).toIso8601String(),
      'fecha_publicacion': DateTime(2026, 3, 2).toIso8601String(),
      'fecha_cierre': DateTime(2026, 3, 30).toIso8601String(),
      'estado': 'adjudicado',
      'cdp_id': cdpId,
      'numero_cdp': numeroCdp,
      'secop_id': null,
      'observaciones': null,
    });
    await db.insert('contratos', {
      'id': 'CONTRATO-PLAN-001',
      'entidad_id': entidadId,
      'numero_contrato': 'CT-PLAN-001',
      'proceso_id': 'PROCESO-PLAN-001',
      'numero_proceso': 'PC-PLAN-001',
      'objeto_contrato': 'Construccion de aulas rurales',
      'tipo_contrato': 'obra',
      'valor_contrato': 5000000000,
      'contratista_id': 'CONTRATISTA-001',
      'contratista_nombre': 'Constructora Rural S.A.S.',
      'contratista_identificacion': '900111222-3',
      'cdp_id': cdpId,
      'numero_cdp': numeroCdp,
      'rp_id': null,
      'numero_rp': null,
      'fecha_firma': DateTime(2026, 4, 1).toIso8601String(),
      'fecha_inicio_ejecucion': DateTime(2026, 4, 5).toIso8601String(),
      'fecha_fin_ejecucion': DateTime(2026, 12, 20).toIso8601String(),
      'duracion_dias': 260,
      'estado': 'firmado',
      'fecha_legalizacion': null,
      'fecha_terminacion': null,
      'fecha_liquidacion': null,
      'supervisor_id': null,
      'supervisor_nombre': null,
      'interventor_id': null,
      'interventor_nombre': null,
      'observaciones': null,
    });
  }

  test('meta MGA vinculada a rubro queda trazada en CDP y RP', () async {
    final apropiacion = await crearApropiacion(presupuesto);
    await crearProyectoMGA();

    await trazabilidad.vincularRubroAMeta(
      id: 'VINCULO-001',
      entidadId: entidadId,
      proyectoId: proyectoId,
      apropiacionId: apropiacion.id,
      metaCodigo: metaCodigo,
      metaDescripcion: 'Construir 10 aulas rurales',
      avanceFisicoPorcentaje: 35,
      fechaReporte: DateTime(2026, 3, 1),
    );

    final sugeridas = await trazabilidad.sugerirMetasParaApropiacion(
      entidadId: entidadId,
      apropiacionId: apropiacion.id,
    );
    expect(sugeridas, hasLength(1));
    expect(sugeridas.single.codigoBPIN, '202600000001');
    expect(sugeridas.single.codigoRubro, '231010101');
    expect(sugeridas.single.metaCodigo, metaCodigo);

    final cdp = await presupuesto.expedirCDP(
      entidadId: entidadId,
      usuarioId: usuarioPresupuesto,
      apropiacionId: apropiacion.id,
      valorCDP: publicMoneyFromMajor('50000000'),
      funcionarioExpedidor: 'Jefe de Presupuesto',
      funcionarioSolicitante: 'Secretaria de Educacion',
      objetoGasto: 'Construccion de aulas rurales',
      contratoNumero: null,
      proyectoId: proyectoId,
      metaCodigo: metaCodigo,
    );

    final cdpTrace = await db.query('cdp_meta_trazabilidad');
    expect(cdpTrace, hasLength(1));
    expect(cdpTrace.single['cdp_id'], cdp.id);
    expect(cdpTrace.single['codigo_bpin'], '202600000001');
    expect(cdpTrace.single['meta_codigo'], metaCodigo);

    final numeroCdp =
        (await db.query(
              'cdps',
              columns: ['numero_cdp'],
              where: 'id = ?',
              whereArgs: [cdp.id],
            )).single['numero_cdp']
            as String;
    await crearContratoFirmado(cdp.id, numeroCdp);

    final rp = await presupuesto.expedirRP(
      entidadId: entidadId,
      usuarioId: usuarioPresupuesto,
      cdpId: cdp.id,
      contratoId: 'CONTRATO-PLAN-001',
      contratoNumero: 'CT-PLAN-001',
      valorRP: publicMoneyFromMajor('40000000'),
      funcionarioExpedidor: 'Jefe de Presupuesto',
      funcionarioSolicitante: 'Secretaria de Educacion',
      objetoGasto: 'Construccion de aulas rurales',
    );

    final rpTrace = await db.query('rp_meta_trazabilidad');
    expect(rpTrace, hasLength(1));
    expect(rpTrace.single['rp_id'], rp.id);
    expect(rpTrace.single['cdp_id'], cdp.id);
    expect(rpTrace.single['codigo_bpin'], '202600000001');
    expect(rpTrace.single['meta_codigo'], metaCodigo);
  });

  test(
    'CDP con meta no vinculada al rubro se bloquea antes de insertar',
    () async {
      final apropiacion = await crearApropiacion(presupuesto);
      await crearProyectoMGA();

      await expectLater(
        presupuesto.expedirCDP(
          entidadId: entidadId,
          usuarioId: usuarioPresupuesto,
          apropiacionId: apropiacion.id,
          valorCDP: publicMoneyFromMajor('10000000'),
          funcionarioExpedidor: 'Jefe de Presupuesto',
          funcionarioSolicitante: 'Secretaria de Educacion',
          objetoGasto: 'Construccion de aulas rurales',
          contratoNumero: null,
          proyectoId: proyectoId,
          metaCodigo: metaCodigo,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await db.query('cdps'), isEmpty);
      expect(await db.query('cdp_meta_trazabilidad'), isEmpty);
    },
  );
}
