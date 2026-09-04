import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'go_live_service.dart';

class GoLivePage extends StatefulWidget {
  const GoLivePage({super.key});

  @override
  State<GoLivePage> createState() => _GoLivePageState();
}

class _GoLivePageState extends State<GoLivePage> {
  late Future<GoLiveSnapshot> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = GoLiveService.instance.load();
  }

  void _reload() => setState(() => _future = GoLiveService.instance.load());

  Future<void> _edit(GoLiveCheckDefinition definition, GoLiveCheckState state) async {
    var status = state.status;
    final note = TextEditingController(text: state.note);
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(definition.title),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(definition.description),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Resultado', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                    DropdownMenuItem(value: 'pass', child: Text('Aprobado')),
                    DropdownMenuItem(value: 'fail', child: Text('Falló')),
                    DropdownMenuItem(value: 'na', child: Text('No aplica')),
                  ],
                  onChanged: (value) { if (value != null) setDialogState(() => status = value); },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Evidencia / observación', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, (status, note.text)), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    note.dispose();
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await GoLiveService.instance.update(definition.id, result.$1, note: result.$2);
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportReport() async {
    setState(() => _busy = true);
    try {
      final files = await GoLiveService.instance.exportReport();
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(files.report.path), XFile(files.checksum.path)],
        subject: 'Reporte Go-Live MerkaERP',
        text: 'Reporte de puesta en marcha con checksum SHA-256.',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No fue posible exportar el reporte: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reiniciar checklist'),
        content: const Text('Se eliminarán los resultados del checklist de esta organización. La auditoría del reinicio se conserva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Reiniciar')),
        ],
      ),
    );
    if (yes != true) return;
    await GoLiveService.instance.reset();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go-Live · Validación de puesta en marcha'),
        actions: [
          IconButton(tooltip: 'Exportar evidencia', onPressed: _busy ? null : _exportReport, icon: const Icon(Icons.ios_share_outlined)),
          IconButton(tooltip: 'Reiniciar', onPressed: _busy ? null : _reset, icon: const Icon(Icons.restart_alt)),
        ],
      ),
      body: FutureBuilder<GoLiveSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError || !snapshot.hasData) return Center(child: Text('No fue posible cargar el checklist: ${snapshot.error}'));
          final data = snapshot.data!;
          final progress = data.total == 0 ? 0.0 : data.passed / data.total;
          final grouped = <String, List<GoLiveCheckDefinition>>{};
          for (final item in data.definitions) {
            grouped.putIfAbsent(item.area, () => []).add(item);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(data.ready ? Icons.verified : Icons.fact_check_outlined, color: data.ready ? Colors.green : Colors.orange, size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(data.ready ? 'Organización validada para puesta en marcha' : 'Validación de puesta en marcha pendiente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        Text('${data.passed}/${data.total} controles aprobados o N/A · ${data.blockingPending} bloqueantes pendientes · ${data.blockingFailures} fallidos'),
                      ])),
                    ]),
                    const SizedBox(height: 14),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 10),
                    const Text('Este checklist no reemplaza pruebas automatizadas: registra la aceptación funcional/UAT de la instalación real antes de operar.'),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              for (final group in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(group.key, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                ...group.value.map((definition) {
                  final state = data.states[definition.id] ?? const GoLiveCheckState(status: 'pending');
                  final icon = switch (state.status) {
                    'pass' => Icons.check_circle,
                    'fail' => Icons.cancel,
                    'na' => Icons.remove_circle,
                    _ => Icons.schedule,
                  };
                  final color = switch (state.status) {
                    'pass' => Colors.green,
                    'fail' => Colors.red,
                    'na' => Colors.blueGrey,
                    _ => Colors.orange,
                  };
                  return Card(
                    child: ListTile(
                      leading: Icon(icon, color: color),
                      title: Row(children: [
                        Expanded(child: Text(definition.title)),
                        if (definition.blocking) const Chip(label: Text('Bloqueante'), visualDensity: VisualDensity.compact),
                      ]),
                      subtitle: Text('${definition.description}${definition.automatic ? '\nControl automático: no admite aprobación manual.' : ''}${state.note.isEmpty ? '' : '\nEvidencia: ${state.note}'}'),
                      isThreeLine: state.note.isNotEmpty,
                      trailing: Icon(definition.automatic ? Icons.verified_user_outlined : Icons.edit_outlined),
                      onTap: _busy || definition.automatic ? null : () => _edit(definition, state),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
