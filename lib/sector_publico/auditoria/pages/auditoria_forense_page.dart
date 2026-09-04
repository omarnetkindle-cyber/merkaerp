import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/chip_reporter_service.dart';
import '../services/sia_observa_service.dart';
import '../services/fut_territorial_service.dart';
import '../../siif/pages/siif_page.dart';
import '../../models/registro_auditoria.dart';
import '../models/reporte_chip.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatter.dart';

class AuditoriaForensePage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final int initialTabIndex;

  const AuditoriaForensePage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
    this.initialTabIndex = 0,
  });

  @override
  State<AuditoriaForensePage> createState() => _AuditoriaForensePageState();
}

class _AuditoriaForensePageState extends State<AuditoriaForensePage> {
  int _selectedIndex = 0;
  bool _loading = true;
  late AuditoriaService _auditoriaService;
  late CHIPReporterService _chipReporterService;

  List<RegistroAuditoria> _registros = [];
  List<ReporteCHIP> _reportesChip = [];
  List<RegistroAuditoria> _anomalias = [];

  // Filtros de búsqueda
  String? _filtroModulo;
  TipoEventoAuditoria? _filtroEvento;
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  final List<String> _titulos = [
    'Registros de Auditoría',
    'Reportes CHIP CGN',
    'Verificación de Integridad',
    'Alertas de Anomalías',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _inicializarServicios();
  }

  Future<void> _inicializarServicios() async {
    if (mounted) setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      _auditoriaService = AuditoriaService(db);
      _chipReporterService = CHIPReporterService(
        db: db,
        auditoriaService: _auditoriaService,
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
      // 1. Consultar registros de auditoría con filtros actuales
      _registros = await _auditoriaService.consultarRegistros(
        entidadId: widget.entidadId,
        modulo: _filtroModulo,
        tipoEvento: _filtroEvento,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        limite: 100,
      );
      if (!mounted) return;

      // 2. Consultar reportes CHIP
      _reportesChip = await _chipReporterService.consultarReportes(
        entidadId: widget.entidadId,
      );
      if (!mounted) return;

      // 3. Detectar anomalías forenses automáticamente
      await _detectarAnomalias();
    } catch (e) {
      _mostrarError('Error al cargar datos de auditoría: $e');
    }
  }

  Future<void> _detectarAnomalias() async {
    try {
      // Cargamos los últimos 500 registros para escanear anomalías
      final todos = await _auditoriaService.consultarRegistros(
        entidadId: widget.entidadId,
        limite: 500,
      );

      final tempAnomalias = <RegistroAuditoria>[];
      for (final reg in todos) {
        // Regla 1: Intentos de eliminación son anomalías críticas
        if (reg.tipoEvento == TipoEventoAuditoria.intentoEliminacion) {
          tempAnomalias.add(reg);
          continue;
        }

        // Regla 2: Transacciones hechas en horario no laboral nocturno (10 PM - 5 AM)
        final hora = reg.fechaHora.hour;
        if (hora >= 22 || hora < 5) {
          tempAnomalias.add(reg);
          continue;
        }
      }

      if (!mounted) return;
      setState(() {
        _anomalias = tempAnomalias;
      });
    } catch (e) {
      debugPrint('Error detectando anomalías: $e');
    }
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
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
                _buildRegistrosTab(),
                _buildReportesCHIPTab(),
                _buildIntegridadTab(),
                _buildAlertasTab(),
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
            icon: Icon(Icons.history),
            label: 'Registros',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description),
            label: 'CHIP CGN',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.verified_user),
            label: 'Integridad',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Alertas'),
        ],
      ),
    );
  }

  Widget _buildRegistrosTab() {
    return Column(
      children: [
        _buildPanelFiltros(),
        Expanded(
          child: _registros.isEmpty
              ? const Center(
                  child: Text('No se encontraron registros de auditoría'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _registros.length,
                  itemBuilder: (context, index) {
                    final reg = _registros[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          _getIconoEvento(reg.tipoEvento),
                          color: _getColorEvento(reg.tipoEvento),
                        ),
                        title: Text(reg.accion),
                        subtitle: Text(
                          'Módulo: ${reg.modulo} | Usuario: ${reg.usuarioNombre ?? reg.usuarioId}\nFecha: ${reg.fechaHora.toLocal()}',
                        ),
                        trailing: Text(
                          '#${reg.hashActual.substring(0, 8)}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                        isThreeLine: true,
                        onTap: () => _mostrarDetalleRegistro(reg),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPanelFiltros() {
    return Container(
      color: Colors.grey[200],
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filtroModulo,
                  decoration: const InputDecoration(labelText: 'Módulo'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...[
                      'contabilidad',
                      'tesoreria',
                      'contratacion',
                      'nomina',
                      'transparencia',
                      'seguridad',
                      'configuracion',
                      'auditoria',
                    ].map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.toUpperCase()),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() => _filtroModulo = val);
                    _cargarDatos();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<TipoEventoAuditoria>(
                  initialValue: _filtroEvento,
                  decoration: const InputDecoration(labelText: 'Evento'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...TipoEventoAuditoria.values.map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.toString().split('.').last),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() => _filtroEvento = val);
                    _cargarDatos();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                icon: Icon(Icons.date_range),
                label: Text(
                  _fechaDesde == null
                      ? 'Desde: Inicial'
                      : 'Desde: ${_fechaDesde!.toString().split(' ')[0]}',
                ),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _fechaDesde ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) {
                    setState(() => _fechaDesde = d);
                    _cargarDatos();
                  }
                },
              ),
              TextButton.icon(
                icon: Icon(Icons.date_range),
                label: Text(
                  _fechaHasta == null
                      ? 'Hasta: Actual'
                      : 'Hasta: ${_fechaHasta!.toString().split(' ')[0]}',
                ),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _fechaHasta ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) {
                    setState(() => _fechaHasta = d);
                    _cargarDatos();
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.clear_all),
                tooltip: 'Limpiar Filtros',
                onPressed: () {
                  setState(() {
                    _filtroModulo = null;
                    _filtroEvento = null;
                    _fechaDesde = null;
                    _fechaHasta = null;
                  });
                  _cargarDatos();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportesCHIPTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reportes CGN Historial',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _dialogoGenerarCHIP,
                icon: Icon(Icons.add),
                label: const Text('Generar Paquete CHIP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _reportesChip.isEmpty
              ? const Center(child: Text('No hay reportes CHIP generados'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _reportesChip.length,
                  itemBuilder: (context, index) {
                    final rep = _reportesChip[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(rep.nombreFormulario),
                        subtitle: Text(
                          'Vigencia: ${rep.vigencia} | Fecha: ${DateFormatter.format(rep.fechaGeneracion)}',
                        ),
                        trailing: Chip(
                          label: Text(rep.estado.toUpperCase()),
                          backgroundColor: rep.estado == 'enviado'
                              ? Colors.green
                              : Colors.grey,
                          labelStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ID de Reporte: ${rep.id}'),
                                Text('Usuario Generador: ${rep.usuarioGenero}'),
                                const Divider(),
                                const Text(
                                  'Datos Reportados:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(rep.datos.toString()),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: Icon(Icons.text_snippet),
                                      label: const Text('Exportar Plano'),
                                      onPressed: () => _exportarPlanoCHIP(rep),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      icon: Icon(Icons.verified),
                                      label: const Text('Validar Estructura'),
                                      onPressed: () =>
                                          _validarEstructuraCHIP(rep),
                                    ),
                                    if (rep.estado != 'enviado') ...[
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        icon: Icon(Icons.send),
                                        label: const Text('Transmitir'),
                                        onPressed: () => _transmitirCHIP(rep),
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
                ),
        ),
      ],
    );
  }

  Widget _buildIntegridadTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 96,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          const Text(
            'Verificación Criptográfica de la Cadena',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'El sistema audita de forma append-only. Cada transacción calcula un hash SHA-256 que encadena criptográficamente el hash del registro anterior. '
            'Si un registro se modifica por fuera del software o se elimina de la base de datos local, la verificación fallará.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _verificarIntegridadChain,
            icon: Icon(Icons.verified),
            label: const Text('Verificar Cadena Completa'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Integraciones regulatorias disponibles:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: MerkaThemeTokens.graphite600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              Icons.cloud_upload,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Módulo SIIF Nación II (MinHacienda)'),
            subtitle: const Text(
              'Consolidación y exportación de reportes presupuestales y financieros mensuales.',
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SIIFPage(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(
              Icons.assessment,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Rendición SIA Observa (CGR)'),
            subtitle: const Text(
              'Consolidado anual de Contratación, Presupuesto y Nómina para Plan de Mejoramiento.',
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _dialogoGenerarSIAObserva,
          ),
          ListTile(
            leading: Icon(
              Icons.assignment_turned_in,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Reportes FUT Territorial (DNP)'),
            subtitle: const Text(
              'Estructuración trimestral de Ingresos, Gastos, Deuda Pública y Regalías.',
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _dialogoGenerarFUTTerritorial,
          ),
        ],
      ),
    );
  }

  void _dialogoGenerarFUTTerritorial() {
    final vigenciaCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    int trimestreSeleccionado = 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Formulario FUT Territorial (DNP)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: vigenciaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Vigencia Fiscal',
                  hintText: 'ej. 2026',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: trimestreSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Trimestre a Reportar',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 1,
                    child: Text('Trimestre 1 (Ene-Mar)'),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text('Trimestre 2 (Abr-Jun)'),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text('Trimestre 3 (Jul-Sep)'),
                  ),
                  DropdownMenuItem(
                    value: 4,
                    child: Text('Trimestre 4 (Oct-Dic)'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => trimestreSeleccionado = val);
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
                  final db = await DatabaseHelper.instance.database;
                  final auditoria = AuditoriaService(db);
                  final service = FUTTerritorialService(
                    db: db,
                    auditoriaService: auditoria,
                  );

                  final rep = await service.generarFUTIngresos(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    vigencia: vigenciaCtrl.text,
                    trimestre: trimestreSeleccionado,
                  );

                  final plano = await service.exportarAPlano(rep.id);

                  if (context.mounted) {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text(
                          'Formulario FUT DNP Generado (.txt / CSV)',
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
              child: const Text('Generar y Exportar'),
            ),
          ],
        ),
      ),
    );
  }

  void _dialogoGenerarSIAObserva() {
    final vigenciaCtrl = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final hallazgosCtrl = TextEditingController();
    final accionesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rendición SIA Observa (CGR)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: vigenciaCtrl,
              decoration: const InputDecoration(
                labelText: 'Vigencia Fiscal',
                hintText: 'ej. 2026',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: hallazgosCtrl,
              decoration: const InputDecoration(
                labelText: 'Total Hallazgos Atendidos',
                hintText: 'ej. 10',
              ),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: accionesCtrl,
              decoration: const InputDecoration(
                labelText: 'Total Acciones Implementadas',
                hintText: 'ej. 8',
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
              if (vigenciaCtrl.text.isEmpty ||
                  hallazgosCtrl.text.isEmpty ||
                  accionesCtrl.text.isEmpty) {
                return;
              }
              try {
                final db = await DatabaseHelper.instance.database;
                final auditoria = AuditoriaService(db);
                final service = SIAObservaService(
                  db: db,
                  auditoriaService: auditoria,
                );

                final rep = await service.generarReportePlanMejoramiento(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  vigencia: vigenciaCtrl.text,
                  hallazgosAtendidos: int.parse(hallazgosCtrl.text),
                  accionesImplementadas: int.parse(accionesCtrl.text),
                );

                final plano = await service.exportarAPlano(rep.id);

                if (context.mounted) {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Reporte SIA Observa Generado (.txt)'),
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

  Widget _buildAlertasTab() {
    if (_anomalias.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'No se detectaron anomalías en la base de datos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Cadena de eventos e ingresos limpia.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _anomalias.length,
      itemBuilder: (context, index) {
        final anom = _anomalias[index];
        final esHoraNoLaboral =
            anom.fechaHora.hour >= 22 || anom.fechaHora.hour < 5;
        return Card(
          color: AppTheme.getWarningColor(context).withOpacity(0.12),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(Icons.warning, color: Colors.orange),
            title: Text('Anomalía: ${anom.accion}'),
            subtitle: Text(
              '${esHoraNoLaboral ? "REGISTRO NOCTURNO INUSUAL" : "INTENTO DE ELIMINACIÓN BLOQUEADO"}\n'
              'Módulo: ${anom.modulo} | Usuario: ${anom.usuarioNombre ?? anom.usuarioId}\n'
              'Fecha: ${anom.fechaHora.toLocal()}',
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16),
            isThreeLine: true,
            onTap: () => _mostrarDetalleRegistro(anom),
          ),
        );
      },
    );
  }

  IconData _getIconoEvento(TipoEventoAuditoria tipo) {
    switch (tipo) {
      case TipoEventoAuditoria.login:
        return Icons.login;
      case TipoEventoAuditoria.logout:
        return Icons.logout;
      case TipoEventoAuditoria.cambioContrasena:
        return Icons.password;
      case TipoEventoAuditoria.cambioPermiso:
        return Icons.security;
      case TipoEventoAuditoria.expedicionCDP:
      case TipoEventoAuditoria.expedicionRP:
        return Icons.assignment_turned_in;
      case TipoEventoAuditoria.modificacionCDP:
      case TipoEventoAuditoria.modificacionRP:
        return Icons.edit_attributes;
      case TipoEventoAuditoria.registroObligacion:
        return Icons.account_balance_wallet;
      case TipoEventoAuditoria.pago:
      case TipoEventoAuditoria.pagoNomina:
        return Icons.payment;
      case TipoEventoAuditoria.asientoContable:
        return Icons.book;
      case TipoEventoAuditoria.reversaAsiento:
        return Icons.settings_backup_restore;
      case TipoEventoAuditoria.cierreVigencia:
        return Icons.lock;
      case TipoEventoAuditoria.liquidacionNomina:
      case TipoEventoAuditoria.reliquidacion:
        return Icons.calculate;
      case TipoEventoAuditoria.liquidacionTributo:
        return Icons.assessment;
      case TipoEventoAuditoria.recaudoTributo:
        return Icons.attach_money;
      case TipoEventoAuditoria.inicioCobroCoactivo:
        return Icons.gavel;
      case TipoEventoAuditoria.inicioProceso:
        return Icons.work_outline;
      case TipoEventoAuditoria.adjudicacion:
        return Icons.assignment;
      case TipoEventoAuditoria.firmaContrato:
        return Icons.border_color;
      case TipoEventoAuditoria.liquidacionContrato:
        return Icons.assignment_return;
      case TipoEventoAuditoria.creacionRegistro:
        return Icons.add_circle_outline;
      case TipoEventoAuditoria.modificacionRegistro:
        return Icons.edit_note;
      case TipoEventoAuditoria.intentoEliminacion:
        return Icons.delete_forever;
    }
  }

  Color _getColorEvento(TipoEventoAuditoria tipo) {
    switch (tipo) {
      case TipoEventoAuditoria.login:
      case TipoEventoAuditoria.logout:
        return MerkaThemeTokens.navy600;
      case TipoEventoAuditoria.cambioContrasena:
      case TipoEventoAuditoria.cambioPermiso:
        return Colors.amber;
      case TipoEventoAuditoria.expedicionCDP:
      case TipoEventoAuditoria.expedicionRP:
      case TipoEventoAuditoria.creacionRegistro:
        return Colors.green;
      case TipoEventoAuditoria.modificacionCDP:
      case TipoEventoAuditoria.modificacionRP:
      case TipoEventoAuditoria.modificacionRegistro:
        return MerkaThemeTokens.info;
      case TipoEventoAuditoria.registroObligacion:
      case TipoEventoAuditoria.pago:
      case TipoEventoAuditoria.pagoNomina:
        return MerkaThemeTokens.navy700;
      case TipoEventoAuditoria.asientoContable:
      case TipoEventoAuditoria.reversaAsiento:
      case TipoEventoAuditoria.cierreVigencia:
        return MerkaThemeTokens.gold500;
      case TipoEventoAuditoria.liquidacionNomina:
      case TipoEventoAuditoria.reliquidacion:
      case TipoEventoAuditoria.liquidacionTributo:
      case TipoEventoAuditoria.recaudoTributo:
        return MerkaThemeTokens.graphite600;
      case TipoEventoAuditoria.inicioCobroCoactivo:
        return MerkaThemeTokens.gold400;
      case TipoEventoAuditoria.inicioProceso:
      case TipoEventoAuditoria.adjudicacion:
      case TipoEventoAuditoria.firmaContrato:
      case TipoEventoAuditoria.liquidacionContrato:
        return MerkaThemeTokens.navy600;
      case TipoEventoAuditoria.intentoEliminacion:
        return Colors.red;
    }
  }

  void _mostrarDetalleRegistro(RegistroAuditoria reg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reg.accion),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ID: ${reg.id}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Divider(),
              Text('Módulo: ${reg.modulo}'),
              Text('Tipo Evento: ${reg.tipoEvento.toString().split('.').last}'),
              Text('Fecha/Hora: ${reg.fechaHora.toLocal()}'),
              Text('Usuario: ${reg.usuarioNombre ?? reg.usuarioId}'),
              Text('IP: ${reg.ipDireccion ?? "N/A"}'),
              const Divider(),
              const Text(
                'Valor Anterior:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(reg.valorAnterior.toString()),
              const SizedBox(height: 8),
              const Text(
                'Valor Nuevo:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(reg.valorNuevo.toString()),
              const Divider(),
              Text(
                'Hash Anterior: ${reg.hashAnterior ?? "N/A"}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              Text(
                'Hash Actual: ${reg.hashActual}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (reg.observaciones != null) ...[
                const Divider(),
                Text('Observaciones: ${reg.observaciones}'),
              ],
            ],
          ),
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

  void _dialogoGenerarCHIP() async {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generar reportes CHIP desde datos del sistema'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CGN 2015_001 usa entidad y funcionarios; CGN 2015_002 usa saldos contables; CGN 2015_003 usa el Estado de Situacion Financiera.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: vigenciaController,
                decoration: const InputDecoration(labelText: 'Vigencia fiscal'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value == null || int.tryParse(value) == null
                    ? 'Ingrese una vigencia valida'
                    : null,
              ),
              const SizedBox(height: 12),
              const Text(
                'CGN 2015_004, CGN 2015_005 y CGN 2016C01 no se emiten: faltan fuentes persistidas para sus campos obligatorios.',
                style: TextStyle(fontSize: 12),
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
              if (!formKey.currentState!.validate()) return;
              final navigator = Navigator.of(context);
              navigator.pop();
              setState(() => _loading = true);
              try {
                await _chipReporterService.generarReportesDesdeDatosSistema(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  vigencia: vigenciaController.text,
                );
                _mostrarExito(
                  'CHIP CGN 2015_001 a 003 generado desde datos del sistema',
                );
                await _cargarDatos();
              } catch (e) {
                _mostrarError('No fue posible generar CHIP: $e');
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
            child: const Text('Generar'),
          ),
        ],
      ),
    );
  }

  void _exportarPlanoCHIP(ReporteCHIP rep) async {
    setState(() => _loading = true);
    try {
      final plano = await _chipReporterService.exportarAPlano(rep.id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Archivo Plano CHIP - ${rep.tipoFormulario.toString().split('.').last.toUpperCase()}',
          ),
          content: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black87,
              child: Text(
                plano,
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _mostrarError('Error al exportar a plano: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _validarEstructuraCHIP(ReporteCHIP rep) async {
    setState(() => _loading = true);
    try {
      final plano = await _chipReporterService.exportarAPlano(rep.id);
      final res = await _chipReporterService.validarFormatoCHIP(
        formatoPlano: plano,
        tipoFormulario: rep.tipoFormulario,
      );
      final esValido = res['valido'] as bool;
      final errores = res['errores'] as List<dynamic>;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Verificación de Formato CHIP CGN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    esValido ? Icons.check_circle : Icons.error,
                    color: esValido ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    esValido
                        ? 'Estructura Correcta'
                        : 'Estructura con Inconsistencias',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Total Líneas Validadas: ${res['total_lineas']}'),
              if (errores.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Errores de Formato/Cuadraturas:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...errores.map(
                  (e) => Text('• $e', style: TextStyle(color: Colors.red)),
                ),
              ] else
                const Text(
                  '• Cumple con reglas de balance activo/pasivo+patrimonio.',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _mostrarError('Error al validar formato CHIP: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _transmitirCHIP(ReporteCHIP rep) async {
    setState(() => _loading = true);
    try {
      await _chipReporterService.transmitirReporte(
        reporteId: rep.id,
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
      );
      _mostrarExito('El canal CHIP configurado aceptó la transmisión.');
      await _cargarDatos();
    } catch (e) {
      _mostrarError('No fue posible transmitir CHIP: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _verificarIntegridadChain() async {
    setState(() => _loading = true);
    try {
      final esValida = await _auditoriaService.verificarIntegridadCadena(
        widget.entidadId,
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Verificación Criptográfica'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                esValida ? Icons.verified_user : Icons.gpp_bad,
                size: 64,
                color: esValida ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                esValida
                    ? 'INTEGRIDAD CONFIRMADA: La secuencia completa de hashes SHA-256 está intacta. No hay registros alterados ni eliminados.'
                    : 'ALERTA DE SEGURIDAD: La secuencia de hashes está rota. Se detectaron modificaciones directas o registros eliminados en la base de datos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } catch (e) {
      _mostrarError('Error verificando integridad: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
