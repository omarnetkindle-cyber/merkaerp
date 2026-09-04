// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:merka_erp/db_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Prueba 1: Instalacion Nueva (_onCreate desde cero v61) genera todas las 9 tablas de Lote 2', () async {
    final tempDbPath = p.join(Directory.systemTemp.path, 'test_fresh_install_v61.db');
    final file = File(tempDbPath);
    if (file.existsSync()) {
      await file.delete();
    }

    print('=== PASO 1: Creando base de datos limpia desde cero en v61 ===');
    final db = await openDatabase(
      tempDbPath,
      version: 61,
      onCreate: (Database db, int version) async {
        await DatabaseHelper.instance.crearDBForTesting(db, version);
      },
    );

    final version = await db.getVersion();
    print('Versión instalada desde cero: $version');
    expect(version, equals(61));

    print('=== PASO 2: Verificando presencia de las 9 tablas nuevas de Lote 2 ===');
    final tablasNuevas = [
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

    for (final tabla in tablasNuevas) {
      final res = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name=?;", [tabla]);
      if (res.isNotEmpty) {
        print('  [OK] Tabla en _onCreate: $tabla');
      } else {
        print('  [FAIL] Tabla faltante en _onCreate: $tabla');
      }
      expect(res.isNotEmpty, isTrue);
    }

    await db.close();
    if (file.existsSync()) {
      await file.delete();
    }
  });

  test('Prueba 2: Integridad Referencial FK en Cadenas Profundas (Activos e ICA)', () async {
    final tempDbPath = p.join(Directory.systemTemp.path, 'test_fk_constraints_v61.db');
    final file = File(tempDbPath);
    if (file.existsSync()) {
      await file.delete();
    }

    final db = await openDatabase(
      tempDbPath,
      version: 61,
      onCreate: (Database db, int version) async {
        await DatabaseHelper.instance.crearDBForTesting(db, version);
      },
    );

    // Habilitar encriptación / llaves foráneas estrictas en SQLite
    await db.execute('PRAGMA foreign_keys = ON;');

    final entidadId = 'MUN-SOP-TEST';

    // Insertar Entidad Territorial Mock requerida por la FK raíz
    await db.insert('entidades_territoriales', {
      'id': entidadId,
      'nit': '800.123.456-7',
      'razon_social': 'Municipio Test FK',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime.now().toIso8601String(),
      'plan_cuentas_cgc': 'CGC_2015',
      'configuracion_normativa': 'Resolucion_533'
    });

    // --- CADENA A: Activos (registros_produccion -> configuracion -> activos_estado) ---
    print('=== CADENA A: Probando violación de FK en registros_produccion sin padre ===');
    try {
      await db.insert('registros_produccion', {
        'id': 'REG-PROD-FAIL',
        'entidad_id': entidadId,
        'configuracion_id': 'CFG-INEXISTENTE',
        'activo_id': 'ACT-INEXISTENTE',
        'unidades_producidas': 100.0,
        'costo_por_unidad': 500.0,
        'depreciacion_periodo': 50000.0,
        'fecha_produccion': DateTime.now().toIso8601String(),
        'fecha_registro': DateTime.now().toIso8601String(),
      });
      fail('Debería haber fallado con error de FK');
    } catch (e) {
      print('✓ Violación de FK capturada correctamente en registros_produccion sin padre:');
      print('  Error crudo: $e');
      expect(e.toString(), contains('FOREIGN KEY constraint failed'));
    }

    print('=== CADENA A: Insertando abuelo (activos_estado) y padre (configuracion) ===');
    const activoId = 'ACT-CAMION-01';
    await db.insert('activos_estado', {
      'id': activoId,
      'entidad_id': entidadId,
      'numero_inventario': 'INV-CAM-01',
      'nombre_activo': 'Camión Volqueta Obras',
      'tipo_activo': 'vehiculo',
      'marca': 'Chevrolet',
      'modelo': '2022',
      'serie': 'SER123456',
      'valor_adquisicion': 250000000.0,
      'valor_libros': 250000000.0,
      'valor_neto': 250000000.0,
      'fecha_adquisicion': DateTime.now().toIso8601String(),
      'fecha_puesta_en_marcha': DateTime.now().toIso8601String(),
      'vida_util_anios': 10,
      'valor_residual': 25000000.0,
      'estado': 'excelente',
    });

    const configId = 'CFG-CAMION-01';
    await db.insert('configuracion_depreciacion_unidades', {
      'id': configId,
      'entidad_id': entidadId,
      'activo_id': activoId,
      'numero_inventario': 'INV-CAM-01',
      'unidades_totales_estimadas': 100000.0, // 100 mil km
      'valor_adquisicion': 250000000.0,
      'valor_residual': 25000000.0,
      'costo_depreciable': 225000000.0,
      'costo_por_unidad': 2250.0,
      'fecha_inicio': DateTime.now().toIso8601String(),
      'fecha_registro': DateTime.now().toIso8601String(),
    });

    print('=== CADENA A: Insertando registros_produccion con jerarquía válida ===');
    await db.insert('registros_produccion', {
      'id': 'REG-PROD-SUCCESS',
      'entidad_id': entidadId,
      'configuracion_id': configId,
      'activo_id': activoId,
      'unidades_producidas': 1000.0,
      'costo_por_unidad': 2250.0,
      'depreciacion_periodo': 2250000.0,
      'fecha_produccion': DateTime.now().toIso8601String(),
      'fecha_registro': DateTime.now().toIso8601String(),
    });

    final regCheck = await db.query('registros_produccion', where: 'id = ?', whereArgs: ['REG-PROD-SUCCESS']);
    print('  ✓ Inserción correcta en registros_produccion. Total filas: ${regCheck.length}');
    expect(regCheck.length, equals(1));


    // --- CADENA B: ICA (pagos_ica -> declaraciones_ica -> censo_ica) ---
    print('\n=== CADENA B: Probando violación de FK en declaraciones_ica sin censo_ica padre ===');
    try {
      await db.insert('declaraciones_ica', {
        'id': 'DEC-ICA-FAIL',
        'entidad_id': entidadId,
        'contribuyente_id': 'CONTRIB-INEXISTENTE',
        'periodo': '2026-01',
        'periodo_declaracion': 'bimestral',
        'fecha_declaracion': DateTime.now().toIso8601String(),
        'ingresos_gravables': 50000000.0,
        'ingresos_no_gravables': 0.0,
        'ingresos_exentos': 0.0,
        'base_gravable': 50000000.0,
        'tarifa': 0.008,
        'impuesto_ica': 400000.0,
        'total_pagar': 400000.0,
      });
      fail('Debería haber fallado con error de FK en declaraciones_ica');
    } catch (e) {
      print('✓ Violación de FK capturada correctamente en declaraciones_ica sin censo_ica padre:');
      print('  Error crudo: $e');
      expect(e.toString(), contains('FOREIGN KEY constraint failed'));
    }

    print('=== CADENA B: Insertando abuelo (censo_ica) y padre (declaraciones_ica) ===');
    const contribId = 'CONTRIB-SOPORTE-01';
    await db.insert('censo_ica', {
      'id': contribId,
      'entidad_id': entidadId,
      'nit': '900.888.777-1',
      'razon_social': 'Comercializadora Soporte S.A.S.',
      'direccion': 'Calle 100 #15-20',
      'telefono': '3001234567',
      'tipo_actividad': 'comercial',
      'actividad_economica': '4711 - Comercio al por menor',
      'ingresos_anuales_estimados': 500000000.0,
      'fecha_registro': DateTime.now().toIso8601String(),
    });

    const declaracionId = 'DEC-ICA-SUCCESS-01';
    await db.insert('declaraciones_ica', {
      'id': declaracionId,
      'entidad_id': entidadId,
      'contribuyente_id': contribId,
      'periodo': '2026-01',
      'periodo_declaracion': 'bimestral',
      'fecha_declaracion': DateTime.now().toIso8601String(),
      'ingresos_gravables': 50000000.0,
      'ingresos_no_gravables': 0.0,
      'ingresos_exentos': 0.0,
      'base_gravable': 50000000.0,
      'tarifa': 0.008,
      'impuesto_ica': 400000.0,
      'total_pagar': 400000.0,
    });

    print('=== CADENA B: Insertando pagos_ica con jerarquía válida ===');
    await db.insert('pagos_ica', {
      'id': 'PAGO-ICA-SUCCESS',
      'entidad_id': entidadId,
      'declaracion_id': declaracionId,
      'periodo': '2026-01',
      'valor_pagado': 400000.0,
      'fecha_pago': DateTime.now().toIso8601String(),
      'numero_recibo': 'REC-2026-001',
    });

    final pagoCheck = await db.query('pagos_ica', where: 'id = ?', whereArgs: ['PAGO-ICA-SUCCESS']);
    print('  ✓ Inserción correcta en pagos_ica. Total filas: ${pagoCheck.length}');
    expect(pagoCheck.length, equals(1));

    await db.close();
    if (file.existsSync()) {
      await file.delete();
    }
  });
}
