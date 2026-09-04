import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/accounting/financial_framework.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dbDir;
  late DatabaseHelper helper;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_niif_block6_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    helper = DatabaseHelper.instance;
    await helper.database;
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
    if (await dbDir.exists()) await dbDir.delete(recursive: true);
  });

  test('v91 crea el grupo NIIF por empresa con fallback defensivo', () async {
    final db = await helper.database;
    final companyId = await helper.obtenerEmpresaActivaId();
    final row = (await db.query(
      'companies',
      columns: ['niif_group'],
      where: 'id = ?',
      whereArgs: [companyId],
    )).single;

    expect(row['niif_group'], 'grupo_2');
    expect(await helper.obtenerGrupoNiif(), FinancialFrameworkGroup.grupo2);
  });

  test(
    'la politica contable cambia visiblemente por grupo configurado',
    () async {
      await helper.configurarGrupoNiif(FinancialFrameworkGroup.grupo1);
      final grupo1 = await helper.obtenerPoliticaMarcoContable();
      expect(grupo1['grupo'], 'grupo_1');
      expect(grupo1['marco'], contains('NIIF plenas'));
      expect(grupo1['perfil_revelacion'], contains('completas'));
      expect(grupo1['politica_deterioro_inventarios'], contains('NIC 36'));

      await helper.configurarGrupoNiif(FinancialFrameworkGroup.grupo3);
      final grupo3 = await helper.obtenerPoliticaMarcoContable();
      expect(grupo3['grupo'], 'grupo_3');
      expect(grupo3['marco'], contains('microempresas'));
      expect(grupo3['perfil_revelacion'], contains('simplificadas'));
      expect(grupo3['politica_deterioro_inventarios'], contains('Anexo 3'));
      expect(grupo1, isNot(equals(grupo3)));
    },
  );
}
