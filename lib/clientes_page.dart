import 'package:flutter/material.dart';
import 'integrations/application/communication_service.dart';

import 'db_helper.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  List<Map<String, dynamic>> clientes = [];

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
    final data = await DatabaseHelper.instance.obtenerClientes();
    if (!mounted) return;
    setState(() => clientes = data);
  }

  Future<void> _abrirFormulario([Map<String, dynamic>? cliente]) async {
    final nombreCtrl = TextEditingController(
      text: cliente?['nombre']?.toString() ?? '',
    );
    final documentoCtrl = TextEditingController(
      text: cliente?['documento']?.toString() ?? '',
    );
    final telefonoCtrl = TextEditingController(
      text: cliente?['telefono']?.toString() ?? '',
    );
    final direccionCtrl = TextEditingController(
      text: cliente?['direccion']?.toString() ?? '',
    );
    final emailCtrl = TextEditingController(
      text: cliente?['email']?.toString() ?? '',
    );
    
    bool granContribuyente = cliente?['gran_contribuyente'] == 1;
    bool autorretenedor = cliente?['autorretenedor'] == 1;
    bool declarante = cliente?['declarante'] != 0;
    String regimenTributario = cliente?['regimen_tributario']?.toString() ?? 'ordinario';
    final regimenes = ['ordinario', 'simple'];

    final guardado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(cliente == null ? 'Nuevo cliente' : 'Editar cliente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                TextField(
                  controller: documentoCtrl,
                  decoration: const InputDecoration(labelText: 'Documento/NIT'),
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
                const Divider(),
                const Text('Banderas Fiscales Colombianas', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Gran Contribuyente'),
                  value: granContribuyente,
                  onChanged: (val) => setDialogState(() => granContribuyente = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: const Text('Autorretenedor'),
                  subtitle: const Text('No se aplica retefuente en ventas'),
                  value: autorretenedor,
                  onChanged: (val) => setDialogState(() => autorretenedor = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: const Text('Declarante de Renta'),
                  value: declarante,
                  onChanged: (val) => setDialogState(() => declarante = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                DropdownButtonFormField<String>(
                  initialValue: regimenTributario,
                  decoration: const InputDecoration(labelText: 'Régimen Tributario'),
                  items: regimenes.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => regimenTributario = val);
                  },
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
                final nombre = nombreCtrl.text.trim();
                if (nombre.isEmpty) return;

                final datos = {
                  'nombre': nombre,
                  'documento': documentoCtrl.text.trim(),
                  'telefono': telefonoCtrl.text.trim(),
                  'direccion': direccionCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'estado': 'activo',
                  'fecha': DateTime.now().toIso8601String(),
                  'gran_contribuyente': granContribuyente ? 1 : 0,
                  'autorretenedor': autorretenedor ? 1 : 0,
                  'declarante': declarante ? 1 : 0,
                  'regimen_tributario': regimenTributario,
                };

                if (cliente == null) {
                  await DatabaseHelper.instance.insertarCliente(datos);
                } else {
                  await DatabaseHelper.instance.actualizarCliente(
                    cliente['id'] as int,
                    datos,
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

    if (guardado == true) {
      await _cargar();
    }
  }

  Future<void> _eliminar(int id) async {
    await DatabaseHelper.instance.eliminarCliente(id);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ELIMINAR_CLIENTE',
      entidad: 'clientes',
      entidadId: id,
      detalle: 'Cliente eliminado',
    );
    await _cargar();
  }

  Future<void> _enviarWhatsApp(Map<String, dynamic> cliente) async {
    final phone = cliente['telefono']?.toString().trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El cliente no tiene teléfono registrado.')));
      return;
    }
    final ctrl = TextEditingController(text: 'Hola ${cliente['nombre'] ?? ''}, te contactamos desde nuestra empresa a través de MerkaERP.');
    final send = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Enviar por WhatsApp Business'),
      content: SizedBox(width: 520, child: TextField(controller: ctrl, minLines: 4, maxLines: 8, decoration: InputDecoration(labelText: 'Mensaje para $phone', border: const OutlineInputBorder()))),
      actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Enviar'))],
    ));
    if (send != true) return;
    final result = await CommunicationService.instance.sendWhatsAppText(recipient: phone, message: ctrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.person_add),
        label: const Text('Cliente'),
      ),
      body: clientes.isEmpty
          ? const Center(child: Text('No hay clientes registrados'))
          : ListView.builder(
              itemCount: clientes.length,
              itemBuilder: (context, index) {
                final c = clientes[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(c['nombre']?.toString() ?? ''),
                    subtitle: Text(
                      [c['documento'], c['telefono'], c['email']]
                          .where((v) => v != null && v.toString().isNotEmpty)
                          .join(' · '),
                    ),
                    onTap: () => _abrirFormulario(c),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Enviar mensaje por WhatsApp Business',
                          icon: const Icon(Icons.chat_outlined),
                          onPressed: () => _enviarWhatsApp(c),
                        ),
                        IconButton(
                          tooltip: 'Eliminar cliente',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _eliminar(c['id'] as int),
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
