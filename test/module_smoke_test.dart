import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/activos_fijos_page.dart';
import 'package:merka_erp/adjuntos_page.dart';
import 'package:merka_erp/app_session.dart';
import 'package:merka_erp/auditoria_page.dart';
import 'package:merka_erp/caja_page.dart';
import 'package:merka_erp/cierres_caja_page.dart';
import 'package:merka_erp/clientes_page.dart';
import 'package:merka_erp/compras_page.dart';
import 'package:merka_erp/comprobantes_page.dart';
import 'package:merka_erp/conciliacion_bancaria_page.dart';
import 'package:merka_erp/configuracion_page.dart';
import 'package:merka_erp/contabilidad_page.dart';
import 'package:merka_erp/cuentas_por_cobrar_page.dart';
import 'package:merka_erp/cuentas_por_pagar_page.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/empresas_page.dart';
import 'package:merka_erp/erp_readiness_page.dart';
import 'package:merka_erp/estados_financieros_page.dart';
import 'package:merka_erp/extractos_bancarios_page.dart';
import 'package:merka_erp/facturacion_electronica_page.dart';
import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/features/module_definition.dart';
import 'package:merka_erp/core/workspace/public_sector_config.dart';
import 'package:merka_erp/core/workspace/workspace_config.dart';
import 'package:merka_erp/inventario_page.dart';
import 'package:merka_erp/manual_page.dart';
import 'package:merka_erp/nomina_page.dart';
import 'package:merka_erp/periodos_contables_page.dart';
import 'package:merka_erp/presupuestos_page.dart';
import 'package:merka_erp/proveedores_page.dart';
import 'package:merka_erp/recibos_page.dart';
import 'package:merka_erp/reportes_fiscales_page.dart';
import 'package:merka_erp/reportes_page.dart';
import 'package:merka_erp/respaldos_page.dart';
import 'package:merka_erp/ui/enterprise_design_system.dart';
import 'package:merka_erp/usuarios_page.dart';
import 'package:merka_erp/ventas_page.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/services/licencia_service.dart';
import 'package:merka_erp/services/license_secure_store.dart';

void main() {
  late final Directory dbDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_smoke_db_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    LicenciaService.instance.configureSecureStoreForTests(
      LicenseSecureStore(testKey: 'module-smoke-secure-test-key'),
    );
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await DatabaseHelper.instance.guardarCompanySettings(companyId, {
      'onboarding_completed': '1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
    });
    await SchemaMultiTenant.crearEntidadPublicaDesdeConfiguracion(
      await DatabaseHelper.instance.database,
      companyId: companyId,
      nombreEmpresa: 'Entidad pública de humo',
      nit: 'SMOKE-$companyId',
      subtipoLegado: 'municipio',
    );
  });

  tearDownAll(() async {
    CompanyConfigurationService.instance.resetForTests();
    await DatabaseHelper.resetForTests();
  });

  testWidgets('todos los modulos principales abren sin excepciones', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DatabaseHelper.disableAutoLoadsForTests = true;
    addTearDown(() => DatabaseHelper.disableAutoLoadsForTests = false);
    AppSession.iniciar({
      'nombre': 'Administrador',
      'usuario': 'admin',
      'rol': 'administrador',
    });
    addTearDown(AppSession.cerrar);

    final modules = <_SmokeModule>[
      _SmokeModule('Caja y bancos', () => const CajaPage()),
      _SmokeModule('Ventas', () => const VentasPage()),
      _SmokeModule('Compras', () => const ComprasPage()),
      _SmokeModule('Inventario', () => const InventarioPage()),
      _SmokeModule('Clientes', () => const ClientesPage()),
      _SmokeModule('Proveedores', () => const ProveedoresPage()),
      _SmokeModule('Contabilidad', () => const ContabilidadPage()),
      _SmokeModule('Cuentas por cobrar', () => const CuentasPorCobrarPage()),
      _SmokeModule('Cuentas por pagar', () => const CuentasPorPagarPage()),
      _SmokeModule('Comprobantes', () => const ComprobantesPage()),
      _SmokeModule('Periodos', () => const PeriodosContablesPage()),
      _SmokeModule('Estados financieros', () => const EstadosFinancierosPage()),
      _SmokeModule('Reportes', () => const ReportesPage()),
      _SmokeModule('Fiscal', () => const ReportesFiscalesPage()),
      _SmokeModule('Conciliacion', () => const ConciliacionBancariaPage()),
      _SmokeModule('Extractos', () => const ExtractosBancariosPage()),
      _SmokeModule('Presupuestos', () => const PresupuestosPage()),
      _SmokeModule('Cierres caja', () => const CierresCajaPage()),
      _SmokeModule('Centro ERP', () => const ErpReadinessPage()),
      _SmokeModule('Manual', () => const ManualPage()),
      _SmokeModule('Empresas', () => const EmpresasPage()),
      _SmokeModule('Facturacion', () => const FacturacionElectronicaPage()),
      _SmokeModule('Recibos', () => const RecibosPage()),
      _SmokeModule('Nomina', () => const NominaPage()),
      _SmokeModule('Activos fijos', () => const ActivosFijosPage()),
      _SmokeModule('Adjuntos', () => const AdjuntosPage()),
      _SmokeModule('Usuarios', () => const UsuariosPage()),
      _SmokeModule('Auditoria', () => const AuditoriaPage()),
      _SmokeModule('Respaldos', () => const RespaldosPage()),
      _SmokeModule('Configuracion', () => const ConfiguracionPage()),
    ];
    final registered = <ModuleDefinition>[
      ...operacion(),
      ...finanzas(),
      ...control(),
      ...gestion(),
      ...modulosPresupuestoPublico(),
      ...modulosContabilidadNICSP(),
      ...modulosContratacionPublica(),
      ...modulosNominaPublica(),
      ...modulosRentas(),
      ...modulosPlaneacion(),
      ...modulosActivosEstado(),
      ...modulosAuditoriaTransparencia(),
      ...modulosConfiguracionEntidad(),
    ];
    final knownTitles = modules.map((module) => module.name).toSet();
    modules.addAll(
      registered
          .where((module) => !knownTitles.contains(module.title))
          .map(
            (module) => _SmokeModule(
              module.title,
              () => Builder(builder: module.builder),
            ),
          ),
    );

    final failures = <String>[];

    for (final module in modules) {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: EnterpriseThemeEngine.theme(),
          home: module.builder(),
        ),
      );
      try {
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(
            module.name == 'Salud y soporte'
                ? const Duration(seconds: 4)
                : const Duration(milliseconds: 250),
          );
        });
        for (var tick = 0; tick < 30; tick++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (!tester.binding.hasScheduledFrame) break;
        }
      } catch (error) {
        failures.add('${module.name}: timeout/error durante settle: $error');
      }
      final exception = tester.takeException();
      if (exception != null) {
        failures.add('${module.name}: $exception');
      }
      final visibleErrors = find.byWidgetPredicate((widget) {
        if (widget is! Text) return false;
        final text = widget.data ?? '';
        return text.contains('SqliteException') ||
            text.contains('DatabaseException') ||
            text.startsWith('Error:');
      });
      if (visibleErrors.evaluate().isNotEmpty) {
        final messages = visibleErrors
            .evaluate()
            .map((element) => (element.widget as Text).data ?? '')
            .toSet()
            .join(' | ');
        failures.add('${module.name}: widget de error visible: $messages');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

class _SmokeModule {
  const _SmokeModule(this.name, this.builder);

  final String name;
  final Widget Function() builder;
}
