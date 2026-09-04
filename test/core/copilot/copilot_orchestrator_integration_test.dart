import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/copilot/copilot_models.dart';
import 'package:merka_erp/core/copilot/copilot_orchestrator.dart';
import 'package:merka_erp/core/copilot/copilot_configuration_service.dart';
import 'package:merka_erp/core/copilot/local_llm_client.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late int companyId;
  late CopilotOrchestrator orchestrator;

  const admin = CopilotIdentity(
    userId: 'USR-ADMIN',
    userName: 'Omar QA',
    role: 'administrador',
    allowedModuleIds: {
      'sales',
      'inventory',
      'receivables',
      'payables',
      'purchases',
    },
  );
  const inventoryOnly = CopilotIdentity(
    userId: 'USR-STOCK',
    userName: 'Bodega QA',
    role: 'consulta',
    allowedModuleIds: {'inventory'},
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('copilot_secure_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    orchestrator = CopilotOrchestrator();
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('v97 crea auditoria atribuible y registra herramienta real', () async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(conversaciones_copilot)',
    );
    final names = columns.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll({
        'usuario_id',
        'tool_id',
        'proveedor',
        'resultado',
        'detalle_error',
        'acciones',
      }),
    );

    await db.insert('ventas', {
      'company_id': companyId,
      'producto': 'Venta Copilot QA',
      'cantidad': 1,
      'precio_unitario': 100000,
      'costo_unitario': 60000,
      'fecha': DateTime.now().toIso8601String(),
      'subtotal': 100000,
      'impuesto_total': 19000,
      'total': 119000,
      'metodo_pago_id': 1,
      'estado': 'emitida',
    });
    final response = await orchestrator.respond(
      prompt: 'ventas hoy',
      identity: admin,
    );
    expect(response.intent, 'sales_today');
    expect(response.text, contains(r'$1.190'));

    final rows = await db.query(
      'conversaciones_copilot',
      orderBy: 'id DESC',
      limit: 1,
    );
    expect(rows.single['usuario'], 'Omar QA');
    expect(rows.single['usuario_id'], 'USR-ADMIN');
    expect(rows.single['tool_id'], 'sales_today');
    expect(rows.single['resultado'], 'exitoso');
  });

  test('configuracion del modelo solo acepta loopback', () async {
    final service = CopilotConfigurationService();
    await service.save(
      LocalLlmConfiguration(
        enabled: true,
        endpoint: Uri.parse('http://127.0.0.1:8080/v1/chat/completions'),
        model: 'modelo-prueba',
      ),
    );
    final loaded = await service.load();
    expect(loaded.enabled, isTrue);
    expect(loaded.model, 'modelo-prueba');

    await expectLater(
      service.save(
        LocalLlmConfiguration(
          enabled: true,
          endpoint: Uri.parse('https://modelo-remoto.example/v1/chat'),
          model: 'prohibido',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    await service.save(
      LocalLlmConfiguration(
        enabled: false,
        endpoint: Uri.parse('http://127.0.0.1:8080/v1/chat/completions'),
        model: 'modelo-prueba',
      ),
    );
  });

  test('deniega ventas sin permiso y no revela el total', () async {
    final response = await orchestrator.respond(
      prompt: 'ventas hoy',
      identity: inventoryOnly,
    );
    expect(response.intent, 'denied_or_failed');
    expect(response.text, contains('permiso'));
    expect(response.text, isNot(contains(r'$1.190')));

    final rows = await db.query(
      'conversaciones_copilot',
      orderBy: 'id DESC',
      limit: 1,
    );
    expect(rows.single['resultado'], 'rechazado');
    expect(rows.single['usuario_id'], 'USR-STOCK');
  });

  test('prepara una venta como propuesta confirmable sin escribirla', () async {
    await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Cafe prueba IA',
      'unidad_base': 'unidad',
      'stock': 8,
      'costo': 5000,
      'precio': 9000,
      'impuesto_pct': 0,
      'codigo_barras': 'IA-CAFE-1',
    });
    final before = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ventas'),
    );
    final response = await orchestrator.respond(
      prompt: 'vender Cafe prueba IA',
      identity: admin,
    );
    final after = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ventas'),
    );

    expect(response.intent, 'prepare_sale');
    expect(response.actions.single.requiresConfirmation, isTrue);
    expect(response.actions.single.kind, CopilotActionKind.prepareSale);
    expect(after, before);

    await orchestrator.auditAction(
      action: response.actions.single,
      identity: admin,
      outcome: 'delegado_modulo',
    );
    final actionAudit = await db.query(
      'conversaciones_copilot',
      where: 'intent = ?',
      whereArgs: ['copilot_action'],
      orderBy: 'id DESC',
      limit: 1,
    );
    expect(actionAudit.single['usuario_id'], 'USR-ADMIN');
    expect(actionAudit.single['resultado'], 'delegado_modulo');
  });

  test('no atribuye lotes legacy sin empresa al tenant activo', () async {
    final productId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Producto tenant',
      'unidad_base': 'unidad',
      'stock': 10,
      'costo': 100,
      'precio': 200,
      'impuesto_pct': 0,
    });
    await db.insert('lotes', {
      'company_id': null,
      'producto_id': productId,
      'codigo_lote': 'LEGACY-SIN-TENANT',
      'fecha_vencimiento': DateTime.now()
          .add(const Duration(days: 2))
          .toIso8601String(),
      'cantidad': 1,
      'costo': 100,
      'created_at': DateTime.now().toIso8601String(),
    });
    final alerts = await orchestrator.authorizedAlerts(admin);
    expect(
      alerts.any((alert) => alert.title.contains('Producto tenant')),
      isFalse,
    );
  });
}
