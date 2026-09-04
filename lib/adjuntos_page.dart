import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'db_helper.dart';
import 'numeric_input.dart';

class AdjuntosPage extends StatefulWidget {
  const AdjuntosPage({super.key});

  @override
  State<AdjuntosPage> createState() => _AdjuntosPageState();
}

class _AdjuntosPageState extends State<AdjuntosPage> {
  List<Map<String, dynamic>> adjuntos = [];

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
    final data = await DatabaseHelper.instance.obtenerAdjuntos();
    if (!mounted) return;
    setState(() => adjuntos = data);
  }

  Future<void> _nuevo() async {
    final nombreCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final notasCtrl = TextEditingController();
    var entidad = 'ventas';
    String? rutaArchivo;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adjunto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: entidad,
                  items: const [
                    DropdownMenuItem(value: 'ventas', child: Text('Ventas')),
                    DropdownMenuItem(value: 'compras', child: Text('Compras')),
                    DropdownMenuItem(value: 'clientes', child: Text('Clientes')),
                    DropdownMenuItem(value: 'proveedores', child: Text('Proveedores')),
                    DropdownMenuItem(value: 'nomina', child: Text('Nomina')),
                    DropdownMenuItem(value: 'activos_fijos', child: Text('Activos fijos')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => entidad = value);
                  },
                ),
                TextField(
                  controller: idCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [NumericInput.integer],
                  decoration: const InputDecoration(labelText: 'ID relacionado'),
                ),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre documento'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(rutaArchivo == null ? 'Seleccionar archivo' : p.basename(rutaArchivo!)),
                  subtitle: rutaArchivo != null ? Text(rutaArchivo!, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                  trailing: IconButton(
                    tooltip: 'Seleccionar archivo',
                    icon: const Icon(Icons.folder_open),
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'xlsx', 'csv'],
                      );
                      if (result == null || result.files.isEmpty) return;
                      setDialogState(() {
                        rutaArchivo = result.files.single.path;
                        if (nombreCtrl.text.isEmpty && rutaArchivo != null) {
                          nombreCtrl.text = p.basename(rutaArchivo!);
                        }
                      });
                    },
                  ),
                ),
                TextField(
                  controller: notasCtrl,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nombreCtrl.text.trim().isEmpty || rutaArchivo == null) return;
                await DatabaseHelper.instance.guardarAdjunto(
                  entidad: entidad,
                  entidadId: int.tryParse(idCtrl.text),
                  nombre: nombreCtrl.text.trim(),
                  ruta: rutaArchivo!,
                  notas: notasCtrl.text.trim(),
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

  Future<void> _eliminar(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('adjuntos_documentos', where: 'id = ?', whereArgs: [id]);
    await _cargar();
  }

  bool _esImagen(String ruta) {
    final ext = p.extension(ruta).toLowerCase();
    return ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adjuntos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        icon: const Icon(Icons.attach_file),
        label: const Text('Adjunto'),
      ),
      body: adjuntos.isEmpty
          ? const Center(child: Text('No hay adjuntos registrados'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: adjuntos.length,
              itemBuilder: (context, index) {
                final a = adjuntos[index];
                final ruta = a['ruta']?.toString() ?? '';
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ruta.isNotEmpty && File(ruta).existsSync() && _esImagen(ruta)
                            ? Image.file(File(ruta), fit: BoxFit.cover)
                            : Center(
                                child: Icon(
                                  ruta.endsWith('.pdf') ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                  size: 48,
                                ),
                              ),
                      ),
                      ListTile(
                        dense: true,
                        title: Text(a['nombre']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${a['entidad']} #${a['entidad_id'] ?? ''}'),
                        trailing: IconButton(
                          tooltip: 'Eliminar adjunto',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _eliminar(a['id'] as int),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
