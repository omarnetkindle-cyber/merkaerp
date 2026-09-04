import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/app_session.dart';
import 'package:merka_erp/core/security/action_permission.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DatabaseHelper.setTestDatabase(db);
    AppSession.cerrar();

    // Crear esquema de tablas comerciales
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_config (
        clave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS empresas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nit TEXT NOT NULL,
        razon_social TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE companies (
        id INTEGER PRIMARY KEY,
        currency TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_currencies (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        decimal_places INTEGER NOT NULL,
        is_default INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ventas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        cliente TEXT,
        total INTEGER NOT NULL,
        impuesto_total INTEGER NOT NULL DEFAULT 0,
        retefuente INTEGER NOT NULL DEFAULT 0,
        reteiva INTEGER NOT NULL DEFAULT 0,
        reteica INTEGER NOT NULL DEFAULT 0,
        estado TEXT DEFAULT 'emitida',
        fecha TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS compras (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        proveedor TEXT,
        total INTEGER NOT NULL,
        impuesto_total INTEGER NOT NULL DEFAULT 0,
        retefuente INTEGER NOT NULL DEFAULT 0,
        estado TEXT DEFAULT 'completada',
        fecha TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS nomina_liquidaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        neto_pagar INTEGER NOT NULL,
        estado TEXT DEFAULT 'activo',
        fecha TEXT NOT NULL
      )
    ''');

    // Datos semilla de 2 empresas distintas
    await db.insert('app_config', {'clave': 'company_active_id', 'valor': '1'});

    await db.insert('empresas', {
      'id': 1,
      'nit': '900111111-1',
      'razon_social': 'Empresa A',
    });
    await db.insert('empresas', {
      'id': 2,
      'nit': '900222222-2',
      'razon_social': 'Empresa B',
    });
    await db.insert('companies', {'id': 1, 'currency': 'COP'});
    await db.insert('companies', {'id': 2, 'currency': 'COP'});
    await db.insert('app_currencies', {
      'code': 'COP',
      'name': 'Peso colombiano',
      'symbol': r'$',
      'decimal_places': 2,
      'is_default': 1,
    });

    final fechaPrueba = '2026-07-15T10:00:00.000';

    // Empresa A (company_id = 1) -> Ventas: 100,000, Compras: 40,000
    await db.insert('ventas', {
      'company_id': 1,
      'cliente': 'Cliente A',
      'total': 10000000,
      'impuesto_total': 1900000,
      'retefuente': 250000,
      'reteiva': 285000,
      'reteica': 110400,
      'estado': 'emitida',
      'fecha': fechaPrueba,
    });

    await db.insert('compras', {
      'company_id': 1,
      'proveedor': 'Proveedor A',
      'total': 4000000,
      'impuesto_total': 760000,
      'retefuente': 100000,
      'estado': 'completada',
      'fecha': fechaPrueba,
    });

    // Empresa B (company_id = 2) -> Ventas: 500,000, Compras: 200,000
    await db.insert('ventas', {
      'company_id': 2,
      'cliente': 'Cliente B',
      'total': 50000000,
      'impuesto_total': 9500000,
      'retefuente': 1250000,
      'reteiva': 1425000,
      'reteica': 552000,
      'estado': 'emitida',
      'fecha': fechaPrueba,
    });

    await db.insert('compras', {
      'company_id': 2,
      'proveedor': 'Proveedor B',
      'total': 20000000,
      'impuesto_total': 3800000,
      'retefuente': 500000,
      'estado': 'completada',
      'fecha': fechaPrueba,
    });
  });

  tearDown(() async {
    await db.close();
  });

  group('Seguridad Comercial & Aislamiento Multi-Empresa', () {
    test(
      '1. Consultas tributarias aisladas por company_id no mezclan cifras entre empresas',
      () async {
        // Activar Empresa A (company_id = 1)
        await db.update(
          'app_config',
          {'valor': '1'},
          where: 'clave = ?',
          whereArgs: ['company_active_id'],
        );

        final fiscalA = await DatabaseHelper.instance.obtenerReporteFiscal(
          anio: 2026,
          mes: 7,
        );
        expect(fiscalA['ventas']?.minorUnits, equals(10000000));
        expect(fiscalA['compras']?.minorUnits, equals(4000000));

        final icAA = await DatabaseHelper.instance.obtenerBorradorICA(
          anio: 2026,
          mesInicio: 7,
          mesFin: 7,
        );
        expect(
          (icAA['reteica_practicada'] as dynamic).minorUnits,
          equals(110400),
        );

        // Activar Empresa B (company_id = 2)
        await db.update(
          'app_config',
          {'valor': '2'},
          where: 'clave = ?',
          whereArgs: ['company_active_id'],
        );

        final fiscalB = await DatabaseHelper.instance.obtenerReporteFiscal(
          anio: 2026,
          mes: 7,
        );
        expect(fiscalB['ventas']?.minorUnits, equals(50000000));
        expect(fiscalB['compras']?.minorUnits, equals(20000000));

        final icaB = await DatabaseHelper.instance.obtenerBorradorICA(
          anio: 2026,
          mesInicio: 7,
          mesFin: 7,
        );
        expect(
          (icaB['reteica_practicada'] as dynamic).minorUnits,
          equals(552000),
        );
      },
    );

    test(
      '2. Sesión nula/sin autenticar responde FAIL-CLOSED (bloquea view y export)',
      () {
        AppSession.cerrar();

        expect(AppSession.rol, isNull);
        expect(AppSession.puedeAbrir('ventas'), isFalse);
        expect(AppSession.puedeAbrir('reportes'), isFalse);

        expect(
          AppSession.puedeEjecutarAccion('sales', AppAction.view),
          isFalse,
        );
        expect(
          AppSession.puedeEjecutarAccion('sales', AppAction.export),
          isFalse,
        );
        expect(
          AppSession.puedeEjecutarAccion('reports', AppAction.view),
          isFalse,
        );
        expect(
          AppSession.puedeEjecutarAccion('reports', AppAction.export),
          isFalse,
        );
      },
    );

    test(
      '3. Usuario autenticado con rol consulta SÍ puede ver pero NO crear/editar',
      () {
        AppSession.iniciar({
          'id': 50,
          'usuario': 'lector',
          'nombre': 'Lector de Pruebas',
          'rol': 'consulta',
        });

        expect(AppSession.rol, equals('consulta'));
        expect(AppSession.puedeAbrir('reportes'), isTrue);
        expect(
          AppSession.puedeEjecutarAccion('reports', AppAction.view),
          isTrue,
        );
        expect(
          AppSession.puedeEjecutarAccion('sales', AppAction.create),
          isFalse,
        );
        expect(
          AppSession.puedeEjecutarAccion('sales', AppAction.cancel),
          isFalse,
        );
      },
    );

    test(
      '4. Rol explícito "sistema" permite ejecución de procesos internos/batch',
      () {
        expect(
          PermissionService.instance.can(
            role: 'sistema',
            moduleId: 'sales',
            action: AppAction.create,
          ),
          isTrue,
        );
        expect(
          PermissionService.instance.can(
            role: 'sistema',
            moduleId: 'purchases',
            action: AppAction.post,
          ),
          isTrue,
        );
      },
    );

    test(
      '5. El rol "sistema" está protegido contra asignación a usuarios humanos (Fail-Closed)',
      () async {
        expect(
          () => DatabaseHelper.instance.guardarUsuario(
            nombre: 'Hacker',
            usuario: 'hacker',
            rol: 'sistema',
          ),
          throwsA(isA<ArgumentError>()),
        );

        AppSession.iniciar({
          'id': 999,
          'usuario': 'backdoor',
          'nombre': 'Inyección Maliciosa',
          'rol': 'sistema',
        });

        expect(AppSession.rol, isNull);
        expect(AppSession.puedeAbrir('ventas'), isFalse);
        expect(
          AppSession.puedeEjecutarAccion('sales', AppAction.create),
          isFalse,
        );
        expect(
          AppSession.puedeEjecutarAccion('sales', AppAction.view),
          isFalse,
        );
      },
    );

    test(
      '6. obtenerEmpresaActivaId transaccional lanza StateError en BD sin empresa (Fail-Closed)',
      () async {
        final blankDb = await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        await blankDb.execute(
          'CREATE TABLE app_config (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)',
        );
        await blankDb.execute(
          'CREATE TABLE companies (id INTEGER PRIMARY KEY)',
        );

        await blankDb.transaction((txn) async {
          expect(
            () => DatabaseHelper.instance.obtenerEmpresaActivaId(txn),
            throwsA(isA<StateError>()),
          );
        });

        await blankDb.close();
      },
    );
  });
}
