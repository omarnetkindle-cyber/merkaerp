import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'documento_pdf_service.dart';
import 'integrations/application/communication_service.dart';

class RecibosPage extends StatefulWidget {
  const RecibosPage({super.key});

  @override
  State<RecibosPage> createState() => _RecibosPageState();
}

class _RecibosPageState extends State<RecibosPage> {
  List<Map<String, dynamic>> ventas = [];
  List<Map<String, dynamic>> compras = [];
  var tipo = 'ventas';

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
    final ventasData = await DatabaseHelper.instance.obtenerVentas();
    final comprasData = await DatabaseHelper.instance.obtenerCompras();
    if (!mounted) return;
    setState(() {
      ventas = ventasData;
      compras = comprasData;
    });
  }

  Future<void> _compartirVenta(Map<String, dynamic> venta) async {
    final archivo = await DocumentoPdfService.crearFacturaVenta(venta);
    await DocumentoPdfService.compartir(archivo, 'Factura POS #${venta['id']}');
  }

  Future<void> _compartirCompra(Map<String, dynamic> compra) async {
    final archivo = await DocumentoPdfService.crearComprobanteCompra(compra);
    await DocumentoPdfService.compartir(
      archivo,
      'Comprobante de compra #${compra['id']}',
    );
  }


  Future<void> _whatsAppVenta(Map<String, dynamic> venta) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    List<Map<String, Object?>> rows = const [];
    final customerId = (venta['cliente_id'] as num?)?.toInt();
    if (customerId != null) {
      rows = await db.query('clientes', columns: ['nombre', 'telefono'], where: 'company_id = ? AND id = ?', whereArgs: [companyId, customerId], limit: 1);
    }
    if (rows.isEmpty) {
      final customerName = venta['cliente']?.toString().trim();
      if (customerName != null && customerName.isNotEmpty && customerName.toLowerCase() != 'cliente general') {
        rows = await db.query('clientes', columns: ['nombre', 'telefono'], where: 'company_id = ? AND nombre = ?', whereArgs: [companyId, customerName], limit: 1);
      }
    }
    if (rows.isEmpty || (rows.first['telefono']?.toString().trim().isEmpty ?? true)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El cliente no tiene un teléfono de WhatsApp registrado.')));
      return;
    }
    final phone = rows.first['telefono'].toString();
    final file = await DocumentoPdfService.crearFacturaVenta(venta);
    final result = await CommunicationService.instance.sendWhatsAppDocument(
      recipient: phone,
      file: file,
      caption: 'Factura POS #${venta['id']} · ${rows.first['nombre'] ?? ''}',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  String _fmt(num valor) => '\$${valor.toStringAsFixed(2)}';

  String _fecha(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String pad(int n) => n.toString().padLeft(2, '0');
      return '${pad(dt.day)}/${pad(dt.month)}/${dt.year} ${pad(dt.hour)}:${pad(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = tipo == 'ventas' ? ventas : compras;

    return Scaffold(
      appBar: AppBar(title: const Text('Recibos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'ventas',
                  label: Text('Ventas'),
                  icon: Icon(Icons.receipt_long),
                ),
                ButtonSegment(
                  value: 'compras',
                  label: Text('Compras'),
                  icon: Icon(Icons.shopping_bag),
                ),
              ],
              selected: {tipo},
              onSelectionChanged: (seleccion) {
                setState(() => tipo = seleccion.first);
              },
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? const Center(child: Text('No hay documentos para compartir'))
                : ListView.builder(
                    itemCount: lista.length,
                    itemBuilder: (context, index) {
                      final item = lista[index];
                      final total = (item['total'] as num?)?.toDouble() ?? 0;
                      final titulo = tipo == 'ventas'
                          ? 'Factura POS #${item['id']}'
                          : 'Compra #${item['id']}';
                      final subtitulo = tipo == 'ventas'
                          ? '${item['cliente'] ?? 'Cliente general'}'
                          : '${item['proveedor'] ?? 'Sin proveedor'}';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.description),
                          title: Text(titulo),
                          subtitle: Text(
                            '$subtitulo\n${_fecha(item['fecha']?.toString() ?? '')} · ${_fmt(total)}',
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Acciones del documento',
                            onSelected: (action) async {
                              if (action == 'share') {
                                if (tipo == 'ventas') { await _compartirVenta(item); } else { await _compartirCompra(item); }
                              } else if (action == 'whatsapp' && tipo == 'ventas') {
                                await _whatsAppVenta(item);
                              } else if (action == 'output') {
                                final archivo = tipo == 'ventas'
                                    ? await DocumentoPdfService.crearFacturaVenta(item)
                                    : await DocumentoPdfService.crearComprobanteCompra(item);
                                if (!context.mounted) return;
                                await DocumentoPdfService.mostrarOpcionesSalida(context, archivo, titulo: titulo);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Compartir PDF'))),
                              if (tipo == 'ventas') const PopupMenuItem(value: 'whatsapp', child: ListTile(leading: Icon(Icons.chat_outlined), title: Text('Enviar por WhatsApp'))),
                              const PopupMenuItem(value: 'output', child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Imprimir / visualizar / correo'))),
                            ],
                          ),
                          onLongPress: () async {
                            final archivo = tipo == 'ventas'
                                ? await DocumentoPdfService.crearFacturaVenta(
                                    item,
                                  )
                                : await DocumentoPdfService.crearComprobanteCompra(
                                    item,
                                  );
                            if (!context.mounted) return;
                            await DocumentoPdfService.mostrarOpcionesSalida(
                              context,
                              archivo,
                              titulo: tipo == 'ventas'
                                  ? 'Factura POS #${item['id']}'
                                  : 'Compra #${item['id']}',
                            );
                          },
                          onTap: () {
                            if (tipo == 'ventas') {
                              _compartirVenta(item);
                            } else {
                              _compartirCompra(item);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
