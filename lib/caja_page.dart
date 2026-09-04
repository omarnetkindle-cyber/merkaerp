import 'package:flutter/material.dart';

import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'logo_widget.dart';
import 'numeric_input.dart';
import 'transferencias_page.dart';
import 'ui/enterprise_design_system.dart';
import 'ui/merka_theme_tokens.dart';

class CajaPage extends StatefulWidget {
  const CajaPage({super.key});

  @override
  State<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends State<CajaPage> {
  List<Map<String, dynamic>> _movimientos = [];
  List<Map<String, dynamic>> _bancos = [];
  Currency? _currency;
  MoneyValue? _saldoCaja;
  MoneyValue? _saldoBanco;
  MoneyValue? _saldoCartera;
  String _filtroCuenta = 'todas';
  String _filtroTipo = 'todos';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarDatos);
      }
    });
  }

  Future<void> _cargarDatos() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final movs = await DatabaseHelper.instance.obtenerMovimientos();
    final bancos = await DatabaseHelper.instance.obtenerBancos();
    final saldoCaja = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      'caja',
    );
    final saldoBanco = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      'banco',
    );
    final saldoCartera = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      'cartera',
    );

    if (!mounted) return;

    setState(() {
      _movimientos = movs;
      _bancos = bancos;
      _currency = currency;
      _saldoCaja = saldoCaja;
      _saldoBanco = saldoBanco;
      _saldoCartera = saldoCartera;
    });
  }

  Future<void> _agregarMovimiento({
    required String tipo,
    required String concepto,
    required MoneyValue monto,
    required String origen,
    int? bancoId,
  }) async {
    if (concepto.trim().isEmpty) {
      throw Exception('El concepto es obligatorio.');
    }
    if (monto.minorUnits <= 0) {
      throw Exception('El monto debe ser mayor que cero.');
    }

    // Validación de saldo insuficiente para egresos
    if (tipo == 'egreso') {
      final cuentaOrigen = bancoId != null ? 'banco' : origen;
      final saldoActual = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
        cuentaOrigen,
      );

      if (saldoActual < monto) {
        throw Exception(
          'Saldo insuficiente en $cuentaOrigen. Saldo actual: '
          '${saldoActual.format()}, monto requerido: ${monto.format()}',
        );
      }
    }

    await DatabaseHelper.instance.insertarMovimiento({
      'tipo': tipo,
      'concepto': concepto,
      'monto': monto.toSql(),
      'fecha': DateTime.now().toIso8601String(),
      'origen': origen,
      'banco_id': bancoId,
    });

    await DatabaseHelper.instance.registrarAsientoMovimientoCaja(
      tipo: tipo,
      concepto: concepto,
      monto: monto,
      origen: bancoId != null ? 'banco' : origen,
    );

    await _cargarDatos();
  }

  void _abrirFormulario() {
    DatabaseHelper.instance.operacionBloqueadaPorCierre().then((bloqueada) {
      if (!mounted) return;
      if (bloqueada) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Caja cerrada. Reabre operacion para registrar movimientos.',
            ),
            backgroundColor: MerkaThemeTokens.warning,
          ),
        );
        return;
      }
      _mostrarFormularioMovimiento();
    });
  }

  Future<void> _abrirTransferencia() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (await DatabaseHelper.instance.operacionBloqueadaPorCierre()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Caja cerrada. Reabre operacion para transferir.'),
          backgroundColor: MerkaThemeTokens.warning,
        ),
      );
      return;
    }

    await navigator.push(
      MaterialPageRoute(builder: (_) => const TransferenciasPage()),
    );

    if (!context.mounted) return;
    await _cargarDatos();
  }

  void _mostrarFormularioMovimiento() {
    String tipoSeleccionado = 'ingreso';
    String cuentaSel = 'caja';
    final conceptoCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Nuevo movimiento'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: cuentaSel,
                  decoration: const InputDecoration(
                    labelText: 'Cuenta origen/destino',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'caja',
                      child: Text('Caja General'),
                    ),
                    const DropdownMenuItem(
                      value: 'banco',
                      child: Text('Banco (general)'),
                    ),
                    ..._bancos.map(
                      (b) => DropdownMenuItem(
                        value: 'banco_${b['id']}',
                        child: Text('${b['nombre']} (${b['numero_cuenta']})'),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setStateDialog(() => cuentaSel = v);
                  },
                ),
                const SizedBox(height: EnterpriseSpacing.sm),
                TextFormField(
                  controller: conceptoCtrl,
                  decoration: const InputDecoration(labelText: 'Concepto'),
                ),
                const SizedBox(height: EnterpriseSpacing.sm),
                TextFormField(
                  controller: montoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [NumericInput.decimal],
                  decoration: const InputDecoration(labelText: 'Monto'),
                ),
                const SizedBox(height: EnterpriseSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: tipoSeleccionado,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'ingreso', child: Text('Ingreso')),
                    DropdownMenuItem(value: 'egreso', child: Text('Egreso')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setStateDialog(() => tipoSeleccionado = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final currency = _currency;
                if (currency == null) return;
                MoneyValue monto;
                try {
                  monto = MoneyValue.fromMajorUnits(
                    montoCtrl.text.replaceAll(',', '.'),
                    currency: currency,
                  );
                } on FormatException {
                  return;
                }
                String origen = 'caja';
                int? bancoId;
                if (cuentaSel.startsWith('banco_')) {
                  bancoId = int.tryParse(cuentaSel.split('_').last);
                  origen = 'banco';
                } else {
                  origen = cuentaSel;
                }

                try {
                  await _agregarMovimiento(
                    tipo: tipoSeleccionado,
                    concepto: conceptoCtrl.text,
                    monto: monto,
                    origen: origen,
                    bancoId: bancoId,
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e.toString().contains('insuficiente')
                            ? 'Fondos insuficientes'
                            : e.toString(),
                      ),
                      backgroundColor: MerkaThemeTokens.danger,
                    ),
                  );
                  return;
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.check),
              label: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _anularMovimiento(Map<String, dynamic> mov) async {
    final id = mov['id'] as int;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular movimiento'),
        content: const Text(
          'Se marcará como anulado y se generará el contrasiento contable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Actualizar estado local inmediatamente para feedback visual
    setState(() {
      _movimientos.removeWhere((m) => m['id'] == id);
    });

    await DatabaseHelper.instance.anularMovimientoCaja(id);

    // Recargar datos completos para asegurar consistencia
    await _cargarDatos();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Movimiento anulado correctamente'),
        backgroundColor: MerkaThemeTokens.success,
      ),
    );
  }

  String _monedaSql(Object? value) {
    final currency = _currency;
    if (currency == null) return '-';
    return MoneyValue.fromSql(
      value,
      currency: currency,
      nullableAsZero: true,
    ).format();
  }

  String _moneda(MoneyValue? value) => value?.format() ?? '-';

  @override
  Widget build(BuildContext context) {
    final movimientos = _movimientosFiltrados;
    final ingresosVisibles = movimientos.fold<int>(
      0,
      (sum, movimiento) => movimiento['tipo'] == 'ingreso'
          ? sum + (movimiento['monto'] as int? ?? 0)
          : sum,
    );
    final egresosVisibles = movimientos.fold<int>(0, (sum, movimiento) {
      final tipo = movimiento['tipo']?.toString();
      if (tipo != 'egreso' && tipo != 'transferencia') return sum;
      return sum + (movimiento['monto'] as int? ?? 0);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja y bancos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar saldos',
            onPressed: _cargarDatos,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: EnterpriseSpacing.sm),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = EnterpriseBreakpoints.fromWidth(
            constraints.maxWidth,
          );
          final padding = viewport.isMobile
              ? EnterpriseSpacing.md
              : EnterpriseSpacing.lg;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              children: [
                _CajaCommandPanel(
                  saldoCaja: _moneda(_saldoCaja),
                  saldoBanco: _moneda(_saldoBanco),
                  cartera: _moneda(_saldoCartera),
                  disponible: _saldoCaja == null || _saldoBanco == null
                      ? '-'
                      : _moneda(_saldoCaja! + _saldoBanco!),
                  movimientos: movimientos.length,
                  ingresos: _monedaSql(ingresosVisibles),
                  egresos: _monedaSql(egresosVisibles),
                  onNewMovement: _abrirFormulario,
                  onTransfer: _abrirTransferencia,
                  onRefresh: _cargarDatos,
                ),
                const SizedBox(height: EnterpriseSpacing.md),
                _CajaFilters(
                  filtroCuenta: _filtroCuenta,
                  filtroTipo: _filtroTipo,
                  onCuenta: (value) => setState(() => _filtroCuenta = value),
                  onTipo: (value) => setState(() => _filtroTipo = value),
                ),
                const SizedBox(height: EnterpriseSpacing.md),
                Expanded(
                  child: EnterprisePanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            EnterpriseSpacing.lg,
                            EnterpriseSpacing.md,
                            EnterpriseSpacing.lg,
                            EnterpriseSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet,
                                color: AppBrand.secondary,
                              ),
                              const SizedBox(width: EnterpriseSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Movimientos de tesoreria',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              EnterpriseStatusPill(
                                icon: Icons.filter_list,
                                label: '${movimientos.length} visibles',
                                color: AppBrand.info,
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        Expanded(
                          child: movimientos.isEmpty
                              ? const _CajaEmptyState()
                              : ListView.separated(
                                  padding: const EdgeInsets.all(
                                    EnterpriseSpacing.md,
                                  ),
                                  itemCount: movimientos.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(
                                        height: EnterpriseSpacing.sm,
                                      ),
                                  itemBuilder: (ctx, i) {
                                    return _MovimientoCajaTile(
                                      movimiento: movimientos[i],
                                      moneda: _monedaSql,
                                      onAnular: () =>
                                          _anularMovimiento(movimientos[i]),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> get _movimientosFiltrados {
    return _movimientos.where((m) {
      final cuentaOk =
          _filtroCuenta == 'todas' || m['origen']?.toString() == _filtroCuenta;
      final tipoOk =
          _filtroTipo == 'todos' || m['tipo']?.toString() == _filtroTipo;
      return cuentaOk && tipoOk;
    }).toList();
  }
}

class _CajaCommandPanel extends StatelessWidget {
  const _CajaCommandPanel({
    required this.saldoCaja,
    required this.saldoBanco,
    required this.cartera,
    required this.disponible,
    required this.movimientos,
    required this.ingresos,
    required this.egresos,
    required this.onNewMovement,
    required this.onTransfer,
    required this.onRefresh,
  });

  final String saldoCaja;
  final String saldoBanco;
  final String cartera;
  final String disponible;
  final int movimientos;
  final String ingresos;
  final String egresos;
  final VoidCallback onNewMovement;
  final VoidCallback onTransfer;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1040;
          final isMobile = constraints.maxWidth < 600;

          // En móvil, mostrar menos métricas
          final metrics = isMobile
              ? [
                  _CajaMetric(
                    'Caja',
                    saldoCaja,
                    Icons.point_of_sale,
                    AppBrand.success,
                  ),
                  _CajaMetric(
                    'Banco',
                    saldoBanco,
                    Icons.account_balance,
                    AppBrand.secondary,
                  ),
                ]
              : [
                  _CajaMetric(
                    'Caja',
                    saldoCaja,
                    Icons.point_of_sale,
                    AppBrand.success,
                  ),
                  _CajaMetric(
                    'Banco',
                    saldoBanco,
                    Icons.account_balance,
                    AppBrand.secondary,
                  ),
                  _CajaMetric(
                    'Disponible',
                    disponible,
                    Icons.account_balance_wallet,
                    AppBrand.info,
                  ),
                  _CajaMetric(
                    'Cartera',
                    cartera,
                    Icons.person_pin,
                    AppBrand.warning,
                  ),
                ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMobile) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppBrand.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet,
                        color: AppBrand.secondary,
                      ),
                    ),
                    const SizedBox(width: EnterpriseSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Caja y tesoreria',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Saldos, movimientos, transferencias y control de caja para operacion diaria.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      IconButton(
                        tooltip: 'Actualizar saldos',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                      ),
                      const SizedBox(width: EnterpriseSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: onTransfer,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Transferir'),
                      ),
                      const SizedBox(width: EnterpriseSpacing.sm),
                      FilledButton.icon(
                        onPressed: onNewMovement,
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo movimiento'),
                      ),
                    ],
                  ],
                ),
              ],
              if (compact) ...[
                const SizedBox(height: EnterpriseSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onNewMovement,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text(
                          'Nuevo',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: EnterpriseSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onTransfer,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text(
                          'Transferir',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: EnterpriseSpacing.sm),
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 20),
                      padding: const EdgeInsets.all(8),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: EnterpriseSpacing.sm),
              Wrap(
                spacing: EnterpriseSpacing.sm,
                runSpacing: EnterpriseSpacing.sm,
                children: [
                  EnterpriseStatusPill(
                    icon: Icons.receipt_long,
                    label: isMobile
                        ? '$movimientos'
                        : '$movimientos movimientos',
                    color: AppBrand.info,
                  ),
                  EnterpriseStatusPill(
                    icon: Icons.south_west,
                    label: isMobile ? ingresos : 'Ingresos $ingresos',
                    color: AppBrand.success,
                  ),
                  if (!isMobile)
                    EnterpriseStatusPill(
                      icon: Icons.north_east,
                      label: 'Salidas $egresos',
                      color: AppBrand.error,
                    ),
                ],
              ),
              const SizedBox(height: EnterpriseSpacing.sm),
              LayoutBuilder(
                builder: (context, grid) {
                  final columns = grid.maxWidth >= 1100
                      ? 4
                      : grid.maxWidth >= 800
                      ? 2
                      : isMobile
                      ? 2
                      : 3;
                  final width =
                      (grid.maxWidth - ((columns - 1) * EnterpriseSpacing.sm)) /
                      columns;
                  return Wrap(
                    spacing: EnterpriseSpacing.sm,
                    runSpacing: EnterpriseSpacing.sm,
                    children: [
                      for (final metric in metrics)
                        SizedBox(
                          width: width,
                          child: _CajaMetricTile(metric: metric),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CajaFilters extends StatelessWidget {
  const _CajaFilters({
    required this.filtroCuenta,
    required this.filtroTipo,
    required this.onCuenta,
    required this.onTipo,
  });

  final String filtroCuenta;
  final String filtroTipo;
  final ValueChanged<String> onCuenta;
  final ValueChanged<String> onTipo;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChipButton(
            label: 'Todas',
            selected: filtroCuenta == 'todas',
            onSelected: () => onCuenta('todas'),
          ),
          _FilterChipButton(
            label: 'Caja',
            selected: filtroCuenta == 'caja',
            onSelected: () => onCuenta('caja'),
          ),
          _FilterChipButton(
            label: 'Banco',
            selected: filtroCuenta == 'banco',
            onSelected: () => onCuenta('banco'),
          ),
          const SizedBox(width: EnterpriseSpacing.md),
          _FilterChipButton(
            label: 'Ingresos',
            selected: filtroTipo == 'ingreso',
            onSelected: () =>
                onTipo(filtroTipo == 'ingreso' ? 'todos' : 'ingreso'),
          ),
          _FilterChipButton(
            label: 'Egresos',
            selected: filtroTipo == 'egreso',
            onSelected: () =>
                onTipo(filtroTipo == 'egreso' ? 'todos' : 'egreso'),
          ),
          _FilterChipButton(
            label: 'Transferencias',
            selected: filtroTipo == 'transferencia',
            onSelected: () => onTipo(
              filtroTipo == 'transferencia' ? 'todos' : 'transferencia',
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: EnterpriseSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _MovimientoCajaTile extends StatelessWidget {
  const _MovimientoCajaTile({
    required this.movimiento,
    required this.moneda,
    this.onAnular,
  });

  final Map<String, dynamic> movimiento;
  final String Function(Object?) moneda;
  final VoidCallback? onAnular;

  @override
  Widget build(BuildContext context) {
    final tipo = movimiento['tipo']?.toString() ?? 'egreso';
    final esIngreso = tipo == 'ingreso';
    final esTransferencia = tipo == 'transferencia';
    final color = esTransferencia
        ? AppBrand.secondary
        : esIngreso
        ? AppBrand.success
        : AppBrand.error;
    final icon = esTransferencia
        ? Icons.swap_horiz
        : esIngreso
        ? Icons.south_west
        : Icons.north_east;
    final monto = movimiento['monto'] as int? ?? 0;
    final valor = esIngreso ? monto : -monto;
    final cuenta = movimiento['origen']?.toString() ?? 'caja';
    final fecha = movimiento['fecha']?.toString() ?? '';

    final activo = (movimiento['activo'] as int? ?? 1) == 1;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(EnterpriseSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(EnterpriseRadii.md),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: EnterpriseSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movimiento['concepto']?.toString() ?? 'Movimiento',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: EnterpriseSpacing.xs),
                  Wrap(
                    spacing: EnterpriseSpacing.sm,
                    runSpacing: EnterpriseSpacing.xs,
                    children: [
                      EnterpriseStatusPill(
                        icon: Icons.account_balance_wallet,
                        label: cuenta,
                        color: AppBrand.info,
                      ),
                      EnterpriseStatusPill(
                        icon: icon,
                        label: tipo,
                        color: color,
                      ),
                    ],
                  ),
                  if (fecha.isNotEmpty) ...[
                    const SizedBox(height: EnterpriseSpacing.xs),
                    Text(
                      fecha,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: EnterpriseSpacing.sm),
            if (onAnular != null && activo)
              IconButton(
                tooltip: 'Anular movimiento',
                icon: const Icon(Icons.block, size: 20),
                onPressed: onAnular,
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                moneda(valor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CajaMetric {
  const _CajaMetric(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _CajaMetricTile extends StatelessWidget {
  const _CajaMetricTile({required this.metric});

  final _CajaMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(EnterpriseSpacing.md),
      decoration: BoxDecoration(
        color: metric.color.withValues(alpha: 0.08),
        border: Border.all(color: metric.color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: Row(
        children: [
          Icon(metric.icon, color: metric.color),
          const SizedBox(width: EnterpriseSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CajaEmptyState extends StatelessWidget {
  const _CajaEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EnterpriseSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet, size: 42),
            const SizedBox(height: EnterpriseSpacing.sm),
            Text(
              'No hay movimientos para mostrar.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              'Registra un ingreso, egreso o cambia los filtros activos.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
