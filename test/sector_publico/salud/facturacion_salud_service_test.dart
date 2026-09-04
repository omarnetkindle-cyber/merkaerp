import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/salud/database/schema_salud.dart';
import 'package:merka_erp/sector_publico/salud/services/facturacion_salud_service.dart';
import 'package:merka_erp/sector_publico/salud/models/contrato_eps.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuditoriaService auditoriaService;
  late FacturacionSaludService service;

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

    await SchemaSalud.crearTablas(db);

    await db.insert('entidades_territoriales', {
      'id': 'entidad-001',
      'nit': '800123456-1',
      'razon_social': 'ESE Hospital Municipal',
      'tipo_entidad': 'ese_hospital',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });

    auditoriaService = AuditoriaService(db);
    service = FacturacionSaludService(
      db: db,
      auditoriaService: auditoriaService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'Registro de Contrato EPS/ADRES, Expedición de Factura de Salud y Exportación Plano',
    () async {
      final contrato = await service.registrarContratoEPS(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        numeroContrato: 'CNT-2026-001',
        epsAdresNombre: 'Nueva EPS S.A.',
        epsAdresNit: '900156877-1',
        regimen: RegimenSalud.subsidiado,
        montoContrato: publicMoneyFromMajor('500000000'),
        fechaInicio: DateTime.now(),
        fechaFin: DateTime.now().add(const Duration(days: 365)),
      );

      expect(contrato.numeroContrato, equals('CNT-2026-001'));

      final factura = await service.generarFacturaSalud(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        contratoId: contrato.id,
        numeroFactura: 'FAC-2026-001',
        periodo: '2026-03',
        montoTotal: publicMoneyFromMajor('45000000'),
      );

      expect(factura.numeroFactura, equals('FAC-2026-001'));

      final plano = await service.exportarFacturaAPlano(factura.id);
      expect(plano, contains('FACTURA_SALUD_HEADER'));
      expect(plano, contains('FAC-2026-001'));
    },
  );
}
