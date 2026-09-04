import 'package:flutter/material.dart';
import 'db_helper.dart';

class ProveedoresPage extends StatefulWidget {
  const ProveedoresPage({super.key});

  @override
  State<ProveedoresPage> createState() => _ProveedoresPageState();
}

class _ProveedoresPageState extends State<ProveedoresPage> {
  List<Map<String, dynamic>> _proveedores = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarProveedores);
      }
    });
  }

  Future<void> _cargarProveedores() async {
    final data = await DatabaseHelper.instance.obtenerProveedores();

    if (!mounted) return;

    setState(() {
      _proveedores = data;
    });
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? proveedor}) async {
    final nombreCtrl = TextEditingController(text: proveedor?['nombre'] ?? '');

    final nitCtrl = TextEditingController(text: proveedor?['nit'] ?? '');

    final telefonoCtrl = TextEditingController(
      text: proveedor?['telefono'] ?? '',
    );

    final direccionCtrl = TextEditingController(
      text: proveedor?['direccion'] ?? '',
    );

    final emailCtrl = TextEditingController(text: proveedor?['email'] ?? '');

    final contactoCtrl = TextEditingController(
      text: proveedor?['contacto'] ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(proveedor == null ? 'Nuevo proveedor' : 'Editar proveedor'),

        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),

              TextField(
                controller: nitCtrl,
                decoration: const InputDecoration(labelText: 'NIT'),
              ),

              TextField(
                controller: telefonoCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),

              TextField(
                controller: direccionCtrl,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),

              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
              ),

              TextField(
                controller: contactoCtrl,
                decoration: const InputDecoration(labelText: 'Contacto'),
              ),
            ],
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),

          ElevatedButton(
            onPressed: () async {
              final nombre = nombreCtrl.text.trim();

              if (nombre.isEmpty) return;

              final datos = {
                'nombre': nombre,

                'nit': nitCtrl.text.trim(),

                'telefono': telefonoCtrl.text.trim(),

                'direccion': direccionCtrl.text.trim(),

                'email': emailCtrl.text.trim(),

                'contacto': contactoCtrl.text.trim(),

                'estado': 'activo',

                'fecha': DateTime.now().toIso8601String(),
              };

              if (proveedor == null) {
                await DatabaseHelper.instance.insertarProveedor(datos);
              } else {
                await DatabaseHelper.instance.actualizarProveedor(
                  proveedor['id'] as int,
                  datos,
                );
              }

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);

              await _cargarProveedores();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarProveedor(int id) async {
    if (await DatabaseHelper.instance.proveedorTieneCompras(id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este proveedor ya tiene compras asociadas. Editalo o dejalo inactivo para conservar el historial.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await DatabaseHelper.instance.eliminarProveedor(id);

    await _cargarProveedores();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proveedores')),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _abrirFormulario();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),

      body: _proveedores.isEmpty
          ? const Center(child: Text('No hay proveedores'))
          : ListView.builder(
              itemCount: _proveedores.length,

              itemBuilder: (_, i) {
                final p = _proveedores[i];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),

                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        p['nombre'].toString().substring(0, 1).toUpperCase(),
                      ),
                    ),

                    title: Text(
                      p['nombre'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((p['nit'] ?? '').toString().isNotEmpty)
                          Text(
                            'NIT: ${p['nit']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                        if ((p['telefono'] ?? '').toString().isNotEmpty)
                          Text(
                            p['telefono'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                        if ((p['email'] ?? '').toString().isNotEmpty)
                          Text(
                            p['email'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),

                    trailing: PopupMenuButton<String>(
                      tooltip: 'Acciones',
                      onSelected: (value) {
                        if (value == 'editar') {
                          _abrirFormulario(proveedor: p);
                        } else if (value == 'eliminar') {
                          _eliminarProveedor(p['id'] as int);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'editar', child: Text('Editar')),
                        PopupMenuItem(
                          value: 'eliminar',
                          child: Text('Eliminar'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
