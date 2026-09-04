/// Página de Activos del Estado
/// NICSP 17 + FUT + Depreciación por Unidades de Producción + Revalorización
library;

import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/activos_service.dart';
import '../services/depreciacion_unidades_service.dart';
import '../services/revalorizacion_service.dart';
import '../services/fondo_unidad_tesoreria_service.dart';
import '../services/acta_responsabilidad_service.dart';
import '../models/activo_estado.dart';
import '../models/fondo_unidad_tesoreria.dart';
import '../../../core/currency/public_sector_money.dart';

class ActivosEstadoPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;

  const ActivosEstadoPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<ActivosEstadoPage> createState() => _ActivosEstadoPageState();
}

class _ActivosEstadoPageState extends State<ActivosEstadoPage> {
  int _selectedIndex = 0;
  bool _cargando = true;

  ActivosService? _activosService;
  DepreciacionUnidadesService? _depreciacionUnidadesService;
  RevalorizacionService? _revalorizacionService;
  FondoUnidadTesoreriaService? _futService;
  ActaResponsabilidadService? _actaService;

  List<ActivoEstado> _activos = [];
  List<FondoUnidadTesoreria> _futs = [];

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

      _activosService = ActivosService(db: db, auditoriaService: auditoria);
      _depreciacionUnidadesService = DepreciacionUnidadesService(
        db: db,
        auditoriaService: auditoria,
      );
      _revalorizacionService = RevalorizacionService(
        db: db,
        auditoriaService: auditoria,
      );
      _futService = FondoUnidadTesoreriaService(
        db: db,
        auditoriaService: auditoria,
      );
      _actaService = ActaResponsabilidadService(
        db: db,
        auditoriaService: auditoria,
      );

      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al inicializar servicios de Activos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDatos() async {
    if (_activosService == null || _futService == null) return;
    try {
      final activos = await _activosService!.consultarActivos(
        entidadId: widget.entidadId,
      );
      final futs = await _futService!.consultarFUT(entidadId: widget.entidadId);

      setState(() {
        _activos = activos;
        _futs = futs;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos de Activos: $e'),
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
        title: const Text('Propiedad, Planta y Equipo (NICSP 17)'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(tooltip: 'Actualizar información', icon: Icon(Icons.refresh), onPressed: _cargarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildResponsibilityBanner(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [_buildActivosTab(), _buildFUTTab()],
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
            icon: Icon(Icons.inventory),
            label: 'Activos NICSP 17',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'FUT',
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

  /// Estado operativo de actas de responsabilidad de cuentadantes.
  Widget _buildResponsibilityBanner() {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Actas de responsabilidad a cuentadantes activas con firma, entrega, traslado y devolucion auditables. '
              'Clasificacion, depreciacion lineal/unidades y revalorizaciones estan activas en SQLite.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivosTab() {
    if (_activos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Gestión de Activos del Estado',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Propiedad, Planta y Equipo según NICSP 17'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _registrarActivoDialog,
              icon: Icon(Icons.add),
              label: const Text('Registrar Activo'),
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
      itemCount: _activos.length,
      itemBuilder: (context, index) {
        final activo = _activos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.precision_manufacturing, color: Colors.white),
            ),
            title: Text(
              '${activo.nombreActivo} (#${activo.numeroInventario})',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tipo: ${activo.tipoActivo.name} | Adquisición: ${publicMoneyForDisplay(activo.valorAdquisicion)}',
                ),
                Text(
                  'Libros: ${publicMoneyForDisplay(activo.valorLibros)} | Deprec. Acum.: ${publicMoneyForDisplay(activo.depreciacionAcumulada)}',
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'depreciar_lineal') _depreciarLinealDialog(activo);
                if (val == 'config_unidades') {
                  _configurarDepreciacionUnidadesDialog(activo);
                }
                if (val == 'revalorizar') _revalorizarActivoDialog(activo);
                if (val == 'asignar_acta') _asignarActaDialog(activo);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'asignar_acta',
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_ind,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(width: 8),
                      Text('Asignar Acta Custodia'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'depreciar_lineal',
                  child: Row(
                    children: [
                      Icon(Icons.trending_down, color: MerkaThemeTokens.info),
                      SizedBox(width: 8),
                      Text('Depreciación Lineal'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'config_unidades',
                  child: Row(
                    children: [
                      Icon(Icons.speed, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Depreciación por Unidades'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'revalorizar',
                  child: Row(
                    children: [
                      Icon(Icons.trending_up, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Revalorizar NICSP 17'),
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

  Widget _buildFUTTab() {
    if (_futs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Fondo de Unidad de Tesorería (FUT)',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('FUT - Cuentas de Tesorería Pública'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _crearFUTDialog,
              icon: Icon(Icons.add),
              label: const Text('Crear FUT'),
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
      itemCount: _futs.length,
      itemBuilder: (context, index) {
        final fut = _futs[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.account_balance, color: Colors.white),
            ),
            title: Text(
              '${fut.nombreFUT} (#${fut.numeroFUT})',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Valor Inicial: ${publicMoneyForDisplay(fut.valorInicial)} | Ejecutado: ${publicMoneyForDisplay(fut.valorEjecutado)}',
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoAccion() {
    switch (_selectedIndex) {
      case 0:
        _registrarActivoDialog();
        break;
      case 1:
        _crearFUTDialog();
        break;
    }
  }

  void _registrarActivoDialog() {
    if (_activosService == null) return;
    final numInvCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    final marcaCtrl = TextEditingController();
    final modeloCtrl = TextEditingController();
    final serieCtrl = TextEditingController();
    final valorAdqCtrl = TextEditingController();
    final vidaUtilCtrl = TextEditingController();
    TipoActivo tipoSeleccionado = TipoActivo.maquinaria;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar Activo NICSP 17'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numInvCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de Inventario',
                    hintText: 'ej. INV-2026-001',
                  ),
                ),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Activo',
                    hintText: 'ej. Maquinaria de Obras Públicas',
                  ),
                ),
                DropdownButtonFormField<TipoActivo>(
                  initialValue: tipoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Clasificación del Activo NICSP 17',
                  ),
                  items: TipoActivo.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: marcaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Marca',
                    hintText: 'ej. Caterpillar',
                  ),
                ),
                TextField(
                  controller: modeloCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Modelo / Año',
                    hintText: 'ej. CAT-320',
                  ),
                ),
                TextField(
                  controller: serieCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de Serie',
                    hintText: 'ej. SN-99887766',
                  ),
                ),
                TextField(
                  controller: valorAdqCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor Adquisición',
                    hintText: 'ej. 120000000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: vidaUtilCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vida Útil (Años)',
                    hintText: 'ej. 10',
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
                if (numInvCtrl.text.isEmpty ||
                    nombreCtrl.text.isEmpty ||
                    valorAdqCtrl.text.isEmpty ||
                    vidaUtilCtrl.text.isEmpty ||
                    marcaCtrl.text.isEmpty ||
                    modeloCtrl.text.isEmpty ||
                    serieCtrl.text.isEmpty) {
                  return;
                }
                try {
                  final valorAdq = publicMoneyFromMajor(valorAdqCtrl.text);
                  await _activosService!.registrarActivo(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    numeroInventario: numInvCtrl.text,
                    nombreActivo: nombreCtrl.text,
                    tipoActivo: tipoSeleccionado,
                    marca: marcaCtrl.text,
                    modelo: modeloCtrl.text,
                    serie: serieCtrl.text,
                    valorAdquisicion: valorAdq,
                    valorResidual: valorAdq.multiplyDecimal('0.1'),
                    vidaUtilAnios: int.parse(vidaUtilCtrl.text),
                    fechaAdquisicion: DateTime.now(),
                    fechaPuestaEnMarcha: DateTime.now(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Activo registrado con éxito'),
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
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _depreciarLinealDialog(ActivoEstado activo) async {
    if (_activosService == null) return;
    try {
      final res = await _activosService!.actualizarDepreciacion(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        activoId: activo.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Depreciación lineal actualizada. Valor en libros: ${publicMoneyForDisplay(res.valorLibros)}',
            ),
          ),
        );
      }
      _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al depreciar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _configurarDepreciacionUnidadesDialog(ActivoEstado activo) {
    if (_depreciacionUnidadesService == null) return;
    final unidadesTotalesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Configurar Depreciación por Unidades - ${activo.nombreActivo}',
        ),
        content: TextField(
          controller: unidadesTotalesCtrl,
          decoration: const InputDecoration(
            labelText: 'Unidades Totales Estimadas (ej. km / horas)',
            hintText: 'ej. 100000',
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
              if (unidadesTotalesCtrl.text.isEmpty) return;
              try {
                await _depreciacionUnidadesService!
                    .configurarDepreciacionUnidades(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      activoId: activo.id,
                      unidadesTotalesEstimadas: double.parse(
                        unidadesTotalesCtrl.text,
                      ),
                      valorAdquisicion: activo.valorAdquisicion,
                      valorResidual: activo.valorResidual,
                      fechaInicio: DateTime.now(),
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Configuración por unidades registrada'),
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
            child: const Text('Guardar Configuración'),
          ),
        ],
      ),
    );
  }

  void _revalorizarActivoDialog(ActivoEstado activo) {
    if (_revalorizacionService == null) return;
    final valorNuevoCtrl = TextEditingController();
    final peritoCtrl = TextEditingController();
    final dictamenCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    MetodoRevalorizacion metodoSeleccionado =
        MetodoRevalorizacion.valorRazonable;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Revalorizar Activo NICSP 17 - ${activo.nombreActivo}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<MetodoRevalorizacion>(
                  initialValue: metodoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Método de Revalorización',
                  ),
                  items: MetodoRevalorizacion.values.map((m) {
                    return DropdownMenuItem(value: m, child: Text(m.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => metodoSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: valorNuevoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nuevo Valor Razonable (min +10%)',
                    hintText: 'ej. 150000000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: peritoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Perito Avaluador',
                    hintText: 'ej. Ing. Carlos Pérez (Reg. ANAV)',
                  ),
                ),
                TextField(
                  controller: dictamenCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número Dictamen / Avalúo',
                    hintText: 'ej. DICT-2026-001',
                  ),
                ),
                TextField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Motivo / Justificación Técnica',
                    hintText: 'ej. Avalúo quinquenal NICSP 17',
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
                if (valorNuevoCtrl.text.isEmpty ||
                    peritoCtrl.text.isEmpty ||
                    dictamenCtrl.text.isEmpty ||
                    motivoCtrl.text.isEmpty) {
                  return;
                }
                try {
                  final valorNuevo = publicMoneyFromMajor(valorNuevoCtrl.text);
                  await _revalorizacionService!.registrarRevalorizacion(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    activoId: activo.id,
                    metodo: metodoSeleccionado,
                    valorAnterior: activo.valorLibros,
                    valorNuevo: valorNuevo,
                    fechaRevalorizacion: DateTime.now(),
                    peritoAvaluo: peritoCtrl.text,
                    numeroDictamen: dictamenCtrl.text,
                    motivo: motivoCtrl.text,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Revalorización aprobada y aplicada al activo',
                        ),
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
              child: const Text('Aprobar Revalorización'),
            ),
          ],
        ),
      ),
    );
  }

  void _crearFUTDialog() {
    if (_futService == null) return;
    final nombreCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final terceroIdCtrl = TextEditingController();
    final terceroNombreCtrl = TextEditingController();
    final terceroIdentificacionCtrl = TextEditingController();
    TipoFondoUnidadTesoreria tipoSeleccionado =
        TipoFondoUnidadTesoreria.convenio;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crear Registro FUT (Tesorería)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre FUT',
                    hintText: 'ej. Fondo Educación Municipal',
                  ),
                ),
                DropdownButtonFormField<TipoFondoUnidadTesoreria>(
                  initialValue: tipoSeleccionado,
                  decoration: const InputDecoration(labelText: 'Tipo de FUT'),
                  items: TipoFondoUnidadTesoreria.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: valorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor Inicial',
                    hintText: 'ej. 50000000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: terceroIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID Tercero',
                    hintText: 'ej. TER-001',
                  ),
                ),
                TextField(
                  controller: terceroNombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Tercero / Entidad',
                    hintText: 'ej. Ministerio de Educación',
                  ),
                ),
                TextField(
                  controller: terceroIdentificacionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'NIT / Cédula Tercero',
                    hintText: 'ej. 899999111',
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
                    valorCtrl.text.isEmpty ||
                    terceroNombreCtrl.text.isEmpty ||
                    terceroIdentificacionCtrl.text.isEmpty ||
                    terceroIdCtrl.text.isEmpty) {
                  return;
                }
                try {
                  await _futService!.crearFUT(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    nombreFUT: nombreCtrl.text,
                    tipoFUT: tipoSeleccionado,
                    terceroId: terceroIdCtrl.text,
                    terceroNombre: terceroNombreCtrl.text,
                    terceroIdentificacion: terceroIdentificacionCtrl.text,
                    valorInicial: publicMoneyFromMajor(valorCtrl.text),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Registro FUT creado con éxito'),
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
              child: const Text('Crear FUT'),
            ),
          ],
        ),
      ),
    );
  }

  void _asignarActaDialog(ActivoEstado activo) async {
    if (_actaService == null) return;

    List<Map<String, dynamic>> empleados = [];
    try {
      final db = await DatabaseHelper.instance.database;
      empleados = await db.query(
        'empleados_sp',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
      );
    } catch (e) {
      debugPrint('Error cargando empleados: $e');
    }

    String? funcionarioIdSel;
    final nombreCtrl = TextEditingController(text: activo.responsable ?? '');
    final cedulaCtrl = TextEditingController();
    final depCtrl = TextEditingController();
    final ubicaCtrl = TextEditingController(text: activo.ubicacion ?? '');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Asignar Acta de Custodia - ${activo.nombreActivo}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (empleados.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar Cuentadante / Funcionario',
                    ),
                    items: empleados.map((emp) {
                      final id = emp['id'] as String;
                      final nombre = emp['nombre_completo'] as String;
                      final cc = emp['numero_identificacion'] as String;
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          '$nombre ($cc)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final sel = empleados.firstWhere((e) => e['id'] == val);
                        setDialogState(() {
                          funcionarioIdSel = val;
                          nombreCtrl.text = sel['nombre_completo'] as String;
                          cedulaCtrl.text =
                              sel['numero_identificacion'] as String;
                          depCtrl.text = sel['dependencia'] as String;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo Cuentadante',
                    hintText: 'ej. Carlos Restrepo',
                  ),
                ),
                TextField(
                  controller: cedulaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cédula / Identificación',
                    hintText: 'ej. 79998877',
                  ),
                ),
                TextField(
                  controller: depCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dependencia / Secretaría',
                    hintText: 'ej. Secretaría de Obras Públicas',
                  ),
                ),
                TextField(
                  controller: ubicaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ubicación Física del Activo',
                    hintText: 'ej. Almacén Central - Bodega 2',
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
                    cedulaCtrl.text.isEmpty ||
                    depCtrl.text.isEmpty ||
                    ubicaCtrl.text.isEmpty) {
                  return;
                }
                try {
                  final acta = await _actaService!.asignarResponsabilidad(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    activoId: activo.id,
                    funcionarioId:
                        funcionarioIdSel ??
                        'FUNC-TEMP-${DateTime.now().millisecondsSinceEpoch}',
                    funcionarioNombre: nombreCtrl.text,
                    funcionarioIdentificacion: cedulaCtrl.text,
                    dependencia: depCtrl.text,
                    ubicacionFisica: ubicaCtrl.text,
                  );
                  final plano = await _actaService!.exportarActaAPlano(acta.id);
                  if (context.mounted) {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Acta de Responsabilidad Generada'),
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
              child: const Text('Generar y Firmar Acta'),
            ),
          ],
        ),
      ),
    );
  }
}
