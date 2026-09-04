import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

import 'app_bootstrap.dart';
import 'app_session.dart';
import 'control_center_agent.dart';
import 'db_helper.dart';
import 'exportar_excel.dart';
import 'features/company_configuration_service.dart';
import 'features/module_definition.dart';
import 'login_page.dart';
import 'logo_widget.dart';
import 'onboarding/onboarding_page.dart';
import 'platform/database_bootstrap.dart';
import 'services/api_server.dart';
import 'services/merka_intelligence_service.dart';
import 'services/task_scheduler_service.dart';
import 'services/licencia_service.dart';
import 'licensing/domain/product_family.dart';
import 'licensing_page.dart';
import 'ui/enterprise_design_system.dart';
import 'ui/merka_theme_tokens.dart';
import 'ui/sales_mode_panel.dart';
import 'ui/operations_mode_panel.dart';
import 'ui/finance_mode_panel.dart';
import 'ui/copilot_panel.dart';
import 'sync/data/sqlite_sync_repository.dart';
import 'sync/domain/sync_models.dart';
import 'services/sync_service.dart';
import 'core/logging/logging_service.dart';
import 'core/commands/command_registry.dart';
import 'core/commands/default_contextual_commands.dart';
import 'core/signals/signal_aggregator.dart';
import 'core/signals/signal.dart';
import 'core/features/feature_flag.dart';
import 'core/cache/cache_manager.dart';
import 'core/theme/theme_service.dart';
import 'core/theme/app_theme.dart';
import 'core/dashboard/dashboard_service.dart';
import 'core/accessibility/accessibility_service.dart';
import 'core/startup/startup_flow.dart';
import 'sector_publico/presupuesto/pages/presupuesto_publico_page.dart';

import 'core/workspace/workspace_config.dart';
import 'core/workspace/public_sector_config.dart';
import 'core/workspace/workspace_helpers.dart';
import 'ui/widgets/expandable_record_card.dart';
part 'ui/widgets/workspace_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Debe ocurrir antes de CUALQUIER acceso SQLite.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint('SQLite FFI inicializado para ${Platform.operatingSystem}');
  }

  // Segundo punto de entrada via bootstrap (idempotente, no hace daño).
  await configureLocalDatabaseRuntime();

  await initializeDateFormatting('es_CO');

  // Cargar variables de entorno (.env). isOptional=true para que no falle
  // si el archivo está vacío o no existe (modo offline / sin credenciales API).
  try {
    await dotenv.load(fileName: '.env', mergeWith: {});
  } catch (_) {
    // .env ausente o vacío — los servicios que dependen de claves API
    // operarán en modo local/SQLite sin integración externa.
  }

  final bootstrap = await AppBootstrap.initialize(
    configureDatabase: () async {
      // configureLocalDatabaseRuntime() ya fue llamado al inicio de main()
      // antes de AppBootstrap, así que aquí solo abrimos la base de datos.
      await DatabaseHelper.instance.database;
    },
    preloadTheme: _loadThemePreference,
    startServices: () async {
      try {
        ControlCenterAgent.startBackground();
      } catch (_) {}
      // Inicializar nuevos servicios
      try {
        await LoggingService.instance.initialize();
      } catch (_) {}
      try {
        await FeatureFlagService.instance.initialize();
      } catch (_) {}
      try {
        await CacheManager.instance.initialize();
      } catch (_) {}
      try {
        await ThemeService.instance.initialize();
      } catch (_) {}
      try {
        await DashboardService.instance.initialize();
      } catch (_) {}
      try {
        await AccessibilityService.instance.initialize();
      } catch (_) {}
      try {
        await SyncService.instance.initialize();
      } catch (_) {}

      // Ejecutar tareas programadas al iniciar la aplicación
      try {
        final taskScheduler = TaskSchedulerService();
        final results = await taskScheduler.runPendingTasks();
        final pendingTasks = results
            .where((r) => r.status == 'completed')
            .toList();
        if (pendingTasks.isNotEmpty) {
          debugPrint(
            'Tareas ejecutadas: ${pendingTasks.map((r) => r.taskName).join(', ')}',
          );
        }
      } catch (_) {}
    },
  );

  if (bootstrap.errors.isNotEmpty) {
    debugPrint('Bootstrap warnings: ${bootstrap.errors.join(', ')}');
  }

  if (!bootstrap.ready) {
    runApp(BootstrapFailureApp(errors: bootstrap.errors));
    return;
  }

  CommandRegistry.instance.setAuthorization(_authorizeGlobalCommand);
  CommandRegistry.instance.registerAll(defaultContextualCommands());
  runApp(const MiApp());
}

class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({super.key, required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storage_outlined,
                      size: 56,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'MerkaERP no pudo abrir la base de datos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No se inició el asistente ni se modificaron datos. Cierra la aplicación, conserva el archivo de base y revisa el Centro de soporte antes de restaurar.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      errors.join('\n'),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _authorizeGlobalCommand(
  CommandDefinition command,
  CommandContext context,
) {
  final action = command.requiredAction;
  if (action == null) return true;
  return AppSession.puedeEjecutarAccion(
    command.permissionModuleId ?? command.moduleId,
    action,
  );
}

final ValueNotifier<ThemeMode> merkaThemeMode = ValueNotifier(ThemeMode.system);

Future<void> _loadThemePreference() async {
  try {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'preferencias_usuario',
      where: 'clave = ?',
      whereArgs: ['theme_mode'],
      orderBy: 'actualizado_en DESC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    final value = rows.first['valor']?.toString();
    if (value == 'dark') merkaThemeMode.value = ThemeMode.dark;
    if (value == 'light') merkaThemeMode.value = ThemeMode.light;
  } catch (_) {
    merkaThemeMode.value = ThemeMode.system;
  }
}

class MiApp extends StatelessWidget {
  const MiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: merkaThemeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: ControlCenterAgent.navigatorKey,
          debugShowCheckedModeBanner: false,
          title: AppBrand.name,
          theme: _merkaTheme(),
          darkTheme: _merkaTheme(brightness: Brightness.dark),
          highContrastTheme: _merkaTheme(highContrast: true),
          highContrastDarkTheme: _merkaTheme(
            brightness: Brightness.dark,
            highContrast: true,
          ),
          themeMode: mode,
          builder: (context, child) =>
              CommandPaletteHost(child: child ?? const SizedBox.shrink()),
          home: const LicenseCheckWrapper(),
        );
      },
    );
  }
}

class LicenseCheckWrapper extends StatefulWidget {
  const LicenseCheckWrapper({super.key});

  @override
  State<LicenseCheckWrapper> createState() => _LicenseCheckWrapperState();
}

class _LicenseCheckWrapperState extends State<LicenseCheckWrapper> {
  late Future<StartupRoute> _startupFuture;

  @override
  void initState() {
    super.initState();
    _startupFuture = _checkStartup();
  }

  void _reload() {
    setState(() {
      _startupFuture = _checkStartup();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StartupRoute>(
      future: _startupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 52,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No fue posible validar la instalación',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Por seguridad no se abrirá el onboarding ni se sobrescribirá la configuración existente.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          snapshot.error.toString(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final state = snapshot.data ?? StartupRoute.needsOnboarding;

        switch (state) {
          case StartupRoute.needsOnboarding:
            return OnboardingPage(onFinished: _reload);
          case StartupRoute.needsLicense:
            return LicensingPage(onActivated: _reload);
          case StartupRoute.login:
            return const LoginPage();
        }
      },
    );
  }

  Future<StartupRoute> _checkStartup() async {
    try {
      return await StartupFlow.resolve(
        licenseIsValid: () async {
          final license = await LicenciaService.instance.obtenerLicencia();
          return license?.esValida == true;
        },
        needsOnboarding: CompanyConfigurationService.instance.needsOnboarding,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError(
          'No fue posible determinar el estado de la instalación: $error',
        ),
        stackTrace,
      );
    }
  }
}

ThemeData _merkaTheme({
  Brightness brightness = Brightness.light,
  bool highContrast = false,
}) {
  return EnterpriseThemeEngine.theme(
    brightness: brightness,
    highContrast: highContrast,
  );
}

class MenuPrincipal extends StatefulWidget {
  const MenuPrincipal({super.key});

  @override
  State<MenuPrincipal> createState() => _MenuPrincipalState();
}

class _MenuPrincipalState extends State<MenuPrincipal> {
  late Future<void> _configurationFuture;
  final _globalSearchController = TextEditingController();
  final Set<String> _favoriteModuleIds = {
    'erp_readiness',
    'sales',
    'purchases',
  };
  final List<String> _recentModuleIds = [];
  bool _sidebarCollapsed = false;
  _WorkspaceMode _workspaceMode = _WorkspaceMode.dashboard;

  @override
  void initState() {
    super.initState();
    // Las pantallas de configuración mantienen la caché sincronizada. Reusar
    // aquí su valor evita repetir toda la conciliación/siembra de la empresa
    // al volver al menú y elimina carreras con otras cargas de inicio.
    _configurationFuture = CompanyConfigurationService.instance.loadActive();
    // La API local solo se expone después de una sesión autenticada y si la
    // empresa la habilitó explícitamente.
    unawaited(_startLocalApiIfEnabled());
  }

  Future<void> _startLocalApiIfEnabled() async {
    try {
      final api = ApiServer.instance;
      if (!await api.estaHabilitado()) return;
      await api.iniciar(port: await api.obtenerPuerto());
    } catch (error) {
      debugPrint('No fue posible iniciar la API local: $error');
    }
  }

  @override
  void dispose() {
    _globalSearchController.dispose();
    super.dispose();
  }

  /// Wrapper para exponer setState() al part file (workspace_widgets.dart) sin
  /// triggers de invalid_use_of_protected_member. El part accede a campos
  /// privados de State sin problemas, pero setState() requiere este wrapper
  /// porque es un miembro protegido (solo instancias de State pueden usarlo).
  void _updateState(VoidCallback fn) {
    setState(fn);
  }

  void _toggleFavorite(String moduleId) {
    setState(() {
      if (_favoriteModuleIds.contains(moduleId)) {
        _favoriteModuleIds.remove(moduleId);
      } else {
        _favoriteModuleIds.add(moduleId);
      }
    });
  }

  Future<void> _toggleTheme() async {
    final next = merkaThemeMode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    merkaThemeMode.value = next;
    // Persistir la preferencia (la lógica de persistencia fue extraída a workspace_helpers.dart)
    await persistThemePreference(next == ThemeMode.dark ? 'dark' : 'light');
  }

  void _openModule(BuildContext context, ModuleDefinition module) {
    if (!AppSession.puedeAbrirModulo(module)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No tienes acceso a ${module.title}.')),
      );
      return;
    }
    setState(() {
      _recentModuleIds.remove(module.id);
      _recentModuleIds.insert(0, module.id);
      if (_recentModuleIds.length > 8) {
        _recentModuleIds.removeLast();
      }
    });
    Navigator.push(context, MaterialPageRoute(builder: module.builder));
  }

  void _showCommandPalette(
    BuildContext context,
    List<ModuleDefinition> modules,
  ) {
    showCommandPalette(context);
  }

  Future<void> _showNotificationCenter(
    BuildContext context,
    List<ModuleDefinition> modules,
  ) async {
    await _showNotificationCenterSheet(this, context, modules);
  }

  void _showCopilot(BuildContext context, List<ModuleDefinition> modules) {
    _showCopilotDialog(this, context, modules);
  }

  void _showMobileQuickActions(
    BuildContext context,
    List<ModuleDefinition> modules,
  ) {
    _showMobileQuickActionsSheet(this, context, modules);
  }

  Widget _buildCentroTrabajo(BuildContext context) {
    return _buildWorkspaceCenter(this, context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _configurationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          // Si hay error en la configuración, mostrar el menú de todos modos
          debugPrint('Error loading configuration: ${snapshot.error}');
          return _buildCentroTrabajo(context);
        }

        final config = CompanyConfigurationService.instance.cached;
        if (config?.onboardingCompleted == false) {
          return OnboardingPage(
            onFinished: () {
              setState(() {
                _configurationFuture = CompanyConfigurationService.instance
                    .loadActive(force: true);
              });
            },
          );
        }
        return _buildCentroTrabajo(context);
      },
    );
  }
}
