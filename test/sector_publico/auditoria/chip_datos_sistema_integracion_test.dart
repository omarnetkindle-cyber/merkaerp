import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:merka_erp/sector_publico/auditoria/services/chip_reporter_service.dart';
import 'package:merka_erp/sector_publico/auditoria/database/schema_auditoria.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/presupuesto/database/schema_presupuesto.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';

Future<void> insertarFuncionario(
  Database db, {
  required String id,
  required String cargo,
  String? usuarioId,
  required String nombre,
  required String identificacion,
  required String tarjeta,
  required String telefono,
  required String email,
  required String direccion,
}) {
  return db.insert('funcionarios_entidad', {
    'id': id,
    'entidad_id': 'ENT-CHIP',
    'usuario_id': usuarioId,
    'cargo_clave': cargo,
    'nombre_completo': nombre,
    'identificacion': identificacion,
    'tarjeta_profesional': tarjeta,
    'telefono': telefono,
    'email': email,
    'direccion': direccion,
  });
}

Future<void> insertarSaldo(
  Database db,
  String codigo,
  String nombre,
  double debito,
  double credito,
  String vigencia,
) {
  return db.insert('saldos_cuentas', {
    'id': 'SALDO-$vigencia-$codigo',
    'entidad_id': 'ENT-CHIP',
    'cuenta_codigo': codigo,
    'cuenta_nombre': nombre,
    'saldo_deudor': publicMoneyFromMajor(debito.toString()).toSql(),
    'saldo_acreedor': publicMoneyFromMajor(credito.toString()).toSql(),
    'saldo_neto': publicMoneyFromMajor((debito - credito).toString()).toSql(),
    'fecha_ultimo_movimiento': '2026-12-31T00:00:00.000',
    'vigencia': vigencia,
  });
}

Future<void> insertarPresupuesto(Database db) async {
  final now = '2026-01-01T00:00:00.000';
  await db.insert('terceros_sector_publico', {
    'id': 'TER-001',
    'entidad_id': 'ENT-CHIP',
    'tipo_identificacion': 'NIT',
    'numero_identificacion': '900999001',
    'razon_social': 'Proveedor CHIP',
    'tipo_tercero': 'proveedor',
    'fecha_creacion': now,
  });
  await db.insert('apropiaciones', {
    'id': 'APR-001',
    'entidad_id': 'ENT-CHIP',
    'vigencia': '2026',
    'codigo_rubro': '2.3.1',
    'nombre_rubro': 'Inversion social',
    'valor_inicial': publicMoneyFromMajor('1000').toSql(),
    'valor_apropiado': publicMoneyFromMajor('1200').toSql(),
    'valor_cdp': publicMoneyFromMajor('900').toSql(),
    'valor_rp': publicMoneyFromMajor('800').toSql(),
    'valor_obligado': publicMoneyFromMajor('700').toSql(),
    'valor_pagado': publicMoneyFromMajor('650').toSql(),
    'saldo_disponible': publicMoneyFromMajor('300').toSql(),
    'fuente_financiacion': 'SGP',
    'sector': 'Educacion',
    'programa': 'Programa',
    'subprograma': 'Subprograma',
    'proyecto': 'Proyecto',
    'actividad': 'Actividad',
    'objeto_gasto': 'Objeto',
    'fecha_creacion': now,
    'fecha_aprobacion_concejo': now,
    'acto_administrativo': 'AC-001',
  });
  await db.insert('cdps', {
    'id': 'CDP-001',
    'entidad_id': 'ENT-CHIP',
    'numero_cdp': 'CDP-001',
    'vigencia': '2026',
    'apropiacion_id': 'APR-001',
    'codigo_rubro': '2.3.1',
    'valor_cdp': publicMoneyFromMajor('900').toSql(),
    'valor_comprometido_rp': publicMoneyFromMajor('800').toSql(),
    'saldo_disponible': publicMoneyFromMajor('100').toSql(),
    'fecha_expedicion': now,
    'fecha_vigencia': now,
    'funcionario_expedidor': 'Presupuesto',
    'funcionario_solicitante': 'Solicitante',
    'objeto_gasto': 'Objeto',
    'estado': 'expedido',
  });
  await db.insert('rps', {
    'id': 'RP-001',
    'entidad_id': 'ENT-CHIP',
    'numero_rp': 'RP-001',
    'vigencia': '2026',
    'cdp_id': 'CDP-001',
    'numero_cdp': 'CDP-001',
    'contrato_id': 'CON-001',
    'contrato_numero': 'CON-001',
    'codigo_rubro': '2.3.1',
    'valor_rp': publicMoneyFromMajor('800').toSql(),
    'valor_obligado': publicMoneyFromMajor('700').toSql(),
    'saldo_disponible': publicMoneyFromMajor('100').toSql(),
    'fecha_expedicion': now,
    'fecha_vigencia': now,
    'funcionario_expedidor': 'Presupuesto',
    'funcionario_solicitante': 'Solicitante',
    'objeto_gasto': 'Objeto',
    'estado': 'expedido',
  });
  await db.insert('obligaciones', {
    'id': 'OBL-001',
    'entidad_id': 'ENT-CHIP',
    'numero_obligacion': 'OBL-001',
    'vigencia': '2026',
    'rp_id': 'RP-001',
    'numero_rp': 'RP-001',
    'contrato_id': 'CON-001',
    'contrato_numero': 'CON-001',
    'tercero_id': 'TER-001',
    'tercero_nombre': 'Proveedor CHIP',
    'codigo_rubro': '2.3.1',
    'valor_obligacion': publicMoneyFromMajor('700').toSql(),
    'valor_pagado': publicMoneyFromMajor('650').toSql(),
    'saldo_pendiente': publicMoneyFromMajor('50').toSql(),
    'fecha_reconocimiento': now,
    'funcionario_reconocio': 'Contador',
    'objeto_gasto': 'Objeto',
    'estado': 'parcial',
  });
  await db.insert('pagos', {
    'id': 'PAG-001',
    'entidad_id': 'ENT-CHIP',
    'numero_pago': 'PAG-001',
    'vigencia': '2026',
    'obligacion_id': 'OBL-001',
    'numero_obligacion': 'OBL-001',
    'rp_id': 'RP-001',
    'numero_rp': 'RP-001',
    'tercero_id': 'TER-001',
    'tercero_nombre': 'Proveedor CHIP',
    'banco_destino': 'Banco',
    'cuenta_destino': '123',
    'tipo_cuenta': 'ahorros',
    'valor_pago': publicMoneyFromMajor('650').toSql(),
    'mes_pac': 12,
    'fecha_programacion': now,
    'funcionario_aprobo': 'Tesorero',
    'funcionario_programo': 'Tesorero',
    'tipo_pago': 'transferencia',
    'estado': 'pagado',
  });
}

void main() {
  late Database db;
  late CHIPReporterService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    await SchemaPresupuesto.crearTablas(db);
    await SchemaAuditoria.crearTablas(db);

    await db.insert('entidades_territoriales', {
      'id': 'ENT-CHIP',
      'nit': '900123456',
      'razon_social': 'Municipio de Prueba',
      'tipo_entidad': 'municipio',
      'departamento': 'Cundinamarca',
      'municipio': 'Prueba',
      'fecha_creacion': '2026-01-01T00:00:00.000',
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });

    await insertarFuncionario(
      db,
      id: 'FUNC-AUDITOR',
      cargo: 'jefeControlInterno',
      usuarioId: 'USR-AUDITOR',
      nombre: 'Auditor Interno',
      identificacion: '100',
      tarjeta: '',
      telefono: '3000000000',
      email: 'auditor@prueba.gov.co',
      direccion: 'Calle 1',
    );
    await insertarFuncionario(
      db,
      id: 'FUNC-REP',
      cargo: 'representante_legal',
      nombre: 'Alcaldesa Prueba',
      identificacion: '101',
      tarjeta: '',
      telefono: '3000000001',
      email: 'alcaldesa@prueba.gov.co',
      direccion: 'Calle 1',
    );
    await insertarFuncionario(
      db,
      id: 'FUNC-ORD',
      cargo: 'ordenador_gasto',
      nombre: 'Ordenador Prueba',
      identificacion: '102',
      tarjeta: '',
      telefono: '3000000002',
      email: 'ordenador@prueba.gov.co',
      direccion: 'Calle 1',
    );
    await insertarFuncionario(
      db,
      id: 'FUNC-CONT',
      cargo: 'contador',
      nombre: 'Contadora Prueba',
      identificacion: '103',
      tarjeta: 'TP-123',
      telefono: '3000000003',
      email: 'contadora@prueba.gov.co',
      direccion: 'Calle 1',
    );
    await insertarFuncionario(
      db,
      id: 'FUNC-CONTACTO',
      cargo: 'contacto_entidad',
      nombre: 'Contacto Prueba',
      identificacion: '104',
      tarjeta: '',
      telefono: '3000000004',
      email: 'contacto@prueba.gov.co',
      direccion: 'Carrera 2',
    );

    await insertarSaldo(db, '1110', 'Efectivo', 1210, 0, '2026');
    await insertarSaldo(db, '2401', 'Cuentas por pagar', 0, 400, '2026');
    await insertarSaldo(db, '3105', 'Capital fiscal', 0, 300, '2026');
    await insertarSaldo(db, '4111', 'Impuesto predial', 0, 600, '2026');
    await insertarSaldo(db, '4401', 'Transferencias SGP', 0, 100, '2026');
    await insertarSaldo(db, '5101', 'Servicios personales', 250, 0, '2026');
    await insertarSaldo(db, '5111', 'Gastos generales', 50, 0, '2026');
    await insertarSaldo(db, '2313', 'Deuda publica interna', 0, 90, '2026');
    await insertarSaldo(db, '2314', 'Deuda publica externa', 0, 40, '2026');
    await insertarSaldo(db, '5320', 'Amortizacion deuda', 12, 0, '2026');
    await insertarSaldo(db, '5802', 'Intereses deuda', 8, 0, '2026');
    await insertarSaldo(db, '1110', 'Efectivo', 900, 0, '2025');
    await insertarSaldo(db, '2401', 'Cuentas por pagar', 0, 300, '2025');
    await insertarPresupuesto(db);

    service = CHIPReporterService(
      db: db,
      auditoriaService: AuditoriaService(db),
    );
  });

  tearDown(() async => db.close());

  test('CGN 2015_001 a 003 reflejan fuentes persistidas del sistema', () async {
    final reportes = await service.generarReportesDesdeDatosSistema(
      entidadId: 'ENT-CHIP',
      usuarioId: 'USR-AUDITOR',
      vigencia: '2026',
    );

    expect(
      reportes.keys,
      containsAll(['cgn2015_001', 'cgn2015_002', 'cgn2015_003']),
    );
    expect(
      reportes.keys,
      containsAll(['cgn2015_004', 'cgn2015_005', 'cgn2016C01']),
    );

    final entidad = reportes['cgn2015_001']!.datos;
    expect(entidad['nit'], '900123456');
    expect(entidad['razon_social'], 'Municipio de Prueba');
    expect(entidad['contador'], 'Contadora Prueba');
    expect(entidad['tarjeta_profesional_contador'], 'TP-123');

    final resultado = reportes['cgn2015_002']!.datos;
    expect(resultado['ingresos_tributarios'], 600.0);
    expect(resultado['transferencias_sgp'], 100.0);
    expect(resultado['total_ingresos'], 700.0);
    expect(resultado['gastos_personal'], 250.0);
    expect(resultado['gastos_generales'], 50.0);
    expect(resultado['total_gastos'], 320.0);
    expect(resultado['resultado_operacional'], 380.0);

    final situacion = reportes['cgn2015_003']!.datos;
    expect(situacion['total_activo'], 1210.0);
    expect(situacion['total_pasivo'], 530.0);
    expect(situacion['patrimonio'], 680.0);
    expect(situacion['total_pasivo_patrimonio'], 1210.0);

    final ejecucion = reportes['cgn2015_004']!.datos;
    expect(ejecucion['apropiacion_inicial'], 1000.0);
    expect(ejecucion['adiciones'], 200.0);
    expect(ejecucion['apropiacion_definitiva'], 1200.0);
    expect(ejecucion['compromisos'], 800.0);
    expect(ejecucion['obligaciones'], 700.0);
    expect(ejecucion['pagos'], 650.0);
    expect(ejecucion['saldo_por_comprometer'], 400.0);

    final deuda = reportes['cgn2015_005']!.datos;
    expect(deuda['deuda_interna'], 90.0);
    expect(deuda['deuda_externa'], 40.0);
    expect(deuda['deuda_total'], 130.0);
    expect(deuda['cuota_amortizacion'], 12.0);
    expect(deuda['intereses'], 8.0);
    expect(deuda['servicio_deuda'], 20.0);

    final variaciones = reportes['cgn2016C01']!.datos;
    expect(
      variaciones['formulario'],
      'CGN_2016_01_VARIACIONES_TRIMESTRALES_SIGNIFICATIVAS',
    );
    final detalle = variaciones['variaciones'] as List<dynamic>;
    expect(
      detalle,
      contains(
        predicate<Map<String, dynamic>>(
          (row) =>
              row['cuenta_codigo'] == '1110' &&
              row['saldo_anterior'] == 900.0 &&
              row['saldo_actual'] == 1210.0 &&
              row['variacion'] == 310.0,
        ),
      ),
    );

    final guardados = await db.query('reportes_chip');
    expect(guardados, hasLength(6));
    final recuperado = await service.obtenerReporte(
      reportes['cgn2015_002']!.id,
    );
    expect(recuperado!.datos['resultado_operacional'], 380.0);
  });
}
