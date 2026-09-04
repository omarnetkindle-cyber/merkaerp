import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/app_session.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/login_page.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    final dbDir = await Directory.systemTemp.createTemp('merkaerp_login_db_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'login-widget-secure-test-key'),
    );
    await DatabaseHelper.instance.guardarCompanySettings(companyId, {
      'onboarding_completed': '1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
    });
    await LicenciaService.instance.guardarLicencia(
      LicenciaInfo(
        uuid: 'TEST-LICENSE',
        plan: TipoPlan.enterprise,
        estado: EstadoLicencia.activa,
        fechaExpiracion: DateTime.now().add(const Duration(days: 30)),
        modulosHabilitados: const [],
      ),
    );
  });

  testWidgets('muestra login de MerkaERP', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(AppSession.cerrar);

    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('MerkaERP'), findsWidgets);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
  });
}
