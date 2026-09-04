/// Pruebas unitarias del camino normativo duro - Fase 1: Presupuesto Público + PAC
/// Validaciones marcadas como "✅ Implementada (Dura)"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/presupuesto/models/pago.dart';
import 'package:merka_erp/sector_publico/presupuesto/services/presupuesto_service.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

void main() {
  late Database db;
  late PresupuestoService presupuestoService;
  
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        // Crear tablas mínimas para pruebas
        await db.execute('''
          CREATE TABLE apropiaciones (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            codigo_rubro TEXT NOT NULL,
            nombre_rubro TEXT NOT NULL,
            valor_inicial INTEGER NOT NULL,
            valor_apropiado INTEGER NOT NULL,
            valor_cdp INTEGER NOT NULL,
            valor_rp INTEGER NOT NULL,
            valor_obligado INTEGER NOT NULL,
            valor_pagado INTEGER NOT NULL,
            saldo_disponible INTEGER NOT NULL,
            fuente_financiacion TEXT NOT NULL,
            sector TEXT NOT NULL,
            programa TEXT NOT NULL,
            subprograma TEXT NOT NULL,
            proyecto TEXT NOT NULL,
            actividad TEXT NOT NULL,
            objeto_gasto TEXT NOT NULL,
            fecha_creacion TEXT NOT NULL,
            fecha_aprobacion_concejo TEXT NOT NULL,
            acto_administrativo TEXT NOT NULL,
            activo INTEGER NOT NULL,
            observaciones TEXT,
            vigencia TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cdps (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            numero_cdp TEXT NOT NULL UNIQUE,
            vigencia TEXT NOT NULL,
            apropiacion_id TEXT NOT NULL,
            codigo_rubro TEXT NOT NULL,
            valor_cdp INTEGER NOT NULL,
            valor_comprometido_rp INTEGER NOT NULL,
            saldo_disponible INTEGER NOT NULL,
            fecha_expedicion TEXT NOT NULL,
            fecha_vigencia TEXT NOT NULL,
            funcionario_expedidor TEXT NOT NULL,
            funcionario_solicitante TEXT NOT NULL,
            objeto_gasto TEXT NOT NULL,
            contrato_numero TEXT,
            estado TEXT NOT NULL,
            acto_administrativo_modificacion TEXT,
            fecha_modificacion TEXT,
            observaciones TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE rps (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            numero_rp TEXT NOT NULL UNIQUE,
            cdp_id TEXT NOT NULL,
            valor_rp INTEGER NOT NULL,
            fecha_expedicion TEXT NOT NULL,
            estado TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE obligaciones (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            numero_obligacion TEXT NOT NULL UNIQUE,
            rp_id TEXT NOT NULL,
            valor_obligacion INTEGER NOT NULL,
            fecha_obligacion TEXT NOT NULL,
            estado TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pagos (
            id TEXT PRIMARY KEY,
            entidad_id TEXT NOT NULL,
            numero_pago TEXT NOT NULL UNIQUE,
            obligacion_id TEXT NOT NULL,
            valor_pago INTEGER NOT NULL,
            fecha_pago TEXT NOT NULL,
            estado TEXT NOT NULL
          )
        ''');
      },
    );
    
    presupuestoService = PresupuestoService(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Validaciones Normativas Duras - Fase 1', () {
    test('NO debe poder expedir CDP sin disponibilidad en rubro', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final rubroId = 'rubro-001';
      
      // Crear rubro con saldo 0 usando la API real para garantizar el tipo booleano correcto
      await presupuestoService.crearApropiacion(
        entidadId: entidadId,
        usuarioId: usuarioId,
        vigencia: '2024',
        codigoRubro: '110101',
        nombreRubro: 'Gastos de Personal',
        valorApropiado: publicMoneyFromMajor('0'),
        fuenteFinanciacion: 'general',
        sector: 'sector-prueba',
        programa: 'programa-prueba',
        subprograma: 'subprograma-prueba',
        proyecto: 'proyecto-prueba',
        actividad: 'actividad-prueba',
        objetoGasto: 'Gastos de Personal',
        fechaAprobacionConcejo: DateTime(2024, 1, 1),
        actoAdministrativo: 'ACT-001',
      );

      // Act & Assert
      expect(
        () => presupuestoService.expedirCDP(
          entidadId: entidadId,
          usuarioId: usuarioId,
          apropiacionId: rubroId,
          valorCDP: publicMoneyFromMajor('1000000'),
          funcionarioExpedidor: 'funcionario-expedidor',
          funcionarioSolicitante: 'funcionario-solicitante',
          objetoGasto: 'Gastos de Personal',
          contratoNumero: null,
        ),
        throwsException,
      );
    });

    test('NO debe poder expedir RP sin CDP previo', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final cdpId = 'cdp-inexistente';
 
      // Act & Assert
      expect(
        () => presupuestoService.expedirRP(
          entidadId: entidadId,
          usuarioId: usuarioId,
          cdpId: cdpId,
          contratoId: 'contrato-001',
          contratoNumero: 'CT-2024-001',
          valorRP: publicMoneyFromMajor('1000000'),
          funcionarioExpedidor: 'funcionario-expedidor',
          funcionarioSolicitante: 'funcionario-solicitante',
          objetoGasto: 'Gastos de Personal',
        ),
        throwsException,
      );
    });

    test('NO debe poder expedir RP si CDP está vencido', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final rubroId = 'rubro-001';
      
      // Crear rubro con saldo usando la API real
      await presupuestoService.crearApropiacion(
        entidadId: entidadId,
        usuarioId: usuarioId,
        vigencia: '2024',
        codigoRubro: '110101',
        nombreRubro: 'Gastos de Personal',
        valorApropiado: publicMoneyFromMajor('10000000'),
        fuenteFinanciacion: 'general',
        sector: 'sector-prueba',
        programa: 'programa-prueba',
        subprograma: 'subprograma-prueba',
        proyecto: 'proyecto-prueba',
        actividad: 'actividad-prueba',
        objetoGasto: 'Gastos de Personal',
        fechaAprobacionConcejo: DateTime(2024, 1, 1),
        actoAdministrativo: 'ACT-001',
      );
 
      // Crear CDP vencido
      final cdpId = 'cdp-001';
      await db.insert('cdps', {
        'id': cdpId,
        'entidad_id': entidadId,
        'numero_cdp': 'CDP-2024-001',
        'vigencia': '2024',
        'apropiacion_id': rubroId,
        'codigo_rubro': '110101',
          'valor_cdp': 100000000,
          'valor_comprometido_rp': 0,
          'saldo_disponible': 100000000,
        'fecha_expedicion': DateTime(2023, 1, 1).toIso8601String(),
        'fecha_vigencia': DateTime(2023, 12, 31).toIso8601String(),
        'funcionario_expedidor': 'funcionario-expedidor',
        'funcionario_solicitante': 'funcionario-solicitante',
        'objeto_gasto': 'Gastos de Personal',
        'contrato_numero': null,
        'estado': 'vigente',
        'acto_administrativo_modificacion': null,
        'fecha_modificacion': null,
        'observaciones': null,
      });

      // Act & Assert
      expect(
        () => presupuestoService.expedirRP(
          entidadId: entidadId,
          usuarioId: usuarioId,
          cdpId: cdpId,
          contratoId: 'contrato-001',
          contratoNumero: 'CT-2024-001',
          valorRP: publicMoneyFromMajor('1000000'),
          funcionarioExpedidor: 'funcionario-expedidor',
          funcionarioSolicitante: 'funcionario-solicitante',
          objetoGasto: 'Gastos de Personal',
        ),
        throwsException,
      );
    });

    test('NO debe poder expedir RP si valor excede saldo CDP', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final rubroId = 'rubro-001';
      
      // Crear rubro con saldo usando la API real
      await presupuestoService.crearApropiacion(
        entidadId: entidadId,
        usuarioId: usuarioId,
        vigencia: '2024',
        codigoRubro: '110101',
        nombreRubro: 'Gastos de Personal',
        valorApropiado: publicMoneyFromMajor('10000000'),
        fuenteFinanciacion: 'general',
        sector: 'sector-prueba',
        programa: 'programa-prueba',
        subprograma: 'subprograma-prueba',
        proyecto: 'proyecto-prueba',
        actividad: 'actividad-prueba',
        objetoGasto: 'Gastos de Personal',
        fechaAprobacionConcejo: DateTime(2024, 1, 1),
        actoAdministrativo: 'ACT-001',
      );
 
      // Crear CDP con valor menor
      final cdpId = 'cdp-001';
      await db.insert('cdps', {
        'id': cdpId,
        'entidad_id': entidadId,
        'numero_cdp': 'CDP-2024-001',
        'vigencia': '2024',
        'apropiacion_id': rubroId,
        'codigo_rubro': '110101',
          'valor_cdp': 100000000,
        'valor_comprometido_rp': 0,
          'saldo_disponible': 100000000,
        'fecha_expedicion': DateTime(2024, 1, 1).toIso8601String(),
        'fecha_vigencia': DateTime(2024, 12, 31).toIso8601String(),
        'funcionario_expedidor': 'funcionario-expedidor',
        'funcionario_solicitante': 'funcionario-solicitante',
        'objeto_gasto': 'Gastos de Personal',
        'contrato_numero': null,
        'estado': 'vigente',
        'acto_administrativo_modificacion': null,
        'fecha_modificacion': null,
        'observaciones': null,
      });

      // Act & Assert
      expect(
        () => presupuestoService.expedirRP(
          entidadId: entidadId,
          usuarioId: usuarioId,
          cdpId: cdpId,
          contratoId: 'contrato-001',
          contratoNumero: 'CT-2024-001',
          valorRP: publicMoneyFromMajor('2000000'), // Excede el valor del CDP
          funcionarioExpedidor: 'funcionario-expedidor',
          funcionarioSolicitante: 'funcionario-solicitante',
          objetoGasto: 'Gastos de Personal',
        ),
        throwsException,
      );
    });

    test('NO debe poder crear obligación sin RP previo', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final rpId = 'rp-inexistente';

      // Act & Assert
      expect(
        () => presupuestoService.registrarObligacion(
          entidadId: entidadId,
          usuarioId: usuarioId,
          rpId: rpId,
          contratoId: 'contrato-001',
          contratoNumero: 'CT-2024-001',
          terceroId: 'tercero-001',
          terceroNombre: 'Proveedor de Prueba',
          valorObligacion: publicMoneyFromMajor('1000000'),
          funcionarioReconocio: 'funcionario-reconocio',
          objetoGasto: 'Suministros',
        ),
        throwsException,
      );
    });

    test('NO debe poder crear pago sin obligación previa', () async {
      // Arrange
      final entidadId = 'test-entidad';
      final usuarioId = 'test-usuario';
      final obligacionId = 'obligacion-inexistente';

      // Act & Assert
      expect(
        () => presupuestoService.programarPago(
          entidadId: entidadId,
          usuarioId: usuarioId,
          obligacionId: obligacionId,
          terceroId: 'tercero-001',
          terceroNombre: 'Proveedor de Prueba',
          bancoDestino: 'Banco de Prueba',
          cuentaDestino: '1234567890',
          tipoCuenta: 'Corriente',
          valorPago: publicMoneyFromMajor('1000000'),
          funcionarioProgramo: 'funcionario-programo',
          tipoPago: TipoPago.transferenciaBancaria,
          mesPAC: 1,
        ),
        throwsException,
      );
    });
  });
}
