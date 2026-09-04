import 'package:flutter/material.dart';

import 'core/currency/currency.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'logo_widget.dart';
import 'numeric_input.dart';
import 'ui/enterprise_design_system.dart';

class ConciliacionBancariaPage extends StatefulWidget {
  const ConciliacionBancariaPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ConciliacionBancariaPage> createState() =>
      _ConciliacionBancariaPageState();
}

class _ConciliacionBancariaPageState extends State<ConciliacionBancariaPage> {
  List<Map<String, dynamic>> _bancos = [];
  int? _bancoSel;
  List<Map<String, dynamic>> _lineasLibro = [];
  List<Map<String, dynamic>> _extractos = [];
  int? _lineaSel;
  int? _extractoSel;
  MoneyValue? _diferencia;
  Currency? _currency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_init);
      }
    });
  }

  Future<void> _init() async {
    final bancos = await DatabaseHelper.instance.obtenerBancos();
    if (!mounted) return;
    setState(() {
      _bancos = bancos;
      if (bancos.isNotEmpty) {
        _bancoSel = bancos.first['id'] as int;
      }
    });
    if (_bancoSel != null) await _cargarDatos(_bancoSel!);
  }

  Future<void> _cargarDatos(int bancoId) async {
    final saldoBanco = await DatabaseHelper.instance.obtenerSaldoBanco(bancoId);
    final currency = saldoBanco.currency;
    final lineas = await DatabaseHelper.instance
        .obtenerLineasContablesBancariasNoConciliadas(bancoId);
    final extractos = await DatabaseHelper.instance.obtenerExtractosPorBanco(
      bancoId,
    );
    final pendientes = extractos
        .where((e) => (e['conciliado'] as int? ?? 0) == 0)
        .toList();
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    final sumLibro = lineas.fold<MoneyValue>(
      zero,
      (s, l) =>
          s +
          MoneyValue.fromSql(
            l['debito'],
            currency: currency,
            nullableAsZero: true,
          ) -
          MoneyValue.fromSql(
            l['credito'],
            currency: currency,
            nullableAsZero: true,
          ),
    );
    final sumExtracto = pendientes.fold<MoneyValue>(
      zero,
      (s, e) =>
          s +
          MoneyValue.fromSql(
            e['valor'],
            currency: currency,
            nullableAsZero: true,
          ),
    );
    if (!mounted) return;
    setState(() {
      _lineasLibro = lineas;
      _extractos = pendientes;
      _currency = currency;
      _diferencia = sumExtracto - sumLibro;
      _lineaSel = null;
      _extractoSel = null;
    });
  }

  Future<void> _conciliar() async {
    if (_lineaSel == null || _extractoSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione una línea del libro y una del extracto'),
        ),
      );
      return;
    }
    await DatabaseHelper.instance.conciliarTransacciones(
      _extractoSel!,
      _lineaSel!,
    );
    if (_bancoSel != null) await _cargarDatos(_bancoSel!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transacciones conciliadas'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _fmt(MoneyValue? value) => value?.format() ?? '-';

  Future<void> _registrarConciliacionSimple() async {
    var cuenta = 'banco';
    final extractoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    final saldoCaja = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      'caja',
    );
    final saldoBanco = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      'banco',
    );
    extractoCtrl.text = saldoBanco.toMajorUnitsString();
    if (!mounted) return;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final saldoLibros = cuenta == 'banco' ? saldoBanco : saldoCaja;
          return AlertDialog(
            title: const Text('Conciliación rápida'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'banco', label: Text('Banco')),
                    ButtonSegment(value: 'caja', label: Text('Caja')),
                  ],
                  selected: {cuenta},
                  onSelectionChanged: (s) => setDlg(() {
                    cuenta = s.first;
                    extractoCtrl.text =
                        (cuenta == 'banco' ? saldoBanco : saldoCaja)
                            .toMajorUnitsString();
                  }),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Saldo en libros'),
                  trailing: Text(
                    _fmt(saldoLibros),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextField(
                  controller: extractoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [NumericInput.decimal],
                  decoration: const InputDecoration(
                    labelText: 'Saldo según extracto',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: obsCtrl,
                  decoration: const InputDecoration(labelText: 'Observación'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  final saldoExtracto = MoneyValue.fromMajorUnits(
                    extractoCtrl.text.replaceAll(',', '.'),
                    currency: saldoLibros.currency,
                  );
                  await DatabaseHelper.instance.registrarConciliacionBancaria(
                    cuenta: cuenta,
                    saldoExtracto: saldoExtracto,
                    observacion: obsCtrl.text.trim(),
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    if (guardado == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Conciliación registrada')));
    }
  }

  Widget _lista({
    required String titulo,
    required List<Map<String, dynamic>> items,
    required int? seleccion,
    required ValueChanged<int> onSelect,
    required bool esLibro,
  }) {
    return Expanded(
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(EnterpriseSpacing.sm),
              child: Text(
                titulo,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Sin registros pendientes'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        final id = item['id'] as int;
                        final sel = seleccion == id;
                        final currency = _currency;
                        final monto = currency == null
                            ? null
                            : esLibro
                            ? MoneyValue.fromSql(
                                    item['debito'],
                                    currency: currency,
                                    nullableAsZero: true,
                                  ) -
                                  MoneyValue.fromSql(
                                    item['credito'],
                                    currency: currency,
                                    nullableAsZero: true,
                                  )
                            : MoneyValue.fromSql(
                                item['valor'],
                                currency: currency,
                                nullableAsZero: true,
                              );
                        return ListTile(
                          selected: sel,
                          selectedTileColor: AppBrand.secondary.withValues(
                            alpha: 0.12,
                          ),
                          title: Text(
                            esLibro
                                ? item['concepto_asiento']?.toString() ??
                                      item['descripcion']?.toString() ??
                                      ''
                                : item['descripcion']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            item['fecha']?.toString().substring(0, 10) ?? '',
                          ),
                          trailing: Text(
                            _fmt(monto),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => onSelect(id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(EnterpriseSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _bancoSel,
                  decoration: const InputDecoration(
                    labelText: 'Cuenta bancaria',
                    isDense: true,
                  ),
                  items: _bancos
                      .map(
                        (b) => DropdownMenuItem(
                          value: b['id'] as int,
                          child: Text(b['nombre']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _bancoSel = v);
                    await _cargarDatos(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('Diferencia: ${_fmt(_diferencia)}'),
                backgroundColor: (_diferencia?.minorUnits ?? 0) == 0
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.orange.withValues(alpha: 0.15),
              ),
              IconButton(
                tooltip: 'Conciliación rápida',
                onPressed: _registrarConciliacionSimple,
                icon: const Icon(Icons.rule),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _lista(
                titulo: 'Libro auxiliar (PUC bancos)',
                items: _lineasLibro,
                seleccion: _lineaSel,
                onSelect: (id) => setState(() => _lineaSel = id),
                esLibro: true,
              ),
              const SizedBox(width: 8),
              _lista(
                titulo: 'Extracto bancario',
                items: _extractos,
                seleccion: _extractoSel,
                onSelect: (id) => setState(() => _extractoSel = id),
                esLibro: false,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(EnterpriseSpacing.sm),
          child: FilledButton.icon(
            onPressed: _conciliar,
            icon: const Icon(Icons.link),
            label: const Text('Emparejar seleccionados (Match)'),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Conciliación bancaria')),
      body: body,
    );
  }
}
