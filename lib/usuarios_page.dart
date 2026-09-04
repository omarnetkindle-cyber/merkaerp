import 'package:flutter/material.dart';

import 'db_helper.dart';

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  List<Map<String, dynamic>> usuarios = [];

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
    final data = await DatabaseHelper.instance.obtenerUsuarios();
    if (!mounted) return;
    setState(() => usuarios = data);
  }

  Future<void> _nuevo({Map<String, dynamic>? usuario}) async {
    final nombreCtrl = TextEditingController(text: usuario?['nombre']?.toString() ?? '');
    final usuarioCtrl = TextEditingController(text: usuario?['usuario']?.toString() ?? '');
    final pinCtrl = TextEditingController();
    var rol = usuario?['rol']?.toString() ?? 'operador';
    var activo = usuario != null ? ((usuario['activo'] as num?)?.toInt() ?? 1) == 1 : true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(usuario == null ? 'Nuevo usuario' : 'Editar usuario'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                TextField(
                  controller: usuarioCtrl,
                  decoration: const InputDecoration(labelText: 'Usuario'),
                ),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: usuario == null
                        ? 'PIN local (mínimo 6 caracteres)'
                        : 'Nuevo PIN (dejar vacío para conservar)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: rol,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: const [
                    DropdownMenuItem(
                      value: 'administrador',
                      child: Text('Administrador'),
                    ),
                    DropdownMenuItem(
                      value: 'contador',
                      child: Text('Contador'),
                    ),
                    DropdownMenuItem(value: 'cajero', child: Text('Cajero')),
                    DropdownMenuItem(
                      value: 'operador',
                      child: Text('Operador'),
                    ),
                    DropdownMenuItem(
                      value: 'consulta',
                      child: Text('Consulta'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => rol = value);
                  },
                ),
                const SizedBox(height: 12),
                if (usuario != null)
                  SwitchListTile(
                    title: const Text('Usuario activo'),
                    value: activo,
                    onChanged: (value) => setDialogState(() => activo = value),
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
                if (nombreCtrl.text.trim().isEmpty ||
                    usuarioCtrl.text.trim().isEmpty ||
                    (usuario == null && pinCtrl.text.trim().length < 6) ||
                    (usuario != null &&
                        pinCtrl.text.trim().isNotEmpty &&
                        pinCtrl.text.trim().length < 6)) {
                  return;
                }
                if (usuario == null) {
                  await DatabaseHelper.instance.guardarUsuario(
                    nombre: nombreCtrl.text.trim(),
                    usuario: usuarioCtrl.text.trim(),
                    rol: rol,
                    pin: pinCtrl.text.trim(),
                    activo: activo,
                  );
                } else {
                  await DatabaseHelper.instance.actualizarUsuario(
                    id: usuario['id'] as int,
                    nombre: nombreCtrl.text.trim(),
                    usuario: usuarioCtrl.text.trim(),
                    rol: rol,
                    pin: pinCtrl.text.trim(),
                    activo: activo,
                  );
                }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios y permisos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nuevo(),
        icon: const Icon(Icons.person_add),
        label: const Text('Usuario'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.security),
              title: Text('Roles base'),
              subtitle: Text(
                'Administrador, contador, cajero, operador y consulta. La aplicacion ya guarda usuarios; el bloqueo por pantalla se puede endurecer con login local.',
              ),
            ),
          ),
          ...usuarios.map(
            (u) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (u['activo'] as num? ?? 0) == 1
                      ? Colors.green
                      : Colors.grey,
                  child: Text(
                    (u['nombre']?.toString() ?? '')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(u['nombre']?.toString() ?? ''),
                subtitle: Text('${u['usuario']} | ${u['rol']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar usuario',
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _nuevo(usuario: u),
                    ),
                    IconButton(
                      tooltip: 'Eliminar usuario',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Eliminar usuario'),
                            content: const Text('¿Está seguro de eliminar este usuario?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await DatabaseHelper.instance.eliminarUsuario(u['id'] as int);
                          await _cargar();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
