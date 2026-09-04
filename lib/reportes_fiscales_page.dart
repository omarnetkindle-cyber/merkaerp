import 'package:flutter/material.dart';

import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'numeric_input.dart';

class ReportesFiscalesPage extends StatefulWidget {
  const ReportesFiscalesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<ReportesFiscalesPage> createState() => _ReportesFiscalesPageState();
}

class _ReportesFiscalesPageState extends State<ReportesFiscalesPage> {
  int anio = DateTime.now().year;
  int mes = DateTime.now().month;
  Map<String, MoneyValue> reporte = {};

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
    final data = await DatabaseHelper.instance.obtenerReporteFiscal(
      anio: anio,
      mes: mes,
    );
    if (!mounted) return;
    setState(() => reporte = data);
  }

  String _fmt(MoneyValue? valor) => valor?.format() ?? '-';

  @override
  Widget build(BuildContext context) {
    final filas = [
      ['Ventas gravadas/reportadas', reporte['ventas'], 'ventas'],
      ['Compras y costos', reporte['compras'], 'compras'],
      ['IVA generado', reporte['iva_generado'], 'iva_generado'],
      ['IVA descontable', reporte['iva_descontable'], 'iva_descontable'],
      ['IVA estimado por pagar', reporte['iva_por_pagar'], 'iva_por_pagar'],
      [
        'Retefuente practicada',
        reporte['retefuente_practicada'],
        'retefuente_practicada',
      ],
      [
        'ReteIVA practicada',
        reporte['reteiva_practicada'],
        'reteiva_practicada',
      ],
      [
        'ReteICA practicada',
        reporte['reteica_practicada'],
        'reteica_practicada',
      ],
      [
        'Retefuente recibida (compras)',
        reporte['retefuente_recibida'],
        'retefuente_recibida',
      ],
      ['Nómina pagada', reporte['nomina'], 'nomina'],
    ];

    final body = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: '$anio'),
                keyboardType: TextInputType.number,
                inputFormatters: [NumericInput.integer],
                decoration: const InputDecoration(
                  labelText: 'Año',
                  isDense: true,
                ),
                onChanged: (value) =>
                    anio = int.tryParse(value) ?? DateTime.now().year,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: mes,
                decoration: const InputDecoration(
                  labelText: 'Mes',
                  isDense: true,
                ),
                items: List.generate(
                  12,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => mes = value);
                  _cargar();
                },
              ),
            ),
            IconButton(tooltip: 'Actualizar información', onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.gavel),
            title: Text('Resumen fiscal interactivo'),
            subtitle: Text(
              'IVA, retenciones e ICA del período. Toque un concepto para ver el detalle estimado.',
            ),
          ),
        ),
        ...filas.map(
          (f) => Card(
            child: ListTile(
              title: Text(f[0] as String),
              trailing: Text(
                _fmt(f[1] as MoneyValue?),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(f[0] as String),
                    content: Text(
                      'Total del período $mes/$anio: ${_fmt(f[1] as MoneyValue?)}\n\n'
                      'Este valor se calcula desde ventas, compras y nómina registradas en el sistema.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes fiscales')),
      body: body,
    );
  }
}
