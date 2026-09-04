import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'numeric_input.dart';

class ActivosFijosPage extends StatefulWidget {
  const ActivosFijosPage({super.key});

  @override
  State<ActivosFijosPage> createState() => _ActivosFijosPageState();
}

class _ActivosFijosPageState extends State<ActivosFijosPage> {
  List<Map<String, dynamic>> activos = [];

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
    final data = await DatabaseHelper.instance.obtenerActivosFijos();
    if (!mounted) return;
    setState(() => activos = data);
  }

  Future<void> _nuevo() async {
    final nombreCtrl = TextEditingController();
    final categoriaCtrl = TextEditingController();
    final costoCtrl = TextEditingController();
    final vidaCtrl = TextEditingController(text: '60');
    final obsCtrl = TextEditingController();
    var tipoDep = 'maquinaria';
    final pucCtrl = TextEditingController(text: '1524');
    final pucDepCtrl = TextEditingController(text: '5160');

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Activo fijo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: categoriaCtrl,
                decoration: const InputDecoration(labelText: 'Categoria'),
              ),
              TextField(
                controller: costoCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [NumericInput.decimal],
                decoration: const InputDecoration(labelText: 'Costo'),
              ),
              TextField(
                controller: vidaCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [NumericInput.integer],
                decoration: const InputDecoration(labelText: 'Vida util meses'),
              ),
              TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(labelText: 'Observacion'),
              ),
              DropdownButtonFormField<String>(
                initialValue: tipoDep,
                decoration: const InputDecoration(labelText: 'Tipo depreciación (Colombia)'),
                items: const [
                  DropdownMenuItem(value: 'construcciones', child: Text('Construcciones (2.2% anual)')),
                  DropdownMenuItem(value: 'maquinaria', child: Text('Maquinaria/Equipo (10% anual)')),
                  DropdownMenuItem(value: 'computacion', child: Text('Computación (20% anual)')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setDialogState(() {
                    tipoDep = v;
                    if (v == 'construcciones') {
                      pucCtrl.text = '1516';
                      vidaCtrl.text = '540';
                    } else if (v == 'computacion') {
                      pucCtrl.text = '1528';
                      vidaCtrl.text = '60';
                    } else {
                      pucCtrl.text = '1524';
                      vidaCtrl.text = '120';
                    }
                  });
                },
              ),
              TextField(
                controller: pucCtrl,
                decoration: const InputDecoration(labelText: 'Código PUC activo'),
              ),
              TextField(
                controller: pucDepCtrl,
                decoration: const InputDecoration(labelText: 'Código PUC gasto depreciación'),
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
              final costo =
                  double.tryParse(costoCtrl.text.replaceAll(',', '.')) ?? 0;
              final vida = int.tryParse(vidaCtrl.text) ?? 0;
              if (nombreCtrl.text.trim().isEmpty || costo <= 0 || vida <= 0) {
                return;
              }
              await DatabaseHelper.instance.guardarActivoFijo(
                nombre: nombreCtrl.text.trim(),
                categoria: categoriaCtrl.text.trim(),
                costo: costo,
                vidaUtilMeses: vida,
                observacion: obsCtrl.text.trim(),
                tipoDepreciacion: tipoDep,
                codigoPuc: pucCtrl.text.trim(),
                codigoPucDepreciacion: pucDepCtrl.text.trim(),
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

    if (ok == true) await _cargar();
  }

  String _fmt(num valor) => '\$${valor.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final totalCosto = activos.fold<double>(
      0,
      (sum, a) => sum + ((a['costo'] as num?)?.toDouble() ?? 0),
    );
    final totalLibros = activos.fold<double>(
      0,
      (sum, a) => sum + ((a['valor_libros_calc'] as num?)?.toDouble() ?? 0),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Activos fijos')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'depreciar',
            onPressed: () async {
              await DatabaseHelper.instance.procesarDepreciacionMensual();
              await _cargar();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Depreciación mensual procesada'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Icon(Icons.calculate),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'nuevo_activo',
            onPressed: _nuevo,
            icon: const Icon(Icons.add_business),
            label: const Text('Activo'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.domain),
              title: const Text('Resumen'),
              subtitle: Text(
                'Costo ${_fmt(totalCosto)} | Libros ${_fmt(totalLibros)}',
              ),
            ),
          ),
          ...activos.map(
            (a) => Card(
              child: ListTile(
                leading: const Icon(Icons.precision_manufacturing),
                title: Text(a['nombre']?.toString() ?? ''),
                subtitle: Text(
                  '${a['categoria'] ?? ''} | Dep. mensual ${_fmt((a['depreciacion_mensual'] as num?) ?? 0)}\nDep. acum. ${_fmt((a['depreciacion_acumulada_calc'] as num?) ?? 0)}',
                ),
                trailing: Text(
                  _fmt((a['valor_libros_calc'] as num?) ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
