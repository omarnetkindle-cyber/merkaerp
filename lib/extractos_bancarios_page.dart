import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'ui/enterprise_design_system.dart';

class ExtractosBancariosPage extends StatefulWidget {
  const ExtractosBancariosPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ExtractosBancariosPage> createState() => _ExtractosBancariosPageState();
}

class _ExtractosBancariosPageState extends State<ExtractosBancariosPage> {
  List<Map<String, dynamic>> _bancos = [];
  int? _bancoSel;
  List<Map<String, dynamic>> _extractos = [];
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
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final bancos = await DatabaseHelper.instance.obtenerBancos();
    if (!mounted) return;
    setState(() {
      _bancos = bancos;
      _currency = currency;
      if (bancos.isNotEmpty) _bancoSel = bancos.first['id'] as int;
    });
    if (_bancoSel != null) await _cargar(_bancoSel!);
  }

  Future<void> _cargar(int bancoId) async {
    final data = await DatabaseHelper.instance.obtenerExtractosPorBanco(
      bancoId,
    );
    if (!mounted) return;
    setState(() => _extractos = data);
  }

  Future<void> _importarArchivo() async {
    if (_bancoSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registre al menos una cuenta bancaria')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;
    final content = await File(path).readAsString();
    var count = 0;
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.toLowerCase().startsWith('fecha')) continue;
      final parts = line.split(',');
      if (parts.length < 3) continue;
      final currency = _currency;
      if (currency == null) return;
      final valor = MoneyValue.fromMajorUnits(
        parts[2].trim().replaceAll(',', '.'),
        currency: currency,
      );
      await DatabaseHelper.instance.guardarExtractoBancario(
        bancoId: _bancoSel!,
        fecha: parts[0].trim(),
        descripcion: parts[1].trim(),
        monto: valor,
        referencia: parts.length > 3 ? parts[3].trim() : '',
      );
      count++;
    }
    await _cargar(_bancoSel!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count movimientos importados desde archivo')),
    );
  }

  Future<void> _importarCsvManual() async {
    if (_bancoSel == null) return;
    final csvCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pegar extracto CSV'),
        content: TextField(
          controller: csvCtrl,
          minLines: 8,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'fecha,descripcion,valor,referencia',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              for (final raw in csvCtrl.text.split('\n')) {
                final line = raw.trim();
                if (line.isEmpty || line.toLowerCase().startsWith('fecha')) {
                  continue;
                }
                final parts = line.split(',');
                if (parts.length < 3) continue;
                final currency = _currency;
                if (currency == null) return;
                final valor = MoneyValue.fromMajorUnits(
                  parts[2].trim().replaceAll(',', '.'),
                  currency: currency,
                );
                await DatabaseHelper.instance.guardarExtractoBancario(
                  bancoId: _bancoSel!,
                  fecha: parts[0].trim(),
                  descripcion: parts[1].trim(),
                  monto: valor,
                  referencia: parts.length > 3 ? parts[3].trim() : '',
                );
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (ok == true && _bancoSel != null) await _cargar(_bancoSel!);
  }

  String _fmt(Object? value) {
    final currency = _currency;
    if (currency == null) return '-';
    return MoneyValue.fromSql(
      value,
      currency: currency,
      nullableAsZero: true,
    ).format();
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
                    labelText: 'Banco',
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
                    await _cargar(v);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Importar archivo CSV',
                onPressed: _importarArchivo,
                icon: const Icon(Icons.upload_file),
              ),
              IconButton(
                tooltip: 'Pegar CSV',
                onPressed: _importarCsvManual,
                icon: const Icon(Icons.content_paste),
              ),
            ],
          ),
        ),
        Expanded(
          child: _extractos.isEmpty
              ? const Center(child: Text('No hay extractos importados'))
              : ListView.builder(
                  padding: const EdgeInsets.all(EnterpriseSpacing.sm),
                  itemCount: _extractos.length,
                  itemBuilder: (_, i) {
                    final e = _extractos[i];
                    final conciliado = (e['conciliado'] as int? ?? 0) == 1;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          conciliado ? Icons.check_circle : Icons.pending,
                          color: conciliado ? Colors.green : Colors.orange,
                        ),
                        title: Text(e['descripcion']?.toString() ?? ''),
                        subtitle: Text(
                          '${e['fecha']} · ${e['referencia'] ?? ''}',
                        ),
                        trailing: Text(_fmt(e['valor'])),
                      ),
                    );
                  },
                ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Extractos bancarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importarArchivo,
        icon: const Icon(Icons.upload_file),
        label: const Text('Importar archivo'),
      ),
      body: body,
    );
  }
}
