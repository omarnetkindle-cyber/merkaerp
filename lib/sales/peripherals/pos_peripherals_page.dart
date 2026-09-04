import 'package:flutter/material.dart';

import 'pos_peripheral_service.dart';

class PosPeripheralsPage extends StatefulWidget {
  const PosPeripheralsPage({super.key});

  @override
  State<PosPeripheralsPage> createState() => _PosPeripheralsPageState();
}

class _PosPeripheralsPageState extends State<PosPeripheralsPage> {
  final printer = TextEditingController();
  final printerPort = TextEditingController();
  final label = TextEditingController();
  final labelPort = TextEditingController();
  final scale = TextEditingController();
  final scalePort = TextEditingController();

  bool autoPrint = false;
  bool drawer = false;
  bool touchMode = false;
  String language = 'ZPL';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    printer.dispose();
    printerPort.dispose();
    label.dispose();
    labelPort.dispose();
    scale.dispose();
    scalePort.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await PosPeripheralService.instance.load();
    if (!mounted) return;
    setState(() {
      printer.text = config.printerHost;
      printerPort.text = '${config.printerPort}';
      autoPrint = config.autoPrint;
      drawer = config.openDrawerAfterCashSale;
      label.text = config.labelHost;
      labelPort.text = '${config.labelPort}';
      language = config.labelLanguage;
      scale.text = config.scaleHost;
      scalePort.text = '${config.scalePort}';
      touchMode = config.touchMode;
      loading = false;
    });
  }

  Future<void> _save() async {
    await PosPeripheralService.instance.save(
      PosPeripheralConfig(
        printerHost: printer.text,
        printerPort: int.tryParse(printerPort.text) ?? 9100,
        autoPrint: autoPrint,
        openDrawerAfterCashSale: drawer,
        labelHost: label.text,
        labelPort: int.tryParse(labelPort.text) ?? 9100,
        labelLanguage: language,
        scaleHost: scale.text,
        scalePort: int.tryParse(scalePort.text) ?? 4001,
        touchMode: touchMode,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración del POS guardada.')),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prueba completada correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Widget _endpoint(
    String title,
    TextEditingController host,
    TextEditingController port,
  ) {
    Widget hostField() => TextField(
          controller: host,
          decoration: InputDecoration(
            labelText: '$title · IP/host',
            border: const OutlineInputBorder(),
          ),
        );
    Widget portField() => TextField(
          controller: port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Puerto',
            border: OutlineInputBorder(),
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hostField(),
              const SizedBox(height: 8),
              portField(),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: hostField()),
            const SizedBox(width: 8),
            Expanded(child: portField()),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Periféricos y experiencia del POS'),
        actions: [
          IconButton(
            tooltip: 'Guardar configuración',
            onPressed: loading ? null : _save,
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.touch_app_outlined),
                    value: touchMode,
                    onChanged: (value) => setState(() => touchMode = value),
                    title: const Text('Modo pantalla táctil'),
                    subtitle: const Text(
                      'Aumenta las áreas de toque y el tamaño mínimo de los controles del formulario de venta. '
                      'Útil para POS todo-en-uno y monitores táctiles.',
                    ),
                  ),
                ),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.barcode_reader),
                    title: Text('Lectores de código de barras'),
                    subtitle: Text(
                      'Los lectores USB configurados como teclado funcionan directamente con el campo de escaneo. '
                      'También puedes usar F2 para llevar el foco al código de barras.',
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Impresora térmica ESC/POS y cajón',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _endpoint('Impresora de red', printer, printerPort),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: autoPrint,
                          onChanged: (value) => setState(() => autoPrint = value),
                          title: const Text('Imprimir automáticamente al vender'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: drawer,
                          onChanged: (value) => setState(() => drawer = value),
                          title: const Text('Abrir cajón después de venta en efectivo'),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _run(
                                PosPeripheralService.instance.printTestReceipt,
                              ),
                              icon: const Icon(Icons.print),
                              label: const Text('Probar impresión'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _run(
                                PosPeripheralService.instance.openCashDrawer,
                              ),
                              icon: const Icon(Icons.point_of_sale),
                              label: const Text('Probar cajón'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Etiquetas', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _endpoint('Impresora RAW de red', label, labelPort),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: language,
                          decoration: const InputDecoration(
                            labelText: 'Lenguaje',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'ZPL', child: Text('ZPL')),
                            DropdownMenuItem(value: 'TSPL', child: Text('TSPL')),
                          ],
                          onChanged: (value) => setState(() => language = value ?? 'ZPL'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _run(
                            () => PosPeripheralService.instance.printLabel(
                              name: 'Producto de prueba',
                              code: '1234567890',
                              price: r'$ 10.000',
                            ),
                          ),
                          icon: const Icon(Icons.label),
                          label: const Text('Probar etiqueta'),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Báscula TCP', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        _endpoint('Báscula', scale, scalePort),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final value = await PosPeripheralService.instance.readScale();
                              if (!context.mounted) return;
                              await showDialog<void>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Peso recibido'),
                                  content: Text(value),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext),
                                      child: const Text('Cerrar'),
                                    ),
                                  ],
                                ),
                              );
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                          icon: const Icon(Icons.scale),
                          label: const Text('Leer báscula'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('USB/serial específico'),
                    subtitle: Text(
                      'Si un fabricante no ofrece modo teclado, red o RAW, se requiere su driver/SDK. '
                      'MerkaERP no simula compatibilidad con hardware que el fabricante no expone.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
