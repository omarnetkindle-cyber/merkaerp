import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'pdf_output_dialog.dart';

class EstadosFinancierosPage extends StatefulWidget {
  const EstadosFinancierosPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<EstadosFinancierosPage> createState() => _EstadosFinancierosPageState();
}

class _EstadosFinancierosPageState extends State<EstadosFinancierosPage> {
  Map<String, MoneyValue> estados = {};
  Map<String, dynamic> empresa = {};
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargar);
      }
    });
  }

  Future<void> _cargar() async {
    final data = await DatabaseHelper.instance.obtenerEstadosFinancieros();
    final emp = await DatabaseHelper.instance.obtenerEmpresaConfig();
    if (!mounted) return;
    setState(() {
      estados = data;
      empresa = emp;
      cargando = false;
    });
  }

  String _fmt(MoneyValue? valor) => valor?.format() ?? '-';

  Widget _fila(String titulo, String clave, Color color) {
    final valor = estados[clave];
    return Card(
      child: ListTile(
        title: Text(titulo),
        trailing: Text(
          _fmt(valor),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }

  Future<Uint8List> _generarPdfBytes() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            empresa['nombre']?.toString() ?? 'MerkaERP',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'NIT: ${empresa['nit'] ?? ''} · ${empresa['direccion'] ?? ''}',
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'BALANCE GENERAL',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Activos: ${_fmt(estados['activos'])}'),
          pw.Text('Pasivos: ${_fmt(estados['pasivos'])}'),
          pw.Text('Patrimonio: ${_fmt(estados['patrimonio'])}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'ESTADO DE RESULTADOS',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Ingresos: ${_fmt(estados['ingresos'])}'),
          pw.Text('Costos: ${_fmt(estados['costos'])}'),
          pw.Text('Gastos: ${_fmt(estados['gastos'])}'),
          pw.Text('Utilidad: ${_fmt(estados['utilidad'])}'),
          pw.SizedBox(height: 24),
          pw.Text(
            '_________________________          _________________________',
          ),
          pw.Text('Contador                           Representante Legal'),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> _exportarPdf() async {
    await PdfOutputDialog.mostrar(
      context: context,
      titulo: 'Estados financieros',
      generarBytes: _generarPdfBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final utilidad = estados['utilidad'];
    final cuadre = estados['cuadre'];

    final listView = cargando
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _cargar,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (!widget.embedded)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _exportarPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Exportar PDF corporativo'),
                    ),
                  ),
                const Text(
                  'Balance general',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _fila('Activos', 'activos', Colors.green),
                _fila('Pasivos', 'pasivos', Colors.red),
                _fila('Patrimonio', 'patrimonio', MerkaThemeTokens.info),
                Card(
                  child: ListTile(
                    leading: Icon(
                      cuadre?.minorUnits == 0
                          ? Icons.check_circle
                          : Icons.error,
                      color: cuadre?.minorUnits == 0
                          ? Colors.green
                          : Colors.red,
                    ),
                    title: const Text('Cuadre contable'),
                    subtitle: const Text(
                      'Activos - pasivos - patrimonio - utilidad',
                    ),
                    trailing: Text(
                      _fmt(cuadre),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cuadre?.minorUnits == 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Estado de resultados',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _fila('Ingresos', 'ingresos', Colors.green),
                _fila('Costos', 'costos', Colors.orange),
                _fila('Gastos', 'gastos', Colors.red),
                Card(
                  child: ListTile(
                    title: const Text('Utilidad'),
                    trailing: Text(
                      _fmt(utilidad),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (utilidad?.minorUnits ?? 0) >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                ),
                if (widget.embedded)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.icon(
                      onPressed: _exportarPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Exportar PDF corporativo'),
                    ),
                  ),
              ],
            ),
          );

    if (widget.embedded) return listView;
    return Scaffold(
      appBar: AppBar(title: const Text('Estados financieros')),
      body: listView,
    );
  }
}
