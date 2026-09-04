import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'audit/pages/audit_risk_page.dart';

import 'db_helper.dart';

class AuditoriaPage extends StatefulWidget {
  const AuditoriaPage({super.key});

  @override
  State<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends State<AuditoriaPage> {
  List<Map<String, dynamic>> eventos = [];
  String filtro = '';
  String filtroEntidad = 'todas';
  DateTime? filtroDesde;
  DateTime? filtroHasta;

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
    final data = await DatabaseHelper.instance.obtenerAuditoria();
    if (!mounted) return;
    setState(() => eventos = data);
  }

  List<Map<String, dynamic>> get _visibles {
    return eventos.where((e) {
      final texto =
          '${e['accion']} ${e['entidad']} ${e['detalle']} ${e['usuario']}'
              .toLowerCase();
      if (!texto.contains(filtro.toLowerCase().trim())) return false;
      if (filtroEntidad != 'todas' &&
          e['entidad']?.toString().toLowerCase() != filtroEntidad) {
        return false;
      }
      final fechaStr = e['fecha']?.toString() ?? '';
      if (fechaStr.isNotEmpty && (filtroDesde != null || filtroHasta != null)) {
        try {
          final fecha = DateTime.parse(fechaStr);
          if (filtroDesde != null && fecha.isBefore(filtroDesde!)) return false;
          if (filtroHasta != null &&
              fecha.isAfter(filtroHasta!.add(const Duration(days: 1)))) {
            return false;
          }
        } catch (_) {}
      }
      return true;
    }).toList();
  }

  String _nombreEntidadAmigable(String entidad) {
    final mapa = {
      'ventas': 'Ventas',
      'compras': 'Compras',
      'caja': 'Caja',
      'bancos': 'Bancos',
      'inventario': 'Inventario',
      'usuarios': 'Usuarios',
      'asientos_contables': 'Contabilidad',
      'comprobantes_contables': 'Comprobantes',
      'cuentas_contables': 'Plan de Cuentas',
      'cierres_caja': 'Cierres de Caja',
      'movimientos_caja': 'Movimientos',
      'productos': 'Productos',
      'proveedores': 'Proveedores',
      'clientes': 'Clientes',
      'empresa_config': 'Configuración',
    };
    return mapa[entidad.toLowerCase()] ?? entidad;
  }

  String _deviceLabel(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 'No identificado';
    return value.length <= 16 ? value : '${value.substring(0, 16)}…';
  }

  Future<void> _exportarExcel() async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final hoja = excel['Auditoria'];
    hoja.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Acción'),
      TextCellValue('Entidad'),
      TextCellValue('Usuario'),
      TextCellValue('Equipo'),
      TextCellValue('Valor anterior'),
      TextCellValue('Valor nuevo'),
      TextCellValue('Detalle'),
    ]);
    for (final e in _visibles) {
      hoja.appendRow([
        TextCellValue(e['fecha']?.toString() ?? ''),
        TextCellValue(e['accion']?.toString() ?? ''),
        TextCellValue(e['entidad']?.toString() ?? ''),
        TextCellValue(e['usuario']?.toString() ?? 'local'),
        TextCellValue(_deviceLabel(e['device_id'])),
        TextCellValue(e['old_values']?.toString() ?? ''),
        TextCellValue(e['new_values']?.toString() ?? ''),
        TextCellValue(e['detalle']?.toString() ?? ''),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) return;

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Exportar auditoría',
      fileName: 'auditoria_merkaerp.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (path == null) return;
    final destino = path.endsWith('.xlsx') ? path : '$path.xlsx';
    await File(destino).writeAsBytes(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Auditoría exportada: $destino')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final entidades = {
      for (final e in eventos) e['entidad']?.toString() ?? 'general',
    }.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría'),
        actions: [
          IconButton(
            tooltip: 'Analizar operaciones de riesgo',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuditRiskPage())),
            icon: const Icon(Icons.gpp_maybe),
          ),
          IconButton(
            tooltip: 'Exportar Excel',
            onPressed: visibles.isEmpty ? null : _exportarExcel,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: eventos.isEmpty
          ? const Center(child: Text('No hay eventos de auditoría'))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    color: Colors.green.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.fact_check),
                      title: Text('${visibles.length} de ${eventos.length} eventos'),
                      subtitle: const Text(
                        'Trazabilidad de cambios, cierres, usuarios y documentos.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Filtros agrupados por categoría (Mejora 11)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Filtro de búsqueda
                          const Text(
                            'Buscar',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              labelText: 'Texto en acción, entidad, usuario o detalle',
                              border: const OutlineInputBorder(),
                              helperText: 'Escribe para filtrar por cualquier campo',
                              isDense: true,
                            ),
                            onChanged: (value) => setState(() => filtro = value),
                          ),
                          const SizedBox(height: 12),
                          // Filtro por entidad
                          const Text(
                            'Filtrar por módulo',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            children: [
                              FilterChip(
                                label: const Text('Todos los módulos'),
                                selected: filtroEntidad == 'todas',
                                onSelected: (_) => setState(() => filtroEntidad = 'todas'),
                                tooltip: 'Mostrar eventos de todos los módulos del sistema',
                              ),
                              ...entidades.map(
                                (ent) => FilterChip(
                                  label: Text(_nombreEntidadAmigable(ent)),
                                  selected: filtroEntidad == ent.toLowerCase(),
                                  onSelected: (_) =>
                                      setState(() => filtroEntidad = ent.toLowerCase()),
                                  tooltip: 'Mostrar solo eventos del módulo $ent',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Filtro por fecha
                          const Text(
                            'Filtrar por fecha',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              ActionChip(
                                avatar: const Icon(Icons.calendar_today, size: 18),
                                label: Text(
                                  filtroDesde == null
                                      ? 'Fecha inicio'
                                      : 'Desde ${filtroDesde!.day}/${filtroDesde!.month}/${filtroDesde!.year}',
                                ),
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: filtroDesde ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (d != null) setState(() => filtroDesde = d);
                                },
                                tooltip: 'Seleccionar fecha de inicio del rango',
                              ),
                              const SizedBox(width: 8),
                              ActionChip(
                                avatar: const Icon(Icons.calendar_today, size: 18),
                                label: Text(
                                  filtroHasta == null
                                      ? 'Fecha fin'
                                      : 'Hasta ${filtroHasta!.day}/${filtroHasta!.month}/${filtroHasta!.year}',
                                ),
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: filtroHasta ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (d != null) setState(() => filtroHasta = d);
                                },
                                tooltip: 'Seleccionar fecha de fin del rango',
                              ),
                              const SizedBox(width: 8),
                              if (filtroDesde != null || filtroHasta != null)
                                ActionChip(
                                  avatar: const Icon(Icons.clear, size: 18),
                                  label: const Text('Limpiar fechas'),
                                  onPressed: () {
                                    setState(() {
                                      filtroDesde = null;
                                      filtroHasta = null;
                                    });
                                  },
                                  tooltip: 'Quitar filtro de fechas',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...visibles.map(
                    (e) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: MerkaThemeTokens.paper100,
                          child: const Icon(Icons.history),
                        ),
                        title: Text('${e['accion']} - ${e['entidad']}'),
                        subtitle: Text(
                          '${e['fecha']}\nUsuario: ${e['usuario'] ?? 'local'} · Equipo: ${_deviceLabel(e['device_id'])}\n${e['detalle'] ?? ''}',
                        ),
                        isThreeLine: true,
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(e['accion']?.toString() ?? 'Evento'),
                              content: Text(
                                'Entidad: ${e['entidad']}\n'
                                'ID: ${e['entidad_id'] ?? ''}\n'
                                'Fecha: ${e['fecha']}\n'
                                'Usuario: ${e['usuario'] ?? 'local'}\n'
                                'Equipo (huella): ${_deviceLabel(e['device_id'])}\n'
                                'IP: ${e['ip_address'] ?? 'No registrada'}\n\n'
                                'Valor anterior: ${e['old_values'] ?? 'No registrado'}\n'
                                'Valor nuevo: ${e['new_values'] ?? 'No registrado'}\n\n'
                                '${e['detalle'] ?? ''}',
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
              ),
            ),
    );
  }
}
