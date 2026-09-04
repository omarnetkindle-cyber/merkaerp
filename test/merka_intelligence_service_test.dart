import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/services/merka_intelligence_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late int companyId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merka_intelligence_db_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    if (await dbDir.exists()) {
      await dbDir.delete(recursive: true);
    }
  });

  test('busca producto por codigo y detecta lote por vencer', () async {
    final service = MerkaIntelligenceService();
    final now = DateTime.now();
    final productId = await db.insert('productos', {
      'company_id': companyId,
      'nombre': 'Leche QA',
      'unidad_base': 'unid.',
      'stock': 4,
      'costo': 1000,
      'precio': 2500,
      'impuesto_pct': 0,
      'codigo_barras': 'QA-LECHE-001',
      'referencia': 'REF-LECHE',
      'descripcion': 'Producto de prueba con vencimiento',
      'ubicacion_pasillo': 'P3',
      'ubicacion_estante': 'EB',
      'ubicacion_nivel': 'N2',
      'ubicacion_codigo': 'UBI-P3-EB-N2',
    });
    await db.insert('lotes', {
      'company_id': companyId,
      'producto_id': productId,
      'codigo_lote': 'L-QA-1',
      'fecha_vencimiento': now.add(const Duration(days: 7)).toIso8601String(),
      'cantidad': 4,
      'costo': 1000,
      'created_at': now.toIso8601String(),
    });

    final lookup = await service.findProduct('QA-LECHE-001');
    expect(lookup, isNotNull);
    expect(lookup!.location, 'UBI-P3-EB-N2');
    expect(lookup.lot?['codigo_lote'], 'L-QA-1');

    final alerts = await service.operationalAlerts();
    expect(alerts.any((alert) => alert.kind == 'expiring_product'), isTrue);

    final reply = await service.answer('productos criticos');
    expect(reply.intent, 'critical_stock');
    expect(reply.response, contains('Leche QA'));
  });
}
