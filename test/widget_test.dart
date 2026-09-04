import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/app_session.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/main.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';
import 'package:merka_erp/ui/enterprise_design_system.dart';

void main() {
  late final Directory dbDir;

  Future<void> pumpUi(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void addUiCleanup(WidgetTester tester) {
    addTearDown(() async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      AppSession.cerrar();
    });
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    DatabaseHelper.disableAutoLoadsForTests = true;
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_widget_db_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'workspace-widget-secure-test-key'),
    );
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await DatabaseHelper.instance.guardarCompanySettings(companyId, {
      'onboarding_completed': '1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
    });
    await CompanyConfigurationService.instance.loadActive(force: true);
  });

  testWidgets('muestra el centro de trabajo de MerkaERP', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppSession.iniciar({
      'nombre': 'Administrador',
      'usuario': null,
      'rol': 'administrador',
    });
    addUiCleanup(tester);

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MenuPrincipal(),
      ),
    );
    await pumpUi(tester);

    expect(find.text('Centro de trabajo contable'), findsOneWidget);
    expect(find.text('Acciones principales'), findsOneWidget);
    expect(find.text('Directorio de areas'), findsNothing);

    Future<void> expectMenuItem(String text) async {
      final finder = find.text(text);
      expect(finder, findsWidgets);
    }

    for (final item in [
      'Caja y bancos',
      'Inventario',
      'Ventas',
      'Compras',
      'Proveedores',
      'Clientes',
    ]) {
      await expectMenuItem(item);
    }

    for (final item in ['Contabilidad', 'Cuentas por cobrar']) {
      await expectMenuItem(item);
    }

    for (final item in [
      'Reportes',
      'Extracto caja',
      'Bancos',
      'Presupuestos',
      'Cierres caja',
    ]) {
      await expectMenuItem(item);
    }

    for (final item in [
      'Recibos',
      'Usuarios',
      'Facturacion',
      'Recursos humanos y nómina',
      'Activos fijos',
      'Adjuntos',
    ]) {
      await expectMenuItem(item);
    }

    expect(find.byTooltip('Exportar XLS'), findsOneWidget);
  });

  testWidgets('workspace enterprise soporta command palette y busqueda', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppSession.iniciar({
      'nombre': 'Administrador',
      'usuario': null,
      'rol': 'administrador',
    });
    addUiCleanup(tester);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: EnterpriseThemeEngine.theme(),
        home: const MenuPrincipal(),
      ),
    );
    await pumpUi(tester);

    await tester.tap(find.byTooltip('Busqueda global'));
    await pumpUi(tester);

    expect(find.text('Command Palette'), findsOneWidget);
    await tester.enterText(
      find.widgetWithIcon(TextField, Icons.manage_search),
      'tesoreria',
    );
    await pumpUi(tester);
    expect(find.textContaining('Caja y bancos'), findsWidgets);
    Navigator.of(tester.element(find.text('Command Palette'))).pop();
    await pumpUi(tester);
  });

  testWidgets('workspace movil conserva acciones, copilot y notificaciones', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppSession.iniciar({
      'nombre': 'Administrador',
      'usuario': null,
      'rol': 'administrador',
    });
    addUiCleanup(tester);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: EnterpriseThemeEngine.theme(),
        home: const MenuPrincipal(),
      ),
    );
    await pumpUi(tester);

    expect(find.byTooltip('Modulos'), findsOneWidget);
    expect(find.byTooltip('ERP Copilot'), findsOneWidget);
    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    expect(find.text('Areas'), findsNothing);

    await tester.tap(find.byTooltip('Modulos'));
    await pumpUi(tester);
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('Compras'), findsWidgets);
    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await pumpUi(tester);

    await tester.tap(find.byTooltip('ERP Copilot'));
    await pumpUi(tester);
    expect(find.text('Copilot MerkaERP'), findsOneWidget);
    Navigator.of(tester.element(find.text('Copilot MerkaERP'))).pop();
    await pumpUi(tester);

    await tester.tap(find.byTooltip('Notificaciones'));
    await pumpUi(tester);
    expect(find.text('Notification Center'), findsOneWidget);
    expect(find.textContaining('Cartera'), findsWidgets);
    Navigator.of(tester.element(find.text('Notification Center'))).pop();
    await pumpUi(tester);
  });

  testWidgets('workspace renderiza en dark high contrast sin overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppSession.iniciar({
      'nombre': 'Administrador',
      'usuario': null,
      'rol': 'administrador',
    });
    addUiCleanup(tester);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: EnterpriseThemeEngine.theme(
          brightness: Brightness.dark,
          highContrast: true,
        ),
        home: const MenuPrincipal(),
      ),
    );
    await pumpUi(tester);

    expect(find.text('Caja y bancos'), findsWidgets);
    expect(find.text('Ventas'), findsWidgets);
    expect(find.byTooltip('Exportar XLS'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
  });
}
