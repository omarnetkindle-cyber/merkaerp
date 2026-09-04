import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../../contabilidad/services/consolidacion_jerarquica_service.dart';
import '../../contabilidad/services/conciliacion_reciprocas_service.dart';
import '../../contabilidad/pages/conciliacion_reciproca_dialog.dart';
import '../../security/roles_permisos_service.dart';
import '../services/transparencia_service.dart';
import '../services/disciplinario_service.dart';
import '../services/nicsp40_service.dart';
import '../models/reporte_transparencia.dart';
import '../models/proceso_disciplinario.dart';
import '../models/consolidacion_nicsp40.dart';
import '../../nomina/models/empleado.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatter.dart';

class TransparenciaPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;

  const TransparenciaPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<TransparenciaPage> createState() => _TransparenciaPageState();
}

class _TransparenciaPageState extends State<TransparenciaPage> {
  int _selectedIndex = 0;
  bool _loading = true;
  late TransparenciaService _transparenciaService;
  late DisciplinarioService _disciplinarioService;
  late ConsolidacionJerarquicaService _consolidacionJerarquicaService;
  late ConciliacionReciprocasService _conciliacionReciprocasService;
  bool _puedeAprobarReciprocas = false;
  Map<String, dynamic>? _consolidadoJerarquicoReporte;
  late NICSP40Service _nicsp40Service;

  List<ReporteTransparencia> _reportes = [];
  List<ProcesoDisciplinario> _procesos = [];
  List<ConsolidacionNICSP40> _consolidaciones = [];
  List<Map<String, dynamic>> _conciliacionesReciprocas = [];
  List<Empleado> _empleados = [];
  Map<String, dynamic>? _nicsp40Reporte;

  final List<String> _titulos = [
    'Transparencia (Ley 1712 de 2014)',
    'Control Disciplinario',
    'Consolidación NICSP 40',
  ];

  @override
  void initState() {
    super.initState();
    _inicializarServicios();
  }

  Future<void> _inicializarServicios() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoriaService = AuditoriaService(db);

      _transparenciaService = TransparenciaService(
        db: db,
        auditoriaService: auditoriaService,
      );
      _disciplinarioService = DisciplinarioService(
        db: db,
        auditoriaService: auditoriaService,
      );
      _nicsp40Service = NICSP40Service(
        db: db,
        auditoriaService: auditoriaService,
      );
      _consolidacionJerarquicaService = ConsolidacionJerarquicaService(db: db);
      _conciliacionReciprocasService = ConciliacionReciprocasService(db: db);
      final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
        db: db,
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
      );
      _puedeAprobarReciprocas =
          rol != null &&
          RolesPermisosService.tienePermiso(
            rol,
            Permiso.aprobarConciliacionReciproca,
          );

      await _cargarDatos();
    } catch (e) {
      _mostrarError('Error al inicializar servicios: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarDatos() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // 1. Cargar Reportes de Transparencia
      _reportes = await _transparenciaService.consultarReportes(
        entidadId: widget.entidadId,
      );

      // 2. Cargar Procesos Disciplinarios
      _procesos = await _disciplinarioService.consultarProcesos(
        entidadId: widget.entidadId,
      );

      // 3. Cargar Consolidaciones NICSP 40
      _consolidaciones = await _nicsp40Service.consultarConsolidaciones(
        entidadId: widget.entidadId,
      );

      _conciliacionesReciprocas = await _conciliacionReciprocasService
          .listarConciliaciones(
            entidadConsolidadoraId: widget.entidadId,
            vigencia: DateTime.now().year.toString(),
          );

      // 4. Cargar Empleados (para autocompletado opcional en control disciplinario)
      final empleadosResult = await db.query(
        'empleados_sp',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'nombre_completo',
      );
      _empleados = empleadosResult.map((r) => Empleado.fromJson(r)).toList();
    } catch (e) {
      _mostrarError('Error al cargar datos: $e');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_selectedIndex]),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: [
                _buildTransparenciaTab(),
                _buildDisciplinarioTab(),
                _buildNICSP40Tab(),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.visibility),
            label: 'Transparencia',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.gavel),
            label: 'Disciplinario',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description),
            label: 'NICSP 40',
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _crearReporte,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add),
            )
          : _selectedIndex == 1
          ? FloatingActionButton(
              onPressed: _iniciarProceso,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add),
            )
          : _selectedIndex == 2
          ? FloatingActionButton(
              onPressed: _registrarTransferencia,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildTransparenciaTab() {
    if (_reportes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay reportes de transparencia',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _crearReporte,
              icon: Icon(Icons.add),
              label: const Text('Crear Reporte'),
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
      padding: const EdgeInsets.all(16),
      itemCount: _reportes.length,
      itemBuilder: (context, index) {
        final rep = _reportes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(rep.titulo),
            subtitle: Text(
              '${rep.numeroReporte} | Tipo: ${rep.tipoReporte.toString().split('.').last}',
            ),
            trailing: Chip(
              label: Text(rep.estado.toString().split('.').last.toUpperCase()),
              backgroundColor: rep.estado == EstadoReporte.publicado
                  ? Colors.green
                  : Colors.grey,
              labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Descripción: ${rep.descripcion}'),
                    Text(
                      'Periodo: ${DateFormatter.format(rep.periodoInicio)} a ${DateFormatter.format(rep.periodoFin)}',
                    ),
                    if (rep.urlPublicacion != null)
                      Text(
                        'URL Publicación: ${rep.urlPublicacion}',
                        style: TextStyle(color: MerkaThemeTokens.info),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (rep.estado == EstadoReporte.borrador) ...[
                          TextButton.icon(
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('Transmitir'),
                            onPressed: () => _transmitirReporte(rep),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.link),
                            label: const Text('Registrar URL externa'),
                            onPressed: () => _registrarPublicacionExterna(rep),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisciplinarioTab() {
    if (_procesos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay procesos disciplinarios iniciados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _iniciarProceso,
              icon: Icon(Icons.add),
              label: const Text('Iniciar Proceso'),
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
      padding: const EdgeInsets.all(16),
      itemCount: _procesos.length,
      itemBuilder: (context, index) {
        final proc = _procesos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text('${proc.servidorPublico} (${proc.numeroProceso})'),
            subtitle: Text('Cargo: ${proc.cargo} | Dep: ${proc.dependencia}'),
            trailing: Chip(
              label: Text(proc.estado.toString().split('.').last.toUpperCase()),
              backgroundColor: _getEstadoDisciplinarioColor(proc.estado),
              labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Descripción de la Falta: ${proc.descripcion}'),
                    Text('Inicio: ${DateFormatter.format(proc.fechaInicio)}'),
                    if (proc.fechaDecision != null)
                      Text(
                        'Decisión: ${DateFormatter.format(proc.fechaDecision!)}',
                      ),
                    if (proc.sancion != null)
                      Text(
                        'Sanción / Medida: ${proc.sancion}',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    if (proc.montoSancion != null &&
                        proc.montoSancion! > publicMoneyZero())
                      Text(
                        'Monto Sanción: ${publicMoneyForDisplay(proc.montoSancion!)}',
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (proc.estado !=
                                EstadoProcesoDisciplinario.archivado &&
                            proc.estado !=
                                EstadoProcesoDisciplinario.absuelto &&
                            proc.estado !=
                                EstadoProcesoDisciplinario.sancionado)
                          TextButton.icon(
                            icon: Icon(Icons.assignment_turned_in),
                            label: const Text('Registrar Decisión/Fallo'),
                            onPressed: () =>
                                _registrarDecisionDisciplinaria(proc),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNICSP40Tab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transferencias Consolidadas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _generarConsolidadoJerarquico,
                    icon: Icon(Icons.account_balance),
                    label: const Text('Consolidado Jerárquico'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _generarReporteNICSP40,
                    icon: Icon(Icons.assessment),
                    label: const Text('Reporte NICSP 40'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  if (_puedeAprobarReciprocas)
                    OutlinedButton.icon(
                      onPressed: _registrarConciliacionReciproca,
                      icon: const Icon(Icons.rule),
                      label: const Text('Conciliar recíproca'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_consolidadoJerarquicoReporte != null) ...[
            Card(
              color: AppTheme.getSuccessColor(context).withOpacity(0.12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consolidado de Saldos Contables (Gobernación + Entidades Adscritas)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.getSuccessColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Entidades Consolidadas: ${_consolidadoJerarquicoReporte!['total_entidades_consolidadas']}',
                    ),
                    Text(
                      'Vigencia: ${_consolidadoJerarquicoReporte!['vigencia']}',
                    ),
                    const Divider(),
                    Text(
                      'Activos: ${CurrencyFormatter.format((_consolidadoJerarquicoReporte!['resumen']['activos'] as double))}',
                    ),
                    Text(
                      'Pasivos: ${CurrencyFormatter.format((_consolidadoJerarquicoReporte!['resumen']['pasivos'] as double))}',
                    ),
                    Text(
                      'Patrimonio: ${CurrencyFormatter.format((_consolidadoJerarquicoReporte!['resumen']['patrimonio'] as double))}',
                    ),
                    Text(
                      'Ingresos: ${CurrencyFormatter.format((_consolidadoJerarquicoReporte!['resumen']['ingresos'] as double))}',
                    ),
                    Text(
                      'Gastos: ${CurrencyFormatter.format((_consolidadoJerarquicoReporte!['resumen']['gastos'] as double))}',
                    ),
                    Text(
                      'Superávit/Déficit: ${CurrencyFormatter.format((_consolidadoJerarquicoReporte!['resumen']['superavit_deficit'] as double))}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Conciliaciones aplicadas: ${_consolidadoJerarquicoReporte!['eliminaciones_reciprocas']['conciliaciones_aplicadas']}',
                    ),
                    const Text(
                      '* Solo se eliminan partidas recíprocas aprobadas; los asientos originales no cambian.',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_conciliacionesReciprocas.isNotEmpty) ...[
            Text(
              'Conciliaciones recíprocas aprobadas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._conciliacionesReciprocas.map(
              (conciliacion) => ListTile(
                leading: const Icon(Icons.verified),
                title: Text(
                  publicMoneyForDisplay(
                    publicMoneyFromSql(conciliacion['monto_conciliado']),
                  ).toStringAsFixed(2),
                ),
                subtitle: Text(
                  '${conciliacion['total_partidas']} partidas | Aprobó ${conciliacion['aprobado_por']} | '
                  'Tolerancias: ${conciliacion['tolerancia_dias']} días / '
                  '${publicMoneyForDisplay(publicMoneyFromSql(conciliacion['tolerancia_monto']))}',
                ),
              ),
            ),
            const Divider(),
          ],
          if (_nicsp40Reporte != null) ...[
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen Consolidado (Revelaciones)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total Transferido: ${CurrencyFormatter.format((_nicsp40Reporte!['total_transferido'] as double))}',
                    ),
                    Text(
                      'Total Ejecutado: ${CurrencyFormatter.format((_nicsp40Reporte!['total_ejecutado'] as double))}',
                    ),
                    Text(
                      'Total No Ejecutado: ${CurrencyFormatter.format((_nicsp40Reporte!['total_no_ejecutado'] as double))}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_consolidaciones.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No hay transferencias registradas bajo NICSP 40'),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _consolidaciones.length,
              itemBuilder: (context, index) {
                final con = _consolidaciones[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    title: Text('${con.entidadOrigen} ➔ ${con.entidadDestino}'),
                    subtitle: Text(
                      '${con.numeroConsolidacion} | Vigencia: ${con.vigencia}',
                    ),
                    trailing: Text(
                      '${publicMoneyForDisplay(con.valorTransferido)}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tipo: ${con.tipoTransferencia.toString().split('.').last}',
                            ),
                            Text('Descripción: ${con.descripcion}'),
                            Text(
                              'Fecha Transferencia: ${DateFormatter.format(con.fechaTransferencia)}',
                            ),
                            if (con.proyecto != null)
                              Text('Proyecto Asociado: ${con.proyecto}'),
                            const Divider(),
                            Text(
                              'Valor Ejecutado: ${publicMoneyForDisplay(con.valorEjecutado)}',
                            ),
                            Text(
                              'Valor No Ejecutado: ${publicMoneyForDisplay(con.valorNoEjecutado)}',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  icon: Icon(Icons.edit),
                                  label: const Text('Actualizar Ejecución'),
                                  onPressed: () =>
                                      _actualizarEjecucionNICSP40(con),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Color _getEstadoDisciplinarioColor(EstadoProcesoDisciplinario estado) {
    switch (estado) {
      case EstadoProcesoDisciplinario.iniciado:
        return Colors.grey;
      case EstadoProcesoDisciplinario.enInvestigacion:
        return MerkaThemeTokens.info;
      case EstadoProcesoDisciplinario.enDecision:
        return Colors.orange;
      case EstadoProcesoDisciplinario.sancionado:
        return Colors.red;
      case EstadoProcesoDisciplinario.absuelto:
        return Colors.green;
      case EstadoProcesoDisciplinario.archivado:
        return MerkaThemeTokens.navy600;
    }
  }

  void _crearReporte() {
    final formKey = GlobalKey<FormState>();
    final tituloController = TextEditingController();
    final descripcionController = TextEditingController();
    TipoReporteTransparencia tipoSeleccionado =
        TipoReporteTransparencia.contratacion;

    DateTime fechaInicio = DateTime.now().subtract(const Duration(days: 30));
    DateTime fechaFin = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crear Reporte Ley 1712'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<TipoReporteTransparencia>(
                    initialValue: tipoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Reporte',
                    ),
                    items: TipoReporteTransparencia.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(t.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tipoSeleccionado = val);
                      }
                    },
                  ),
                  TextFormField(
                    controller: tituloController,
                    decoration: const InputDecoration(
                      labelText: 'Título del Reporte',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: descripcionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Resumen',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Inicio: ${fechaInicio.toString().split(' ')[0]}'),
                      TextButton(
                        onPressed: () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: fechaInicio,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (selected != null) {
                            setDialogState(() => fechaInicio = selected);
                          }
                        },
                        child: const Text('Fecha Inicio'),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Fin: ${fechaFin.toString().split(' ')[0]}'),
                      TextButton(
                        onPressed: () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: fechaFin,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (selected != null) {
                            setDialogState(() => fechaFin = selected);
                          }
                        },
                        child: const Text('Fecha Fin'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  setState(() => _loading = true);
                  try {
                    await _transparenciaService.crearReporteTransparencia(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      tipoReporte: tipoSeleccionado,
                      titulo: tituloController.text,
                      descripcion: descripcionController.text,
                      periodoInicio: fechaInicio,
                      periodoFin: fechaFin,
                    );
                    _mostrarExito('Reporte de transparencia creado');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al crear reporte: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _transmitirReporte(ReporteTransparencia rep) async {
    setState(() => _loading = true);
    try {
      await _transparenciaService.transmitirReporte(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        reporteId: rep.id,
      );
      _mostrarExito('Transmisión aceptada por el portal configurado');
      await _cargarDatos();
    } catch (e) {
      _mostrarError('No fue posible transmitir: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _registrarPublicacionExterna(ReporteTransparencia rep) {
    final formKey = GlobalKey<FormState>();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar publicación externa'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: urlController,
            decoration: const InputDecoration(
              labelText: 'URL HTTPS donde ya fue publicado',
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Requerido' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                setState(() => _loading = true);
                try {
                  await _transparenciaService.registrarPublicacionExterna(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    reporteId: rep.id,
                    urlPublicacion: urlController.text,
                  );
                  _mostrarExito('Evidencia de publicación registrada');
                  await _cargarDatos();
                } catch (e) {
                  _mostrarError('Error al publicar: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  void _iniciarProceso() {
    final formKey = GlobalKey<FormState>();
    final servidorController = TextEditingController();
    final identificacionController = TextEditingController();
    final cargoController = TextEditingController();
    final dependenciaController = TextEditingController();
    final descripcionController = TextEditingController();
    TipoProceso tipoSeleccionado = TipoProceso.investigacion;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Iniciar Proceso Disciplinario'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<TipoProceso>(
                    initialValue: tipoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Proceso',
                    ),
                    items: TipoProceso.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(t.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tipoSeleccionado = val);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Empleado?>(
                    initialValue: null,
                    decoration: const InputDecoration(
                      labelText: 'Autocompletar con Empleado (Opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<Empleado?>(
                        value: null,
                        child: Text('Ninguno (Ingreso Manual)'),
                      ),
                      ..._empleados.map(
                        (e) => DropdownMenuItem<Empleado?>(
                          value: e,
                          child: Text(e.nombreCompleto),
                        ),
                      ),
                    ],
                    onChanged: (emp) {
                      if (emp != null) {
                        setDialogState(() {
                          servidorController.text = emp.nombreCompleto;
                          identificacionController.text =
                              emp.numeroIdentificacion;
                          cargoController.text = emp.cargo;
                          dependenciaController.text = emp.dependencia;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: servidorController,
                    decoration: const InputDecoration(
                      labelText: 'Servidor Público Implicado',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: identificacionController,
                    decoration: const InputDecoration(
                      labelText: 'Identificación (NIT/CC)',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: cargoController,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: dependenciaController,
                    decoration: const InputDecoration(labelText: 'Dependencia'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: descripcionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción de los Hechos',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  setState(() => _loading = true);
                  try {
                    await _disciplinarioService.iniciarProceso(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      tipoProceso: tipoSeleccionado,
                      servidorPublico: servidorController.text,
                      identificacion: identificacionController.text,
                      cargo: cargoController.text,
                      dependencia: dependenciaController.text,
                      descripcion: descripcionController.text,
                    );
                    _mostrarExito('Proceso disciplinario iniciado');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al iniciar proceso: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Iniciar'),
            ),
          ],
        ),
      ),
    );
  }

  void _registrarDecisionDisciplinaria(ProcesoDisciplinario proc) {
    final formKey = GlobalKey<FormState>();
    final actoController = TextEditingController();
    final sancionController = TextEditingController();
    final montoController = TextEditingController(text: '0.0');
    EstadoProcesoDisciplinario estadoSeleccionado =
        EstadoProcesoDisciplinario.sancionado;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar Fallo / Decisión'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Proceso: ${proc.numeroProceso}'),
                  Text('Servidor: ${proc.servidorPublico}'),
                  const Divider(),
                  DropdownButtonFormField<EstadoProcesoDisciplinario>(
                    initialValue: estadoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Fallo/Estado',
                    ),
                    items:
                        [
                          EstadoProcesoDisciplinario.sancionado,
                          EstadoProcesoDisciplinario.absuelto,
                          EstadoProcesoDisciplinario.archivado,
                        ].map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text(t.toString().split('.').last),
                          );
                        }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => estadoSeleccionado = val);
                      }
                    },
                  ),
                  TextFormField(
                    controller: actoController,
                    decoration: const InputDecoration(
                      labelText: 'Acto Administrativo / Resolución #',
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Requerido (Exigencia Auditoría)'
                        : null,
                  ),
                  TextFormField(
                    controller: sancionController,
                    decoration: const InputDecoration(
                      labelText: 'Sanción / Medida Aplicada',
                    ),
                  ),
                  TextFormField(
                    controller: montoController,
                    decoration: const InputDecoration(
                      labelText: 'Monto de Multa (\$)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  setState(() => _loading = true);
                  try {
                    await _disciplinarioService.registrarDecision(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      procesoId: proc.id,
                      estadoDecision: estadoSeleccionado,
                      sancion:
                          'Acto Administrativo: ${actoController.text}. Sanción: ${sancionController.text}',
                      montoSancion: publicMoneyFromMajor(montoController.text),
                    );
                    _mostrarExito('Fallo registrado correctamente');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al registrar decisión: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _registrarTransferencia() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final origenController = TextEditingController();
    final destinoController = TextEditingController();
    final descripcionController = TextEditingController();
    final valorController = TextEditingController();
    final proyectoController = TextEditingController();
    TipoTransferencia tipoSeleccionado = TipoTransferencia.transferencia;

    DateTime fechaTransferencia = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar Transferencia NICSP 40'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: vigenciaController,
                    decoration: const InputDecoration(
                      labelText: 'Vigencia Fiscal',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: origenController,
                    decoration: const InputDecoration(
                      labelText: 'Entidad de Origen (Aportante)',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: destinoController,
                    decoration: const InputDecoration(
                      labelText: 'Entidad Destino (Receptora)',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  DropdownButtonFormField<TipoTransferencia>(
                    initialValue: tipoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Transferencia',
                    ),
                    items: TipoTransferencia.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(t.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tipoSeleccionado = val);
                      }
                    },
                  ),
                  TextFormField(
                    controller: descripcionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Concepto',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: valorController,
                    decoration: const InputDecoration(
                      labelText: 'Valor Transferido (\$)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: proyectoController,
                    decoration: const InputDecoration(
                      labelText: 'Proyecto Asociado (Opcional)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Fecha: ${fechaTransferencia.toString().split(' ')[0]}',
                      ),
                      TextButton(
                        onPressed: () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: fechaTransferencia,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (selected != null) {
                            setDialogState(() => fechaTransferencia = selected);
                          }
                        },
                        child: const Text('Fecha Transferencia'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  setState(() => _loading = true);
                  try {
                    await _nicsp40Service.registrarTransferencia(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      vigencia: vigenciaController.text,
                      entidadOrigen: origenController.text,
                      entidadDestino: destinoController.text,
                      tipoTransferencia: tipoSeleccionado,
                      descripcion: descripcionController.text,
                      valorTransferido: publicMoneyFromMajor(
                        valorController.text,
                      ),
                      fechaTransferencia: fechaTransferencia,
                      proyecto: proyectoController.text.isEmpty
                          ? null
                          : proyectoController.text,
                    );
                    _mostrarExito('Transferencia registrada exitosamente');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al registrar: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _actualizarEjecucionNICSP40(ConsolidacionNICSP40 con) {
    final formKey = GlobalKey<FormState>();
    final valorEjecutadoController = TextEditingController(
      text: con.valorEjecutado.toString(),
    );
    final observacionesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizar Ejecución'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Consolidación: ${con.numeroConsolidacion}'),
              Text(
                'Valor Transferido: ${publicMoneyForDisplay(con.valorTransferido)}',
              ),
              const Divider(),
              TextFormField(
                controller: valorEjecutadoController,
                decoration: const InputDecoration(
                  labelText: 'Valor Ejecutado (\$)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: observacionesController,
                decoration: const InputDecoration(labelText: 'Observaciones'),
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
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                setState(() => _loading = true);
                try {
                  await _nicsp40Service.actualizarEjecucion(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    consolidacionId: con.id,
                    valorEjecutado: publicMoneyFromMajor(
                      valorEjecutadoController.text,
                    ),
                  );
                  _mostrarExito('Ejecución actualizada correctamente');
                  await _cargarDatos();
                } catch (e) {
                  _mostrarError('Error al actualizar ejecución: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  void _generarReporteNICSP40() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generar Reporte NICSP 40'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: vigenciaController,
            decoration: const InputDecoration(
              labelText: 'Vigencia Fiscal (Año)',
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Requerido' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                setState(() => _loading = true);
                try {
                  final res = await _nicsp40Service.generarReporteNICSP40(
                    entidadId: widget.entidadId,
                    vigencia: vigenciaController.text,
                  );
                  setState(() {
                    _nicsp40Reporte = res;
                  });
                  _mostrarExito('Reporte de revelación NICSP 40 consolidado');
                } catch (e) {
                  _mostrarError('Error al generar consolidado: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
  }

  void _generarConsolidadoJerarquico() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Consolidado de Saldos Contables (Gobernación + Entidades Adscritas)',
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: vigenciaController,
            decoration: const InputDecoration(
              labelText: 'Vigencia Fiscal (Año)',
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Requerido' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                setState(() => _loading = true);
                try {
                  final res = await _consolidacionJerarquicaService
                      .obtenerConsolidadoContable(
                        entidadIdPadre: widget.entidadId,
                        vigencia: vigenciaController.text,
                      );
                  setState(() {
                    _consolidadoJerarquicoReporte = res;
                  });
                  _mostrarExito(
                    'Consolidado jerárquico de saldos generado correctamente',
                  );
                } catch (e) {
                  _mostrarError('Error al generar consolidado jerárquico: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Consolidar'),
          ),
        ],
      ),
    );
  }

  Future<void> _registrarConciliacionReciproca() async {
    final registrada = await showDialog<bool>(
      context: context,
      builder: (context) => ConciliacionReciprocaDialog(
        service: _conciliacionReciprocasService,
        entidadConsolidadoraId: widget.entidadId,
        usuarioId: widget.usuarioId,
      ),
    );
    if (registrada != true || !mounted) return;
    await _cargarDatos();
    if (!mounted) return;
    setState(() {});
    _mostrarExito('Conciliación recíproca aprobada.');
  }
}
