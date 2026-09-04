import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/activos/database/schema_activos.dart';
import 'package:merka_erp/sector_publico/activos/services/acta_responsabilidad_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuditoriaService auditoriaService;
  late ActaResponsabilidadService service;

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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS empleados_sp (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        numero_identificacion TEXT NOT NULL,
        dependencia TEXT NOT NULL
      )
    ''');

    await SchemaActivos.crearTablas(db);

    await db.insert('entidades_territoriales', {
      'id': 'entidad-001',
      'nit': '800123456-1',
      'razon_social': 'Municipio Test',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });

    await db.insert('activos_estado', {
      'id': 'activo-001',
      'entidad_id': 'entidad-001',
      'numero_inventario': 'INV-2026-001',
      'nombre_activo': 'Camioneta Computadora',
      'tipo_activo': 'maquinaria',
      'marca': 'Toyota',
      'modelo': '2025',
      'serie': 'SER12345',
      'valor_adquisicion': 120000000.0,
      'valor_libros': 120000000.0,
      'valor_neto': 120000000.0,
      'fecha_adquisicion': DateTime.now().toIso8601String(),
      'fecha_puesta_en_marcha': DateTime.now().toIso8601String(),
      'vida_util_anios': 10,
      'valor_residual': 10000000.0,
      'depreciacion_acumulada': 0.0,
      'estado': 'excelente',
    });

    await db.insert('empleados_sp', {
      'id': 'emp-001',
      'entidad_id': 'entidad-001',
      'nombre_completo': 'Carlos Restrepo',
      'numero_identificacion': '79998877',
      'dependencia': 'Secretaría de Obras Públicas',
    });

    auditoriaService = AuditoriaService(db);
    service = ActaResponsabilidadService(
      db: db,
      auditoriaService: auditoriaService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'Generar, firmar, entregar y exportar acta de responsabilidad',
    () async {
      final pendiente = await service.generarActaPendiente(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        activoId: 'activo-001',
        funcionarioId: 'emp-001',
        funcionarioNombre: 'Carlos Restrepo',
        funcionarioIdentificacion: '79998877',
        dependencia: 'SecretarÃ­a de Obras PÃºblicas',
        ubicacionFisica: 'AlmacÃ©n Central - Bodega 2',
      );

      expect(pendiente.estadoActa.name, equals('pendienteFirma'));

      final firmada = await service.firmarYEntregarActa(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        actaId: pendiente.id,
        firmadoPorFuncionario: 'Carlos Restrepo',
        firmadoPorAlmacen: 'Almacen General',
      );

      expect(firmada.numeroActa, contains('ACTA-'));
      expect(firmada.estadoActa.name, equals('activa'));
      expect(firmada.fechaEntrega, isNotNull);
      expect(firmada.hashActa, isNotNull);
      expect(firmada.hashActa, hasLength(64));

      final activo = await db.query(
        'activos_estado',
        where: 'id = ?',
        whereArgs: ['activo-001'],
      );
      expect(activo.single['responsable'], equals('Carlos Restrepo'));
      expect(activo.single['ubicacion'], equals('AlmacÃ©n Central - Bodega 2'));

      final plano = await service.exportarActaAPlano(firmada.id);
      expect(plano, contains('ACTA_RESPONSABILIDAD_HEADER'));
      expect(plano, contains('Carlos Restrepo'));
      expect(plano, contains('FIRMA_FUNCIONARIO|Carlos Restrepo'));
      expect(plano, contains('FIRMA_ALMACEN|Almacen General'));
      expect(plano, contains('HASH_ACTA|${firmada.hashActa}'));
    },
  );

  test(
    'Asignar Acta de Responsabilidad conserva API y permite devolver',
    () async {
      final acta = await service.asignarResponsabilidad(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        activoId: 'activo-001',
        funcionarioId: 'emp-001',
        funcionarioNombre: 'Carlos Restrepo',
        funcionarioIdentificacion: '79998877',
        dependencia: 'Secretaría de Obras Públicas',
        ubicacionFisica: 'Almacén Central - Bodega 2',
      );

      expect(acta.numeroActa, contains('ACTA-'));
      expect(acta.funcionarioNombre, equals('Carlos Restrepo'));
      expect(acta.estadoActa.name, equals('activa'));

      final plano = await service.exportarActaAPlano(acta.id);
      expect(plano, contains('ACTA_RESPONSABILIDAD_HEADER'));
      expect(plano, contains('Carlos Restrepo'));

      final devuelta = await service.devolverResponsabilidad(
        entidadId: 'entidad-001',
        usuarioId: 'usr-001',
        actaId: acta.id,
        observaciones: 'Reintegro al almacen',
      );

      expect(devuelta.estadoActa.name, equals('devuelta'));
      final activo = await db.query(
        'activos_estado',
        where: 'id = ?',
        whereArgs: ['activo-001'],
      );
      expect(activo.single['responsable'], isNull);
      expect(activo.single['ubicacion'], isNull);
    },
  );
}
