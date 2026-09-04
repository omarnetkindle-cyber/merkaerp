/// Página de Planeación
/// Banco de Proyectos MGA + PDT + Flujo de Viabilización DNP
library;

import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/banco_proyectos_service.dart';
import '../services/pdt_service.dart';
import '../services/formulacion_mga_service.dart';
import '../services/viabilizacion_service.dart';
import '../models/proyecto_mga.dart';
import '../models/pdt.dart';
import 'formulacion_mga_form_page.dart';
import '../../../core/currency/public_sector_money.dart';

class PlaneacionPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final int tabInicial;

  const PlaneacionPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
    this.tabInicial = 0,
  });

  @override
  State<PlaneacionPage> createState() => _PlaneacionPageState();
}

class _PlaneacionPageState extends State<PlaneacionPage> {
  int _selectedIndex = 0;
  bool _cargando = true;

  BancoProyectosService? _bancoProyectosService;
  PDTService? _pdtService;
  FormulacionMGAService? _formulacionMGAService;
  ViabilizacionService? _viabilizacionService;

  List<ProyectoMGA> _proyectos = [];
  List<PDT> _pdts = [];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.tabInicial.clamp(0, 1).toInt();
    _inicializarServicios();
  }

  Future<void> _inicializarServicios() async {
    setState(() => _cargando = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoria = AuditoriaService(db);

      _bancoProyectosService = BancoProyectosService(
        db: db,
        auditoriaService: auditoria,
      );
      _pdtService = PDTService(db: db, auditoriaService: auditoria);
      _formulacionMGAService = FormulacionMGAService(
        db: db,
        auditoriaService: auditoria,
      );
      _viabilizacionService = ViabilizacionService(
        db: db,
        auditoriaService: auditoria,
      );

      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al inicializar servicios: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDatos() async {
    if (_bancoProyectosService == null || _pdtService == null) return;
    try {
      final proyectos = await _bancoProyectosService!.consultarProyectos(
        entidadId: widget.entidadId,
      );
      final pdts = await _pdtService!.consultarPDT(entidadId: widget.entidadId);

      setState(() {
        _proyectos = proyectos;
        _pdts = pdts;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planeación Territorial & BPIN (DNP)'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(tooltip: 'Actualizar información', icon: Icon(Icons.refresh), onPressed: _cargarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTraceabilityBanner(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [_buildProyectosMGATab(), _buildPDTTab()],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.account_tree),
            label: 'Proyectos MGA',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'PDT'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarDialogoAccion,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add),
      ),
    );
  }

  /// Brecha documentada: la vinculacion automatica PDT/MGA con rubros de
  /// inversion y su cadena CDP/RP aun requiere un frente propio.
  Widget _buildTraceabilityBanner() {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Pendiente: vincular automaticamente metas PDT/MGA con rubros de inversion y su cadena CDP/RP. '
              'La planeacion y el presupuesto siguen operativos por separado.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProyectosMGATab() {
    if (_proyectos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_tree, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Banco de Proyectos MGA (BPIN)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Metodología General Ajustada - DNP'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _registrarProyectoForm,
              icon: Icon(Icons.add),
              label: const Text('Registrar Proyecto MGA'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _proyectos.length,
      itemBuilder: (context, index) {
        final proyecto = _proyectos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                proyecto.codigoBPIN.length >= 4
                    ? proyecto.codigoBPIN.substring(0, 4)
                    : 'BPIN',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
            title: Text(
              proyecto.nombreProyecto,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BPIN: ${proyecto.codigoBPIN} | Sector: ${proyecto.sector}',
                ),
                Text(
                  'Valor Total: ${publicMoneyForDisplay(proyecto.valorTotal)} | Estado: ${proyecto.estado.toString().split('.').last}',
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'sincronizar') _sincronizarBPIN(proyecto);
                if (val == 'viabilizar') _iniciarViabilizacion(proyecto);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'sincronizar',
                  child: Row(
                    children: [
                      Icon(Icons.cloud_upload, color: MerkaThemeTokens.info),
                      SizedBox(width: 8),
                      Text('Sincronizar BPIN DNP'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'viabilizar',
                  child: Row(
                    children: [
                      Icon(Icons.rule, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Iniciar Viabilización'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPDTTab() {
    if (_pdts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Plan de Desarrollo Territorial',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('PDT - Planificación Cuatrienal'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _crearPDTDialog,
              icon: Icon(Icons.add),
              label: const Text('Crear PDT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _pdts.length,
      itemBuilder: (context, index) {
        final pdt = _pdts[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.map, color: Colors.white),
            ),
            title: Text(
              pdt.nombrePDT,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vigencia: ${pdt.vigencia} | Estado: ${pdt.estado.toString().split('.').last}',
                ),
                Text('Visión: ${pdt.vision}'),
              ],
            ),
            trailing: pdt.estado == EstadoPDT.borrador
                ? ElevatedButton(
                    onPressed: () => _aprobarPDTConcejoDialog(pdt),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Aprobar Concejo',
                      style: TextStyle(fontSize: 11),
                    ),
                  )
                : const Chip(
                    label: Text(
                      'Aprobado',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                    backgroundColor: Colors.green,
                  ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoAccion() {
    switch (_selectedIndex) {
      case 0:
        _registrarProyectoForm();
        break;
      case 1:
        _crearPDTDialog();
        break;
    }
  }

  void _registrarProyectoForm() {
    if (_formulacionMGAService == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FormulacionMGAFormPage(
          formulacionMGAService: _formulacionMGAService!,
          entidadId: widget.entidadId,
          usuarioId: widget.usuarioId,
        ),
      ),
    ).then((_) => _cargarDatos());
  }

  void _sincronizarBPIN(ProyectoMGA proyecto) async {
    if (_bancoProyectosService == null) return;
    try {
      await _bancoProyectosService!.sincronizarConBPIN(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        proyectoId: proyecto.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Proyecto BPIN ${proyecto.codigoBPIN} sincronizado con DNP',
            ),
          ),
        );
      }
      _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al sincronizar con BPIN DNP: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _iniciarViabilizacion(ProyectoMGA proyecto) async {
    if (_viabilizacionService == null) return;
    final motivoCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Iniciar Flujo de Viabilización - ${proyecto.nombreProyecto}',
        ),
        content: TextField(
          controller: motivoCtrl,
          decoration: const InputDecoration(
            labelText: 'Motivo / Justificación DNP',
            hintText: 'ej. Justificación técnica de impacto municipal',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (motivoCtrl.text.isEmpty) return;
              try {
                await _viabilizacionService!.iniciarViabilizacion(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  proyectoId: proyecto.id,
                  motivo: motivoCtrl.text,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Flujo de viabilización iniciado exitosamente',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
  }

  void _crearPDTDialog() {
    if (_pdtService == null) return;
    final nombreCtrl = TextEditingController();
    final vigenciaCtrl = TextEditingController();
    final visionCtrl = TextEditingController();
    final misionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Plan de Desarrollo Territorial (PDT)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del PDT',
                  hintText: 'ej. Plan de Desarrollo Municipal 2024-2027',
                ),
              ),
              TextField(
                controller: vigenciaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Vigencia Cuatrienal',
                  hintText: 'ej. 2024-2027',
                ),
              ),
              TextField(
                controller: visionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Visión Territorial',
                  hintText: 'ej. Municipio sostenible e incluyente',
                ),
              ),
              TextField(
                controller: misionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Misión Institucional',
                  hintText: 'ej. Garantizar el desarrollo social y económico',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nombreCtrl.text.isEmpty ||
                  vigenciaCtrl.text.isEmpty ||
                  visionCtrl.text.isEmpty) {
                return;
              }
              try {
                await _pdtService!.crearPDT(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  vigencia: vigenciaCtrl.text,
                  nombrePDT: nombreCtrl.text,
                  vision: visionCtrl.text,
                  mision: misionCtrl.text,
                  fechaInicio: DateTime.now(),
                  fechaFin: DateTime.now().add(const Duration(days: 365 * 4)),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PDT creado en estado borrador'),
                    ),
                  );
                }
                _cargarDatos();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Crear PDT'),
          ),
        ],
      ),
    );
  }

  void _aprobarPDTConcejoDialog(PDT pdt) {
    if (_pdtService == null) return;
    final acuerdoCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aprobar PDT por Concejo - ${pdt.nombrePDT}'),
        content: TextField(
          controller: acuerdoCtrl,
          decoration: const InputDecoration(
            labelText: 'Acto Administrativo (Acuerdo municipal)',
            hintText: 'ej. Acuerdo 005 de 2024',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (acuerdoCtrl.text.isEmpty) return;
              try {
                await _pdtService!.aprobarPDTConcejo(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  pdtId: pdt.id,
                  actoAdministrativo: acuerdoCtrl.text,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PDT aprobado por Concejo municipal'),
                    ),
                  );
                }
                _cargarDatos();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }
}
