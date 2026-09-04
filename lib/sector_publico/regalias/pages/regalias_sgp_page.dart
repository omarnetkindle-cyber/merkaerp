/// Página de Regalías (SGR), SGP, Proyectos OCAD y Reportes SPGR
/// Ley 2056 de 2020 (SGR) + Ley 1176 de 2007 (SGP)
library;

import 'package:flutter/material.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/regalias_service.dart';
import '../services/sgp_service.dart';
import '../services/spgr_service.dart';
import '../services/sicodis_service.dart';
import '../models/regalia.dart';
import '../models/sgp.dart';
import '../models/proyecto_ocad.dart';
import '../models/bienio_sgr.dart';
import '../../../core/currency/public_sector_money.dart';

class RegaliasSGPPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;

  const RegaliasSGPPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<RegaliasSGPPage> createState() => _RegaliasSGPPageState();
}

class _RegaliasSGPPageState extends State<RegaliasSGPPage> {
  int _selectedIndex = 0;
  bool _cargando = true;

  RegaliasService? _regaliasService;
  SGPService? _sgpService;
  SPGRService? _spgrService;
  SICODISService? _sicodisService;

  List<Regalia> _regalias = [];
  List<SGP> _sgps = [];
  List<ProyectoOCAD> _proyectosOCAD = [];
  List<BienioSGR> _bienios = [];

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

      _regaliasService = RegaliasService(db: db, auditoriaService: auditoria);
      _sgpService = SGPService(db: db, auditoriaService: auditoria);
      _spgrService = SPGRService(db: db, auditoriaService: auditoria);
      _sicodisService = SICODISService(db: db, auditoriaService: auditoria);

      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al inicializar servicios de Regalías: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDatos() async {
    if (_regaliasService == null ||
        _sgpService == null ||
        _spgrService == null) {
      return;
    }
    try {
      final regalias = await _regaliasService!.consultarRegalias(
        entidadId: widget.entidadId,
      );
      final sgps = await _sgpService!.consultarSGP(entidadId: widget.entidadId);
      final ocads = await _spgrService!.consultarProyectosOCAD(
        entidadId: widget.entidadId,
      );
      final bienios = await _spgrService!.consultarBieniosSGR(
        entidadId: widget.entidadId,
      );

      setState(() {
        _regalias = regalias;
        _sgps = sgps;
        _proyectosOCAD = ocads;
        _bienios = bienios;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos de Regalías/SGP: $e'),
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
        title: const Text('Regalías (SGR) y SGP'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: Icon(Icons.date_range),
            tooltip: 'Crear Bienio SGR',
            onPressed: _crearBienioSGRDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar información',
            onPressed: _cargarDatos,
          ),
          IconButton(
            icon: Icon(Icons.cloud_upload),
            tooltip: 'Reporte SPGR (MinHacienda)',
            onPressed: _generarReporteSPGRDialog,
          ),
          IconButton(
            icon: Icon(Icons.verified_user),
            tooltip: 'Certificación SICODIS (DNP)',
            onPressed: _generarReporteSICODISDialog,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: [_buildRegaliasTab(), _buildSGPTab(), _buildOCADTab(), _buildBieniosTab()],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.monetization_on),
            label: 'Regalías (SGR)',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance),
            label: 'SGP',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.gavel),
            label: 'Proyectos OCAD',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.date_range),
            label: 'Bienios SGR',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarDialogoAccion,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildRegaliasTab() {
    if (_regalias.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monetization_on, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Regalías (SGR)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Sistema General de Regalías - Ley 2056 de 2020'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _estimarRegaliaDialog,
              icon: Icon(Icons.add),
              label: const Text('Estimar Regalía'),
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
      itemCount: _regalias.length,
      itemBuilder: (context, index) {
        final r = _regalias[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.monetization_on, color: Colors.white),
            ),
            title: Text(
              '${r.proyecto} (#${r.numeroRegalia})',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Tipo: ${r.tipoRegalia.name} | Vigencia: ${r.vigencia}\nEstimado: ${publicMoneyForDisplay(r.valorEstimado)} | Recibido: ${publicMoneyForDisplay(r.valorRecibido)}',
            ),
          ),
        );
      },
    );
  }

  Widget _buildSGPTab() {
    if (_sgps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('SGP', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Sistema General de Participaciones - Ley 1176 de 2007'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _asignarSGPDialog,
              icon: Icon(Icons.add),
              label: const Text('Asignar SGP'),
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
      itemCount: _sgps.length,
      itemBuilder: (context, index) {
        final s = _sgps[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.account_balance, color: Colors.white),
            ),
            title: Text(
              '${s.programa} (#${s.numeroSGP})',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Participación: ${s.tipoParticipacion.name} | Vigencia: ${s.vigencia}\nAsignado: ${publicMoneyForDisplay(s.valorAsignado)} | Saldo: ${publicMoneyForDisplay(s.saldoDisponible)}',
            ),
          ),
        );
      },
    );
  }

  Widget _buildOCADTab() {
    if (_proyectosOCAD.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Proyectos OCAD SGR',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Órganos Colegiados de Administración y Decisión (Banco MGA DNP)',
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _crearProyectoOCADDialog,
              icon: Icon(Icons.add),
              label: const Text('Registrar Proyecto OCAD'),
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
      itemCount: _proyectosOCAD.length,
      itemBuilder: (context, index) {
        final p = _proyectosOCAD[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.gavel, color: Colors.white),
            ),
            title: Text(
              '${p.nombreProyecto} (BPIN: ${p.codigoBPIN})',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Bienalidad: ${p.bienalidad} | OCAD: ${p.tipoOCAD.name}\nAprobado: ${publicMoneyForDisplay(p.montoAprobado)} | Girado SPGR: ${publicMoneyForDisplay(p.montoGiroSPGR)}',
            ),
            trailing: IconButton(
              icon: Icon(Icons.payment, color: Colors.green),
              tooltip: 'Registrar Giro SPGR',
              onPressed: () => _registrarGiroSPGRDialog(p),
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoAccion() {
    switch (_selectedIndex) {
      case 0:
        _estimarRegaliaDialog();
        break;
      case 1:
        _asignarSGPDialog();
        break;
      case 2:
        _crearProyectoOCADDialog();
        break;
      case 3:
        _crearBienioSGRDialog();
        break;
    }
  }

  Widget _buildBieniosTab() {
    if (_bienios.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay bienios SGR registrados. Usa el botón + para crear el primer período bienal.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _bienios.length,
      itemBuilder: (context, index) {
        final bienio = _bienios[index];
        final budgeted = bienio.montoPresupuestadoBienio.minorUnits;
        final executed = bienio.montoEjecutadoBienio.minorUnits;
        final progress = budgeted <= 0
            ? 0.0
            : (executed / budgeted).clamp(0.0, 1.0).toDouble();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_view_month_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bienio.codigoBienio,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Chip(
                      label: Text(bienio.estado == EstadoBienioSGR.vigente ? 'Vigente' : 'Cerrado'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${bienio.fechaInicio.day}/${bienio.fechaInicio.month}/${bienio.fechaInicio.year} → '
                  '${bienio.fechaFin.day}/${bienio.fechaFin.month}/${bienio.fechaFin.year}',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 6),
                Text(
                  'Ejecutado ${bienio.montoEjecutadoBienio.format()} de ${bienio.montoPresupuestadoBienio.format()} '
                  '(${(progress * 100).toStringAsFixed(1)}%)',
                ),
                if ((bienio.observaciones ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(bienio.observaciones!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _crearBienioSGRDialog() {
    if (_spgrService == null) return;
    final codigoCtrl = TextEditingController(text: '2025-2026');
    final montoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Bienio Presupuestal SGR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codigoCtrl,
              decoration: const InputDecoration(
                labelText: 'Código Bienalidad (ej. 2025-2026)',
                hintText: 'ej. 2025-2026',
              ),
            ),
            TextField(
              controller: montoCtrl,
              decoration: const InputDecoration(
                labelText: 'Monto Presupuestado Bienio',
                hintText: 'ej. 1000000000',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (codigoCtrl.text.isEmpty || montoCtrl.text.isEmpty) return;
              try {
                final ahora = DateTime.now();
                await _spgrService!.crearBienioSGR(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  codigoBienio: codigoCtrl.text,
                  fechaInicio: DateTime(ahora.year, 1, 1),
                  fechaFin: DateTime(ahora.year + 1, 12, 31),
                  montoPresupuestado: publicMoneyFromMajor(montoCtrl.text),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bienio SGR registrado')),
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
            child: const Text('Crear Bienio'),
          ),
        ],
      ),
    );
  }

  void _estimarRegaliaDialog() {
    if (_regaliasService == null) return;
    final proyectoCtrl = TextEditingController();
    final municipioCtrl = TextEditingController();
    final departamentoCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final vigenciaCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    TipoRegalia tipoSeleccionado = TipoRegalia.hidrocarburos;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Estimar Regalía (SGR)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: proyectoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Proyecto / Asignación',
                    hintText: 'ej. Pavimentación Vía Principal',
                  ),
                ),
                DropdownButtonFormField<TipoRegalia>(
                  initialValue: tipoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Regalía',
                  ),
                  items: TipoRegalia.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: municipioCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Municipio',
                    hintText: 'ej. Sopó',
                  ),
                ),
                TextField(
                  controller: departamentoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Departamento',
                    hintText: 'ej. Cundinamarca',
                  ),
                ),
                TextField(
                  controller: valorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor Estimado',
                    hintText: 'ej. 150000000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: vigenciaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vigencia Fiscal (año)',
                    hintText: 'ej. 2026',
                  ),
                  keyboardType: TextInputType.number,
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
                if (proyectoCtrl.text.isEmpty ||
                    municipioCtrl.text.isEmpty ||
                    departamentoCtrl.text.isEmpty ||
                    valorCtrl.text.isEmpty ||
                    vigenciaCtrl.text.isEmpty) {
                  return;
                }
                try {
                  await _regaliasService!.estimarRegalia(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    tipoRegalia: tipoSeleccionado,
                    proyecto: proyectoCtrl.text,
                    municipio: municipioCtrl.text,
                    departamento: departamentoCtrl.text,
                    valorEstimado: publicMoneyFromMajor(valorCtrl.text),
                    vigencia: DateTime(int.parse(vigenciaCtrl.text), 1, 1),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Regalía estimada con éxito'),
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
              child: const Text('Estimar'),
            ),
          ],
        ),
      ),
    );
  }

  void _asignarSGPDialog() {
    if (_sgpService == null) return;
    final programaCtrl = TextEditingController();
    final municipioCtrl = TextEditingController();
    final departamentoCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final vigenciaCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    TipoParticipacion tipoSeleccionado = TipoParticipacion.educacion;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Asignar SGP'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: programaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Programa / Destinación',
                    hintText: 'ej. Alimentación Escolar PAE',
                  ),
                ),
                DropdownButtonFormField<TipoParticipacion>(
                  initialValue: tipoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Participación SGP',
                  ),
                  items: TipoParticipacion.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: municipioCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Municipio',
                    hintText: 'ej. Sopó',
                  ),
                ),
                TextField(
                  controller: departamentoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Departamento',
                    hintText: 'ej. Cundinamarca',
                  ),
                ),
                TextField(
                  controller: valorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor Asignado',
                    hintText: 'ej. 80000000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: vigenciaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vigencia Fiscal (año)',
                    hintText: 'ej. 2026',
                  ),
                  keyboardType: TextInputType.number,
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
                if (programaCtrl.text.isEmpty ||
                    municipioCtrl.text.isEmpty ||
                    departamentoCtrl.text.isEmpty ||
                    valorCtrl.text.isEmpty ||
                    vigenciaCtrl.text.isEmpty) {
                  return;
                }
                try {
                  await _sgpService!.asignarSGP(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    tipoParticipacion: tipoSeleccionado,
                    programa: programaCtrl.text,
                    municipio: municipioCtrl.text,
                    departamento: departamentoCtrl.text,
                    valorAsignado: publicMoneyFromMajor(valorCtrl.text),
                    vigencia: DateTime(int.parse(vigenciaCtrl.text), 1, 1),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Asignación SGP registrada'),
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
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );
  }

  void _crearProyectoOCADDialog() async {
    if (_spgrService == null) return;

    List<Map<String, dynamic>> proyectosMGA = [];
    List<BienioSGR> bienios = [];

    try {
      final db = await DatabaseHelper.instance.database;
      proyectosMGA = await db.query(
        'proyectos_mga',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
      );
      bienios = await _spgrService!.consultarBieniosSGR(
        entidadId: widget.entidadId,
      );
    } catch (e) {
      debugPrint('Error cargando MGA/Bienios: $e');
    }

    String? mgaSeleccionadoId;
    String? bienioSeleccionadoId;
    final bpinCtrl = TextEditingController();
    final nombreProyCtrl = TextEditingController();
    final bienalidadCtrl = TextEditingController(text: '2025-2026');
    final montoAprobadoCtrl = TextEditingController();
    final actaCtrl = TextEditingController();
    final fuenteCtrl = TextEditingController();
    final ejecutoraCtrl = TextEditingController();
    TipoOCAD tipoSeleccionado = TipoOCAD.municipal;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar Proyecto OCAD (SGR)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (proyectosMGA.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar Proyecto Banco MGA DNP',
                    ),
                    items: proyectosMGA.map((mga) {
                      final bpin = mga['codigo_bpin'] as String;
                      final nombre = mga['nombre_proyecto'] as String;
                      final id = mga['id'] as String;
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          '$bpin - $nombre',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final sel = proyectosMGA.firstWhere(
                          (element) => element['id'] == val,
                        );
                        setDialogState(() {
                          mgaSeleccionadoId = val;
                          bpinCtrl.text = sel['codigo_bpin'] as String;
                          nombreProyCtrl.text =
                              sel['nombre_proyecto'] as String;
                          if (sel['valor_total'] != null) {
                            montoAprobadoCtrl.text = publicMoneyFromSql(
                              sel['valor_total'],
                            ).toMajorUnitsString();
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: bpinCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código BPIN DNP',
                    hintText: 'ej. BPIN-2025-25001',
                  ),
                ),
                TextField(
                  controller: nombreProyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Proyecto',
                    hintText: 'ej. Construcción Centro de Salud',
                  ),
                ),
                if (bienios.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar Bienio Presupuestal SGR',
                    ),
                    items: bienios.map((b) {
                      return DropdownMenuItem(
                        value: b.id,
                        child: Text('${b.codigoBienio} (${b.estado.name})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final sel = bienios.firstWhere((b) => b.id == val);
                        setDialogState(() {
                          bienioSeleccionadoId = val;
                          bienalidadCtrl.text = sel.codigoBienio;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: bienalidadCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bienalidad SGR',
                    hintText: 'ej. 2025-2026',
                  ),
                ),
                DropdownButtonFormField<TipoOCAD>(
                  initialValue: tipoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Nivel / Tipo de OCAD',
                  ),
                  items: TipoOCAD.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: montoAprobadoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Monto Aprobado OCAD',
                    hintText: 'ej. 500000000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: actaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Acta de aprobacion OCAD',
                  ),
                ),
                TextField(
                  controller: fuenteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Fuente de financiacion SGR',
                  ),
                ),
                TextField(
                  controller: ejecutoraCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Entidad ejecutora',
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
                if (bpinCtrl.text.isEmpty ||
                    nombreProyCtrl.text.isEmpty ||
                    bienalidadCtrl.text.isEmpty ||
                    montoAprobadoCtrl.text.isEmpty ||
                    actaCtrl.text.isEmpty ||
                    fuenteCtrl.text.isEmpty ||
                    ejecutoraCtrl.text.isEmpty) {
                  return;
                }
                try {
                  await _spgrService!.crearProyectoOCAD(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    proyectoMgaId: mgaSeleccionadoId,
                    bienioId: bienioSeleccionadoId,
                    codigoBPIN: bpinCtrl.text,
                    nombreProyecto: nombreProyCtrl.text,
                    bienalidad: bienalidadCtrl.text,
                    tipoOCAD: tipoSeleccionado,
                    montoAprobado: publicMoneyFromMajor(montoAprobadoCtrl.text),
                    fechaAprobacion: DateTime.now(),
                    actaAprobacion: actaCtrl.text,
                    fuenteFinanciacion: fuenteCtrl.text,
                    entidadEjecutora: ejecutoraCtrl.text,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Proyecto OCAD registrado')),
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
              child: const Text('Registrar Proyecto'),
            ),
          ],
        ),
      ),
    );
  }

  void _registrarGiroSPGRDialog(ProyectoOCAD proyecto) {
    if (_spgrService == null) return;
    final montoGiroCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Registrar Giro SPGR - ${proyecto.nombreProyecto}'),
        content: TextField(
          controller: montoGiroCtrl,
          decoration: InputDecoration(
            labelText: 'Monto del Giro SPGR',
            hintText: 'ej. ${proyecto.saldoPendienteGiro.toMajorUnitsString()}',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (montoGiroCtrl.text.isEmpty) return;
              try {
                await _spgrService!.registrarGiroSPGR(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  proyectoId: proyecto.id,
                  montoGiro: publicMoneyFromMajor(montoGiroCtrl.text),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Giro SPGR aplicado al proyecto OCAD'),
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
            child: const Text('Registrar Giro'),
          ),
        ],
      ),
    );
  }

  void _generarReporteSPGRDialog() {
    if (_spgrService == null) return;
    final bienalidadCtrl = TextEditingController(text: '2025-2026');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generar Reporte SPGR (MinHacienda / DNP)'),
        content: TextField(
          controller: bienalidadCtrl,
          decoration: const InputDecoration(
            labelText: 'Bienalidad SGR',
            hintText: 'ej. 2025-2026',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (bienalidadCtrl.text.isEmpty) return;
              try {
                final rep = await _spgrService!.generarReporteSPGR(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  bienalidad: bienalidadCtrl.text,
                );
                final plano = await _spgrService!.exportarAPlano(rep.id);

                if (context.mounted) {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Reporte SPGR Generado (.txt MHCP)'),
                      content: SingleChildScrollView(
                        child: SelectableText(plano),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cerrar'),
                        ),
                      ],
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
            child: const Text('Generar y Exportar'),
          ),
        ],
      ),
    );
  }

  void _generarReporteSICODISDialog() {
    if (_sicodisService == null) return;
    final vigenciaCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    String sectorSeleccionado = 'Educación';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Certificación SICODIS SGP (DNP)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vigenciaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Vigencia Fiscal SGP',
                  hintText: 'ej. 2026',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: sectorSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Sector de Participación SGP',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Educación',
                    child: Text('Educación (SGP)'),
                  ),
                  DropdownMenuItem(value: 'Salud', child: Text('Salud (SGP)')),
                  DropdownMenuItem(
                    value: 'Agua Potable',
                    child: Text('Agua Potable y Saneamiento (APSB)'),
                  ),
                  DropdownMenuItem(
                    value: 'Propósito General',
                    child: Text('Propósito General'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => sectorSeleccionado = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (vigenciaCtrl.text.isEmpty) return;
                try {
                  final rep = await _sicodisService!
                      .generarCertificacionSICODIS(
                        entidadId: widget.entidadId,
                        usuarioId: widget.usuarioId,
                        vigencia: vigenciaCtrl.text,
                        sectorParticipacion: sectorSeleccionado,
                      );
                  final plano = await _sicodisService!.exportarAPlano(rep.id);

                  if (context.mounted) {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text(
                          'Certificación SICODIS Generada (.txt DNP)',
                        ),
                        content: SingleChildScrollView(
                          child: SelectableText(plano),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cerrar'),
                          ),
                        ],
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
              child: const Text('Generar Certificación'),
            ),
          ],
        ),
      ),
    );
  }
}
