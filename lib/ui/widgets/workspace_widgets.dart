part of '../../main.dart';

class _WorkspaceSection {
  const _WorkspaceSection({
    required this.label,
    required this.icon,
    required this.modules,
  });

  final String label;
  final IconData icon;
  final List<ModuleDefinition> modules;
}

List<_WorkspaceSection> _seccionesSectorPublico(_MenuPrincipalState state) {
  return [
    _WorkspaceSection(
      label: 'Presupuesto Público',
      icon: Icons.account_balance,
      modules: visible(modulosPresupuestoPublico()),
    ),
    _WorkspaceSection(
      label: 'Contabilidad NICSP',
      icon: Icons.receipt_long,
      modules: visible(modulosContabilidadNICSP()),
    ),
    _WorkspaceSection(
      label: 'Contratación Pública',
      icon: Icons.gavel,
      modules: visible(modulosContratacionPublica()),
    ),
    _WorkspaceSection(
      label: 'Nómina Pública',
      icon: Icons.badge,
      modules: visible(modulosNominaPublica()),
    ),
    _WorkspaceSection(
      label: 'Rentas',
      icon: Icons.attach_money,
      modules: visible(modulosRentas()),
    ),
    _WorkspaceSection(
      label: 'Planeación',
      icon: Icons.map,
      modules: visible(modulosPlaneacion()),
    ),
    _WorkspaceSection(
      label: 'Regalías y Transferencias',
      icon: Icons.savings_outlined,
      modules: visible(modulosRegaliasYTransferencias()),
    ),
    _WorkspaceSection(
      label: 'Salud Pública',
      icon: Icons.local_hospital_outlined,
      modules: visible(modulosSaludPublica()),
    ),
    _WorkspaceSection(
      label: 'Activos del Estado',
      icon: Icons.factory,
      modules: visible(modulosActivosEstado()),
    ),
    _WorkspaceSection(
      label: 'Auditoría y Transparencia',
      icon: Icons.security,
      modules: visible(modulosAuditoriaTransparencia()),
    ),
    _WorkspaceSection(
      label: 'Gestión Documental',
      icon: Icons.folder_copy_outlined,
      modules: visible(modulosGestionDocumentalPublica()),
    ),
    _WorkspaceSection(
      label: 'Configuración',
      icon: Icons.settings,
      modules: visible(modulosConfiguracionEntidad()),
    ),
  ];
}

// Moved from _MenuPrincipalState in main.dart (Bloque 4d.3).
List<ModuleDefinition> _allModules(List<_WorkspaceSection> sections) {
  return sections.expand((section) => section.modules).toList();
}

// Moved from _MenuPrincipalState in main.dart (Bloque 4d.3).
List<_WorkspaceSection> _filterSections(
  _MenuPrincipalState state,
  List<_WorkspaceSection> sections,
) {
  final query = state._globalSearchController.text.toLowerCase().trim();
  if (query.isEmpty) return sections;
  return [
    for (final section in sections)
      _WorkspaceSection(
        label: section.label,
        icon: section.icon,
        modules: section.modules.where((module) {
          final haystack =
              '${module.title} ${module.id} ${_moduleSubtitle(module.id)} ${section.label}'
                  .toLowerCase();
          return haystack.contains(query);
        }).toList(),
      ),
  ];
}

enum _WorkspaceMode {
  dashboard,
  sales,
  operations,
  finance,
  publicBudget,
  publicCompliance,
  publicTransparency,
}

Future<String> _obtenerTipoEntidad() async {
  final licencia = await LicenciaService.instance.obtenerLicencia();
  final family = licencia?.productFamily ?? ProductFamily.commercial;
  if (family == ProductFamily.publicSector) {
    try {
      await AppSession.cargarRolSectorPublico();
    } catch (e) {
      debugPrint('No se pudo cargar rol publico: $e');
    }
    return 'publica';
  }
  return 'privada';
}

Widget _buildWorkspaceCenter(_MenuPrincipalState state, BuildContext context) {
  return FutureBuilder<String>(
    future: _obtenerTipoEntidad(),
    builder: (context, snapshot) {
      final tipoEntidad = snapshot.data ?? 'privada';

      List<_WorkspaceSection> baseSections;

      if (tipoEntidad == 'publica') {
        // Mostrar módulos del sector público
        baseSections = _seccionesSectorPublico(state);
      } else {
        // Mostrar módulos privados (default)
        baseSections = [
          _WorkspaceSection(
            label: 'Operacion',
            icon: Icons.storefront,
            modules: visible(operacion()),
          ),
          _WorkspaceSection(
            label: 'Finanzas',
            icon: Icons.account_balance,
            modules: visible(finanzas()),
          ),
          _WorkspaceSection(
            label: 'Control',
            icon: Icons.query_stats,
            modules: visible(control()),
          ),
          _WorkspaceSection(
            label: 'Gestion',
            icon: Icons.tune,
            modules: visible(gestion()),
          ),
        ];
      }

      final sections = _filterSections(state, baseSections);
      final allModules = _allModules(baseSections);
      final favoriteModules = modulesByIds(
        allModules,
        state._favoriteModuleIds,
      );
      final recentModules = modulesByIds(allModules, state._recentModuleIds);
      void commandPalette() => state._showCommandPalette(context, allModules);
      void copilot() => state._showCopilot(context, allModules);
      void notifications() =>
          state._showNotificationCenter(context, allModules);

      CommandRegistry.instance.registerModuleCommands(
        allModules,
        authorize: AppSession.puedeAbrirModulo,
        onOpen: (commandContext, module) =>
            state._openModule(commandContext, module),
      );

      return Focus(
        autofocus: true,
        child: DefaultTabController(
          length: sections.length,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = EnterpriseBreakpoints.fromWidth(
                constraints.maxWidth,
              );
              final mobile = viewport.isMobile;

              return Scaffold(
                drawer: mobile
                    ? _MobileModuleDrawer(
                        sections: baseSections,
                        favoriteIds: state._favoriteModuleIds,
                        onToggleFavorite: state._toggleFavorite,
                        onOpen: (module) => state._openModule(context, module),
                        onLogout: () {
                          AppSession.cerrar();
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          );
                        },
                      )
                    : null,
                appBar: AppBar(
                  title: mobile
                      ? const Text(AppBrand.name)
                      : const MerkaBrandHeader(compact: true),
                  actions: [
                    IconButton(
                      tooltip: 'Busqueda global',
                      onPressed: commandPalette,
                      icon: const Icon(Icons.search),
                    ),
                    IconButton(
                      tooltip: 'ERP Copilot',
                      onPressed: copilot,
                      icon: const Icon(Icons.auto_awesome),
                    ),
                    IconButton(
                      tooltip: 'Notificaciones',
                      onPressed: notifications,
                      icon: const Icon(Icons.notifications_none),
                    ),
                    IconButton(
                      tooltip: 'Modo oscuro',
                      onPressed: state._toggleTheme,
                      icon: Icon(
                        merkaThemeMode.value == ThemeMode.dark
                            ? PhosphorIcons.sun()
                            : PhosphorIcons.moon(),
                      ),
                    ),
                    if (!mobile)
                      IconButton.filledTonal(
                        tooltip: 'Exportar XLS',
                        onPressed: () => ExportarExcel.exportar(context),
                        icon: const Icon(Icons.table_chart),
                      ),
                    const SizedBox(width: 6),
                    if (!mobile)
                      IconButton(
                        tooltip: 'Cerrar sesion',
                        onPressed: () {
                          AppSession.cerrar();
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.logout),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
                floatingActionButton: mobile
                    ? FloatingActionButton.extended(
                        tooltip: 'Accion rapida',
                        onPressed: () =>
                            state._showMobileQuickActions(context, allModules),
                        icon: const Icon(Icons.bolt),
                        label: const Text('Acciones'),
                      )
                    : null,
                body: SafeArea(
                  child: Row(
                    children: [
                      if (viewport.isDesktop)
                        _EnterpriseSidebar(
                          sections: baseSections,
                          collapsed: state._sidebarCollapsed,
                          onToggleCollapsed: () {
                            state._updateState(() {
                              state._sidebarCollapsed =
                                  !state._sidebarCollapsed;
                            });
                          },
                          onOpen: (module) =>
                              state._openModule(context, module),
                        ),
                      Expanded(
                        child: _WorkspaceBody(
                          sections: sections,
                          favoriteModules: favoriteModules,
                          recentModules: recentModules,
                          tipoEntidad: tipoEntidad,
                          viewport: viewport,
                          mode: state._workspaceMode,
                          onModeChanged: (mode) {
                            state._updateState(
                              () => state._workspaceMode = mode,
                            );
                          },
                          searchController: state._globalSearchController,
                          onSearchChanged: (_) => state._updateState(() {}),
                          onOpen: (module) =>
                              state._openModule(context, module),
                          onToggleFavorite: state._toggleFavorite,
                          favoriteIds: state._favoriteModuleIds,
                          onCommandPalette: commandPalette,
                          onCopilot: copilot,
                          onNotifications: notifications,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.sections,
    required this.favoriteModules,
    required this.recentModules,
    required this.tipoEntidad,
    required this.viewport,
    required this.mode,
    required this.onModeChanged,
    required this.searchController,
    required this.onSearchChanged,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.favoriteIds,
    required this.onCommandPalette,
    required this.onCopilot,
    required this.onNotifications,
  });

  final List<_WorkspaceSection> sections;
  final List<ModuleDefinition> favoriteModules;
  final List<ModuleDefinition> recentModules;
  final String tipoEntidad;
  final EnterpriseViewport viewport;
  final _WorkspaceMode mode;
  final ValueChanged<_WorkspaceMode> onModeChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ModuleDefinition> onOpen;
  final ValueChanged<String> onToggleFavorite;
  final Set<String> favoriteIds;
  final VoidCallback onCommandPalette;
  final VoidCallback onCopilot;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    if (viewport.isMobile) {
      return _MobileWorkspace(
        sections: sections,
        favoriteModules: favoriteModules,
        recentModules: recentModules,
        searchController: searchController,
        onSearchChanged: onSearchChanged,
        onOpen: onOpen,
        onToggleFavorite: onToggleFavorite,
        favoriteIds: favoriteIds,
        onCommandPalette: onCommandPalette,
        onCopilot: onCopilot,
        onNotifications: onNotifications,
      );
    }

    return _DesktopWorkspace(
      sections: sections,
      favoriteModules: favoriteModules,
      recentModules: recentModules,
      tipoEntidad: tipoEntidad,
      viewport: viewport,
      mode: mode,
      onModeChanged: onModeChanged,
      searchController: searchController,
      onSearchChanged: onSearchChanged,
      onOpen: onOpen,
      onToggleFavorite: onToggleFavorite,
      favoriteIds: favoriteIds,
      onCommandPalette: onCommandPalette,
      onCopilot: onCopilot,
      onNotifications: onNotifications,
    );
  }
}

class _DesktopWorkspace extends StatelessWidget {
  const _DesktopWorkspace({
    required this.sections,
    required this.favoriteModules,
    required this.recentModules,
    required this.tipoEntidad,
    required this.viewport,
    required this.mode,
    required this.onModeChanged,
    required this.searchController,
    required this.onSearchChanged,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.favoriteIds,
    required this.onCommandPalette,
    required this.onCopilot,
    required this.onNotifications,
  });

  final List<_WorkspaceSection> sections;
  final List<ModuleDefinition> favoriteModules;
  final List<ModuleDefinition> recentModules;
  final String tipoEntidad;
  final EnterpriseViewport viewport;
  final _WorkspaceMode mode;
  final ValueChanged<_WorkspaceMode> onModeChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ModuleDefinition> onOpen;
  final ValueChanged<String> onToggleFavorite;
  final Set<String> favoriteIds;
  final VoidCallback onCommandPalette;
  final VoidCallback onCopilot;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final padding = viewport == EnterpriseViewport.ultraWide ? 24.0 : 16.0;
    final query = searchController.text.trim();
    final modules = sections.expand((section) => section.modules).toList();
    final searchResults = query.isEmpty
        ? const <ModuleDefinition>[]
        : modules.where((module) {
            final haystack =
                '${module.title} ${module.id} ${_moduleSubtitle(module.id)}'
                    .toLowerCase();
            return haystack.contains(query.toLowerCase());
          }).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 10, padding, 12),
      child: Column(
        children: [
          _EnterpriseTopBar(
            searchController: searchController,
            tipoEntidad: tipoEntidad,
            mode: mode,
            onModeChanged: onModeChanged,
            favoriteModules: favoriteModules,
            recentModules: recentModules,
            onSearchChanged: onSearchChanged,
            onOpen: onOpen,
            onCommandPalette: onCommandPalette,
            onCopilot: onCopilot,
            onNotifications: onNotifications,
          ),
          const SizedBox(height: EnterpriseSpacing.md),
          Expanded(
            child: query.isNotEmpty
                ? _DesktopSearchResults(
                    query: query,
                    modules: searchResults,
                    favoriteIds: favoriteIds,
                    onOpen: onOpen,
                    onToggleFavorite: onToggleFavorite,
                    onCommandPalette: onCommandPalette,
                  )
                : _ModeWorkspace(
                    mode: mode,
                    tipoEntidad: tipoEntidad,
                    modules: modules,
                    onOpen: onOpen,
                    onCommandPalette: onCommandPalette,
                    onCopilot: onCopilot,
                    onNotifications: onNotifications,
                  ),
          ),
          const SizedBox(height: EnterpriseSpacing.xs),
          Text(
            '${AppBrand.name} v1.0 - escritorio contable',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MobileWorkspace extends StatelessWidget {
  const _MobileWorkspace({
    required this.sections,
    required this.favoriteModules,
    required this.recentModules,
    required this.searchController,
    required this.onSearchChanged,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.favoriteIds,
    required this.onCommandPalette,
    required this.onCopilot,
    required this.onNotifications,
  });

  final List<_WorkspaceSection> sections;
  final List<ModuleDefinition> favoriteModules;
  final List<ModuleDefinition> recentModules;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ModuleDefinition> onOpen;
  final ValueChanged<String> onToggleFavorite;
  final Set<String> favoriteIds;
  final VoidCallback onCommandPalette;
  final VoidCallback onCopilot;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim();
    final resultModules = sections
        .expand((section) => section.modules)
        .take(query.isEmpty ? 0 : 12)
        .toList();
    final primaryModules = favoriteModules.isNotEmpty
        ? favoriteModules.take(4).toList()
        : sections.expand((section) => section.modules).take(4).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      children: [
        _MobileWorkspaceHero(
          onOpenDrawer: () => Scaffold.of(context).openDrawer(),
        ),
        const SizedBox(height: EnterpriseSpacing.md),
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar cliente, compra, venta o reporte',
            suffixIcon: query.isEmpty
                ? IconButton(
                    tooltip: 'Command Palette',
                    onPressed: onCommandPalette,
                    icon: const Icon(Icons.keyboard_command_key),
                  )
                : IconButton(
                    tooltip: 'Limpiar busqueda',
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: EnterpriseSpacing.md),
        if (query.isNotEmpty) ...[
          const _SectionHeading(label: 'Resultados', icon: Icons.manage_search),
          const SizedBox(height: EnterpriseSpacing.sm),
          if (resultModules.isEmpty)
            const _ShellEmptyState(
              icon: Icons.search_off,
              title: 'Sin resultados',
              detail: 'Prueba con ventas, compras, cartera o reportes.',
            )
          else
            for (final module in resultModules)
              Padding(
                padding: const EdgeInsets.only(bottom: EnterpriseSpacing.sm),
                child: _MobileModuleCard(
                  module: module,
                  favorite: favoriteIds.contains(module.id),
                  onTap: () => onOpen(module),
                  onFavorite: () => onToggleFavorite(module.id),
                ),
              ),
        ] else ...[
          _MobileActionGrid(
            onCommandPalette: onCommandPalette,
            onCopilot: onCopilot,
            onNotifications: onNotifications,
            onOpenModules: () => Scaffold.of(context).openDrawer(),
          ),
          const SizedBox(height: EnterpriseSpacing.lg),
          const _SectionHeading(label: 'Favoritos', icon: Icons.star),
          const SizedBox(height: EnterpriseSpacing.sm),
          for (final module in primaryModules)
            Padding(
              padding: const EdgeInsets.only(bottom: EnterpriseSpacing.sm),
              child: _MobileModuleCard(
                module: module,
                favorite: favoriteIds.contains(module.id),
                onTap: () => onOpen(module),
                onFavorite: () => onToggleFavorite(module.id),
              ),
            ),
          if (recentModules.isNotEmpty) ...[
            const SizedBox(height: EnterpriseSpacing.md),
            const _SectionHeading(label: 'Recientes', icon: Icons.history),
            const SizedBox(height: EnterpriseSpacing.sm),
            for (final module in recentModules.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: EnterpriseSpacing.sm),
                child: _MobileModuleCard(
                  module: module,
                  favorite: favoriteIds.contains(module.id),
                  onTap: () => onOpen(module),
                  onFavorite: () => onToggleFavorite(module.id),
                ),
              ),
          ],
          const SizedBox(height: EnterpriseSpacing.md),
          _MobileAttentionPanel(
            onNotifications: onNotifications,
            onCopilot: onCopilot,
          ),
        ],
      ],
    );
  }
}

class _MobileWorkspaceHero extends StatelessWidget {
  const _MobileWorkspaceHero({required this.onOpenDrawer});

  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final company = CompanyConfigurationService.instance.cached?.companyName;
    return EnterprisePanel(
      padding: const EdgeInsets.all(EnterpriseSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MerkaLogo(size: 34),
              const SizedBox(width: EnterpriseSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hola, ${AppSession.nombre}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      company ?? 'Tenant local',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Modulos',
                onPressed: onOpenDrawer,
                icon: const Icon(Icons.menu_open),
              ),
            ],
          ),
          const SizedBox(height: EnterpriseSpacing.md),
          Wrap(
            spacing: EnterpriseSpacing.sm,
            runSpacing: EnterpriseSpacing.sm,
            children: [
              EnterpriseStatusPill(
                icon: Icons.approval,
                label: 'Aprobaciones',
                color: AppBrand.warning,
              ),
              EnterpriseStatusPill(
                icon: Icons.sync,
                label: 'Sync local',
                color: AppBrand.success,
              ),
              EnterpriseStatusPill(
                icon: Icons.auto_awesome,
                label: 'Copilot listo',
                color: AppBrand.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileActionGrid extends StatelessWidget {
  const _MobileActionGrid({
    required this.onCommandPalette,
    required this.onCopilot,
    required this.onNotifications,
    required this.onOpenModules,
  });

  final VoidCallback onCommandPalette;
  final VoidCallback onCopilot;
  final VoidCallback onNotifications;
  final VoidCallback onOpenModules;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: EnterpriseSpacing.sm,
      mainAxisSpacing: EnterpriseSpacing.sm,
      childAspectRatio: 1.72,
      children: [
        _MobileActionButton(
          icon: Icons.search,
          label: 'Buscar',
          color: AppBrand.secondary,
          onTap: onCommandPalette,
        ),
        _MobileActionButton(
          icon: Icons.auto_awesome,
          label: 'Copilot',
          color: AppBrand.accent,
          onTap: onCopilot,
        ),
        _MobileActionButton(
          icon: Icons.notifications_none,
          label: 'Alertas',
          color: AppBrand.warning,
          onTap: onNotifications,
        ),
        _MobileActionButton(
          icon: Icons.apps,
          label: 'Modulos',
          color: AppBrand.success,
          onTap: onOpenModules,
        ),
      ],
    );
  }
}

class _MobileActionButton extends StatelessWidget {
  const _MobileActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(EnterpriseSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: EnterpriseSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileAttentionPanel extends StatelessWidget {
  const _MobileAttentionPanel({
    required this.onNotifications,
    required this.onCopilot,
  });

  final VoidCallback onNotifications;
  final VoidCallback onCopilot;

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      padding: const EdgeInsets.all(EnterpriseSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Para revisar hoy',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: EnterpriseSpacing.sm),
          _MobileQuickActionTile(
            icon: Icons.schedule,
            color: AppBrand.warning,
            title: 'Vencimientos y aprobaciones',
            detail: 'Pagos, cartera, impuestos y escalaciones.',
            onTap: onNotifications,
          ),
          _MobileQuickActionTile(
            icon: Icons.insights,
            color: AppBrand.info,
            title: 'Pedir resumen operativo',
            detail: 'Copilot puede resumir flujo de caja y pendientes.',
            onTap: onCopilot,
          ),
        ],
      ),
    );
  }
}

class _MobileQuickActionTile extends StatelessWidget {
  const _MobileQuickActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EnterpriseSpacing.sm),
      child: Material(
        color: color.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.24)),
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _AccountingCommandCenter extends StatelessWidget {
  const _AccountingCommandCenter({
    required this.modules,
    required this.onOpen,
    required this.onCommandPalette,
    required this.onCopilot,
  });

  final List<ModuleDefinition> modules;
  final ValueChanged<ModuleDefinition> onOpen;
  final VoidCallback onCommandPalette;
  final VoidCallback onCopilot;

  ModuleDefinition? _find(String id) {
    for (final module in modules) {
      if (module.id == id) return module;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final company = CompanyConfigurationService.instance.cached?.companyName;
    return EnterprisePanel(
      padding: const EdgeInsets.all(EnterpriseSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centro de trabajo contable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: EnterpriseSpacing.xs),
                    Text(
                      '${company ?? 'Tenant local'} - sesion ${AppSession.nombre}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onCommandPalette,
                icon: const Icon(Icons.keyboard_command_key),
                label: const Text('Comando'),
              ),
              const SizedBox(width: EnterpriseSpacing.sm),
              IconButton.filledTonal(
                tooltip: 'Copilot',
                onPressed: onCopilot,
                icon: const Icon(Icons.auto_awesome),
              ),
            ],
          ),
          const SizedBox(height: EnterpriseSpacing.md),
          Text(
            'Acciones principales',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: EnterpriseSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final itemWidth = width >= 900
                  ? (width - 32) / 5
                  : width >= 620
                  ? (width - 16) / 3
                  : width;
              final workflows = <_DesktopWorkflow>[
                _DesktopWorkflow(
                  title: 'Vender',
                  detail: 'Factura, POS y cartera',
                  icon: Icons.point_of_sale,
                  color: AppBrand.secondary,
                  module: _find('sales'),
                ),
                _DesktopWorkflow(
                  title: 'Comprar',
                  detail: 'Orden, recepcion y AP',
                  icon: Icons.shopping_bag,
                  color: AppBrand.success,
                  module: _find('purchases'),
                ),
                _DesktopWorkflow(
                  title: 'Cobrar',
                  detail: 'Aplicar pagos y aging',
                  icon: Icons.request_quote,
                  color: AppBrand.info,
                  module: _find('receivables'),
                ),
                _DesktopWorkflow(
                  title: 'Pagar',
                  detail: 'Agenda y tesoreria',
                  icon: Icons.payments,
                  color: AppBrand.warning,
                  module: _find('payables'),
                ),
                _DesktopWorkflow(
                  title: 'Reportar',
                  detail: 'BI, fiscal y exportes',
                  icon: Icons.bar_chart,
                  color: MerkaThemeTokens.gold400,
                  module: _find('reports'),
                ),
              ];
              return Wrap(
                spacing: EnterpriseSpacing.sm,
                runSpacing: EnterpriseSpacing.sm,
                children: [
                  for (final workflow in workflows)
                    SizedBox(
                      width: itemWidth,
                      child: _DesktopWorkflowButton(
                        workflow: workflow,
                        onOpen: onOpen,
                        onFallback: onCommandPalette,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DesktopWorkflow {
  const _DesktopWorkflow({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.module,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final ModuleDefinition? module;
}

class _DesktopWorkflowButton extends StatelessWidget {
  const _DesktopWorkflowButton({
    required this.workflow,
    required this.onOpen,
    required this.onFallback,
  });

  final _DesktopWorkflow workflow;
  final ValueChanged<ModuleDefinition> onOpen;
  final VoidCallback onFallback;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.42),
        ),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        onTap: () {
          final module = workflow.module;
          if (module == null) {
            onFallback();
          } else {
            onOpen(module);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(EnterpriseSpacing.md),
          child: Row(
            children: [
              Icon(workflow.icon, color: workflow.color, size: 22),
              const SizedBox(width: EnterpriseSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workflow.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      workflow.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _DesktopModuleDirectory extends StatelessWidget {
  const _DesktopModuleDirectory({
    required this.sections,
    required this.favoriteIds,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final List<_WorkspaceSection> sections;
  final Set<String> favoriteIds;
  final ValueChanged<ModuleDefinition> onOpen;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Directorio de areas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'Usa el sidebar para abrir todo',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: EnterpriseSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980 ? 2 : 1;
              final width =
                  (constraints.maxWidth -
                      (columns - 1) * EnterpriseSpacing.sm) /
                  columns;
              return Wrap(
                spacing: EnterpriseSpacing.sm,
                runSpacing: EnterpriseSpacing.sm,
                children: [
                  for (final section in sections)
                    SizedBox(
                      width: width,
                      child: _DesktopModuleGroup(
                        section: section,
                        favoriteIds: favoriteIds,
                        onOpen: onOpen,
                        onToggleFavorite: onToggleFavorite,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DesktopModuleGroup extends StatelessWidget {
  const _DesktopModuleGroup({
    required this.section,
    required this.favoriteIds,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final _WorkspaceSection section;
  final Set<String> favoriteIds;
  final ValueChanged<ModuleDefinition> onOpen;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: section.label == 'Operacion',
      leading: Icon(
        section.icon,
        color: Theme.of(context).colorScheme.secondary,
      ),
      title: Text(section.label),
      subtitle: Text('${section.modules.length} modulos disponibles'),
      children: [
        for (final module in section.modules)
          ListTile(
            dense: true,
            leading: Icon(module.icon, color: module.color, size: 20),
            title: Text(
              module.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _moduleSubtitle(module.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: favoriteIds.contains(module.id)
                  ? 'Quitar favorito'
                  : 'Favorito',
              onPressed: () => onToggleFavorite(module.id),
              icon: Icon(
                favoriteIds.contains(module.id)
                    ? Icons.star
                    : Icons.star_border,
                color: favoriteIds.contains(module.id)
                    ? AppBrand.warning
                    : AppBrand.muted,
              ),
            ),
            onTap: () => onOpen(module),
          ),
      ],
    );
  }
}

class _DesktopSearchResults extends StatelessWidget {
  const _DesktopSearchResults({
    required this.query,
    required this.modules,
    required this.favoriteIds,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onCommandPalette,
  });

  final String query;
  final List<ModuleDefinition> modules;
  final Set<String> favoriteIds;
  final ValueChanged<ModuleDefinition> onOpen;
  final ValueChanged<String> onToggleFavorite;
  final VoidCallback onCommandPalette;

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Resultados para "$query"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onCommandPalette,
                icon: const Icon(Icons.keyboard_command_key),
                label: const Text('Paleta'),
              ),
            ],
          ),
          const SizedBox(height: EnterpriseSpacing.md),
          Expanded(
            child: modules.isEmpty
                ? const _ShellEmptyState(
                    icon: Icons.search_off,
                    title: 'Sin resultados',
                    detail: 'Prueba con ventas, cartera, bancos o soporte.',
                  )
                : ListView.separated(
                    itemCount: modules.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final module = modules[index];
                      return ListTile(
                        leading: Icon(module.icon, color: module.color),
                        title: Text(module.title),
                        subtitle: Text(
                          _moduleSubtitle(module.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: favoriteIds.contains(module.id)
                              ? 'Quitar favorito'
                              : 'Favorito',
                          onPressed: () => onToggleFavorite(module.id),
                          icon: Icon(
                            favoriteIds.contains(module.id)
                                ? Icons.star
                                : Icons.star_border,
                          ),
                        ),
                        onTap: () => onOpen(module),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceModeSelector extends StatelessWidget {
  const _WorkspaceModeSelector({
    required this.tipoEntidad,
    required this.mode,
    required this.onChanged,
  });

  final String tipoEntidad;
  final _WorkspaceMode mode;
  final ValueChanged<_WorkspaceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = tipoEntidad == 'publica'
        ? [
            (
              _WorkspaceMode.publicBudget,
              PhosphorIcons.chartBar(),
              'Ejecución Presupuestal',
            ),
            (
              _WorkspaceMode.publicCompliance,
              PhosphorIcons.warning(),
              'Cumplimiento y Alertas',
            ),
            (_WorkspaceMode.publicTransparency, Icons.public, 'Transparencia'),
          ]
        : [
            (_WorkspaceMode.dashboard, PhosphorIcons.house(), 'Dashboard'),
            (_WorkspaceMode.sales, PhosphorIcons.shoppingCart(), 'Ventas'),
            (_WorkspaceMode.operations, PhosphorIcons.cube(), 'Operaciones'),
            (_WorkspaceMode.finance, PhosphorIcons.chartBar(), 'Finanzas'),
          ];
    final selectedMode = items.any((item) => item.$1 == mode)
        ? mode
        : items.first.$1;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                avatar: Icon(
                  item.$2,
                  size: 16,
                  color: item.$1 == selectedMode
                      ? MerkaThemeTokens.onDark
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: Text(item.$3),
                selected: item.$1 == selectedMode,
                showCheckmark: false,
                selectedColor: MerkaThemeTokens.navy800,
                labelStyle: TextStyle(
                  color: item.$1 == selectedMode
                      ? MerkaThemeTokens.onDark
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => onChanged(item.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeWorkspace extends StatelessWidget {
  const _ModeWorkspace({
    required this.mode,
    required this.tipoEntidad,
    required this.modules,
    required this.onOpen,
    required this.onCommandPalette,
    required this.onCopilot,
    required this.onNotifications,
  });

  final _WorkspaceMode mode;
  final String tipoEntidad;
  final List<ModuleDefinition> modules;
  final ValueChanged<ModuleDefinition> onOpen;
  final VoidCallback onCommandPalette;
  final VoidCallback onCopilot;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    ModuleDefinition? find(String id) {
      for (final module in modules) {
        if (module.id == id) return module;
      }
      return null;
    }

    final publicModes = {
      _WorkspaceMode.publicBudget,
      _WorkspaceMode.publicCompliance,
      _WorkspaceMode.publicTransparency,
    };
    final effectiveMode = tipoEntidad == 'publica'
        ? (publicModes.contains(mode) ? mode : _WorkspaceMode.publicBudget)
        : (publicModes.contains(mode) ? _WorkspaceMode.dashboard : mode);

    switch (effectiveMode) {
      case _WorkspaceMode.dashboard:
        return SingleChildScrollView(
          child: _DashboardModePanel(
            onNotifications: onNotifications,
            onCopilot: onCopilot,
          ),
        );
      case _WorkspaceMode.sales:
        return SalesModePanel(onCopilot: onCopilot);
      case _WorkspaceMode.operations:
        return SingleChildScrollView(
          child: OperationsModePanel(
            onOpenInventory: () {
              final module = find('inventory');
              if (module != null) onOpen(module);
            },
            onOpenPurchases: () {
              final module = find('purchases');
              if (module != null) onOpen(module);
            },
            onNotifications: onNotifications,
          ),
        );
      case _WorkspaceMode.finance:
        return SingleChildScrollView(
          child: FinanceModePanel(
            onOpenReceivables: () {
              final module = find('receivables');
              if (module != null) onOpen(module);
            },
            onOpenPayables: () {
              final module = find('payables');
              if (module != null) onOpen(module);
            },
            onOpenCash: () {
              final module = find('cash');
              if (module != null) onOpen(module);
            },
            onCommandPalette: onCommandPalette,
          ),
        );
      case _WorkspaceMode.publicBudget:
        return SingleChildScrollView(
          child: _PublicDashboardModePanel(
            onNotifications: onNotifications,
            onCopilot: onCopilot,
          ),
        );
      case _WorkspaceMode.publicCompliance:
        return const SingleChildScrollView(child: _PublicComplianceModePanel());
      case _WorkspaceMode.publicTransparency:
        return const SingleChildScrollView(
          child: _PublicTransparencyModePanel(),
        );
    }
  }
}

class _DashboardModePanel extends StatefulWidget {
  const _DashboardModePanel({
    required this.onNotifications,
    required this.onCopilot,
  });

  final VoidCallback onNotifications;
  final VoidCallback onCopilot;

  @override
  State<_DashboardModePanel> createState() => _DashboardModePanelState();
}

class _DashboardModePanelState extends State<_DashboardModePanel> {
  static const _allKpis = {
    'sales': 'Ventas hoy',
    'sales_month': 'Ventas del mes',
    'profit': 'Utilidad bruta',
    'stock': 'Stock crítico',
    'receivables': 'Cartera',
    'payables': 'Por pagar',
    'inventory_value': 'Inventario valorizado',
    'cash': 'Flujo de caja',
  };

  Set<String> _visibleKpis = _allKpis.keys.toSet();
  String? _tipoEntidad;

  @override
  void initState() {
    super.initState();
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest) {
      _loadVisibleKpis();
      _loadTipoEntidad();
    }
  }

  Future<void> _loadTipoEntidad() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final companyRows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['company_active_id'],
        limit: 1,
      );
      if (companyRows.isEmpty) return;
      final companyId = companyRows.first['valor']?.toString();
      if (companyId == null) return;

      final rows = await db.query(
        'company_settings',
        where: 'company_id = ? AND setting_key = ?',
        whereArgs: [int.parse(companyId), 'tipo_entidad'],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        setState(() => _tipoEntidad = rows.first['setting_value']?.toString());
      }
    } catch (e) {
      debugPrint('Error al obtener tipo de entidad: $e');
    }
  }

  Future<void> _loadVisibleKpis() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'preferencias_usuario',
      where: 'usuario = ? AND clave = ?',
      whereArgs: [AppSession.nombre, 'dashboard_widgets'],
      limit: 1,
    );
    if (!mounted || rows.isEmpty) return;
    final values = rows.first['valor']
        ?.toString()
        .split(',')
        .where(_allKpis.containsKey)
        .toSet();
    if (values == null || values.isEmpty) return;
    setState(() => _visibleKpis = values);
  }

  Future<void> _toggleKpi(String key) async {
    final next = {..._visibleKpis};
    if (next.contains(key)) {
      if (next.length == 1) return;
      next.remove(key);
    } else {
      next.add(key);
    }
    setState(() => _visibleKpis = next);
    final db = await DatabaseHelper.instance.database;
    await db.insert('preferencias_usuario', {
      'usuario': AppSession.nombre,
      'clave': 'dashboard_widgets',
      'valor': next.join(','),
      'actualizado_en': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Widget build(BuildContext context) {
    if (_tipoEntidad == 'publica') {
      return _PublicDashboardModePanel(
        onNotifications: widget.onNotifications,
        onCopilot: widget.onCopilot,
      );
    }

    return FutureBuilder<DashboardSnapshot>(
      future: MerkaIntelligenceService().dashboardSnapshot(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        return EnterprisePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ModeHeader(
                icon: PhosphorIcons.house(),
                title: 'Dashboard',
                detail:
                    'Vista ejecutiva con ventas, inventario, cartera y flujo de caja.',
              ),
              const SizedBox(height: 16),
              if (data == null)
                const LinearProgressIndicator()
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in _allKpis.entries)
                      FilterChip(
                        label: Text(entry.value),
                        selected: _visibleKpis.contains(entry.key),
                        onSelected: (_) => _toggleKpi(entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (_visibleKpis.contains('sales'))
                      _DashboardKpi(
                        label: 'Ventas hoy',
                        value: _moneyCompact(data.salesToday),
                        icon: PhosphorIcons.shoppingCart(),
                        color: MerkaThemeTokens.navy800,
                      ),
                    if (_visibleKpis.contains('sales_month'))
                      _DashboardKpi(
                        label: 'Ventas del mes',
                        value: _moneyCompact(data.salesMonth),
                        icon: PhosphorIcons.chartLineUp(),
                        color: MerkaThemeTokens.navy600,
                      ),
                    if (_visibleKpis.contains('profit'))
                      _DashboardKpi(
                        label: 'Utilidad bruta',
                        value: '${_moneyCompact(data.grossProfitMonth)} · ${data.grossMarginPct.toStringAsFixed(1)}%',
                        icon: PhosphorIcons.trendUp(),
                        color: data.grossProfitMonth >= 0
                            ? MerkaThemeTokens.success
                            : MerkaThemeTokens.danger,
                      ),
                    if (_visibleKpis.contains('stock'))
                      _DashboardKpi(
                        label: 'Stock critico',
                        value: '${data.criticalStock}',
                        icon: PhosphorIcons.warningCircle(),
                        color: MerkaThemeTokens.danger,
                      ),
                    if (_visibleKpis.contains('receivables'))
                      _DashboardKpi(
                        label: 'Cartera pendiente',
                        value: _moneyCompact(data.overdueReceivables),
                        icon: PhosphorIcons.wallet(),
                        color: MerkaThemeTokens.warning,
                      ),
                    if (_visibleKpis.contains('payables'))
                      _DashboardKpi(
                        label: 'Cuentas por pagar',
                        value: _moneyCompact(data.payables),
                        icon: PhosphorIcons.receipt(),
                        color: MerkaThemeTokens.danger,
                      ),
                    if (_visibleKpis.contains('inventory_value'))
                      _DashboardKpi(
                        label: 'Inventario valorizado',
                        value: _moneyCompact(data.inventoryValue),
                        icon: PhosphorIcons.package(),
                        color: MerkaThemeTokens.gold500,
                      ),
                    if (_visibleKpis.contains('cash'))
                      _DashboardKpi(
                        label: 'Flujo de caja',
                        value: _moneyCompact(data.cashFlow),
                        icon: PhosphorIcons.coins(),
                        color: MerkaThemeTokens.success,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 720;
                    final charts = [
                      _MiniChartPanel(
                        title: 'Ventas ultimos 7 dias',
                        values: data.salesLast7Days,
                        color: MerkaThemeTokens.navy800,
                      ),
                      _MiniChartPanel(
                        title: 'Ingresos vs gastos del mes',
                        values: [data.incomeMonth, data.expenseMonth],
                        color: MerkaThemeTokens.success,
                        secondColor: MerkaThemeTokens.danger,
                      ),
                    ];
                    return compact
                        ? Column(
                            children: [
                              charts[0],
                              const SizedBox(height: 12),
                              charts[1],
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: charts[0]),
                              const SizedBox(width: 12),
                              Expanded(child: charts[1]),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 12),
                _BusinessHealthPanel(data: data),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 920;
                    final panels = [
                      _DashboardRankingPanel(
                        title: 'Productos con más ventas',
                        items: data.topProducts,
                        valueBuilder: (item) => _moneyCompact(item.value),
                        icon: Icons.emoji_events_outlined,
                      ),
                      _DashboardRankingPanel(
                        title: 'Clientes principales',
                        items: data.topCustomers,
                        valueBuilder: (item) => _moneyCompact(item.value),
                        icon: Icons.groups_outlined,
                      ),
                      _DashboardRankingPanel(
                        title: 'Margen a revisar',
                        items: data.lowMarginProducts,
                        valueBuilder: (item) => '${item.value.toStringAsFixed(1)}%',
                        icon: Icons.trending_down,
                      ),
                    ];
                    if (compact) {
                      return Column(
                        children: [
                          for (var i = 0; i < panels.length; i++) ...[
                            panels[i],
                            if (i < panels.length - 1) const SizedBox(height: 10),
                          ],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < panels.length; i++) ...[
                          Expanded(child: panels[i]),
                          if (i < panels.length - 1) const SizedBox(width: 10),
                        ],
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Acciones principales',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ModeAction(
                    icon: PhosphorIcons.bell(),
                    label: 'Ver alertas',
                    color: MerkaThemeTokens.warning,
                    onTap: widget.onNotifications,
                  ),
                  _ModeAction(
                    icon: PhosphorIcons.brain(),
                    label: 'Preguntar al Copilot',
                    color: MerkaThemeTokens.navy800,
                    onTap: widget.onCopilot,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BusinessHealthPanel extends StatelessWidget {
  const _BusinessHealthPanel({required this.data});

  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final score = data.businessHealthScore;
    final color = score >= 80
        ? MerkaThemeTokens.success
        : score >= 60
            ? MerkaThemeTokens.gold500
            : score >= 40
                ? MerkaThemeTokens.warning
                : MerkaThemeTokens.danger;
    final label = score >= 80
        ? 'Muy sólida'
        : score >= 60
            ? 'Estable'
            : score >= 40
                ? 'Requiere atención'
                : 'Crítica';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.12),
                  ),
                  Center(
                    child: Text(
                      '$score',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Cómo va mi empresa?', style: Theme.of(context).textTheme.titleMedium),
                  Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Indicador orientativo basado en margen bruto, liquidez frente a cuentas por pagar, cartera, stock crítico y tendencia reciente. No reemplaza un análisis financiero profesional.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Caja ${_moneyCompact(data.cashAvailable)} · Bancos ${_moneyCompact(data.bankAvailable)} · Ventas semana ${_moneyCompact(data.salesWeek)} · Año ${_moneyCompact(data.salesYear)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardRankingPanel extends StatelessWidget {
  const _DashboardRankingPanel({
    required this.title,
    required this.items,
    required this.valueBuilder,
    required this.icon,
  });

  final String title;
  final List<DashboardRankingItem> items;
  final String Function(DashboardRankingItem item) valueBuilder;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: MerkaThemeTokens.navy700),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text('Sin datos suficientes.', style: Theme.of(context).textTheme.bodySmall)
            else
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(width: 22, child: Text('${i + 1}.')),
                      Expanded(
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(valueBuilder(items[i]), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ModeHeader extends StatelessWidget {
  const _ModeHeader({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: MerkaThemeTokens.navy800, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeAction extends StatelessWidget {
  const _ModeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : MerkaThemeTokens.navy900,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _DashboardKpi extends StatelessWidget {
  const _DashboardKpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 24,
                      color: MerkaThemeTokens.graphite900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: MerkaThemeTokens.graphite600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChartPanel extends StatelessWidget {
  const _MiniChartPanel({
    required this.title,
    required this.values,
    required this.color,
    this.secondColor,
  });

  final String title;
  final List<double> values;
  final Color color;
  final Color? secondColor;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<double>(
      1,
      (max, item) => item > max ? item : max,
    );
    return Container(
      height: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FractionallySizedBox(
                        heightFactor: (values[i] / maxValue).clamp(0.05, 1),
                        alignment: Alignment.bottomCenter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == 1 && secondColor != null
                                ? secondColor
                                : color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _moneyCompact(double value) {
  final rounded = value.round().toString();
  return '\$${rounded.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
}

class _EnterpriseTopBar extends StatelessWidget {
  const _EnterpriseTopBar({
    required this.searchController,
    required this.tipoEntidad,
    required this.mode,
    required this.onModeChanged,
    required this.favoriteModules,
    required this.recentModules,
    required this.onSearchChanged,
    required this.onOpen,
    required this.onCommandPalette,
    required this.onCopilot,
    required this.onNotifications,
  });

  final TextEditingController searchController;
  final String tipoEntidad;
  final _WorkspaceMode mode;
  final ValueChanged<_WorkspaceMode> onModeChanged;
  final List<ModuleDefinition> favoriteModules;
  final List<ModuleDefinition> recentModules;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ModuleDefinition> onOpen;
  final VoidCallback onCommandPalette;
  final VoidCallback onCopilot;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final company = CompanyConfigurationService.instance.cached?.companyName;
    return EnterprisePanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          return Wrap(
            spacing: EnterpriseSpacing.md,
            runSpacing: EnterpriseSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centro de trabajo contable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: EnterpriseSpacing.xs),
                    Text(
                      company == null ? 'Tenant local' : 'Tenant: $company',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: compact ? constraints.maxWidth : 360,
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search global',
                    suffixIcon: searchController.text.isEmpty
                        ? IconButton(
                            tooltip: 'Abrir Command Palette',
                            onPressed: onCommandPalette,
                            icon: const Icon(Icons.keyboard_command_key),
                          )
                        : IconButton(
                            tooltip: 'Limpiar busqueda',
                            onPressed: () {
                              searchController.clear();
                              onSearchChanged('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              _WorkspaceModeSelector(
                tipoEntidad: tipoEntidad,
                mode: mode,
                onChanged: onModeChanged,
              ),
              const _SyncIndicator(),
              _TopBarButton(
                icon: Icons.keyboard_command_key,
                label: 'Comandos',
                onTap: onCommandPalette,
              ),
              _TopBarButton(
                icon: Icons.auto_awesome,
                label: 'Copilot',
                onTap: onCopilot,
              ),
              _TopBarButton(
                icon: Icons.notifications_none,
                label: 'Alertas',
                onTap: onNotifications,
              ),
              if (!compact)
                _MiniModuleRail(
                  label: 'Recientes',
                  modules: recentModules,
                  fallback: favoriteModules,
                  onOpen: onOpen,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _SyncIndicator extends StatefulWidget {
  const _SyncIndicator();

  @override
  State<_SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<_SyncIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final _repository = const SqliteSyncRepository();
  SyncStatusSnapshot? _snapshot;
  bool _isSyncing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest) {
      _loadStatus();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _loadStatus());
    } else {
      _snapshot = const SyncStatusSnapshot(
        pendingOutbox: 0,
        pendingInbox: 0,
        conflicts: 0,
        lastPushAt: null,
        lastPullAt: null,
        online: true,
      );
    }
  }

  Future<void> _loadStatus() async {
    try {
      final snap = await _repository.status();
      if (mounted) {
        setState(() {
          _snapshot = snap;
        });
      }
    } catch (_) {
      // Ignore database initialization timing issues
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshSyncStatus() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
    });
    await _loadStatus();
    if (mounted) {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final hasConflicts = snap != null && snap.conflicts > 0;
    final hasPending = snap != null && snap.pendingOutbox > 0;

    Color color;
    IconData icon;
    String text;

    if (_isSyncing) {
      color = MerkaThemeTokens.navy600;
      icon = Icons.sync;
      text = 'Actualizando estado...';
    } else if (hasConflicts) {
      color = MerkaThemeTokens.danger;
      icon = Icons.warning;
      text = 'Conflictos (${snap.conflicts})';
    } else if (hasPending) {
      color = MerkaThemeTokens.warning;
      icon = Icons.cloud_queue;
      text = 'Pendientes (${snap.pendingOutbox})';
    } else {
      color = MerkaThemeTokens.success;
      icon = Icons.cloud_done;
      text = 'Offline-First Activo';
    }

    return InkWell(
      onTap: _refreshSyncStatus,
      borderRadius: BorderRadius.circular(EnterpriseSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(EnterpriseSpacing.sm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _isSyncing
                ? AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Icon(
                        icon,
                        size: 16,
                        color: Color.lerp(
                          color,
                          color.withValues(alpha: 0.3),
                          _controller.value,
                        ),
                      );
                    },
                  )
                : Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniModuleRail extends StatelessWidget {
  const _MiniModuleRail({
    required this.label,
    required this.modules,
    required this.fallback,
    required this.onOpen,
  });

  final String label;
  final List<ModuleDefinition> modules;
  final List<ModuleDefinition> fallback;
  final ValueChanged<ModuleDefinition> onOpen;

  @override
  Widget build(BuildContext context) {
    final items = modules.isEmpty ? fallback : modules;
    if (items.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Wrap(
        spacing: EnterpriseSpacing.sm,
        runSpacing: EnterpriseSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          for (final module in items.take(3))
            ActionChip(
              avatar: Icon(module.icon, size: 16, color: module.color),
              label: Text(module.title, overflow: TextOverflow.ellipsis),
              onPressed: () => onOpen(module),
            ),
        ],
      ),
    );
  }
}

class _EnterpriseSidebar extends StatelessWidget {
  const _EnterpriseSidebar({
    required this.sections,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onOpen,
  });

  final List<_WorkspaceSection> sections;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<ModuleDefinition> onOpen;

  @override
  Widget build(BuildContext context) {
    final width = collapsed ? 74.0 : 264.0;
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: width,
      margin: const EdgeInsets.fromLTRB(12, 10, 0, 12),
      padding: const EdgeInsets.all(EnterpriseSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outline.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(EnterpriseRadii.lg),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const MerkaLogo(size: 34),
              if (!collapsed) ...[
                const SizedBox(width: EnterpriseSpacing.sm),
                Expanded(
                  child: Text(
                    'Workspace',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
              IconButton(
                tooltip: collapsed ? 'Expandir sidebar' : 'Colapsar sidebar',
                onPressed: onToggleCollapsed,
                icon: Icon(
                  collapsed ? Icons.chevron_right : Icons.chevron_left,
                ),
              ),
            ],
          ),
          const SizedBox(height: EnterpriseSpacing.md),
          Expanded(
            child: ListView(
              children: [
                for (final section in sections) ...[
                  _SidebarGroupLabel(
                    label: section.label,
                    collapsed: collapsed,
                  ),
                  for (final module in section.modules)
                    _SidebarModuleButton(
                      module: module,
                      collapsed: collapsed,
                      onTap: () => onOpen(module),
                    ),
                  const SizedBox(height: EnterpriseSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileModuleDrawer extends StatelessWidget {
  const _MobileModuleDrawer({
    required this.sections,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onOpen,
    required this.onLogout,
  });

  final List<_WorkspaceSection> sections;
  final Set<String> favoriteIds;
  final ValueChanged<String> onToggleFavorite;
  final ValueChanged<ModuleDefinition> onOpen;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final company = CompanyConfigurationService.instance.cached?.companyName;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(EnterpriseSpacing.lg),
              child: Row(
                children: [
                  const MerkaLogo(size: 38),
                  const SizedBox(width: EnterpriseSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppBrand.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          company ?? 'Tenant local',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final section in sections) ...[
                    _SidebarGroupLabel(label: section.label, collapsed: false),
                    for (final module in section.modules)
                      _MobileDrawerModuleTile(
                        module: module,
                        favorite: favoriteIds.contains(module.id),
                        onFavorite: () => onToggleFavorite(module.id),
                        onOpen: () {
                          Navigator.pop(context);
                          onOpen(module);
                        },
                      ),
                    const SizedBox(height: EnterpriseSpacing.sm),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(EnterpriseSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesion'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileDrawerModuleTile extends StatelessWidget {
  const _MobileDrawerModuleTile({
    required this.module,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
  });

  final ModuleDefinition module;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(module.icon, color: module.color, size: 20),
      title: Text(
        module.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        _moduleSubtitle(module.id),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: favorite ? 'Quitar favorito' : 'Favorito',
        onPressed: onFavorite,
        icon: Icon(
          favorite ? Icons.star : Icons.star_border,
          color: favorite ? AppBrand.warning : AppBrand.muted,
        ),
      ),
      onTap: onOpen,
    );
  }
}

class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel({required this.label, required this.collapsed});

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) return const SizedBox(height: EnterpriseSpacing.sm);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _SidebarModuleButton extends StatelessWidget {
  const _SidebarModuleButton({
    required this.module,
    required this.collapsed,
    required this.onTap,
  });

  final ModuleDefinition module;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: module.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(module.icon, size: 19, color: module.color),
              if (!collapsed) ...[
                const SizedBox(width: EnterpriseSpacing.sm),
                Expanded(
                  child: Text(
                    module.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: EnterpriseSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _MobileModuleCard extends StatelessWidget {
  const _MobileModuleCard({
    required this.module,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
  });

  final ModuleDefinition module;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outline.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(EnterpriseSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(EnterpriseRadii.md),
                ),
                child: Icon(module.icon, color: module.color),
              ),
              const SizedBox(width: EnterpriseSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: EnterpriseSpacing.xs),
                    Text(
                      _moduleSubtitle(module.id),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: favorite ? 'Quitar de favoritos' : 'Favorito',
                onPressed: onFavorite,
                icon: Icon(
                  favorite ? Icons.star : Icons.star_border,
                  color: favorite ? AppBrand.warning : AppBrand.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellEmptyState extends StatelessWidget {
  const _ShellEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: EnterpriseSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: EnterpriseSpacing.xs),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

Future<void> _showNotificationCenterSheet(
  _MenuPrincipalState state,
  BuildContext context,
  List<ModuleDefinition> modules,
) async {
  final signalsFuture = SignalAggregator.forCurrentSession().collect();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (context) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: _SignalFeedContent(
              signalsFuture: signalsFuture,
              modules: modules,
              onNavigate: (module) {
                Navigator.pop(context);
                state._openModule(context, module);
              },
            ),
          ),
        ),
      );
    },
  );
}

class _SignalFeedContent extends StatelessWidget {
  const _SignalFeedContent({
    required this.signalsFuture,
    required this.modules,
    required this.onNavigate,
  });

  final Future<List<Signal>> signalsFuture;
  final List<ModuleDefinition> modules;
  final ValueChanged<ModuleDefinition> onNavigate;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Signal>>(
      future: signalsFuture,
      builder: (context, snapshot) {
        final signals = snapshot.data ?? const <Signal>[];
        final showFallback =
            snapshot.connectionState != ConnectionState.done || signals.isEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Center',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: EnterpriseSpacing.md),
            if (showFallback)
              for (final item in _notificationItems(modules))
                _NotificationTile(
                  item: item,
                  onTap: () => onNavigate(item.module),
                )
            else
              for (final signal in signals)
                _SignalNotificationCard(
                  signal: signal,
                  modules: modules,
                  onNavigate: onNavigate,
                ),
          ],
        );
      },
    );
  }
}

class _SignalNotificationCard extends StatelessWidget {
  const _SignalNotificationCard({
    required this.signal,
    required this.modules,
    required this.onNavigate,
  });

  final Signal signal;
  final List<ModuleDefinition> modules;
  final ValueChanged<ModuleDefinition> onNavigate;

  @override
  Widget build(BuildContext context) {
    final module = _findModule(modules, signal.navigationModuleId);
    final actions = <RecordCardAction>[];
    if (signal.commandId != null && signal.commandContext != null) {
      actions.add(
        RecordCardAction(
          id: 'signal-command-${signal.id}',
          label: signal.suggestedAction ?? 'Ejecutar acción',
          icon: Icons.play_arrow,
          commandId: signal.commandId,
          commandContext: signal.commandContext,
        ),
      );
    }
    if (module != null) {
      actions.add(
        RecordCardAction(
          id: 'signal-open-${signal.id}',
          label: 'Abrir módulo',
          icon: Icons.open_in_new,
          onPressed: (_) async => onNavigate(module),
        ),
      );
    }
    return ExpandableRecordCard(
      criticalFields: [
        RecordCardField(
          label: 'Prioridad',
          value: signal.priority.label,
          icon: signal.priority == SignalPriority.urgent
              ? Icons.warning
              : Icons.notifications_active,
          emphasized: true,
        ),
        RecordCardField(label: 'Origen', value: signal.source, icon: Icons.hub),
        RecordCardField(
          label: 'Señal',
          value: signal.title,
          icon: Icons.insights,
          emphasized: true,
        ),
      ],
      secondaryFields: [
        RecordCardField(label: 'Detalle', value: signal.description),
        if (signal.entityId != null)
          RecordCardField(
            label: 'Entidad relacionada',
            value: '${signal.entityType ?? 'registro'} #${signal.entityId}',
          ),
        if (signal.requiredPermission != null)
          RecordCardField(
            label: 'Permiso requerido',
            value: signal.requiredPermission!,
          ),
      ],
      actions: actions,
    );
  }
}

ModuleDefinition? _findModule(
  List<ModuleDefinition> modules,
  String? moduleId,
) {
  if (moduleId == null) return null;
  for (final module in modules) {
    if (module.id == moduleId) return module;
  }
  return null;
}

ModuleDefinition? _moduleById(List<ModuleDefinition> modules, String id) {
  for (final module in modules) {
    if (module.id == id) return module;
  }
  return null;
}

List<_NotificationItem> _notificationItems(List<ModuleDefinition> modules) {
  if (modules.isEmpty) return const [];

  ModuleDefinition module(String id) {
    for (final item in modules) {
      if (item.id == id) return item;
    }
    return modules.first;
  }

  _NotificationItem notification({
    required String title,
    required String detail,
    required IconData icon,
    required Color color,
    required String moduleId,
  }) {
    return _NotificationItem(
      title: title,
      detail: detail,
      icon: icon,
      color: color,
      module: module(moduleId),
    );
  }

  return [
    notification(
      title: 'Aprobaciones de compras',
      detail: 'Revisa RFQ, ordenes y recepciones con SLA activo.',
      icon: Icons.approval,
      color: AppBrand.warning,
      moduleId: 'purchases',
    ),
    notification(
      title: 'Cartera y vencimientos',
      detail: 'Consulta aging, promesas de pago y reglas de bloqueo.',
      icon: Icons.request_quote,
      color: AppBrand.info,
      moduleId: 'receivables',
    ),
    notification(
      title: 'Posicion de tesoreria',
      detail: 'Valida cash flow, bancos, conciliacion y pagos programados.',
      icon: Icons.account_balance_wallet,
      color: AppBrand.success,
      moduleId: 'erp_readiness',
    ),
    notification(
      title: 'Impuestos y reportes',
      detail: 'Revisa tax engine, reportes fiscales y materializados.',
      icon: Icons.gavel,
      color: AppBrand.error,
      moduleId: 'accounting', // tax_reports no existe como módulo; accounting contiene los reportes fiscales
    ),
  ];
}

void _showCopilotDialog(
  _MenuPrincipalState state,
  BuildContext context,
  List<ModuleDefinition> modules,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        alignment: Alignment.centerRight,
        insetPadding: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 380,
          height: MediaQuery.sizeOf(context).height * 0.85,
          child: CopilotPanel(
            onClose: () => Navigator.pop(dialogContext),
            modules: modules,
            onNavigateToModule: (moduleId) {
              final module = _moduleById(modules, moduleId);
              if (module == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El modulo solicitado no esta disponible.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              state._openModule(context, module);
            },
            onLoadSaleProduct: (query) {
              final module = _moduleById(modules, 'sales');
              if (module == null || !AppSession.puedeAbrirModulo(module)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No tienes acceso a Ventas.')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              state._updateState(() {
                state._workspaceMode = _WorkspaceMode.sales;
              });
            },
            onLoadClientPayment: () {
              final module = _moduleById(modules, 'receivables');
              if (module == null) return;
              Navigator.pop(dialogContext);
              state._openModule(context, module);
            },
            onLoadPurchaseOrder: () {
              final module = _moduleById(modules, 'purchases');
              if (module == null) return;
              Navigator.pop(dialogContext);
              state._openModule(context, module);
            },
          ),
        ),
      );
    },
  );
}

void _showMobileQuickActionsSheet(
  _MenuPrincipalState state,
  BuildContext context,
  List<ModuleDefinition> modules,
) {
  ModuleDefinition? findModule(String id) {
    for (final module in modules) {
      if (module.id == id) return module;
    }
    return null;
  }

  void openIfAvailable(String id) {
    final module = findModule(id);
    Navigator.pop(context);
    if (module != null) {
      state._openModule(context, module);
    } else {
      state._showCommandPalette(context, modules);
    }
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Acciones rapidas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: EnterpriseSpacing.md),
              _MobileQuickActionTile(
                icon: Icons.point_of_sale,
                color: AppBrand.secondary,
                title: 'Crear venta',
                detail: 'POS, factura o documento comercial.',
                onTap: () => openIfAvailable('sales'),
              ),
              _MobileQuickActionTile(
                icon: Icons.shopping_bag,
                color: AppBrand.success,
                title: 'Crear compra',
                detail: 'Orden, recepcion o factura proveedor.',
                onTap: () => openIfAvailable('purchases'),
              ),
              _MobileQuickActionTile(
                icon: Icons.payments,
                color: AppBrand.warning,
                title: 'Registrar pago',
                detail: 'Cobros, pagos y aplicaciones parciales.',
                onTap: () => openIfAvailable('receivables'),
              ),
              _MobileQuickActionTile(
                icon: Icons.search,
                color: AppBrand.info,
                title: 'Buscar en el ERP',
                detail: 'Clientes, compras, ventas, activos y reportes.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  state._showCommandPalette(context, modules);
                },
              ),
              _MobileQuickActionTile(
                icon: Icons.auto_awesome,
                color: AppBrand.accent,
                title: 'Preguntar al Copilot',
                detail: 'Analisis, pendientes, alertas y acciones.',
                onTap: () {
                  Navigator.pop(sheetContext);
                  state._showCopilot(context, modules);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _NotificationItem {
  const _NotificationItem({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.module,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final ModuleDefinition module;
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final _NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EnterpriseSpacing.sm),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
        child: ListTile(
          minVerticalPadding: EnterpriseSpacing.md,
          leading: CircleAvatar(
            backgroundColor: item.color.withValues(alpha: 0.12),
            foregroundColor: item.color,
            child: Icon(item.icon),
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            item.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

double _publicNum(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

String _publicText(
  Map<String, Object?> row,
  List<String> keys, {
  String fallback = '-',
}) {
  for (final key in keys) {
    final value = row[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return fallback;
}

class _PublicDashboardModePanel extends StatefulWidget {
  const _PublicDashboardModePanel({
    required this.onNotifications,
    required this.onCopilot,
  });

  final VoidCallback onNotifications;
  final VoidCallback onCopilot;

  @override
  State<_PublicDashboardModePanel> createState() =>
      _PublicDashboardModePanelState();
}

class _PublicDashboardModePanelState extends State<_PublicDashboardModePanel> {
  Map<String, dynamic> _dashboardData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final entityId = AppSession.entidadId;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
      final now = DateTime.now();
      final in30 = now.add(const Duration(days: 30));

      Future<double> sum(String table, String column, {String? where, List<Object?>? args}) async {
        final rows = await db.rawQuery(
          'SELECT COALESCE(SUM($column),0) AS total FROM $table${where == null ? '' : ' WHERE $where'}',
          args,
        );
        return rows.isEmpty ? 0 : ((rows.first['total'] as num?)?.toDouble() ?? 0);
      }

      final totalApropiacion = await sum('apropiaciones', 'valor_apropiado', where: 'entidad_id = ? AND activo = 1', args: [entityId]);
      final totalCDP = await sum('cdps', 'valor_cdp', where: 'entidad_id = ?', args: [entityId]);
      final totalRP = await sum('rps', 'valor_rp', where: 'entidad_id = ?', args: [entityId]);
      final totalObligado = await sum('obligaciones', 'valor_obligacion', where: 'entidad_id = ?', args: [entityId]);
      final totalPagado = await sum('pagos', 'valor_pago', where: "entidad_id = ? AND LOWER(estado) IN ('pagado','ejecutado','aprobado')", args: [entityId]);
      final executionPct = totalApropiacion <= 0 ? 0.0 : (totalPagado / totalApropiacion) * 100;

      final pacRows = await db.query('pac', where: 'entidad_id = ?', whereArgs: [entityId]);
      final criticalPac = pacRows.where((row) {
        final programmed = (row['valor_programado'] as num?)?.toDouble() ?? 0;
        final executed = (row['valor_ejecutado'] as num?)?.toDouble() ?? 0;
        return programmed > 0 && (executed / programmed) < 0.80;
      }).length;

      Future<int> countDue(String table, String column) async {
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM $table WHERE entidad_id = ? AND $column >= ? AND $column <= ?',
          [entityId, now.toIso8601String(), in30.toIso8601String()],
        );
        return (rows.first['n'] as num?)?.toInt() ?? 0;
      }

      final cdpsDue = await countDue('cdps', 'fecha_vigencia');
      final rpsDue = await countDue('rps', 'fecha_vigencia');
      final contractsDueRows = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM contratos WHERE entidad_id = ? AND fecha_fin_ejecucion >= ? AND fecha_fin_ejecucion <= ? AND LOWER(estado) NOT IN ('liquidado','expediente_cerrado','terminado')",
        [entityId, now.toIso8601String(), in30.toIso8601String()],
      );
      final contractsDue = (contractsDueRows.first['n'] as num?)?.toInt() ?? 0;
      final policiesDueRows = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM polizas WHERE entidad_id = ? AND fecha_fin_vigencia >= ? AND fecha_fin_vigencia <= ? AND LOWER(estado) NOT IN ('cancelada','vencida')",
        [entityId, now.toIso8601String(), in30.toIso8601String()],
      );
      final policiesDue = (policiesDueRows.first['n'] as num?)?.toInt() ?? 0;
      final supervisionAlertsRows = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM alertas_incumplimiento WHERE entidad_id = ? AND LOWER(estado) NOT IN ('resuelto','cerrado')",
        [entityId],
      );
      final supervisionAlerts = (supervisionAlertsRows.first['n'] as num?)?.toInt() ?? 0;

      final obligations = await db.query('obligaciones', where: 'entidad_id = ?', whereArgs: [entityId]);
      final pendingObligations = obligations.where((row) {
        final status = row['estado']?.toString().toLowerCase() ?? '';
        return status == 'pendiente' || status == 'reconocida' || status == 'parcial';
      }).toList();
      final totalPending = pendingObligations.fold<double>(0, (sum, row) => sum + ((row['saldo_pendiente'] ?? row['valor_obligacion']) as num? ?? 0).toDouble());

      final documentDueRows = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM gd_radicados WHERE company_id = ? AND due_at IS NOT NULL AND due_at < ? AND closed_at IS NULL AND LOWER(status) NOT IN ('closed','archived','cerrado','archivado')",
        [companyId, now.toUtc().toIso8601String()],
      );
      final overdueDocuments = (documentDueRows.first['n'] as num?)?.toInt() ?? 0;
      final instrumentsRows = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM gd_instruments WHERE company_id = ? AND LOWER(status) IN ('pending','draft','pendiente','borrador')",
        [companyId],
      );
      final pendingInstruments = (instrumentsRows.first['n'] as num?)?.toInt() ?? 0;

      if (mounted) {
        setState(() {
          _dashboardData = {
            'ejecucion_porcentaje': executionPct,
            'total_apropiacion': totalApropiacion,
            'total_cdp': totalCDP,
            'total_rp': totalRP,
            'total_obligado': totalObligado,
            'total_pagado': totalPagado,
            'meses_criticos': criticalPac,
            'cdps_vencen': cdpsDue,
            'rps_vencen': rpsDue,
            'contratos_vencen': contractsDue,
            'polizas_vencen': policiesDue,
            'alertas_supervision': supervisionAlerts,
            'obligaciones_pendientes': pendingObligations.length,
            'total_pendiente': totalPending,
            'documentos_vencidos': overdueDocuments,
            'instrumentos_pendientes': pendingInstruments,
            'tiene_datos': totalApropiacion > 0 || totalCDP > 0 || obligations.isNotEmpty,
          };
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar datos del dashboard público: $e');
      if (mounted) setState(() { _dashboardData = {'tiene_datos': false}; _loading = false; });
    }
  }

  String _formatCurrency(double minorUnits) {
    final value = minorUnits / 100;
    if (value.abs() >= 1000000000) return '\$${(value / 1000000000).toStringAsFixed(1)}B';
    if (value.abs() >= 1000000) return '\$${(value / 1000000).toStringAsFixed(1)}M';
    if (value.abs() >= 1000) return '\$${(value / 1000).toStringAsFixed(1)}K';
    return '\$${value.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return EnterprisePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ModeHeader(
              icon: PhosphorIcons.buildings(),
              title: 'Dashboard Sector Público',
              detail:
                  'Vista ejecutiva con ejecución presupuestal, PAC y vencimientos.',
            ),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ),
      );
    }

    final tieneDatos = _dashboardData['tiene_datos'] == true;

    if (!tieneDatos) {
      return EnterprisePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ModeHeader(
              icon: PhosphorIcons.buildings(),
              title: 'Dashboard Sector Público',
              detail:
                  'Vista ejecutiva con ejecución presupuestal, PAC y vencimientos.',
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Icon(
                    PhosphorIcons.folderOpen(),
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Aún no hay datos presupuestales registrados',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Comienza registrando apropiaciones presupuestales',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PresupuestoPublicoPage(
                            entidadId: 'default',
                            usuarioId: 'default',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Ir a Presupuesto'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final ejecucionPorcentaje =
        _dashboardData['ejecucion_porcentaje'] as double? ?? 0.0;
    final mesesCriticos = _dashboardData['meses_criticos'] as int? ?? 0;
    final cdpsVencen = _dashboardData['cdps_vencen'] as int? ?? 0;
    final rpsVencen = _dashboardData['rps_vencen'] as int? ?? 0;
    final totalVencen = cdpsVencen + rpsVencen;
    final obligacionesPendientes =
        _dashboardData['obligaciones_pendientes'] as int? ?? 0;
    final totalPendiente = _dashboardData['total_pendiente'] as double? ?? 0.0;
    final totalApropiacion =
        _dashboardData['total_apropiacion'] as double? ?? 0.0;
    final totalCDP = _dashboardData['total_cdp'] as double? ?? 0.0;
    final totalRP = _dashboardData['total_rp'] as double? ?? 0.0;
    final totalObligado = _dashboardData['total_obligado'] as double? ?? 0.0;
    final totalPagado = _dashboardData['total_pagado'] as double? ?? 0.0;
    final contratosVencen = _dashboardData['contratos_vencen'] as int? ?? 0;
    final polizasVencen = _dashboardData['polizas_vencen'] as int? ?? 0;
    final alertasSupervision = _dashboardData['alertas_supervision'] as int? ?? 0;
    final documentosVencidos = _dashboardData['documentos_vencidos'] as int? ?? 0;
    final instrumentosPendientes = _dashboardData['instrumentos_pendientes'] as int? ?? 0;

    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ModeHeader(
            icon: PhosphorIcons.buildings(),
            title: 'Dashboard Sector Público',
            detail:
                'Vista ejecutiva con ejecución presupuestal, PAC y vencimientos.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PublicDashboardKpi(
                label: 'Ejecución Presupuestal',
                value: '${ejecucionPorcentaje.toStringAsFixed(1)}%',
                icon: PhosphorIcons.chartPie(),
                color: AppTheme.info,
                detail: 'Apropiación vs Pagado',
              ),
              _PublicDashboardKpi(
                label: 'Alertas PAC',
                value: '$mesesCriticos meses',
                icon: PhosphorIcons.warning(),
                color: mesesCriticos > 0 ? AppTheme.warning : AppTheme.success,
                detail: mesesCriticos > 0
                    ? 'Por debajo del cupo'
                    : 'Ejecución normal',
              ),
              _PublicDashboardKpi(
                label: 'CDP/RP Vencen',
                value: '$totalVencen documentos',
                icon: PhosphorIcons.clock(),
                color: totalVencen > 0 ? AppTheme.danger : AppTheme.success,
                detail: 'Próximos 30 días',
              ),
              _PublicDashboardKpi(
                label: 'Obligaciones Pendientes',
                value: _formatCurrency(totalPendiente),
                icon: PhosphorIcons.currencyDollar(),
                color: obligacionesPendientes > 0
                    ? AppTheme.warning
                    : AppTheme.success,
                detail: '$obligacionesPendientes obligaciones',
              ),
              _PublicDashboardKpi(
                label: 'Contratos / pólizas',
                value: '${contratosVencen + polizasVencen}',
                icon: PhosphorIcons.shieldCheck(),
                color: (contratosVencen + polizasVencen) > 0 ? AppTheme.warning : AppTheme.success,
                detail: '$contratosVencen contratos · $polizasVencen pólizas',
              ),
              _PublicDashboardKpi(
                label: 'Supervisión',
                value: '$alertasSupervision alertas',
                icon: Icons.assignment_turned_in_outlined,
                color: alertasSupervision > 0 ? AppTheme.danger : AppTheme.success,
                detail: 'Alertas contractuales abiertas',
              ),
              _PublicDashboardKpi(
                label: 'Gestión documental',
                value: '$documentosVencidos vencidos',
                icon: Icons.folder_copy_outlined,
                color: documentosVencidos > 0 ? AppTheme.danger : AppTheme.success,
                detail: '$instrumentosPendientes instrumento(s) por adoptar',
              ),
            ],
          ),
          const SizedBox(height: 24),
          _PublicDashboardCard(
            title: 'Ejecución Presupuestal',
            icon: PhosphorIcons.chartBar(),
            color: AppTheme.info,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PublicProgressBar(
                  label: 'Apropiación Total',
                  value: 1.0,
                  color: AppTheme.info,
                  valor: _formatCurrency(totalApropiacion),
                ),
                const SizedBox(height: 12),
                _PublicProgressBar(
                  label: 'Comprometido (CDP)',
                  value: totalApropiacion > 0
                      ? totalCDP / totalApropiacion
                      : 0.0,
                  color: AppTheme.success,
                  valor: _formatCurrency(totalCDP),
                ),
                const SizedBox(height: 12),
                _PublicProgressBar(
                  label: 'Registrado (RP)',
                  value: totalApropiacion > 0
                      ? totalRP / totalApropiacion
                      : 0.0,
                  color: AppTheme.warning,
                  valor: _formatCurrency(totalRP),
                ),
                const SizedBox(height: 12),
                _PublicProgressBar(
                  label: 'Obligado',
                  value: totalApropiacion > 0
                      ? totalObligado / totalApropiacion
                      : 0.0,
                  color: AppTheme.danger,
                  valor: _formatCurrency(totalObligado),
                ),
                const SizedBox(height: 12),
                _PublicProgressBar(
                  label: 'Pagado',
                  value: totalApropiacion > 0
                      ? totalPagado / totalApropiacion
                      : 0.0,
                  color: AppTheme.success,
                  valor: _formatCurrency(totalPagado),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PublicDashboardCard(
            title: 'Alertas de Cupo PAC',
            icon: PhosphorIcons.warning(),
            color: mesesCriticos > 0 ? AppTheme.warning : AppTheme.success,
            child: mesesCriticos > 0
                ? Text(
                    '$mesesCriticos mes(es) con ejecución por debajo del cupo asignado',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Text(
                    'Todos los meses están dentro del cupo asignado',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.success),
                  ),
          ),
          const SizedBox(height: 16),
          _PublicDashboardCard(
            title: 'Vencimientos Próximos CDP/RP',
            icon: PhosphorIcons.clock(),
            color: totalVencen > 0 ? AppTheme.danger : AppTheme.success,
            child: totalVencen > 0
                ? Text(
                    '$cdpsVencen CDP(s) y $rpsVencen RP(s) vencen en los próximos 30 días',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Text(
                    'No hay CDPs ni RPs próximos a vencer',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.success),
                  ),
          ),
          const SizedBox(height: 16),
          _PublicDashboardCard(
            title: 'Obligaciones Pendientes de Pago',
            icon: PhosphorIcons.currencyDollar(),
            color: obligacionesPendientes > 0
                ? AppTheme.warning
                : AppTheme.success,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Pendiente',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      _formatCurrency(totalPendiente),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: obligacionesPendientes > 0
                            ? AppTheme.warning
                            : AppTheme.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$obligacionesPendientes obligaciones por pagar',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Acciones principales',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ModeAction(
                icon: PhosphorIcons.bell(),
                label: 'Ver alertas',
                color: AppTheme.warning,
                onTap: widget.onNotifications,
              ),
              _ModeAction(
                icon: PhosphorIcons.brain(),
                label: 'Preguntar al Copilot',
                color: AppTheme.info,
                onTap: widget.onCopilot,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublicComplianceModePanel extends StatefulWidget {
  const _PublicComplianceModePanel();

  @override
  State<_PublicComplianceModePanel> createState() =>
      _PublicComplianceModePanelState();
}

class _PublicComplianceModePanelState
    extends State<_PublicComplianceModePanel> {
  bool _loading = true;
  List<Map<String, Object?>> _vencimientos = const [];
  List<Map<String, Object?>> _obligaciones = const [];
  List<Map<String, Object?>> _pac = const [];

  @override
  void initState() {
    super.initState();
    _loadComplianceData();
  }

  Future<void> _loadComplianceData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final hoy = DateTime.now();
      final hasta = hoy.add(const Duration(days: 30)).toIso8601String();

      final cdps = await db.query(
        'cdps',
        where: 'fecha_vigencia >= ? AND fecha_vigencia <= ?',
        whereArgs: [hoy.toIso8601String(), hasta],
        orderBy: 'fecha_vigencia ASC',
        limit: 4,
      );
      final rps = await db.query(
        'rps',
        where: 'fecha_vigencia >= ? AND fecha_vigencia <= ?',
        whereArgs: [hoy.toIso8601String(), hasta],
        orderBy: 'fecha_vigencia ASC',
        limit: 4,
      );
      final vencimientos =
          <Map<String, Object?>>[
            for (final row in cdps) {...row, 'tipo_documento': 'CDP'},
            for (final row in rps) {...row, 'tipo_documento': 'RP'},
          ]..sort((a, b) {
            final fechaA = _publicText(a, ['fecha_vigencia']);
            final fechaB = _publicText(b, ['fecha_vigencia']);
            return fechaA.compareTo(fechaB);
          });

      final obligaciones = await db.query(
        'obligaciones',
        where: 'estado IN (?, ?)',
        whereArgs: ['pendiente', 'reconocida'],
        orderBy: 'fecha_obligacion ASC',
        limit: 6,
      );
      final pac = await db.query('pac', orderBy: 'mes ASC', limit: 12);

      if (!mounted) return;
      setState(() {
        _vencimientos = vencimientos.take(6).toList();
        _obligaciones = obligaciones;
        _pac = pac;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error al cargar cumplimiento publico: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _diasRestantes(Map<String, Object?> row) {
    final fecha = DateTime.tryParse(_publicText(row, ['fecha_vigencia']));
    if (fecha == null) return 'sin fecha';
    final dias = fecha.difference(DateTime.now()).inDays;
    if (dias <= 0) return 'hoy';
    return '$dias dias';
  }

  String _estadoPac(Map<String, Object?> row) {
    final cupo = _publicNum(row, 'cupo_asignado');
    final ejecutado = _publicNum(row, 'valor_ejecutado');
    if (cupo <= 0) return 'warning';
    final avance = ejecutado / cupo;
    if (avance < 0.8) return 'critical';
    if (avance > 0.95) return 'warning';
    return 'ok';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const EnterprisePanel(child: LinearProgressIndicator());
    }

    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ModeHeader(
            icon: PhosphorIcons.warning(),
            title: 'Cumplimiento y Alertas',
            detail:
                'Vencimientos de CDP/RP, cupos PAC y obligaciones pendientes.',
          ),
          const SizedBox(height: 16),
          _PublicDashboardCard(
            title: 'Vencimientos CDP/RP',
            icon: PhosphorIcons.clock(),
            color: AppTheme.danger,
            child: _vencimientos.isEmpty
                ? Text(
                    'No hay CDP ni RP por vencer en los proximos 30 dias.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    children: [
                      for (final row in _vencimientos) ...[
                        _PublicVencimientoItem(
                          tipo: _publicText(row, ['tipo_documento']),
                          numero: _publicText(row, [
                            'numero_cdp',
                            'numero_rp',
                            'numero',
                          ], fallback: 'Sin numero'),
                          venceEn: _diasRestantes(row),
                          monto: _moneyCompact(
                            _publicNum(row, 'valor_cdp') +
                                _publicNum(row, 'valor_rp'),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _PublicDashboardCard(
            title: 'Obligaciones Pendientes',
            icon: PhosphorIcons.currencyDollar(),
            color: AppTheme.warning,
            child: _obligaciones.isEmpty
                ? Text(
                    'No hay obligaciones pendientes o reconocidas.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Column(
                    children: [
                      for (final row in _obligaciones) ...[
                        _PublicObligacionItem(
                          numero: _publicText(row, [
                            'numero_obligacion',
                            'numero',
                          ], fallback: 'Obligacion'),
                          proveedor: _publicText(row, [
                            'tercero_nombre',
                            'proveedor',
                            'beneficiario',
                          ], fallback: 'Tercero sin nombre'),
                          monto: _moneyCompact(
                            _publicNum(row, 'valor_obligacion'),
                          ),
                          diasVencido: 0,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _PublicDashboardCard(
            title: 'PAC por mes',
            icon: Icons.calendar_month,
            color: AppTheme.info,
            child: _pac.isEmpty
                ? Text(
                    'No hay programacion PAC registrada.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final row in _pac)
                        _PublicMonthChip(
                          label: _publicText(row, ['mes', 'periodo']),
                          status: _estadoPac(row),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PublicTransparencyModePanel extends StatefulWidget {
  const _PublicTransparencyModePanel();

  @override
  State<_PublicTransparencyModePanel> createState() =>
      _PublicTransparencyModePanelState();
}

class _PublicTransparencyModePanelState
    extends State<_PublicTransparencyModePanel> {
  bool _loading = true;
  int _reportes = 0;
  int _procesos = 0;
  int _consolidaciones = 0;
  double _transferido = 0;
  double _ejecutado = 0;

  @override
  void initState() {
    super.initState();
    _loadTransparencyData();
  }

  Future<void> _loadTransparencyData() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final reportes = await db.query('reportes_transparencia');
      final procesos = await db.query('procesos_disciplinarios');
      final consolidaciones = await db.query('consolidaciones_nicsp40');
      final transferido = consolidaciones.fold<double>(
        0,
        (sum, row) => sum + _publicNum(row, 'valor_transferido'),
      );
      final ejecutado = consolidaciones.fold<double>(
        0,
        (sum, row) => sum + _publicNum(row, 'valor_ejecutado'),
      );

      if (!mounted) return;
      setState(() {
        _reportes = reportes.length;
        _procesos = procesos.length;
        _consolidaciones = consolidaciones.length;
        _transferido = transferido;
        _ejecutado = ejecutado;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error al cargar transparencia publica: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const EnterprisePanel(child: LinearProgressIndicator());
    }

    final avance = _transferido > 0 ? _ejecutado / _transferido : 0.0;
    return EnterprisePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ModeHeader(
            icon: Icons.public,
            title: 'Transparencia',
            detail: 'Reportes publicados, procesos disciplinarios y NICSP 40.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PublicDashboardKpi(
                label: 'Reportes',
                value: '$_reportes',
                icon: Icons.description,
                color: AppTheme.info,
                detail: 'Transparencia registrados',
              ),
              _PublicDashboardKpi(
                label: 'Disciplinarios',
                value: '$_procesos',
                icon: Icons.security,
                color: AppTheme.warning,
                detail: 'Procesos en control interno',
              ),
              _PublicDashboardKpi(
                label: 'NICSP 40',
                value: '$_consolidaciones',
                icon: Icons.account_balance,
                color: AppTheme.success,
                detail: 'Consolidaciones registradas',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PublicDashboardCard(
            title: 'Ejecucion NICSP 40',
            icon: Icons.trending_up,
            color: AppTheme.success,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PublicProgressBar(
                  label: 'Transferido',
                  value: 1,
                  color: AppTheme.info,
                  valor: _moneyCompact(_transferido),
                ),
                const SizedBox(height: 12),
                _PublicProgressBar(
                  label: 'Ejecutado',
                  value: avance.clamp(0, 1),
                  color: AppTheme.success,
                  valor: _moneyCompact(_ejecutado),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicDashboardKpi extends StatelessWidget {
  const _PublicDashboardKpi({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.detail,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicDashboardCard extends StatelessWidget {
  const _PublicDashboardCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PublicProgressBar extends StatelessWidget {
  const _PublicProgressBar({
    required this.label,
    required this.value,
    required this.color,
    this.valor,
  });

  final String label;
  final double value;
  final Color color;
  final String? valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            if (valor != null)
              Text(
                valor!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              )
            else
              Text(
                '${(value * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

class _PublicMonthChip extends StatelessWidget {
  const _PublicMonthChip({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'critical':
        color = AppTheme.danger;
        break;
      case 'warning':
        color = AppTheme.warning;
        break;
      default:
        color = AppTheme.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status == 'critical'
                ? 'Crítico'
                : status == 'warning'
                ? 'Alerta'
                : 'OK',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _PublicVencimientoItem extends StatelessWidget {
  const _PublicVencimientoItem({
    required this.tipo,
    required this.numero,
    required this.venceEn,
    required this.monto,
  });

  final String tipo;
  final String numero;
  final String venceEn;
  final String monto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            tipo,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.danger,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                numero,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                'Vence en $venceEn',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        Text(
          monto,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.success,
          ),
        ),
      ],
    );
  }
}

class _PublicObligacionItem extends StatelessWidget {
  const _PublicObligacionItem({
    required this.numero,
    required this.proveedor,
    required this.monto,
    required this.diasVencido,
  });

  final String numero;
  final String proveedor;
  final String monto;
  final int diasVencido;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: diasVencido > 10
            ? AppTheme.danger.withValues(alpha: 0.1)
            : AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: diasVencido > 10
              ? AppTheme.danger.withValues(alpha: 0.3)
              : AppTheme.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  numero,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  proveedor,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  'Vencido hace $diasVencido días',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: diasVencido > 10
                        ? AppTheme.danger
                        : AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),
          Text(
            monto,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}

String _moduleSubtitle(String moduleId) {
  return switch (moduleId) {
    'cash' => 'Tesoreria operativa, cierres y movimientos de caja.',
    'sales' => 'Cotizaciones, pedidos, POS, facturacion y cartera.',
    'purchases' => 'Requisiciones, RFQ, ordenes, recepciones y facturas.',
    'inventory' => 'Stock, bodegas, reservas y movimientos warehouse-aware.',
    'clients' => 'CRM, clientes, riesgos, actividades y seguimiento.',
    'suppliers' => 'Proveedores, balances, documentos y condiciones.',
    'accounting' => 'Diario, mayor, politicas contables y cierres.',
    'receivables' => 'Aging, cobros, promesas, limites y bloqueos.',
    'payables' => 'Programacion de pagos, matching y cash forecasting.',
    'vouchers' => 'Comprobantes, trazabilidad y soporte documental.',
    'periods' => 'Periodos contables, bloqueos y gobierno financiero.',
    'financial_statements' => 'Balance, PYG, flujo y reportes oficiales.',
    'reports' => 'BI-ready reporting, filtros, exports y dashboards.',
    'tax_reports' => 'Tax engine, retenciones, exenciones y reportes fiscales.',
    'reconciliation' => 'Conciliacion bancaria, matching y auditoria.',
    'bank_statements' => 'Importacion de extractos y movimientos bancarios.',
    'budgets' => 'Presupuestos, control de gasto y validaciones.',
    'cash_closings' => 'Cierres de caja, turnos y auditoria sensible.',
    'erp_readiness' => 'Dashboard ejecutivo enterprise de todos los contextos.',
    'manual' => 'Documentacion operativa y guias de proceso.',
    'companies' => 'Tenant, empresa, sucursales y configuracion base.',
    'electronic_invoice' =>
      'Facturacion electronica y cumplimiento tributario.',
    'receipts' => 'Recibos, aplicaciones y soporte de pagos.',
        'fixed_assets' => 'Activos, depreciacion, deterioros y disposiciones.',
    'attachments' => 'Adjuntos, evidencia y documentacion transversal.',
    'users' => 'Usuarios, roles, permisos y aislamiento tenant.',
    'audit' => 'Auditoria, eventos, trazabilidad y acciones sensibles.',
    'backups' => 'Respaldos, recuperacion y continuidad operativa.',
    'licensing' => 'Gestion de licencias empresariales, claves y HWID.',
    'settings' => 'Configuracion, modulos, seguridad y parametros.',
    _ => 'Modulo enterprise integrado al workspace ERP.',
  };
}
