import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'app_session.dart';
import 'core/api/api_contract.dart';
import 'core/api/api_dispatcher.dart';
import 'core/branch/branch_context.dart';
import 'core/company/company_context.dart';
import 'core/database/data_health_service.dart';
import 'core/release/release_readiness.dart';
import 'core/security/enterprise_security_policy.dart';
import 'db_helper.dart';
import 'features/company_configuration_service.dart';
import 'inventory/data/product_repository.dart';
import 'logo_widget.dart';
import 'purchases/data/purchase_repository.dart';
import 'sales/data/sale_repository.dart';

class ErpReadinessPage extends StatefulWidget {
  const ErpReadinessPage({super.key});

  @override
  State<ErpReadinessPage> createState() => _ErpReadinessPageState();
}

class _ErpReadinessPageState extends State<ErpReadinessPage> {
  late final ApiDispatcher _api;
  late Future<_EnterpriseWorkspaceSnapshot> _snapshotFuture;
  final _searchController = TextEditingController();
  String _selectedArea = 'Todos';

  @override
  void initState() {
    super.initState();
    _api = ApiDispatcher(
      products: SqliteProductRepository(),
      sales: SqliteSaleRepository(),
      purchases: SqlitePurchaseRepository(),
    );
    _snapshotFuture = DatabaseHelper.disableAutoLoadsForTests
        ? Completer<_EnterpriseWorkspaceSnapshot>().future
        : Future.microtask(_loadSnapshot);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_EnterpriseWorkspaceSnapshot> _loadSnapshot() async {
    final health = await DataHealthService().audit();
    final release = const ReleaseReadinessService().localRuntimeReport(
      databaseHealthClean: health.blockingIssues.isEmpty,
    );
    final security = EnterpriseSecurityPolicyService();

    final scope = _mapOrEmpty(
      await _dispatch(ApiMethod.get, '/api/v1/platform/scope'),
    );
    final selectors = await _loadScopeSelectors(
      _intValue(scope['company_id'], fallback: 1),
      scope,
    );

    return _EnterpriseWorkspaceSnapshot(
      release: release,
      health: health,
      sensitiveActions: security.sensitiveActions().length,
      scope: scope,
      selectors: selectors,
      executive: _mapOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/cqrs/executive-dashboard'),
      ),
      summary: _mapOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/reports/summary'),
      ),
      arAging: _mapOrEmpty(await _dispatch(ApiMethod.get, '/api/v1/ar/aging')),
      arLedger: _listOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/ar/ledger'),
      ),
      apAging: _mapOrEmpty(await _dispatch(ApiMethod.get, '/api/v1/ap/aging')),
      apLedger: _listOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/ap/ledger'),
      ),
      treasury: _mapOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/treasury/dashboard'),
      ),
      unmatchedBank: _listOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/bank/unmatched'),
      ),
      assets: _listOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/assets/register'),
      ),
      crm: _mapOrEmpty(await _dispatch(ApiMethod.get, '/api/v1/crm/pipeline')),
      reports: _listOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/reports/materialized'),
      ),
      sync: _mapOrEmpty(await _dispatch(ApiMethod.get, '/api/v1/sync/status')),
      telemetry: _mapOrEmpty(
        await _dispatch(ApiMethod.get, '/api/v1/telemetry/health'),
      ),
      commands: _enterpriseCommands(),
    );
  }

  Future<Object?> _dispatch(ApiMethod method, String path) async {
    final response = await _api.dispatch(
      ApiRequest(
        method: method,
        path: path,
        role: AppSession.rol ?? 'consulta',
        userId: AppSession.nombre,
        requestId: 'ui-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    if (response.ok) return response.data;
    return {
      'error': response.error ?? 'No disponible',
      'status_code': response.statusCode,
    };
  }

  Future<_ScopeSelectors> _loadScopeSelectors(
    int activeCompanyId,
    Map<String, Object?> scope,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final companies = await db.query(
      'companies',
      where: 'active = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    final branches = await db.query(
      'branches',
      where: 'company_id = ? AND active = ?',
      whereArgs: [activeCompanyId, 1],
      orderBy: 'name ASC',
    );

    return _ScopeSelectors(
      companies: companies.isEmpty
          ? [
              _ScopeOption(
                id: _intValue(scope['company_id'], fallback: 1),
                name: scope['company_name']?.toString() ?? 'MerkaERP',
              ),
            ]
          : companies.map(_scopeOptionFromCompany).toList(),
      branches: branches.isEmpty
          ? [
              _ScopeOption(
                id: _intValue(scope['branch_id'], fallback: 1),
                name: scope['branch_name']?.toString() ?? 'Sucursal principal',
              ),
            ]
          : branches.map(_scopeOptionFromBranch).toList(),
    );
  }

  _ScopeOption _scopeOptionFromCompany(Map<String, Object?> row) {
    return _ScopeOption(
      id: _intValue(row['id'], fallback: 1),
      name: row['name']?.toString() ?? 'MerkaERP',
    );
  }

  _ScopeOption _scopeOptionFromBranch(Map<String, Object?> row) {
    return _ScopeOption(
      id: _intValue(row['id'], fallback: 1),
      name: row['name']?.toString() ?? 'Sucursal principal',
    );
  }

  Future<void> _selectCompany(int companyId) async {
    final db = await DatabaseHelper.instance.database;
    await _writeAppConfig(db, 'company_active_id', companyId);

    final branchRows = await db.query(
      'branches',
      where: 'company_id = ? AND active = ?',
      whereArgs: [companyId, 1],
      orderBy: 'name ASC',
      limit: 1,
    );
    if (branchRows.isNotEmpty) {
      await _writeAppConfig(
        db,
        'branch_active_id',
        _intValue(branchRows.first['id'], fallback: 1),
      );
    }

    await CompanyConfigurationService.instance.loadActive(force: true);
    await CompanyContextService.instance.current(force: true);
    BranchContextService.instance.clear();
    _reload();
  }

  Future<void> _selectBranch(int branchId) async {
    final db = await DatabaseHelper.instance.database;
    await _writeAppConfig(db, 'branch_active_id', branchId);
    BranchContextService.instance.clear();
    _reload();
  }

  Future<void> _writeAppConfig(Database db, String key, int value) async {
    await db.insert('app_config', {
      'clave': key,
      'valor': value.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _loadSnapshot();
    });
  }

  void _showCommandPalette(_EnterpriseWorkspaceSnapshot snapshot) {
    var query = _searchController.text;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final commands = _filteredCommands(snapshot.commands, query);
            return AlertDialog(
              title: const Text('Paleta de comandos'),
              content: SizedBox(
                width: 640,
                height: 460,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar proceso, endpoint o contexto',
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          query = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: commands.isEmpty
                          ? const _EmptyState(
                              icon: Icons.manage_search,
                              title: 'Sin resultados',
                              detail:
                                  'Ajusta la busqueda o cambia el filtro de area.',
                            )
                          : ListView.separated(
                              itemCount: commands.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = commands[index];
                                return ListTile(
                                  leading: Icon(item.icon, color: item.color),
                                  title: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    item.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    item.area,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: AppBrand.muted),
                                  ),
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    setState(() {
                                      _selectedArea = item.area;
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<_CommandItem> _filteredCommands(
    List<_CommandItem> commands,
    String query,
  ) {
    final normalized = query.toLowerCase().trim();
    return commands.where((item) {
      final areaMatch = _selectedArea == 'Todos' || item.area == _selectedArea;
      if (!areaMatch) return false;
      if (normalized.isEmpty) return true;
      return item.searchText.contains(normalized);
    }).toList();
  }

  bool _areaVisible(String area) =>
      _selectedArea == 'Todos' || _selectedArea == area;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EnterpriseWorkspaceSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            appBar: _WorkspaceAppBar(),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: const _WorkspaceAppBar(),
            body: _LoadError(
              message: snapshot.error?.toString() ?? 'No fue posible cargar.',
              onRetry: _reload,
            ),
          );
        }

        final data = snapshot.data!;
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _OpenCommandPaletteIntent(),
            SingleActivator(LogicalKeyboardKey.f5): _RefreshWorkspaceIntent(),
          },
          child: Actions(
            actions: {
              _OpenCommandPaletteIntent:
                  CallbackAction<_OpenCommandPaletteIntent>(
                    onInvoke: (_) {
                      _showCommandPalette(data);
                      return null;
                    },
                  ),
              _RefreshWorkspaceIntent: CallbackAction<_RefreshWorkspaceIntent>(
                onInvoke: (_) {
                  _reload();
                  return null;
                },
              ),
            },
            child: DefaultTabController(
              length: 6,
              child: Scaffold(
                appBar: _WorkspaceAppBar(
                  onRefresh: _reload,
                  onCommandPalette: () => _showCommandPalette(data),
                ),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WorkspaceHeader(
                          snapshot: data,
                          searchController: _searchController,
                          selectedArea: _selectedArea,
                          onSearchChanged: (_) => setState(() {}),
                          onAreaChanged: (area) {
                            setState(() {
                              _selectedArea = area;
                            });
                          },
                          onCompanySelected: _selectCompany,
                          onBranchSelected: _selectBranch,
                        ),
                        const SizedBox(height: 10),
                        const _WorkspaceTabs(),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _ExecutiveTab(
                                snapshot: data,
                                query: _searchController.text,
                                visible: _areaVisible('Plataforma'),
                              ),
                              _FinanceTab(
                                snapshot: data,
                                query: _searchController.text,
                                visible: _areaVisible('Finanzas'),
                              ),
                              _TreasuryTab(
                                snapshot: data,
                                query: _searchController.text,
                                visible: _areaVisible('Tesoreria'),
                              ),
                              _CrmTab(
                                snapshot: data,
                                query: _searchController.text,
                                visible: _areaVisible('CRM'),
                              ),
                              _AssetsTab(
                                snapshot: data,
                                query: _searchController.text,
                                visible: _areaVisible('Activos'),
                              ),
                              _ReportingTab(
                                snapshot: data,
                                query: _searchController.text,
                                visible: _areaVisible('Reportes'),
                              ),
                            ],
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
      },
    );
  }
}

class _WorkspaceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _WorkspaceAppBar({this.onRefresh, this.onCommandPalette});

  final VoidCallback? onRefresh;
  final VoidCallback? onCommandPalette;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const MerkaBrandHeader(compact: true),
      actions: [
        IconButton(
          tooltip: 'Buscar comandos',
          onPressed: onCommandPalette,
          icon: const Icon(Icons.manage_search),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.snapshot,
    required this.searchController,
    required this.selectedArea,
    required this.onSearchChanged,
    required this.onAreaChanged,
    required this.onCompanySelected,
    required this.onBranchSelected,
  });

  final _EnterpriseWorkspaceSnapshot snapshot;
  final TextEditingController searchController;
  final String selectedArea;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<int> onCompanySelected;
  final ValueChanged<int> onBranchSelected;

  @override
  Widget build(BuildContext context) {
    final scope = snapshot.scope;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _erpPanelColor(context),
            border: Border.all(color: _erpBorderColor(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? constraints.maxWidth : 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workspace enterprise',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _erpTextColor(context),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Sesion: ${AppSession.nombre}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppBrand.muted),
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
                        suffixIcon: searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar busqueda',
                                onPressed: () {
                                  searchController.clear();
                                  onSearchChanged('');
                                },
                                icon: const Icon(Icons.close),
                              ),
                        hintText: 'Buscar cliente, proveedor, banco o reporte',
                      ),
                    ),
                  ),
                  _ScopeSelector(
                    label: 'Tenant',
                    icon: Icons.domain,
                    value:
                        scope['company_name']?.toString() ?? 'Empresa activa',
                    options: snapshot.selectors.companies,
                    onSelected: onCompanySelected,
                  ),
                  _ScopeSelector(
                    label: 'Sucursal',
                    icon: Icons.store,
                    value:
                        scope['branch_name']?.toString() ??
                        'Sucursal principal',
                    options: snapshot.selectors.branches,
                    onSelected: onBranchSelected,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final area in _areas)
                    ChoiceChip(
                      label: Text(area),
                      selected: selectedArea == area,
                      onSelected: (_) => onAreaChanged(area),
                    ),
                  _ScopeChip(
                    icon: Icons.warehouse,
                    label: 'Bodega ${scope['warehouse_id'] ?? 1}',
                  ),
                  _ScopeChip(
                    icon: Icons.business_center,
                    label: 'Centro ${scope['cost_center_id'] ?? 1}',
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

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final String value;
  final List<_ScopeOption> options;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<int>(value: option.id, child: Text(option.name)),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 40, maxWidth: 230),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _erpSoftColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _erpBorderColor(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _erpAccentColor(context)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: AppBrand.muted),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _erpTextColor(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: _erpAccentColor(context)),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _WorkspaceTabs extends StatelessWidget {
  const _WorkspaceTabs();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: Theme.of(context).colorScheme.secondary,
        unselectedLabelColor: AppBrand.muted,
        indicatorColor: Theme.of(context).colorScheme.secondary,
        tabs: const [
          Tab(icon: Icon(Icons.dashboard), text: 'Ejecutivo'),
          Tab(icon: Icon(Icons.account_balance), text: 'Finanzas'),
          Tab(icon: Icon(Icons.account_balance_wallet), text: 'Tesoreria'),
          Tab(icon: Icon(Icons.handshake), text: 'CRM'),
          Tab(icon: Icon(Icons.factory), text: 'Activos'),
          Tab(icon: Icon(Icons.query_stats), text: 'Reportes'),
        ],
      ),
    );
  }
}

class _ExecutiveTab extends StatelessWidget {
  const _ExecutiveTab({
    required this.snapshot,
    required this.query,
    required this.visible,
  });

  final _EnterpriseWorkspaceSnapshot snapshot;
  final String query;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const _FilteredOutHint(area: 'Plataforma');
    final inventory = _mapOrEmpty(snapshot.summary['inventory']);
    final telemetry = snapshot.telemetry;
    final sync = snapshot.sync;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              title: 'Ventas',
              value: _money(_doubleValue(snapshot.summary['sales_total'])),
              icon: Icons.receipt_long,
              color: AppBrand.primary,
            ),
            _MetricData(
              title: 'Compras',
              value: _money(_doubleValue(snapshot.summary['purchases_total'])),
              icon: Icons.shopping_bag,
              color: AppBrand.secondary,
            ),
            _MetricData(
              title: 'Stock valorizado',
              value: _money(_doubleValue(inventory['cost_value'])),
              icon: Icons.inventory_2,
              color: AppBrand.accent,
            ),
            _MetricData(
              title: 'Caja proyectada',
              value: _money(
                _doubleValue(snapshot.treasury['projected_cash_flow']),
              ),
              icon: Icons.timeline,
              color: AppBrand.info,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _SectionPanel(
          title: 'Controles operativos',
          icon: Icons.verified_user,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusBadge(
                label: 'Release',
                value: snapshot.release.readyForProduction
                    ? 'Produccion'
                    : snapshot.release.readyForPilot
                    ? 'Piloto'
                    : 'Bloqueado',
                color: snapshot.release.readyForProduction
                    ? AppBrand.secondary
                    : snapshot.release.readyForPilot
                    ? AppBrand.primary
                    : Colors.red.shade700,
              ),
              _StatusBadge(
                label: 'Datos',
                value: '${snapshot.health.activeIssues.length} hallazgos',
                color: snapshot.health.blockingIssues.isEmpty
                    ? AppBrand.secondary
                    : Colors.red.shade700,
              ),
              _StatusBadge(
                label: 'Sync',
                value:
                    '${_intValue(sync['pending_outbox'], fallback: 0)} pendientes',
                color: _intValue(sync['conflicts'], fallback: 0) == 0
                    ? AppBrand.secondary
                    : Colors.red.shade700,
              ),
              _StatusBadge(
                label: 'Telemetry',
                value: telemetry.isEmpty ? 'Local' : 'Activo',
                color: AppBrand.primary,
              ),
              _StatusBadge(
                label: 'Auditoria',
                value: '${snapshot.sensitiveActions} sensibles',
                color: AppBrand.secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _ApiSurface(
          commands: _filterCommandRows(snapshot.commands, query),
          title: 'Superficie enterprise activa',
        ),
      ],
    );
  }
}

class _FinanceTab extends StatelessWidget {
  const _FinanceTab({
    required this.snapshot,
    required this.query,
    required this.visible,
  });

  final _EnterpriseWorkspaceSnapshot snapshot;
  final String query;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const _FilteredOutHint(area: 'Finanzas');
    final arOpen = _sumNumeric(snapshot.arAging);
    final apOpen = _sumNumeric(snapshot.apAging);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              title: 'Cartera abierta',
              value: _money(arOpen),
              icon: Icons.request_quote,
              color: AppBrand.primary,
            ),
            _MetricData(
              title: 'CXP abierta',
              value: _money(apOpen),
              icon: Icons.payments,
              color: AppBrand.secondary,
            ),
            _MetricData(
              title: 'Riesgo neto',
              value: _money(arOpen - apOpen),
              icon: Icons.monitor_heart,
              color: AppBrand.secondary,
            ),
            _MetricData(
              title: 'Liquidez proyectada',
              value: _money(
                _doubleValue(snapshot.treasury['projected_cash_flow']),
              ),
              icon: Icons.waterfall_chart,
              color: AppBrand.success,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _SectionPanel(
          title: 'Aging financiero',
          icon: Icons.calendar_month,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 780;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: compact
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2,
                    child: _AgingBars(
                      title: 'Cuentas por cobrar',
                      data: snapshot.arAging,
                    ),
                  ),
                  SizedBox(
                    width: compact
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2,
                    child: _AgingBars(
                      title: 'Cuentas por pagar',
                      data: snapshot.apAging,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _EnterpriseTable(
          title: 'Ledger de clientes',
          icon: Icons.people,
          rows: _filterRows(snapshot.arLedger, query),
          columns: const [
            _TableColumn('Cliente', 'customer_name'),
            _TableColumn('Documento', 'document_id'),
            _TableColumn('Tipo', 'entry_type'),
            _TableColumn('Vence', 'due_date'),
            _TableColumn('Abierto', 'open_amount', numeric: true),
          ],
        ),
        const SizedBox(height: 10),
        _EnterpriseTable(
          title: 'Ledger de proveedores',
          icon: Icons.business,
          rows: _filterRows(snapshot.apLedger, query),
          columns: const [
            _TableColumn('Proveedor', 'supplier_name'),
            _TableColumn('Documento', 'document_id'),
            _TableColumn('Estado', 'status'),
            _TableColumn('Vence', 'due_date'),
            _TableColumn('Abierto', 'open_amount', numeric: true),
          ],
        ),
      ],
    );
  }
}

class _TreasuryTab extends StatelessWidget {
  const _TreasuryTab({
    required this.snapshot,
    required this.query,
    required this.visible,
  });

  final _EnterpriseWorkspaceSnapshot snapshot;
  final String query;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const _FilteredOutHint(area: 'Tesoreria');
    final treasury = snapshot.treasury;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              title: 'Cuentas bancarias',
              value: '${_intValue(treasury['bank_accounts'], fallback: 0)}',
              icon: Icons.account_balance,
              color: AppBrand.info,
            ),
            _MetricData(
              title: 'Posicion',
              value: _money(_doubleValue(treasury['treasury_position'])),
              icon: Icons.account_balance_wallet,
              color: AppBrand.primary,
            ),
            _MetricData(
              title: 'Entradas',
              value: _money(_doubleValue(treasury['inflow'])),
              icon: Icons.south_west,
              color: AppBrand.success,
            ),
            _MetricData(
              title: 'Salidas',
              value: _money(_doubleValue(treasury['outflow'])),
              icon: Icons.north_east,
              color: AppBrand.error,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _EnterpriseTable(
          title: 'Operaciones sin conciliar',
          icon: Icons.rule,
          rows: _filterRows(snapshot.unmatchedBank, query),
          columns: const [
            _TableColumn('Banco', 'bank_account_id'),
            _TableColumn('Fecha', 'movement_date'),
            _TableColumn('Referencia', 'reference'),
            _TableColumn('Descripcion', 'description'),
            _TableColumn('Monto', 'amount', numeric: true),
          ],
        ),
      ],
    );
  }
}

class _CrmTab extends StatelessWidget {
  const _CrmTab({
    required this.snapshot,
    required this.query,
    required this.visible,
  });

  final _EnterpriseWorkspaceSnapshot snapshot;
  final String query;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const _FilteredOutHint(area: 'CRM');
    final values = _mapOrEmpty(snapshot.crm['value_by_stage']);
    final items = _listOrEmpty(snapshot.crm['items']);
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              title: 'Oportunidades',
              value:
                  '${_intValue(snapshot.crm['count'], fallback: items.length)}',
              icon: Icons.handshake,
              color: AppBrand.secondary,
            ),
            _MetricData(
              title: 'Pipeline',
              value: _money(_sumNumeric(values)),
              icon: Icons.filter_alt,
              color: AppBrand.warning,
            ),
            _MetricData(
              title: 'Lead',
              value: _money(_doubleValue(values['lead'])),
              icon: Icons.flag,
              color: AppBrand.accent,
            ),
            _MetricData(
              title: 'Ganadas',
              value: _money(_doubleValue(values['won'])),
              icon: Icons.emoji_events,
              color: AppBrand.success,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _EnterpriseTable(
          title: 'Pipeline comercial',
          icon: Icons.timeline,
          rows: _filterRows(items, query),
          columns: const [
            _TableColumn('Cliente', 'customer_name'),
            _TableColumn('Etapa', 'stage'),
            _TableColumn('Valor', 'value', numeric: true),
            _TableColumn('Prob.', 'probability', numeric: true),
            _TableColumn('Seguimiento', 'next_follow_up_at'),
          ],
        ),
      ],
    );
  }
}

class _AssetsTab extends StatelessWidget {
  const _AssetsTab({
    required this.snapshot,
    required this.query,
    required this.visible,
  });

  final _EnterpriseWorkspaceSnapshot snapshot;
  final String query;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const _FilteredOutHint(area: 'Activos');
    final assets = snapshot.assets;
    final currentValue = assets.fold<double>(
      0,
      (sum, row) => sum + _doubleValue(row['current_value']),
    );
    final depreciation = assets.fold<double>(
      0,
      (sum, row) => sum + _doubleValue(row['accumulated_depreciation']),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              title: 'Activos registrados',
              value: '${assets.length}',
              icon: Icons.factory,
              color: AppBrand.primary,
            ),
            _MetricData(
              title: 'Valor libros',
              value: _money(currentValue),
              icon: Icons.balance,
              color: AppBrand.success,
            ),
            _MetricData(
              title: 'Depreciacion acum.',
              value: _money(depreciation),
              icon: Icons.trending_down,
              color: AppBrand.secondary,
            ),
            _MetricData(
              title: 'Base depreciable',
              value: _money(currentValue + depreciation),
              icon: Icons.calculate,
              color: AppBrand.accent,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _EnterpriseTable(
          title: 'Registro de activos',
          icon: Icons.precision_manufacturing,
          rows: _filterRows(assets, query),
          columns: const [
            _TableColumn('Codigo', 'code'),
            _TableColumn('Nombre', 'name'),
            _TableColumn('Estado', 'status'),
            _TableColumn('Valor', 'current_value', numeric: true),
            _TableColumn('Vida util', 'useful_life_months', numeric: true),
          ],
        ),
      ],
    );
  }
}

class _ReportingTab extends StatelessWidget {
  const _ReportingTab({
    required this.snapshot,
    required this.query,
    required this.visible,
  });

  final _EnterpriseWorkspaceSnapshot snapshot;
  final String query;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const _FilteredOutHint(area: 'Reportes');
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              title: 'Reportes materializados',
              value: '${snapshot.reports.length}',
              icon: Icons.bar_chart,
              color: AppBrand.secondary,
            ),
            _MetricData(
              title: 'Endpoints BI',
              value:
                  '${snapshot.commands.where((item) => item.area == 'Reportes').length}',
              icon: Icons.api,
              color: AppBrand.accent,
            ),
            _MetricData(
              title: 'Contextos',
              value: '8',
              icon: Icons.hub,
              color: AppBrand.primary,
            ),
            _MetricData(
              title: 'Exports',
              value: 'PDF XLS JSON',
              icon: Icons.file_download,
              color: AppBrand.error,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _EnterpriseTable(
          title: 'Reportes materializados',
          icon: Icons.dataset,
          rows: _filterRows(snapshot.reports, query),
          columns: const [
            _TableColumn('Dataset', 'dataset'),
            _TableColumn('Formato', 'format'),
            _TableColumn('Titulo', 'title'),
            _TableColumn('Creado', 'created_at'),
            _TableColumn('Filas', 'row_count', numeric: true),
          ],
        ),
        const SizedBox(height: 10),
        _ApiSurface(
          commands: _filterCommandRows(
            snapshot.commands.where((item) => item.area == 'Reportes').toList(),
            query,
          ),
          title: 'Comandos de reporting',
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricCard(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _MetricData metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _erpPanelColor(context),
        border: Border.all(color: _erpBorderColor(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: metric.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(metric.icon, color: metric.color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  metric.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppBrand.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _erpTextColor(context),
                    fontWeight: FontWeight.w900,
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

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _erpPanelColor(context),
        border: Border.all(color: _erpBorderColor(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: title, icon: icon),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _erpAccentColor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _erpTextColor(context),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _AgingBars extends StatelessWidget {
  const _AgingBars({required this.title, required this.data});

  final String title;
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final total = _sumNumeric(data);
    final rows = [
      ('Corriente', 'current'),
      ('1-30', '1_30'),
      ('31-60', '31_60'),
      ('61-90', '61_90'),
      ('90+', '90_plus'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _erpSoftColor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final row in rows) ...[
            _AgingRow(
              label: row.$1,
              amount: _doubleValue(data[row.$2]),
              total: total <= 0 ? 1 : total,
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _AgingRow extends StatelessWidget {
  const _AgingRow({
    required this.label,
    required this.amount,
    required this.total,
  });

  final String label;
  final double amount;
  final double total;

  @override
  Widget build(BuildContext context) {
    final fraction = (amount / total).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: _erpSoftColor(context),
              valueColor: AlwaysStoppedAnimation(_erpAccentColor(context)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Text(
            _money(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _EnterpriseTable extends StatelessWidget {
  const _EnterpriseTable({
    required this.title,
    required this.icon,
    required this.rows,
    required this.columns,
  });

  final String title;
  final IconData icon;
  final List<Map<String, Object?>> rows;
  final List<_TableColumn> columns;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: title,
      icon: icon,
      child: rows.isEmpty
          ? const _EmptyState(
              icon: Icons.table_rows,
              title: 'Sin registros',
              detail: 'No hay operaciones para el alcance y filtro actual.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 640) {
                  return Column(
                    children: [
                      for (final row in rows.take(60))
                        _EnterpriseRecordCard(row: row, columns: columns),
                    ],
                  );
                }

                final tableWidth = constraints.maxWidth < 720
                    ? 720.0
                    : constraints.maxWidth;
                return Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        columnSpacing: 18,
                        headingRowHeight: 38,
                        dataRowMinHeight: 42,
                        dataRowMaxHeight: 56,
                        columns: [
                          for (final column in columns)
                            DataColumn(
                              numeric: column.numeric,
                              label: Text(
                                column.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                        rows: [
                          for (final row in rows.take(120))
                            DataRow(
                              cells: [
                                for (final column in columns)
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minWidth: 80,
                                        maxWidth: 190,
                                      ),
                                      child: Text(
                                        _cellValue(row[column.key]),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: column.numeric
                                            ? TextAlign.right
                                            : TextAlign.left,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _EnterpriseRecordCard extends StatelessWidget {
  const _EnterpriseRecordCard({required this.row, required this.columns});

  final Map<String, Object?> row;
  final List<_TableColumn> columns;

  @override
  Widget build(BuildContext context) {
    final titleColumn = columns.firstWhere(
      (column) => !column.numeric,
      orElse: () => columns.first,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _erpSoftColor(context),
        border: Border.all(color: _erpBorderColor(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _cellValue(row[titleColumn.key]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final column in columns)
            if (column.key != titleColumn.key)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        column.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _cellValue(row[column.key]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _erpTextColor(context),
                          fontWeight: FontWeight.w800,
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

class _ApiSurface extends StatelessWidget {
  const _ApiSurface({required this.commands, required this.title});

  final List<_CommandItem> commands;
  final String title;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: title,
      icon: Icons.api,
      child: commands.isEmpty
          ? const _EmptyState(
              icon: Icons.api,
              title: 'Sin comandos visibles',
              detail: 'El filtro actual no coincide con procesos enterprise.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [
                      for (final command in commands)
                        _CommandTile(command: command),
                    ],
                  );
                }
                final columns = constraints.maxWidth >= 980
                    ? 3
                    : constraints.maxWidth >= 640
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: commands.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: columns == 1 ? 3.25 : 2.7,
                  ),
                  itemBuilder: (context, index) {
                    final command = commands[index];
                    return _CommandTile(command: command);
                  },
                );
              },
            ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({required this.command});

  final _CommandItem command;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _erpSoftColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _erpBorderColor(context)),
      ),
      child: Row(
        children: [
          Icon(command.icon, color: command.color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  command.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  command.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppBrand.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 7),
          Text(
            '$label: $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _erpTextColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: Colors.grey.shade500),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppBrand.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilteredOutHint extends StatelessWidget {
  const _FilteredOutHint({required this.area});

  final String area;

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: Icons.filter_alt,
      title: 'Filtro activo',
      detail: 'Cambia el area a Todos o $area para ver este tablero.',
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 36),
            const SizedBox(height: 8),
            Text(
              'No se cargo el workspace',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppBrand.muted),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnterpriseWorkspaceSnapshot {
  const _EnterpriseWorkspaceSnapshot({
    required this.release,
    required this.health,
    required this.sensitiveActions,
    required this.scope,
    required this.selectors,
    required this.executive,
    required this.summary,
    required this.arAging,
    required this.arLedger,
    required this.apAging,
    required this.apLedger,
    required this.treasury,
    required this.unmatchedBank,
    required this.assets,
    required this.crm,
    required this.reports,
    required this.sync,
    required this.telemetry,
    required this.commands,
  });

  final ReleaseReadinessReport release;
  final DataHealthReport health;
  final int sensitiveActions;
  final Map<String, Object?> scope;
  final _ScopeSelectors selectors;
  final Map<String, Object?> executive;
  final Map<String, Object?> summary;
  final Map<String, Object?> arAging;
  final List<Map<String, Object?>> arLedger;
  final Map<String, Object?> apAging;
  final List<Map<String, Object?>> apLedger;
  final Map<String, Object?> treasury;
  final List<Map<String, Object?>> unmatchedBank;
  final List<Map<String, Object?>> assets;
  final Map<String, Object?> crm;
  final List<Map<String, Object?>> reports;
  final Map<String, Object?> sync;
  final Map<String, Object?> telemetry;
  final List<_CommandItem> commands;
}

class _ScopeSelectors {
  const _ScopeSelectors({required this.companies, required this.branches});

  final List<_ScopeOption> companies;
  final List<_ScopeOption> branches;
}

class _ScopeOption {
  const _ScopeOption({required this.id, required this.name});

  final int id;
  final String name;
}

class _MetricData {
  const _MetricData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
}

class _TableColumn {
  const _TableColumn(this.label, this.key, {this.numeric = false});

  final String label;
  final String key;
  final bool numeric;
}

class _CommandItem {
  const _CommandItem({
    required this.area,
    required this.title,
    required this.path,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String area;
  final String title;
  final String path;
  final String description;
  final IconData icon;
  final Color color;

  String get searchText =>
      '$area $title $path $description'.toLowerCase().trim();
}

class _OpenCommandPaletteIntent extends Intent {
  const _OpenCommandPaletteIntent();
}

class _RefreshWorkspaceIntent extends Intent {
  const _RefreshWorkspaceIntent();
}

const _areas = [
  'Todos',
  'Dinero y Cuentas',
  'Caja y Bancos',
  'Clientes',
  'Inventario',
  'Informes',
  'Configuración',
];

List<_CommandItem> _enterpriseCommands() {
  return ApiContract.endpoints
      .where((endpoint) => _moduleArea(endpoint.module) != null)
      .map(
        (endpoint) => _CommandItem(
          area: _moduleArea(endpoint.module)!,
          title: _moduleTitle(endpoint.module),
          path: '${endpoint.method.name.toUpperCase()} ${endpoint.path}',
          description: endpoint.description,
          icon: _moduleIcon(endpoint.module),
          color: _moduleColor(endpoint.module),
        ),
      )
      .toList();
}

String? _moduleArea(String module) {
  const areas = {
    'accounts_receivable': 'Dinero y Cuentas',
    'accounts_payable': 'Dinero y Cuentas',
    'treasury': 'Caja y Bancos',
    'bank_reconciliation': 'Caja y Bancos',
    'tax': 'Dinero y Cuentas',
    'fixed_assets': 'Inventario',
    'crm': 'Clientes',
    'reports': 'Informes',
    'sync': 'Configuración',
    'telemetry': 'Configuración',
    'events': 'Configuración',
    'settings': 'Configuración',
  };
  return areas[module];
}

String _moduleTitle(String module) {
  const labels = {
    'accounts_receivable': 'Cuentas por Cobrar',
    'accounts_payable': 'Cuentas por Pagar',
    'treasury': 'Tesorería',
    'bank_reconciliation': 'Conciliación Bancaria',
    'tax': 'Impuestos',
    'fixed_assets': 'Activos Fijos',
    'crm': 'Gestión de Clientes',
    'reports': 'Reportes',
    'sync': 'Sincronización',
    'telemetry': 'Telemetría',
    'events': 'Eventos',
    'settings': 'Configuración',
  };
  return labels[module] ?? module;
}

IconData _moduleIcon(String module) {
  const icons = {
    'accounts_receivable': Icons.request_quote,
    'accounts_payable': Icons.payments,
    'treasury': Icons.account_balance_wallet,
    'bank_reconciliation': Icons.rule,
    'tax': Icons.gavel,
    'fixed_assets': Icons.factory,
    'crm': Icons.handshake,
    'reports': Icons.query_stats,
    'sync': Icons.sync,
    'telemetry': Icons.monitor_heart,
    'events': Icons.hub,
    'settings': Icons.tune,
  };
  return icons[module] ?? Icons.api;
}

Color _moduleColor(String module) {
  const colors = {
    'accounts_receivable': AppBrand.primary,
    'accounts_payable': AppBrand.secondary,
    'treasury': AppBrand.primary,
    'bank_reconciliation': AppBrand.success,
    'tax': AppBrand.error,
    'fixed_assets': AppBrand.primary,
    'crm': AppBrand.secondary,
    'reports': AppBrand.secondary,
    'sync': AppBrand.secondary,
    'telemetry': AppBrand.warning,
    'events': AppBrand.accent,
    'settings': AppBrand.muted,
  };
  return colors[module] ?? AppBrand.primary;
}

List<_CommandItem> _filterCommandRows(
  List<_CommandItem> commands,
  String query,
) {
  final normalized = query.toLowerCase().trim();
  if (normalized.isEmpty) return commands;
  return commands
      .where((item) => item.searchText.contains(normalized))
      .toList();
}

List<Map<String, Object?>> _filterRows(
  List<Map<String, Object?>> rows,
  String query,
) {
  final normalized = query.toLowerCase().trim();
  if (normalized.isEmpty) return rows;
  return rows.where((row) {
    return row.values.any(
      (value) => value?.toString().toLowerCase().contains(normalized) ?? false,
    );
  }).toList();
}

Map<String, Object?> _mapOrEmpty(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<Map<String, Object?>> _listOrEmpty(Object? value) {
  if (value is List<Map<String, Object?>>) return value;
  if (value is List) {
    return value
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }
  return const [];
}

double _sumNumeric(Map<String, Object?> data) {
  return data.values.fold<double>(0, (sum, value) => sum + _doubleValue(value));
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _intValue(Object? value, {required int fallback}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

Color _erpPanelColor(BuildContext context) {
  return Theme.of(context).colorScheme.surface;
}

Color _erpSoftColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.colorScheme.surfaceContainerHighest.withValues(
    alpha: theme.brightness == Brightness.dark ? 0.42 : 0.55,
  );
}

Color _erpBorderColor(BuildContext context) {
  return Theme.of(context).colorScheme.outline.withValues(alpha: 0.55);
}

Color _erpTextColor(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface;
}

Color _erpAccentColor(BuildContext context) {
  return Theme.of(context).colorScheme.secondary;
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  final fixed = value.abs().toStringAsFixed(0);
  final buffer = StringBuffer();
  for (var i = 0; i < fixed.length; i++) {
    final remaining = fixed.length - i;
    buffer.write(fixed[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }
  return '$sign\$${buffer.toString()}';
}

String _cellValue(Object? value) {
  if (value == null) return '';
  if (value is num) return value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
  final text = value.toString();
  if (text.length >= 10 && DateTime.tryParse(text) != null) {
    return text.substring(0, 10);
  }
  return text;
}
