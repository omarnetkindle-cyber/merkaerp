import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'numeric_input.dart';

class PeriodosContablesPage extends StatefulWidget {
  const PeriodosContablesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<PeriodosContablesPage> createState() => _PeriodosContablesPageState();
}

class _PeriodosContablesPageState extends State<PeriodosContablesPage> {
  List<Map<String, dynamic>> periodos = [];
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
    final data = await DatabaseHelper.instance.obtenerPeriodosContables();
    if (!mounted) return;
    setState(() {
      periodos = data;
      cargando = false;
    });
  }

  Future<void> _abrirDialogoPeriodo({required bool cerrar}) async {
    final ahora = DateTime.now();
    int anio = ahora.year;
    int mes = ahora.month;
    final obsCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(cerrar ? 'Cerrar periodo' : 'Abrir periodo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                keyboardType: TextInputType.number,
                inputFormatters: [NumericInput.integer],
                controller: TextEditingController(text: anio.toString()),
                decoration: const InputDecoration(
                  labelText: 'Año',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => anio = int.tryParse(v) ?? anio,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: mes,
                decoration: const InputDecoration(
                  labelText: 'Mes',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(12, (i) {
                  final value = i + 1;
                  return DropdownMenuItem(
                    value: value,
                    child: Text(value.toString().padLeft(2, '0')),
                  );
                }),
                onChanged: (v) {
                  if (v == null) return;
                  setDialogState(() => mes = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observación',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (cerrar) {
                  await DatabaseHelper.instance.cerrarPeriodoContable(
                    anio: anio,
                    mes: mes,
                    observacion: obsCtrl.text.trim(),
                  );
                } else {
                  await DatabaseHelper.instance.abrirPeriodoContable(
                    anio: anio,
                    mes: mes,
                    observacion: obsCtrl.text.trim(),
                  );
                }
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext, true);
              },
              child: Text(cerrar ? 'Cerrar' : 'Abrir'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) await _cargar();
  }

  Widget _listaPeriodos() {
    if (periodos.isEmpty) {
      return const Center(child: Text('No hay periodos configurados'));
    }
    return ListView.builder(
      itemCount: periodos.length,
      itemBuilder: (context, index) {
        final p = periodos[index];
        final estado = p['estado']?.toString() ?? 'abierto';
        final cerrado = estado == 'cerrado';

        return Card(
          child: ListTile(
            leading: Icon(
              cerrado ? Icons.lock : Icons.lock_open,
              color: cerrado ? Colors.red : Colors.green,
            ),
            title: Text('${p['anio']}-${p['mes'].toString().padLeft(2, '0')}'),
            subtitle: Text(p['observacion']?.toString() ?? ''),
            trailing: Text(
              estado.toUpperCase(),
              style: TextStyle(
                color: cerrado ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () async {
              final nuevo = cerrado ? 'abierto' : 'cerrado';
              await DatabaseHelper.instance.cambiarEstadoPeriodo(
                p['anio'] as int,
                p['mes'] as int,
                nuevo,
              );
              await _cargar();
            },
            onLongPress: () => _abrirDialogoPeriodo(cerrar: !cerrado),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = cargando
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: _cargar, child: _listaPeriodos());

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Periodos contables')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'abrir_periodo',
            onPressed: () => _abrirDialogoPeriodo(cerrar: false),
            child: const Icon(Icons.lock_open),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'cerrar_periodo',
            onPressed: () => _abrirDialogoPeriodo(cerrar: true),
            icon: const Icon(Icons.lock),
            label: const Text('Cerrar'),
          ),
        ],
      ),
      body: body,
    );
  }
}
