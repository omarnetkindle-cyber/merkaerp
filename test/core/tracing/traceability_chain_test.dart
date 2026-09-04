import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/commands/command_registry.dart';
import 'package:merka_erp/core/tracing/traceability_chain.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const entityId = 'ENT-TRACE-001';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('reconstruye completa la cadena pública hasta NICSP', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    await _seedEntity(db);
    await _seedPublicChain(db);

    final chain = await TraceabilityChainService.standard().build(
      rootEntityType: 'apropiacion',
      rootRecordId: 'APR-1',
      db: db,
      tenantId: entityId,
    );

    expect(chain.isComplete, isTrue);
    expect(chain.steps.map((step) => step.label), [
      'Apropiación',
      'CDP',
      'RP',
      'Obligación',
      'Pago / PAC',
      'Asiento NICSP',
    ]);
    expect(chain.steps.every((step) => step.recordId != null), isTrue);
  });

  test('expone el bloqueo exacto cuando falta el CDP', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await _seedEntity(db);
    await db.insert('apropiaciones', _appropriation());

    final chain = await TraceabilityChainService.standard().build(
      rootEntityType: 'apropiacion',
      rootRecordId: 'APR-1',
      db: db,
      tenantId: entityId,
    );

    expect(chain.steps[1].state, TraceabilityStepState.blocked);
    expect(
      chain.steps[1].blockingRule,
      'No existe un CDP expedido contra la apropiación.',
    );
    expect(chain.steps.skip(2).every((step) => step.isBlocked), isTrue);
  });

  test('reconstruye venta, cartera, pago e inventario', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE ventas (id INTEGER PRIMARY KEY, company_id INTEGER,
        total INTEGER, estado TEXT, fecha TEXT)
    ''');
    await db.execute('''
      CREATE TABLE cuentas_por_cobrar (id INTEGER PRIMARY KEY,
        company_id INTEGER, venta_id INTEGER, total INTEGER, saldo INTEGER,
        estado TEXT, fecha TEXT)
    ''');
    await db.execute('''
      CREATE TABLE abonos_cxc (id INTEGER PRIMARY KEY, company_id INTEGER,
        cuenta_id INTEGER, monto INTEGER, fecha TEXT)
    ''');
    await db.execute('''
      CREATE TABLE movimientos_inventario (id INTEGER PRIMARY KEY,
        company_id INTEGER, producto_id INTEGER, tipo TEXT, motivo TEXT,
        fecha TEXT)
    ''');
    await db.insert('ventas', {
      'id': 7,
      'company_id': 1,
      'total': 12500,
      'estado': 'emitida',
      'fecha': '2026-08-09',
    });
    await db.insert('cuentas_por_cobrar', {
      'id': 8,
      'company_id': 1,
      'venta_id': 7,
      'total': 12500,
      'saldo': 0,
      'estado': 'pagada',
      'fecha': '2026-08-09',
    });
    await db.insert('abonos_cxc', {
      'id': 9,
      'company_id': 1,
      'cuenta_id': 8,
      'monto': 12500,
      'fecha': '2026-08-09',
    });
    await db.insert('movimientos_inventario', {
      'id': 10,
      'company_id': 1,
      'producto_id': 2,
      'tipo': 'salida',
      'motivo': 'FACTURA POS #7',
      'fecha': '2026-08-09',
    });

    final chain = await TraceabilityChainService.standard().build(
      rootEntityType: 'venta',
      rootRecordId: '7',
      db: db,
      tenantId: '1',
    );

    expect(chain.isComplete, isTrue);
    expect(chain.steps.map((step) => step.entityType), [
      'venta',
      'cuenta_por_cobrar',
      'abono_cxc',
      'movimiento_inventario',
    ]);
  });

  test('un usuario sin RBAC ve el bloqueo pero no la acción resolutiva', () {
    final context = const CommandContext(
      moduleId: 'presupuesto_publico',
      recordType: 'presupuesto_publico',
      recordId: 'APR-1',
      actions: {'create_cdp': _noop},
    );
    final registry = CommandRegistry(authorization: (_, _) => false)
      ..register(
        CommandDefinition(
          id: 'public.budget.create_cdp',
          label: 'Expedir CDP',
          description: 'Expedir CDP',
          icon: Icons.add,
          color: Colors.blue,
          moduleId: 'presupuesto_publico',
          contextual: true,
          contextType: 'presupuesto_publico',
          actionKey: 'create_cdp',
          handler: (_, _) {},
        ),
      );
    final blocked = ChainStep(
      id: 'cdp',
      label: 'CDP',
      entityType: 'cdp',
      state: TraceabilityStepState.blocked,
      blockingRule: 'No existe un CDP expedido contra la apropiación.',
      commandId: 'public.budget.create_cdp',
      commandContext: context,
    );

    expect(blocked.blockingRule, isNotEmpty);
    expect(blocked.actionAvailable(registry), isFalse);
  });
}

Future<void> _seedEntity(Database db) async {
  await db.insert('entidades_territoriales', {
    'id': entityId,
    'nit': '900000001-1',
    'razon_social': 'Entidad de trazabilidad',
    'tipo_entidad': 'municipio',
    'fecha_creacion': '2026-01-01',
    'plan_cuentas_cgc': '{}',
    'configuracion_normativa': '{}',
  });
  await db.insert('terceros_sector_publico', {
    'id': 'TER-1',
    'entidad_id': entityId,
    'tipo_identificacion': 'NIT',
    'numero_identificacion': '900000002',
    'razon_social': 'Proveedor',
    'tipo_tercero': 'juridica',
    'fecha_creacion': '2026-01-01',
  });
}

Map<String, dynamic> _appropriation() => {
  'id': 'APR-1',
  'entidad_id': entityId,
  'vigencia': '2026',
  'codigo_rubro': '2.1.1',
  'nombre_rubro': 'Servicios',
  'valor_inicial': 100000,
  'valor_apropiado': 100000,
  'valor_cdp': 50000,
  'valor_rp': 50000,
  'valor_obligado': 50000,
  'valor_pagado': 50000,
  'saldo_disponible': 50000,
  'fuente_financiacion': 'ICLD',
  'sector': 'Gobierno',
  'programa': 'Gestión',
  'subprograma': 'Operación',
  'proyecto': 'P-1',
  'actividad': 'A-1',
  'objeto_gasto': 'Servicios',
  'fecha_creacion': '2026-01-01',
  'fecha_aprobacion_concejo': '2025-12-20',
  'acto_administrativo': 'AC-1',
};

Future<void> _seedPublicChain(Database db) async {
  await db.insert('apropiaciones', _appropriation());
  await db.insert('cdps', {
    'id': 'CDP-1',
    'entidad_id': entityId,
    'numero_cdp': 'CDP-1',
    'vigencia': '2026',
    'apropiacion_id': 'APR-1',
    'codigo_rubro': '2.1.1',
    'valor_cdp': 50000,
    'saldo_disponible': 50000,
    'fecha_expedicion': '2026-01-02',
    'fecha_vigencia': '2026-12-31',
    'funcionario_expedidor': 'USR-1',
    'funcionario_solicitante': 'USR-2',
    'objeto_gasto': 'Servicios',
    'estado': 'vigente',
  });
  await db.insert('rps', {
    'id': 'RP-1',
    'entidad_id': entityId,
    'numero_rp': 'RP-1',
    'vigencia': '2026',
    'cdp_id': 'CDP-1',
    'numero_cdp': 'CDP-1',
    'contrato_id': 'CTR-1',
    'contrato_numero': 'CTR-1',
    'codigo_rubro': '2.1.1',
    'valor_rp': 50000,
    'saldo_disponible': 50000,
    'fecha_expedicion': '2026-01-03',
    'fecha_vigencia': '2026-12-31',
    'funcionario_expedidor': 'USR-1',
    'funcionario_solicitante': 'USR-2',
    'objeto_gasto': 'Servicios',
    'estado': 'vigente',
  });
  await db.insert('obligaciones', {
    'id': 'OBL-1',
    'entidad_id': entityId,
    'numero_obligacion': 'OBL-1',
    'vigencia': '2026',
    'rp_id': 'RP-1',
    'numero_rp': 'RP-1',
    'contrato_id': 'CTR-1',
    'contrato_numero': 'CTR-1',
    'tercero_id': 'TER-1',
    'tercero_nombre': 'Proveedor',
    'codigo_rubro': '2.1.1',
    'valor_obligacion': 50000,
    'valor_pagado': 50000,
    'saldo_pendiente': 0,
    'fecha_reconocimiento': '2026-01-04',
    'funcionario_reconocio': 'USR-1',
    'objeto_gasto': 'Servicios',
    'estado': 'pagada',
  });
  await db.insert('pagos', {
    'id': 'PAG-1',
    'entidad_id': entityId,
    'numero_pago': 'PAG-1',
    'vigencia': '2026',
    'obligacion_id': 'OBL-1',
    'numero_obligacion': 'OBL-1',
    'rp_id': 'RP-1',
    'numero_rp': 'RP-1',
    'tercero_id': 'TER-1',
    'tercero_nombre': 'Proveedor',
    'banco_destino': 'Banco',
    'cuenta_destino': '0001',
    'tipo_cuenta': 'corriente',
    'valor_pago': 50000,
    'mes_pac': 1,
    'fecha_programacion': '2026-01-05',
    'fecha_ejecucion': '2026-01-06',
    'funcionario_aprobo': 'USR-1',
    'funcionario_programo': 'USR-2',
    'tipo_pago': 'transferencia',
    'estado': 'pagado',
  });
  await db.insert('asientos_contables_sp', {
    'id': 'AST-1',
    'entidad_id': entityId,
    'numero_asiento': 'AST-1',
    'fecha_asiento': '2026-01-06',
    'descripcion': 'Pago OBL-1',
    'tipo_asiento': 'pago',
    'estado': 'borrador',
    'total_debito': 50000,
    'total_credito': 50000,
    'usuario_creo': 'USR-1',
    'referencia_origen': 'PAG-1',
    'tipo_documento_origen': 'pago',
  });
  await db.insert('detalles_asientos', {
    'id': 'DET-1',
    'asiento_id': 'AST-1',
    'cuenta_codigo': '1110',
    'cuenta_nombre': 'Banco',
    'debito': 50000,
    'credito': 0,
    'referencia_id': 'PAG-1',
  });
  await db.insert('detalles_asientos', {
    'id': 'DET-2',
    'asiento_id': 'AST-1',
    'cuenta_codigo': '2401',
    'cuenta_nombre': 'Obligaciones',
    'debito': 0,
    'credito': 50000,
    'referencia_id': 'PAG-1',
  });
  await db.update(
    'asientos_contables_sp',
    {'estado': 'registrado'},
    where: 'id = ?',
    whereArgs: ['AST-1'],
  );
}

Future<void> _noop(BuildContext context, CommandContext command) async {}
