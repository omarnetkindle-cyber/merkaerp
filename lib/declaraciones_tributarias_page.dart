import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'numeric_input.dart';
import 'ui/enterprise_design_system.dart';

class DeclaracionesTributariasPage extends StatefulWidget {
  const DeclaracionesTributariasPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<DeclaracionesTributariasPage> createState() =>
      _DeclaracionesTributariasPageState();
}

class _DeclaracionesTributariasPageState
    extends State<DeclaracionesTributariasPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _anio = DateTime.now().year;
  int _mes = DateTime.now().month;
  final int _mesInicioIca = 1;
  final int _mesFinIca = 2;
  final double _tarifaIca = 11.04;
  Map<String, Object> _f300 = {};
  Map<String, Object> _f350 = {};
  Map<String, Object> _f110 = {};
  Map<String, Object> _ica = {};
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargar);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final f300 = await DatabaseHelper.instance.obtenerBorradorFormulario300(
      anio: _anio,
      mes: _mes,
    );
    final f350 = await DatabaseHelper.instance.obtenerBorradorFormulario350(
      anio: _anio,
      mes: _mes,
    );
    final f110 = await DatabaseHelper.instance.obtenerBorradorFormulario110(
      anio: _anio,
    );
    final ica = await DatabaseHelper.instance.obtenerBorradorICA(
      anio: _anio,
      mesInicio: _mesInicioIca,
      mesFin: _mesFinIca,
      tarifaPorMil: _tarifaIca,
    );
    if (!mounted) return;
    setState(() {
      _f300 = f300;
      _f350 = f350;
      _f110 = f110;
      _ica = ica;
      _cargando = false;
    });
  }

  String _fmt(Object? value) {
    if (value is MoneyValue) return value.format();
    return value?.toString() ?? '-';
  }

  Future<void> _exportarPDF(
    String nombreFormulario,
    Map<String, Object> datos,
    Map<String, String> labels,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text('Borrador $nombreFormulario - MerkaERP'),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Período: $_anio - Mes $_mes'),
              pw.SizedBox(height: 20),
              pw.Table.fromTextArray(
                context: context,
                data: <List<String>>[
                  ['Concepto', 'Valor'],
                  ...labels.entries.map(
                    (e) => [
                      e.value,
                      e.key.contains('tarifa')
                          ? '${datos[e.key] ?? '-'} x1000'
                          : _fmt(datos[e.key] ?? 0),
                    ],
                  ),
                ],
                border: pw.TableBorder.all(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 30),
              pw.Text(
                'Nota: Este es un borrador informativo. Revise con su contador antes de presentar la declaración ante la DIAN o entidad municipal.',
                style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${nombreFormulario}_$_anio-$_mes.pdf',
    );
  }

  Widget _periodoSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EnterpriseSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: '$_anio'),
                keyboardType: TextInputType.number,
                inputFormatters: [NumericInput.integer],
                decoration: const InputDecoration(
                  labelText: 'Año',
                  isDense: true,
                ),
                onChanged: (v) => _anio = int.tryParse(v) ?? _anio,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _mes,
                decoration: const InputDecoration(
                  labelText: 'Mes',
                  isDense: true,
                ),
                items: List.generate(
                  12,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                ),
                onChanged: (v) {
                  if (v != null) setState(() => _mes = v);
                },
              ),
            ),
            IconButton(tooltip: 'Actualizar información', onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
      ),
    );
  }

  Widget _filas(
    Map<String, Object> data,
    Map<String, String> labels,
    String nombreFormulario,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(EnterpriseSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: () => _exportarPDF(nombreFormulario, data, labels),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Exportar PDF'),
              ),
            ],
          ),
        ),
        ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(EnterpriseSpacing.md),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Borrador informativo'),
                subtitle: Text(
                  'Documento de apoyo para declaraciones DIAN/municipales. Revise con contador antes de presentar.',
                ),
              ),
            ),
            ...labels.entries.map(
              (e) => Card(
                child: ListTile(
                  title: Text(e.value),
                  trailing: Text(
                    e.key.contains('tarifa')
                        ? '${data[e.key] ?? '-'} x1000'
                        : _fmt(data[e.key] ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _periodoSelector(),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Form. 300 IVA'),
            Tab(text: 'Form. 350 Retefuente'),
            Tab(text: 'Form. 110 Renta'),
            Tab(text: 'ICA Municipal'),
          ],
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _filas(_f300, {
                      'ingresos_gravados': 'Ingresos gravados',
                      'base_gravada': 'Base gravada',
                      'base_gravada_0': 'Base IVA 0%',
                      'base_gravada_5': 'Base IVA 5%',
                      'base_gravada_19': 'Base IVA 19%',
                      'iva_generado': 'IVA generado',
                      'iva_generado_0': 'IVA generado 0%',
                      'iva_generado_5': 'IVA generado 5%',
                      'iva_generado_19': 'IVA generado 19%',
                      'iva_descontable': 'IVA descontable',
                      'reteiva_practicada': 'ReteIVA practicada',
                      'saldo_pagar': 'Saldo a pagar / a favor',
                    }, 'Formulario_300_IVA'),
                    _filas(_f350, {
                      'retefuente_compras': 'Retención compras',
                      'retefuente_servicios': 'Retención servicios',
                      'retefuente_honorarios': 'Retención honorarios',
                      'retefuente_arrendamientos': 'Retención arrendamientos',
                      'retefuente_otros_ingresos': 'Retencion otros ingresos',
                      'total_retenciones': 'Total retenciones',
                    }, 'Formulario_350_Retefuente'),
                    _filas(_f110, {
                      'patrimonio_bruto': 'Patrimonio bruto',
                      'pasivos': 'Pasivos (deudas)',
                      'patrimonio_liquido': 'Patrimonio líquido',
                      'ingresos_operacionales': 'Ingresos operacionales',
                      'costos_ventas': 'Costos de ventas',
                      'gastos_operativos': 'Gastos operativos',
                      'utilidad_gravable': 'Renta líquida gravable',
                    }, 'Formulario_110_Renta'),
                    _filas(_ica, {
                      'ingresos_brutos': 'Ingresos brutos totales',
                      'ingresos_netos_gravables': 'Ingresos netos gravables',
                      'tarifa_por_mil': 'Tarifa por mil (CIIU)',
                      'impuesto_ica': 'Impuesto ICA',
                      'avisos_tableros': 'Avisos y tableros (15%)',
                      'reteica_practicada': 'ReteICA practicada',
                      'saldo_pagar': 'Saldo a pagar ICA',
                    }, 'ICA_Municipal'),
                  ],
                ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Declaraciones tributarias')),
      body: body,
    );
  }
}
