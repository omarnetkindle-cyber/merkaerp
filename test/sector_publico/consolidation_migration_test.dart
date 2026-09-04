// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:merka_erp/sector_publico/nomina/services/nomina_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Prueba de Integracion: Migrar base de datos real del ERP (v60 -> v61) y verificar Sector Publico', () async {
    final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\PC';
    final dbDir = p.join(home, 'Documents');
    final realDbPath = p.join(dbDir, 'merka_erp_test_fresco.db');
    final tempDbPath = p.join(dbDir, 'merka_erp_test_fresco_integration.db');

    final file = File(realDbPath);
    if (!file.existsSync()) {
      print('El archivo merka_erp_test_fresco.db no existe en Documents.');
      return;
    }

    // 1. Respaldar DB real
    print('=== PASO 1: Copiando base de datos real a: $tempDbPath ===');
    await file.copy(tempDbPath);

    // 2. Abrir para verificar versión inicial
    final dbV60 = await openDatabase(tempDbPath);
    final versionInicial = await dbV60.getVersion();
    print('Versión de esquema inicial: $versionInicial');
    await dbV60.close();

    // 3. Abrir pidiendo versión 61 con la callback oficial de db_helper
    print('=== PASO 2: Abriendo base de datos con version: 61 (gatillando migración v61) ===');
    final db = await openDatabase(
      tempDbPath,
      version: 61,
      onUpgrade: DatabaseHelper.instance.migrarDBForTesting,
    );

    final versionFinal = await db.getVersion();
    print('Versión de esquema final: $versionFinal');
    expect(versionFinal, equals(61));

    // 4. Verificar que las tablas críticas del Sector Público y los nombres renombrados existan
    print('=== PASO 3: Verificando la existencia de las tablas del Sector Público ===');
    final tablasRequeridas = [
      'entidades_territoriales',
      'asientos_contables_sp', // Renombrada
      'empleados_sp',          // Renombrada
      'reportes_chip',
      'procesos_contratacion',
      'liquidaciones_nomina',
      'retroactivos',
      'proyectos_mga',
      'activos_estado',
      'regalias',
      // Tablas Lote 2 completadas en esquema
      'censo_ica',
      'declaraciones_ica',
      'reteica',
      'avisos_tablero',
      'pagos_ica',
      'configuracion_depreciacion_unidades',
      'registros_produccion',
      'revalorizaciones',
      'flujos_viabilizacion',
    ];

    for (final tabla in tablasRequeridas) {
      final res = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?;", [tabla]);
      if (res.isNotEmpty) {
        print('  [OK] Tabla detectada: $tabla');
      } else {
        print('  [FAIL] Tabla faltante: $tabla');
      }
      expect(res.isNotEmpty, isTrue);
    }

    // 5. Probar escritura/lectura en las tablas integradas
    print('=== PASO 4: Probando inserción de funcionario ===');
    final entidadId = 'MUN-SOP-99';

    // Insertar entidad territorial mock requerida por la FK
    await db.insert('entidades_territoriales', {
      'id': entidadId,
      'nit': '999.999.999-9',
      'razon_social': 'Municipio de Soporte Integración',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': 'CGC_2015',
      'configuracion_normativa': 'Resolucion_533'
    });

    await db.insert('funcionarios_entidad', {
      'id': 'FL-MUN-SOP-99-representante_legal',
      'entidad_id': entidadId,
      'cargo_clave': 'representante_legal',
      'nombre_completo': 'Primer Alcalde de Integracion',
      'identificacion': '50.123.456',
      'tarjeta_profesional': '',
      'telefono': '3151234567',
      'email': 'alcaldia@soporte.gov.co',
      'direccion': 'Carrera 10 #20-30',
    });

    final list = await db.query(
      'funcionarios_entidad',
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
    );
    print('Total funcionarios registrados: ${list.length}');
    expect(list.length, equals(1));

    // 4.5. Probar liquidación de nómina real con NominaService
    print('=== PASO 4.5: Probando liquidación de nómina real ===');
    final empleadoId = 'EMP-INTEGRACION-01';

    // Insertar empleado mock en la tabla consolidada empleados_sp
    await db.insert('empleados_sp', {
      'id': empleadoId,
      'entidad_id': entidadId,
      'numero_identificacion': '80.999.888',
      'nombre_completo': 'Empleado de Integracion Publica',
      'cargo': 'Profesional Universitario',
      'dependencia': 'Hacienda',
      'tipo_contrato': 'indefinido',
      'tipo_vinculacion': 'carrera',
      'salario_basico': 3500000.0, // 3.5 millones
      'activo': 1,
      'fecha_ingreso': DateTime.now().toIso8601String(),
    });

    final auditoriaService = AuditoriaService(db);
    final nominaService = NominaService(
      db: db,
      auditoriaService: auditoriaService,
    );

    // Calcular liquidación
    final liquidacion = await nominaService.liquidarNomina(
      entidadId: entidadId,
      usuarioId: 'USR-TEST-1',
      empleadoId: empleadoId,
      periodo: '2026-07',
      diasTrabajados: 30,
    );

    print('✓ Liquidación generada con éxito sin errores de tabla.');
    print('  Neto a Pagar: \$${liquidacion.netoPagar}');
    print('  Observaciones / Warnings: ${liquidacion.observaciones}');

    expect(liquidacion.netoPagar, isNotNull);
    expect(liquidacion.observaciones, contains('SMMLV/auxilio de transporte por defecto'));

    await db.close();

    // 6. Eliminar archivo temporal
    print('=== PASO 5: Eliminando base de datos temporal ===');
    await File(tempDbPath).delete();
    print('Archivo temporal de integración eliminado con éxito.');
  });
}
