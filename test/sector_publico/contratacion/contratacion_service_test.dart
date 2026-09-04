/// Pruebas unitarias del camino normativo duro - Fase 5: Contratación Pública + SECOP II
/// Validaciones marcadas como "✅ Implementada (Dura)"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/contratacion/services/contratacion_service.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';

void main() {
  late Database db;
  late ContratacionService contratacionService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE procesos_contratacion (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            numero_proceso TEXT NOT NULL UNIQUE,
            objeto_contrato TEXT NOT NULL,
            modalidad TEXT NOT NULL,
            valor_estimado INTEGER NOT NULL,
            tipo_contrato TEXT NOT NULL,
            dependencia_solicitante TEXT NOT NULL,
            responsable_proceso TEXT NOT NULL,
            fecha_inicio TEXT NOT NULL,
            fecha_publicacion TEXT,
            fecha_cierre TEXT,
            estado TEXT NOT NULL,
            cdp_id TEXT,
            numero_cdp TEXT,
            secop_id TEXT,
            observaciones TEXT,
            publicado_secop INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE contratos (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            numero_contrato TEXT NOT NULL UNIQUE,
            proceso_id TEXT NOT NULL,
            cdp_id TEXT,
            rp_id TEXT,
            estado TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE rps (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            numero_rp TEXT NOT NULL,
            cdp_id TEXT NOT NULL
          )
        ''');
      },
    );

    contratacionService = ContratacionService(
      db: db,
      presupuestoService: PresupuestoService(db: db),
      auditoriaService: AuditoriaService(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Validaciones Normativas Duras - Fase 5', () {
    test('NO debe poder crear contrato sin CDP', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final procesoId = 'proceso-001';

      // Crear proceso
      await db.insert('procesos_contratacion', {
        'id': procesoId,
        'entidad_id': entidadId,
        'numero_proceso': 'PROC-2024-001',
        'objeto_contrato': 'Contratación de servicios',
        'modalidad': 'licitacionPublica',
        'valor_estimado': 10000000000,
        'tipo_contrato': 'obras',
        'dependencia_solicitante': 'Secretaría de Planeación',
        'responsable_proceso': 'Responsable Prueba',
        'fecha_inicio': DateTime(2024, 1, 1).toIso8601String(),
        'estado': 'adjudicado',
        'cdp_id': null,
        'numero_cdp': null,
        'secop_id': null,
        'observaciones': null,
        'publicado_secop': 1,
      });

      // Act & Assert
      expect(
        () => contratacionService.crearContrato(
          entidadId: entidadId,
          usuarioId: usuarioId,
          procesoId: procesoId,
          contratistaId: 'contratista-001',
          contratistaNombre: 'Contratista de Prueba',
          contratistaIdentificacion: '1234567890',
          cdpId: 'cdp-inexistente',
          numeroCDP: 'CDP-2024-001',
          rpId: 'rp-001',
          numeroRP: 'RP-2024-001',
          fechaFirma: DateTime(2024, 1, 1),
          fechaInicioEjecucion: DateTime(2024, 2, 1),
          fechaFinEjecucion: DateTime(2024, 12, 31),
        ),
        throwsException,
      );
    });

    test('NO debe poder crear contrato sin RP', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final procesoId = 'proceso-001';
      final cdpId = 'cdp-001';

      // Crear proceso CON CDP válido (aislando la prueba de ausencia de RP)
      await db.insert('procesos_contratacion', {
        'id': procesoId,
        'entidad_id': entidadId,
        'numero_proceso': 'PROC-2024-001',
        'objeto_contrato': 'Contratación de servicios',
        'modalidad': 'licitacionPublica',
        'valor_estimado': 10000000000,
        'tipo_contrato': 'obras',
        'dependencia_solicitante': 'Secretaría de Planeación',
        'responsable_proceso': 'Responsable Prueba',
        'fecha_inicio': DateTime(2024, 1, 1).toIso8601String(),
        'estado': 'adjudicado',
        'cdp_id': cdpId,
        'numero_cdp': 'CDP-2024-001',
        'secop_id': 'SECOP-2024-001',
        'fecha_publicacion': DateTime(2024, 1, 2).toIso8601String(),
        'observaciones': null,
        'publicado_secop': 1,
      });

      // Act & Assert
      expect(
        () => contratacionService.crearContrato(
          entidadId: entidadId,
          usuarioId: usuarioId,
          procesoId: procesoId,
          contratistaId: 'contratista-001',
          contratistaNombre: 'Contratista de Prueba',
          contratistaIdentificacion: '1234567890',
          cdpId: cdpId,
          numeroCDP: 'CDP-2024-001',
          rpId: 'rp-inexistente',
          numeroRP: 'RP-2024-001',
          fechaFirma: DateTime(2024, 1, 1),
          fechaInicioEjecucion: DateTime(2024, 2, 1),
          fechaFinEjecucion: DateTime(2024, 12, 31),
        ),
        throwsException,
      );
    });

    test(
      'NO debe poder crear contrato si proceso no está publicado en SECOP',
      () async {
        // Arrange
        final entidadId = 'test-entidad';
        final usuarioId = 'test-usuario';
        final procesoId = 'proceso-001';

        // Crear proceso CON CDP y RP válidos, pero NO publicado en SECOP
        await db.insert('procesos_contratacion', {
          'id': procesoId,
          'entidad_id': entidadId,
          'numero_proceso': 'PROC-2024-001',
          'objeto_contrato': 'Contratación de servicios',
          'modalidad': 'licitacionPublica',
          'valor_estimado': 10000000000,
          'tipo_contrato': 'obras',
          'dependencia_solicitante': 'Secretaría de Planeación',
          'responsable_proceso': 'Responsable Prueba',
          'fecha_inicio': DateTime(2024, 1, 1).toIso8601String(),
          'estado': 'adjudicado',
          'cdp_id': 'cdp-001',
          'numero_cdp': 'CDP-2024-001',
          'secop_id': null,
          'observaciones': null,
          'publicado_secop': 0, // No publicado
        });

        // Act & Assert
        expect(
          () => contratacionService.crearContrato(
            entidadId: entidadId,
            usuarioId: usuarioId,
            procesoId: procesoId,
            contratistaId: 'contratista-001',
            contratistaNombre: 'Contratista de Prueba',
            contratistaIdentificacion: '1234567890',
            cdpId: 'cdp-001',
            numeroCDP: 'CDP-2024-001',
            rpId: 'rp-001',
            numeroRP: 'RP-2024-001',
            fechaFirma: DateTime(2024, 1, 1),
            fechaInicioEjecucion: DateTime(2024, 2, 1),
            fechaFinEjecucion: DateTime(2024, 12, 31),
          ),
          throwsException,
        );
      },
    );
  });
}
