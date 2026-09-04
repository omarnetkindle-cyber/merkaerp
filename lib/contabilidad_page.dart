import 'package:flutter/material.dart';
import 'accounting/pages/accounting_diagnostic_page.dart';

import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'bancos_page.dart';
import 'conciliacion_bancaria_page.dart';
import 'db_helper.dart';
import 'declaraciones_tributarias_page.dart';
import 'estados_financieros_page.dart';
import 'extractos_bancarios_page.dart';
import 'numeric_input.dart';
import 'periodos_contables_page.dart';
import 'reportes_fiscales_page.dart';

class ContabilidadPage extends StatefulWidget {
  const ContabilidadPage({super.key});

  @override
  State<ContabilidadPage> createState() => _ContabilidadPageState();
}

class _ContabilidadPageState extends State<ContabilidadPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Map<String, dynamic>> _cuentas = [];
  List<Map<String, dynamic>> _asientos = [];
  List<Map<String, dynamic>> _balance = [];
  bool _cargando = true;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String _filtroTipoCuenta = 'todos';
  Currency? _currency;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarDatos);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final cuentas = await DatabaseHelper.instance.obtenerCuentasContables();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    var asientos = await DatabaseHelper.instance.obtenerAsientosContables();
    final balance = await DatabaseHelper.instance.obtenerBalanceComprobacion();

    // Aplicar filtros de fecha (Mejora 4)
    if (_fechaInicio != null || _fechaFin != null) {
      asientos = asientos.where((a) {
        final fechaStr = a['fecha']?.toString() ?? '';
        if (fechaStr.isEmpty) return false;
        try {
          final fecha = DateTime.parse(fechaStr);
          if (_fechaInicio != null && fecha.isBefore(_fechaInicio!)) {
            return false;
          }
          if (_fechaFin != null) {
            final fechaFinConHora = DateTime(
              _fechaFin!.year,
              _fechaFin!.month,
              _fechaFin!.day,
              23,
              59,
              59,
            );
            if (fecha.isAfter(fechaFinConHora)) return false;
          }
          return true;
        } catch (e) {
          return false;
        }
      }).toList();
    }

    if (!mounted) return;

    setState(() {
      _cuentas = cuentas;
      _asientos = asientos;
      _balance = balance;
      _currency = currency;
      _cargando = false;
    });
  }

  Future<void> _mostrarNuevoAsiento() async {
    if (_cuentas.length < 2) return;

    final conceptoCtrl = TextEditingController();
    final referenciaCtrl = TextEditingController();
    int cuentaDebitoId = _cuentas.first['id'] as int;
    int cuentaCreditoId = _cuentas[1]['id'] as int;
    final montoCtrl = TextEditingController();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nuevo asiento contable'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: conceptoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: referenciaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referencia',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: cuentaDebitoId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Cuenta débito',
                    border: OutlineInputBorder(),
                  ),
                  items: _cuentas.map((cuenta) {
                    return DropdownMenuItem<int>(
                      value: cuenta['id'] as int,
                      child: Text('${cuenta['codigo']} - ${cuenta['nombre']}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => cuentaDebitoId = value);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: cuentaCreditoId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Cuenta crédito',
                    border: OutlineInputBorder(),
                  ),
                  items: _cuentas.map((cuenta) {
                    return DropdownMenuItem<int>(
                      value: cuenta['id'] as int,
                      child: Text('${cuenta['codigo']} - ${cuenta['nombre']}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => cuentaCreditoId = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [NumericInput.decimal],
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final concepto = conceptoCtrl.text.trim();
                if (concepto.isEmpty || _currency == null) return;
                final monto = MoneyValue.fromMajorUnits(
                  montoCtrl.text.replaceAll(',', '.'),
                  currency: _currency,
                );
                if (monto.minorUnits <= 0) return;
                if (cuentaDebitoId == cuentaCreditoId) return;

                await DatabaseHelper.instance.registrarAsientoContable(
                  concepto: concepto,
                  referencia: referenciaCtrl.text.trim(),
                  lineas: [
                    {
                      'cuenta_id': cuentaDebitoId,
                      'debito': monto,
                      'credito': 0,
                      'descripcion': concepto,
                    },
                    {
                      'cuenta_id': cuentaCreditoId,
                      'debito': 0,
                      'credito': monto,
                      'descripcion': concepto,
                    },
                  ],
                );

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardado == true) {
      await _cargarDatos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Asiento registrado y balanceado'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  MoneyValue _money(Object? value) =>
      MoneyValue.fromSql(value, currency: _currency, nullableAsZero: true);

  String _moneda(MoneyValue valor) => valor.format();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contabilidad'),
        actions: [
          IconButton(
            tooltip: 'Diagnóstico contable',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountingDiagnosticPage())),
            icon: const Icon(Icons.health_and_safety_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'PUC'),
            Tab(text: 'Asientos'),
            Tab(text: 'Balance'),
            Tab(text: 'Bancos'),
            Tab(text: 'Conciliación'),
            Tab(text: 'Extractos'),
            Tab(text: 'Estados'),
            Tab(text: 'Fiscal'),
            Tab(text: 'Períodos'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton.extended(
              onPressed: _mostrarNuevoAsiento,
              icon: const Icon(Icons.add),
              label: const Text('Asiento'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _vistaCuentas(),
                _vistaDiario(),
                _vistaBalance(),
                const BancosPage(embedded: true),
                const ConciliacionBancariaPage(embedded: true),
                const ExtractosBancariosPage(embedded: true),
                const EstadosFinancierosPage(embedded: true),
                _vistaFiscal(),
                const PeriodosContablesPage(embedded: true),
              ],
            ),
    );
  }

  Widget _vistaFiscal() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          TabBar(
            tabs: [
              Tab(text: 'Resumen fiscal'),
              Tab(text: 'Declaraciones DIAN/ICA'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ReportesFiscalesPage(embedded: true),
                DeclaracionesTributariasPage(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaBalance() {
    var totalDebito = MoneyValue(minorUnits: 0, currency: _currency!);
    var totalCredito = MoneyValue(minorUnits: 0, currency: _currency!);
    for (final cuenta in _balance) {
      totalDebito += _money(cuenta['debito']);
      totalCredito += _money(cuenta['credito']);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              (totalDebito - totalCredito).minorUnits == 0
                  ? Icons.check_circle
                  : Icons.error,
              color: (totalDebito - totalCredito).minorUnits == 0
                  ? Colors.green
                  : Colors.red,
            ),
            title: const Text('Balance de comprobación'),
            subtitle: Text(
              'Débitos ${_moneda(totalDebito)} · Créditos ${_moneda(totalCredito)}',
            ),
          ),
        ),
        ..._balance.map(
          (c) => Card(
            child: ListTile(
              title: Text('${c['codigo']} - ${c['nombre']}'),
              subtitle: Text(
                'Débito ${_moneda(_money(c['debito']))} · Crédito ${_moneda(_money(c['credito']))}',
              ),
              trailing: Text(
                _moneda(_money(c['saldo'])),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _vistaDiario() {
    return Column(
      children: [
        // Filtros de fecha (Mejora 4)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final fecha = await showDatePicker(
                        context: context,
                        initialDate:
                            _fechaInicio ??
                            DateTime.now().subtract(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (fecha != null) {
                        setState(() => _fechaInicio = fecha);
                        await _cargarDatos();
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha inicio',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Text(
                        _fechaInicio != null
                            ? '${_fechaInicio!.day}/${_fechaInicio!.month}/${_fechaInicio!.year}'
                            : 'Todas',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final fecha = await showDatePicker(
                        context: context,
                        initialDate: _fechaFin ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (fecha != null) {
                        setState(() => _fechaFin = fecha);
                        await _cargarDatos();
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha fin',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Text(
                        _fechaFin != null
                            ? '${_fechaFin!.day}/${_fechaFin!.month}/${_fechaFin!.year}'
                            : 'Todas',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _fechaInicio = null;
                      _fechaFin = null;
                    });
                    _cargarDatos();
                  },
                  tooltip: 'Limpiar filtros',
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _asientos.length,
            itemBuilder: (_, i) {
              final a = _asientos[i];
              return Card(
                child: ListTile(
                  title: Text(a['concepto']?.toString() ?? ''),
                  subtitle: Text(
                    '${a['fecha']} · Ref: ${a['referencia'] ?? ''}',
                  ),
                  trailing: Text(
                    _moneda(_money(a['total'])),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _vistaCuentas() {
    // Filtrar cuentas por tipo
    List<Map<String, dynamic>> cuentasFiltradas = _cuentas;
    if (_filtroTipoCuenta != 'todos') {
      cuentasFiltradas = _cuentas
          .where((c) => c['tipo']?.toString() == _filtroTipoCuenta)
          .toList();
    }

    return Column(
      children: [
        // Filtro por tipo de cuenta
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text(
                  'Filtrar por tipo: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _filtroTipoCuenta,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'activo', child: Text('Activos')),
                      DropdownMenuItem(value: 'pasivo', child: Text('Pasivos')),
                      DropdownMenuItem(
                        value: 'patrimonio',
                        child: Text('Patrimonio'),
                      ),
                      DropdownMenuItem(
                        value: 'ingreso',
                        child: Text('Ingresos'),
                      ),
                      DropdownMenuItem(value: 'gasto', child: Text('Gastos')),
                      DropdownMenuItem(value: 'costo', child: Text('Costos')),
                      DropdownMenuItem(
                        value: 'costo_venta',
                        child: Text('Costos de Venta'),
                      ),
                      DropdownMenuItem(
                        value: 'cuenta_orden_debito',
                        child: Text('Cuentas de Orden Débito'),
                      ),
                      DropdownMenuItem(
                        value: 'cuenta_orden_credito',
                        child: Text('Cuentas de Orden Crédito'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _filtroTipoCuenta = value ?? 'todos');
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // Lista de cuentas filtradas
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: cuentasFiltradas.length,
            itemBuilder: (_, i) {
              final c = cuentasFiltradas[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(c['codigo']?.toString() ?? ''),
                  ),
                  title: Text(c['nombre']?.toString() ?? ''),
                  subtitle: Text('${c['tipo']} · ${c['naturaleza']}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
