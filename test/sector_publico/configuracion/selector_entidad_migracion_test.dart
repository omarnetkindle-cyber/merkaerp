import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/configuracion/services/matriz_visibilidad_service.dart';
import 'package:merka_erp/sector_publico/configuracion/services/selector_entidad_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/nomina/database/schema_nomina.dart';
import 'package:merka_erp/sector_publico/nomina/services/nomina_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'selector guarda historial vigente y convierte tipos del onboarding legado',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await SchemaMultiTenant.crearTablas(db);
      final selector = SelectorEntidadService(
        db: db,
        auditoriaService: AuditoriaService(db),
      );

      await selector.configurarTipoEntidad(
        entidadId: 'ENT-001',
        usuarioId: 'USR-001',
        tipo: TipoEntidad.hospitalEse,
        nombreEntidad: 'Hospital municipal',
        codigoDANE: '11001',
        departamento: 'Cundinamarca',
      );
      await selector.actualizarTipoEntidad(
        entidadId: 'ENT-001',
        usuarioId: 'USR-001',
        nuevoTipo: TipoEntidad.otroEnte,
        motivo: 'Cambio de naturaleza juridica',
      );

      final actual = await selector.consultarConfiguracion(
        entidadId: 'ENT-001',
      );
      final historial = await selector.consultarHistorialCambios(
        entidadId: 'ENT-001',
      );
      expect(actual!['tipo'], 'otroEnte');
      expect(actual['parametro'], 'tipo_entidad');
      expect(actual['vigente'], 1);
      expect(historial, hasLength(2));
      expect(
        historial.where((fila) => fila['vigente'] == 0).single['fecha_fin'],
        isNotNull,
      );
      expect(
        TipoEntidadCompatibilidad.desdeTipoOnboarding('gobernacion'),
        TipoEntidad.departamento,
      );
      expect(
        TipoEntidadCompatibilidad.desdeTipoOnboarding('hospital'),
        TipoEntidad.hospitalEse,
      );
      expect(
        TipoEntidadCompatibilidad.desdeTipoOnboarding('otro'),
        TipoEntidad.otroEnte,
      );
    },
  );

  test(
    'migracion conserva y Nomina usa la configuracion_legal vigente',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
      CREATE TABLE configuracion_entidad (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL UNIQUE,
        parametro TEXT NOT NULL,
        valor TEXT NOT NULL,
        fecha_actualizacion TEXT NOT NULL,
        actualizado_por TEXT NOT NULL,
        tipo TEXT,
        subtipo TEXT,
        nombre_entidad TEXT,
        codigo_dane TEXT,
        departamento TEXT,
        municipio TEXT,
        fecha_configuracion TEXT,
        configurado_por TEXT,
        motivo_cambio TEXT,
        estado TEXT NOT NULL DEFAULT 'activo'
      )
    ''');
      await db.insert('configuracion_entidad', {
        'id': 'CFG-LEGAL',
        'entidad_id': 'ENT-001',
        'parametro': 'configuracion_legal',
        'valor': jsonEncode({'smmlv': 1400000, 'auxilio_transporte': 175000}),
        'fecha_actualizacion': '2026-01-01T00:00:00.000',
        'actualizado_por': 'USR-001',
      });

      await SchemaMultiTenant.migrarConfiguracionEntidadParaHistorial(db);
      await SchemaMultiTenant.crearTablas(db);
      await SchemaNomina.crearTablas(db);
      await db.insert('configuracion_entidad', {
        'id': 'CFG-TIPO',
        'entidad_id': 'ENT-001',
        'parametro': 'tipo_entidad',
        'valor': 'departamento',
        'fecha_actualizacion': '2026-01-02T00:00:00.000',
        'actualizado_por': 'USR-001',
        'tipo': 'departamento',
      });
      await db.insert('empleados_sp', {
        'id': 'EMP-001',
        'entidad_id': 'ENT-001',
        'numero_identificacion': '1001',
        'nombre_completo': 'Empleado de prueba',
        'cargo': 'Analista',
        'dependencia': 'Nomina',
        'tipo_contrato': 'indefinido',
        'tipo_vinculacion': 'carrera',
        'salario_basico': 1000000,
        'fecha_ingreso': '2020-01-01T00:00:00.000',
        'activo': 1,
      });

      final migrada = await db.query(
        'configuracion_entidad',
        where: 'id = ?',
        whereArgs: ['CFG-LEGAL'],
      );
      expect(migrada.single['vigente'], 1);
      expect(migrada.single['fecha_fin'], isNull);

      final nomina = NominaService(
        db: db,
        auditoriaService: AuditoriaService(db),
      );
      final liquidacion = await nomina.liquidarNomina(
        entidadId: 'ENT-001',
        usuarioId: 'USR-001',
        empleadoId: 'EMP-001',
        periodo: '2026-07',
        diasTrabajados: 30,
      );
      expect(liquidacion.auxilioTransporte, publicMoneyFromMajor('175000'));

      await db.update(
        'configuracion_entidad',
        {
          'valor': jsonEncode({'smmlv': 1400000, 'auxilio_transporte': 190000}),
        },
        where: 'entidad_id = ? AND parametro = ? AND vigente = 1',
        whereArgs: ['ENT-001', 'configuracion_legal'],
      );
      final actualizada = await db.query(
        'configuracion_entidad',
        where: 'entidad_id = ? AND parametro = ? AND vigente = 1',
        whereArgs: ['ENT-001', 'configuracion_legal'],
      );
      expect(
        jsonDecode(actualizada.single['valor'] as String)['auxilio_transporte'],
        190000,
      );
    },
  );

  test(
    'matriz se siembra y se consulta desde modulos_por_tipo_entidad',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await SchemaMultiTenant.crearTablas(db);
      final matriz = MatrizVisibilidadService(
        db: db,
        auditoriaService: AuditoriaService(db),
      );

      final modulos = await matriz.obtenerModulosVisibles(
        tipo: 'municipio',
        subtipo: 'categoriaSegunda',
      );
      final filas = await db.query(
        'modulos_por_tipo_entidad',
        where: 'tipo = ? AND subtipo = ?',
        whereArgs: ['municipio', 'categoriaSegunda'],
      );
      expect(filas, hasLength(9));
      expect(modulos, {
        Modulo.presupuesto,
        Modulo.contabilidad,
        Modulo.auditoria,
        Modulo.rentas,
        Modulo.contratacion,
        Modulo.nomina,
        Modulo.planeacion,
        Modulo.activos,
        Modulo.transparencia,
      });
    },
  );
}
