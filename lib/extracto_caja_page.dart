import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'logo_widget.dart';
import 'pdf_output_dialog.dart';
import 'ui/enterprise_design_system.dart';

class ExtractoCajaPage extends StatefulWidget {
  const ExtractoCajaPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ExtractoCajaPage> createState() => _ExtractoCajaPageState();
}

class _ExtractoCajaPageState extends State<ExtractoCajaPage> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();
  String _origen = 'todas';
  List<Map<String, dynamic>> _movimientos = [];
  MoneyValue? _saldoInicial;
  MoneyValue? _ingresos;
  MoneyValue? _egresos;
  bool _cargando = false;

  Future<void> _generar() async {
    setState(() => _cargando = true);
    final movs = await DatabaseHelper.instance.obtenerMovimientosPorPeriodo(
      desde: _desde,
      hasta: _hasta,
      origen: _origen == 'todas' ? null : _origen,
    );
    final saldoActual = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      _origen == 'todas' ? 'caja' : _origen,
    );
    var ing = MoneyValue(minorUnits: 0, currency: saldoActual.currency);
    var egr = MoneyValue(minorUnits: 0, currency: saldoActual.currency);
    for (final m in movs) {
      final monto = MoneyValue.fromSql(
        m['monto'],
        currency: saldoActual.currency,
        nullableAsZero: true,
      );
      if (m['tipo'] == 'ingreso') {
        ing = ing + monto;
      } else {
        egr = egr + monto;
      }
    }
    final saldoInicial = saldoActual - ing + egr;
    if (!mounted) return;
    setState(() {
      _movimientos = movs;
      _ingresos = ing;
      _egresos = egr;
      _saldoInicial = saldoInicial;
      _cargando = false;
    });
  }

  String _moneda(MoneyValue? value) => value?.format() ?? '-';

  MoneyValue? _fromSql(Object? value) {
    final currency = _saldoInicial?.currency;
    if (currency == null) return null;
    return MoneyValue.fromSql(value, currency: currency, nullableAsZero: true);
  }

  Future<void> _exportarPdf() async {
    await PdfOutputDialog.mostrar(
      context: context,
      titulo: 'Extracto de caja',
      generarBytes: () async {
        final empresa = await DatabaseHelper.instance.obtenerEmpresaConfig();
        final pdf = pw.Document();
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            build: (ctx) => [
              pw.Text(
                empresa['nombre']?.toString() ?? 'MerkaERP',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('NIT: ${empresa['nit'] ?? ''}'),
              pw.SizedBox(height: 12),
              pw.Text(
                'Extracto de caja ${_fmt(_desde)} - ${_fmt(_hasta)}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Saldo inicial: ${_moneda(_saldoInicial)}'),
              pw.Text('Total ingresos: ${_moneda(_ingresos)}'),
              pw.Text('Total egresos: ${_moneda(_egresos)}'),
              pw.Text(
                'Saldo final: ${_moneda(_saldoInicial! + _ingresos! - _egresos!)}',
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: ['Fecha', 'Concepto', 'Tipo', 'Monto'],
                data: _movimientos.map((m) {
                  return [
                    m['fecha']?.toString().substring(0, 10) ?? '',
                    m['concepto']?.toString() ?? '',
                    m['tipo']?.toString() ?? '',
                    _moneda(_fromSql(m['monto'])),
                  ];
                }).toList(),
              ),
            ],
          ),
        );
        return pdf.save();
      },
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate(bool desde) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: desde ? _desde : _hasta,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (desde) {
        _desde = picked;
      } else {
        _hasta = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final saldoFinal = _saldoInicial == null
        ? null
        : _saldoInicial! + _ingresos! - _egresos!;
    final content = ListView(
      padding: const EdgeInsets.all(EnterpriseSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(EnterpriseSpacing.md),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(true),
                        child: Text('Desde: ${_fmt(_desde)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(false),
                        child: Text('Hasta: ${_fmt(_hasta)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _origen,
                  decoration: const InputDecoration(labelText: 'Cuenta'),
                  items: const [
                    DropdownMenuItem(value: 'todas', child: Text('Todas')),
                    DropdownMenuItem(value: 'caja', child: Text('Caja')),
                    DropdownMenuItem(value: 'banco', child: Text('Banco')),
                  ],
                  onChanged: (v) => setState(() => _origen = v ?? 'todas'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _cargando ? null : _generar,
                      icon: _cargando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Generar'),
                    ),
                    const SizedBox(width: 8),
                    if (_movimientos.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _exportarPdf,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Exportar PDF'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_movimientos.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip('Saldo inicial', _moneda(_saldoInicial)),
              _MetricChip('Ingresos', _moneda(_ingresos), color: Colors.green),
              _MetricChip('Egresos', _moneda(_egresos), color: Colors.red),
              _MetricChip(
                'Saldo final',
                _moneda(saldoFinal),
                color: AppBrand.secondary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._movimientos.map(
            (m) => Card(
              child: ListTile(
                leading: Icon(
                  m['tipo'] == 'ingreso' ? Icons.south_west : Icons.north_east,
                  color: m['tipo'] == 'ingreso' ? Colors.green : Colors.red,
                ),
                title: Text(m['concepto']?.toString() ?? ''),
                subtitle: Text(
                  '${m['fecha']?.toString().substring(0, 16)} · ${m['origen']}',
                ),
                trailing: Text(
                  _moneda(_fromSql(m['monto'])),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: m['tipo'] == 'ingreso' ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Extracto de caja')),
      body: content,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        Icons.account_balance_wallet,
        color: color ?? AppBrand.info,
        size: 18,
      ),
      label: Text('$label: $value'),
    );
  }
}
