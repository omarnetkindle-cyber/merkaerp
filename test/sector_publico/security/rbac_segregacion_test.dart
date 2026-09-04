import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/security/roles_permisos_service.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuditoriaService auditoriaService;
  late PresupuestoService presupuestoService;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Crear esquemas
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);

    auditoriaService = AuditoriaService(db);
    presupuestoService = PresupuestoService(
      db: db,
      auditoriaService: auditoriaService,
    );
    // Crear Entidad Territorial
    await db.insert('entidades_territoriales', {
      'id': 'ENT-001',
      'nit': '899999111-1',
      'razon_social': 'Alcaldía de Ejemplo',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });

    // Vincular Funcionarios con usuario_id y cargo_clave
    // 1. Tesorero
    await db.insert('funcionarios_entidad', {
      'id': 'FUNC-TESORERO',
      'entidad_id': 'ENT-001',
      'usuario_id': 'USR-TESORERO-01',
      'cargo_clave': 'tesorero',
      'nombre_completo': 'Tesorero General',
      'identificacion': '11111111',
      'telefono': '3000000000',
      'email': 'tesorero@municipio.gov.co',
      'direccion': 'Alcaldía Municipal',
    });

    // 2. Contador
    await db.insert('funcionarios_entidad', {
      'id': 'FUNC-CONTADOR',
      'entidad_id': 'ENT-001',
      'usuario_id': 'USR-CONTADOR-01',
      'cargo_clave': 'contador',
      'nombre_completo': 'Contador General',
      'identificacion': '22222222',
      'telefono': '3000000001',
      'email': 'contador@municipio.gov.co',
      'direccion': 'Alcaldía Municipal',
    });

    // 3. Jefe de Control Interno / Auditor
    await db.insert('funcionarios_entidad', {
      'id': 'FUNC-AUDITOR',
      'entidad_id': 'ENT-001',
      'usuario_id': 'USR-AUDITOR-01',
      'cargo_clave': 'jefeControlInterno',
      'nombre_completo': 'Jefe Control Interno',
      'identificacion': '44444444',
      'telefono': '3000000003',
      'email': 'auditor@municipio.gov.co',
      'direccion': 'Alcaldía Municipal',
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('Segregación de Funciones y Reglas Fail-Closed RBAC por Módulo', () {
    test(
      '1. Tesoreria/Presupuesto: Un Tesorero NO puede aprobar su propio pago (Segregación de Funciones)',
      () async {
        final rolTesorero =
            await RolesPermisosService.obtenerRolUsuarioEnEntidad(
              db: db,
              entidadId: 'ENT-001',
              usuarioId: 'USR-TESORERO-01',
            );
        expect(rolTesorero, equals(RolSectorPublico.tesorero));

        final esValido = RolesPermisosService.validarSegregacionFunciones(
          rolQuienEjecuta: RolSectorPublico.tesorero,
          rolQuienAprobo: RolSectorPublico.tesorero,
          accion: Permiso.aprobarPago,
        );

        expect(esValido, isFalse);
      },
    );

    test(
      '2. Presupuesto/Tesorería: Un Contador NO puede ejecutar pagos (Negación Explícita)',
      () async {
        final tienePermiso = RolesPermisosService.tienePermiso(
          RolSectorPublico.contador,
          Permiso.ejecutarPago,
        );

        expect(tienePermiso, isFalse);
      },
    );

    test(
      '3. Auditoría: El Jefe de Control Interno tiene acceso SOLO LECTURA y NO puede expedir CDP ni reversar asientos',
      () async {
        final tienePermisoCDP = RolesPermisosService.tienePermiso(
          RolSectorPublico.jefeControlInterno,
          Permiso.expedirCDP,
        );
        final tienePermisoReversa = RolesPermisosService.tienePermiso(
          RolSectorPublico.jefeControlInterno,
          Permiso.reversarAsiento,
        );

        expect(tienePermisoCDP, isFalse);
        expect(tienePermisoReversa, isFalse);
      },
    );

    test(
      '4. Seguridad Fail-Closed: Un usuario SIN funcionario vinculado es bloqueado inmediatamente',
      () async {
        final usuarioDesconocidoId = 'USR-DESCONOCIDO-999';

        final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
          db: db,
          entidadId: 'ENT-001',
          usuarioId: usuarioDesconocidoId,
        );

        expect(rol, isNull);

        expect(
          () async => await presupuestoService.expedirCDP(
            entidadId: 'ENT-001',
            usuarioId: usuarioDesconocidoId,
            apropiacionId: 'APROP-001',
            valorCDP: publicMoneyFromMajor('1000000'),
            funcionarioExpedidor: 'Sin Rol',
            funcionarioSolicitante: 'Sin Rol',
            objetoGasto: 'Intento no autorizado',
            contratoNumero: null,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'mensaje',
              contains('Acceso denegado'),
            ),
          ),
        );
      },
    );
  });
}
