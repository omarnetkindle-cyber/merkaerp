import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/rentas/database/schema_rentas.dart';
import 'package:merka_erp/sector_publico/rentas/services/predial_service.dart';
import 'package:merka_erp/sector_publico/rentas/services/ica_service.dart';
import 'package:merka_erp/sector_publico/rentas/services/intereses_moratorios_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuditoriaService auditoriaService;
  late InteresesMoratoriosService interesesService;
  late PredialService predialService;
  late ICAService icaService;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS entidades_territoriales (
        id TEXT PRIMARY KEY,
        nit TEXT NOT NULL,
        razon_social TEXT NOT NULL,
        tipo_entidad TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        plan_cuentas_cgc TEXT NOT NULL,
        configuracion_normativa TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auditoria_registros (
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
        observaciones TEXT,
        archivado INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await SchemaRentas.crearTablas(db);

    await db.insert('entidades_territoriales', {
      'id': 'entidad-001',
      'nit': '800123456-1',
      'razon_social': 'Municipio Test',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });

    await db.insert('predios', {
      'id': 'predio-001',
      'entidad_id': 'entidad-001',
      'numero_predial': '010100010001000',
      'numero_matricula': '50N-123456',
      'direccion': 'Calle 10 # 5-20',
      'barrio': 'Centro',
      'municipio': 'Test',
      'departamento': 'Test',
      'area': 150.0,
      'avaluo_catastral': 20000000000,
      'avaluo_anterior': 19000000000,
      'uso_suelo': 'residencial',
      'estrato': 'tres',
      'zona': 'urbana',
      'propietario_id': 'prop-001',
      'propietario_nombre': 'Ana Gómez',
      'propietario_identificacion': '52111222',
      'fecha_registro': DateTime.now().toIso8601String(),
      'activo': 1,
      'exento': 0,
    });

    auditoriaService = AuditoriaService(db);
    interesesService = InteresesMoratoriosService();
    predialService = PredialService(
      db: db,
      interesesService: interesesService,
      auditoriaService: auditoriaService,
    );
    icaService = ICAService(db: db, auditoriaService: auditoriaService);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'Exportación de Liquidación Predial y Declaración ICA a formato plano',
    () async {
      final liqPredial = await predialService.liquidarPredio(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        vigencia: '2026',
        predioId: 'predio-001',
        ipcAnual: 0.05,
      );

      final planoPredial = await predialService
          .exportarDeclaracionPredialAPlano(liqPredial.id);
      expect(planoPredial, contains('PREDIAL_HEADER'));
      expect(planoPredial, contains('010100010001000'));

      final contrib = await icaService.registrarContribuyenteCenso(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        nit: '900999888-1',
        razonSocial: 'Comercializadora Test SAS',
        direccion: 'Carrera 7 # 12-34',
        telefono: '3001234567',
        tipoActividad: TipoActividadICA.comercial,
        actividadEconomica: '4711 - Comercio al por menor',
        ingresosAnualesEstimados: publicMoneyFromMajor('500000000'),
      );

      final decICA = await icaService.generarDeclaracionICA(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        contribuyenteId: contrib['contribuyente_id'] as String,
        periodo: '2026-01',
        periodoDeclaracion: PeriodoDeclaracionICA.bimestral,
        ingresosGravables: publicMoneyFromMajor('100000000'),
        ingresosNoGravables: publicMoneyZero(),
        ingresosExentos: publicMoneyZero(),
      );
      await icaService.registrarReteICA(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        nitRetenedor: '800777666-2',
        nitRetenido: '900999888-1',
        periodo: '2026-01',
        valorRetenido: publicMoneyFromMajor('120000'),
        numeroFactura: 'FE-ICA-001',
        fechaFactura: DateTime(2026, 1, 15),
      );

      final planoICA = await icaService.exportarDeclaracionICAAPlano(
        decICA['declaracion_id'] as String,
      );
      expect(planoICA, contains('ICA_DECLARATION_HEADER'));
      expect(planoICA, contains('2026-01'));

      final xmlICA = await icaService.exportarDeclaracionICAXml(
        decICA['declaracion_id'] as String,
      );
      expect(xmlICA, contains('<DeclaracionICA'));
      expect(xmlICA, contains('<Nit>900999888-1</Nit>'));
      expect(xmlICA, contains('<BaseGravable>100000000.00</BaseGravable>'));
      expect(xmlICA, contains('<ImpuestoICA>800000.00</ImpuestoICA>'));
      expect(xmlICA, contains('<ReteICA>120000.00</ReteICA>'));

      final pdfBytes = await icaService.exportarDeclaracionICAPdfBytes(
        decICA['declaracion_id'] as String,
      );
      expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');
      expect(pdfBytes.length, greaterThan(1000));
    },
  );
}
