/// Página de SIIF Nación (Ministerio de Hacienda y Crédito Público)
/// Consolidación y exportación de reportes presupuestales y financieros mensuales
library;

import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/siif_service.dart';
import '../models/reporte_siif.dart';

class SIIFPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;

  const SIIFPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<SIIFPage> createState() => _SIIFPageState();
}

class _SIIFPageState extends State<SIIFPage> {
  bool _cargando = true;
  SIIFService? _siifService;
  List<ReporteSIIF> _reportes = [];

  @override
  void initState() {
    super.initState();
    _inicializarServicios();
  }

  Future<void> _inicializarServicios() async {
    setState(() => _cargando = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoria = AuditoriaService(db);
      _siifService = SIIFService(db: db, auditoriaService: auditoria);
      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al inicializar SIIF Nación: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDatos() async {
    if (_siifService == null) return;
    try {
      final list = await _siifService!.consultarReportes(entidadId: widget.entidadId);
      setState(() {
        _reportes = list;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar reportes SIIF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SIIF Nación (MinHacienda)'),
        actions: [
          IconButton(
            tooltip: 'Actualizar reportes',
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSIIFBanner(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _generarReportePresupuestoDialog,
                          icon: const Icon(Icons.account_balance),
                          label: const Text('Reporte Presupuesto'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _generarReporteTesoreriaDialog,
                          icon: const Icon(Icons.payments),
                          label: const Text('Reporte Tesorería'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _reportes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_upload, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text('Reportes SIIF Nación', style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              const Text('Generación e integración mensual para el Ministerio de Hacienda'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: _reportes.length,
                          itemBuilder: (context, index) {
                            final r = _reportes[index];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: MerkaThemeTokens.navy800,
                                  child: Icon(Icons.description, color: Colors.white),
                                ),
                                title: Text('${r.nombreReporte} - Mes: ${r.mes} / ${r.vigencia}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Fecha: ${r.fechaGeneracion.toString().substring(0, 16)} | Estado: ${r.estado}'),
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'Acciones',
                                  onSelected: (value) {
                                    if (value == 'export') _exportarPlano(r.id);
                                    if (value == 'send') _transmitir(r.id);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.file_download), title: Text('Exportar plano'))),
                                    if (r.estado != 'enviado')
                                      const PopupMenuItem(value: 'send', child: ListTile(leading: Icon(Icons.send), title: Text('Transmitir por canal configurado'))),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSIIFBanner() {
    return Container(
      color: MerkaThemeTokens.paper100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.info, color: MerkaThemeTokens.info),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Módulo de preparación e interoperabilidad SIIF configurada por la entidad. '
              'Genera la estructura de intercambio de Presupuesto y Tesorería en formato plano .txt.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _transmitir(String reporteId) async {
    if (_siifService == null) return;
    setState(() => _cargando = true);
    try {
      await _siifService!.transmitirReporte(
        reporteId: reporteId,
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El canal SIIF configurado aceptó la transmisión.')),
        );
      }
      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible transmitir SIIF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _generarReportePresupuestoDialog() {
    if (_siifService == null) return;
    final vigenciaCtrl = TextEditingController(text: DateTime.now().year.toString());
    int mesSeleccionado = DateTime.now().month;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Reporte Presupuesto SIIF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vigenciaCtrl,
                decoration: const InputDecoration(labelText: 'Vigencia Fiscal', hintText: 'ej. 2026'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: mesSeleccionado,
                decoration: const InputDecoration(labelText: 'Mes a Reportar'),
                items: List.generate(12, (i) => i + 1).map((m) {
                  return DropdownMenuItem(
                    value: m,
                    child: Text('Mes $m - ${_nombreMes(m)}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => mesSeleccionado = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (vigenciaCtrl.text.isEmpty) return;
                try {
                  final rep = await _siifService!.generarReportePresupuestoMensual(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    vigencia: vigenciaCtrl.text,
                    mes: mesSeleccionado,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Reporte Presupuestal SIIF generado (#${rep.id.substring(0, 8)})')),
                    );
                  }
                  _cargarDatos();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Generar'),
            ),
          ],
        ),
      ),
    );
  }

  void _generarReporteTesoreriaDialog() {
    if (_siifService == null) return;
    final vigenciaCtrl = TextEditingController(text: DateTime.now().year.toString());
    int mesSeleccionado = DateTime.now().month;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Reporte Tesorería SIIF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vigenciaCtrl,
                decoration: const InputDecoration(labelText: 'Vigencia Fiscal', hintText: 'ej. 2026'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: mesSeleccionado,
                decoration: const InputDecoration(labelText: 'Mes a Reportar'),
                items: List.generate(12, (i) => i + 1).map((m) {
                  return DropdownMenuItem(
                    value: m,
                    child: Text('Mes $m - ${_nombreMes(m)}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => mesSeleccionado = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (vigenciaCtrl.text.isEmpty) return;
                try {
                  final rep = await _siifService!.generarReporteTesoreriaMensual(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    vigencia: vigenciaCtrl.text,
                    mes: mesSeleccionado,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Reporte Tesorería SIIF generado (#${rep.id.substring(0, 8)})')),
                    );
                  }
                  _cargarDatos();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Generar'),
            ),
          ],
        ),
      ),
    );
  }

  void _exportarPlano(String reporteId) async {
    if (_siifService == null) return;
    try {
      final plano = await _siifService!.exportarAPlano(reporteId);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Archivo Plano SIIF Nación (.txt)'),
            content: SingleChildScrollView(
              child: SelectableText(plano),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar plano: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _nombreMes(int m) {
    const meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return meses[m - 1];
  }
}
