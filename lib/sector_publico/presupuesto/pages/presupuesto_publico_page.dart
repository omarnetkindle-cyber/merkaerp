/// Página principal del módulo de Presupuesto Público
/// Implementa el flujo: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:merka_erp/db_helper.dart';
import '../../security/auditoria_service.dart';
import '../models/apropiacion.dart';
import '../models/cdp.dart';
import '../models/rp.dart';
import '../models/obligacion.dart';
import '../models/pago.dart';
import '../services/presupuesto_service.dart';
import '../../../core/commands/command_registry.dart';
import '../../../core/evidence/evidence_capsule_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../ui/widgets/expandable_record_card.dart';
import '../../../core/tracing/traceability_record_action.dart';

class PresupuestoPublicoPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final void Function(Future<void> ready)? onReady;

  const PresupuestoPublicoPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
    this.onReady,
  });

  @override
  State<PresupuestoPublicoPage> createState() => _PresupuestoPublicoPageState();
}

class _PresupuestoPublicoPageState extends State<PresupuestoPublicoPage> {
  int _selectedIndex = 0;
  // ignore: unused_field — títulos usados en versión anterior de TabBar, pendiente migración
  final List<String> _titulos = [
    'Apropiaciones',
    'CDPs',
    'RPs',
    'Obligaciones',
    'Pagos',
  ];

  // Datos cargados
  List<Apropiacion> _apropiaciones = [];
  List<CDP> _cdps = [];
  List<RP> _rps = [];
  List<Obligacion> _obligaciones = [];
  List<Pago> _pagos = [];
  bool _loading = true;

  late PresupuestoService _presupuestoService;
  late final String _commandOwner;

  @override
  void initState() {
    super.initState();
    _commandOwner = 'presupuesto.publico:${identityHashCode(this)}';
    final ready = _inicializarServicio();
    widget.onReady?.call(ready);
  }

  Future<void> _inicializarServicio() async {
    final db = await DatabaseHelper.instance.database;
    final auditoriaService = AuditoriaService(db);
    _presupuestoService = PresupuestoService(
      db: db,
      auditoriaService: auditoriaService,
    );
    await _cargarDatos();
    if (mounted) _activateCommandContext();
  }

  void _activateCommandContext() {
    CommandRegistry.instance.setContext(
      CommandContext(
        moduleId: 'presupuesto_publico',
        recordType: 'presupuesto_publico',
        recordId: widget.entidadId,
        label: 'Presupuesto publico',
        ownerId: _commandOwner,
        actions: {
          'create_appropriation': (commandContext, _) => _crearApropiacion(),
          'create_cdp': (commandContext, _) => _expedirCDP(),
          'create_rp': (commandContext, _) => _expedirRP(),
        },
      ),
    );
  }

  Future<void> _cargarDatos() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      final apropiacionesResult = await db.query(
        'apropiaciones',
        where: 'entidad_id = ? AND activo = 1',
        whereArgs: [widget.entidadId],
        orderBy: 'vigencia DESC, codigo_rubro',
      );
      _apropiaciones = apropiacionesResult
          .map((r) => Apropiacion.fromJson(r))
          .toList();

      final cdpsResult = await db.query(
        'cdps',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'fecha_expedicion DESC',
      );
      _cdps = cdpsResult.map((r) => CDP.fromJson(r)).toList();

      final rpsResult = await db.query(
        'rps',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'fecha_expedicion DESC',
      );
      _rps = rpsResult.map((r) => RP.fromJson(r)).toList();

      final obligacionesResult = await db.query(
        'obligaciones',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'fecha_reconocimiento DESC',
      );
      _obligaciones = obligacionesResult
          .map((r) => Obligacion.fromJson(r))
          .toList();

      final pagosResult = await db.query(
        'pagos',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'fecha_programacion DESC',
      );
      _pagos = pagosResult.map((r) => Pago.fromJson(r)).toList();
    } catch (e) {
      debugPrint('Error al cargar datos: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _exportarEvidencia(EvidenceRequest request) async {
    final path = await EvidenceCapsuleService().exportJson(request);
    if (!mounted || path == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Cápsula exportada en $path')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuesto Público'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildApropiacionesTab(),
          _buildCDPsTab(),
          _buildRPsTab(),
          _buildObligacionesTab(),
          _buildPagosTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Apropiaciones',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.description), label: 'CDPs'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'RPs'),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Obligaciones',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'Pagos'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarDialogoCreacion,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildApropiacionesTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_apropiaciones.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet,
              size: 64,
              color: MerkaThemeTokens.graphite600,
            ),
            const SizedBox(height: 16),
            Text(
              'Apropiaciones Presupuestales',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('No hay apropiaciones registradas'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _crearApropiacion(),
              icon: Icon(Icons.add),
              label: const Text('Crear Apropiación'),
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
      itemCount: _apropiaciones.length,
      itemBuilder: (context, index) {
        final apropiacion = _apropiaciones[index];
        return ExpandableRecordCard(
          actions: [
            traceabilityRecordAction(
              rootEntityType: 'apropiacion',
              rootRecordId: apropiacion.id,
              tenantId: widget.entidadId,
            ),
          ],
          evidenceRequest: EvidenceRequest(
            domain: 'presupuesto',
            recordType: 'apropiacion',
            recordId: apropiacion.id,
          ),
          onEvidenceRequested: _exportarEvidencia,
          criticalFields: [
            RecordCardField(
              label: 'Vigencia',
              value: apropiacion.vigencia,
              icon: Icons.calendar_today,
              emphasized: true,
            ),
            RecordCardField(
              label: 'Rubro',
              value: apropiacion.codigoRubro,
              icon: Icons.account_tree,
              emphasized: true,
            ),
            RecordCardField(
              label: 'Apropiado',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(apropiacion.valorApropiado),
              ),
              icon: Icons.account_balance_wallet,
              emphasized: true,
            ),
            RecordCardField(
              label: 'Saldo disponible',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(apropiacion.saldoDisponible),
              ),
              icon: Icons.savings,
              emphasized: true,
            ),
          ],
          secondaryFields: [
            RecordCardField(
              label: 'Nombre del rubro',
              value: apropiacion.nombreRubro,
            ),
            RecordCardField(
              label: 'Pagado',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(apropiacion.valorPagado),
              ),
            ),
            RecordCardField(
              label: 'CDP acumulado',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(apropiacion.valorCDP),
              ),
            ),
            RecordCardField(
              label: 'RP acumulado',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(apropiacion.valorRP),
              ),
            ),
            RecordCardField(
              label: 'Fuente',
              value: apropiacion.fuenteFinanciacion,
            ),
            RecordCardField(
              label: 'Sector / programa',
              value: '${apropiacion.sector} / ${apropiacion.programa}',
            ),
            RecordCardField(
              label: 'Acto administrativo',
              value: apropiacion.actoAdministrativo,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCDPsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_cdps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description,
              size: 64,
              color: MerkaThemeTokens.graphite600,
            ),
            const SizedBox(height: 16),
            Text(
              'Certificados de Disponibilidad Presupuestal',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('No hay CDPs expedidos'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _expedirCDP(),
              icon: Icon(Icons.add),
              label: const Text('Expedir CDP'),
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
      itemCount: _cdps.length,
      itemBuilder: (context, index) {
        final cdp = _cdps[index];
        return ExpandableRecordCard(
          actions: [
            traceabilityRecordAction(
              rootEntityType: 'cdp',
              rootRecordId: cdp.id,
              tenantId: widget.entidadId,
            ),
          ],
          evidenceRequest: EvidenceRequest(
            domain: 'presupuesto',
            recordType: 'cdp',
            recordId: cdp.id,
          ),
          onEvidenceRequested: _exportarEvidencia,
          criticalFields: [
            RecordCardField(
              label: 'CDP',
              value: cdp.numeroCDP,
              icon: Icons.description,
              emphasized: true,
            ),
            RecordCardField(
              label: 'Rubro',
              value: cdp.codigoRubro,
              icon: Icons.account_tree,
            ),
            RecordCardField(
              label: 'Valor',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(cdp.valorCDP),
              ),
              icon: Icons.payments,
              emphasized: true,
            ),
            RecordCardField(
              label: 'Saldo',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(cdp.saldoDisponible),
              ),
              icon: Icons.savings,
              emphasized: true,
            ),
          ],
          secondaryFields: [
            RecordCardField(label: 'Vigencia', value: cdp.vigencia),
            RecordCardField(
              label: 'Vence',
              value: DateFormatter.format(cdp.fechaVigencia),
            ),
            RecordCardField(
              label: 'Funcionario expedidor',
              value: cdp.funcionarioExpedidor,
            ),
            RecordCardField(
              label: 'Funcionario solicitante',
              value: cdp.funcionarioSolicitante,
            ),
            RecordCardField(label: 'Objeto del gasto', value: cdp.objetoGasto),
            RecordCardField(
              label: 'Contrato',
              value: cdp.contratoNumero ?? 'Sin contrato asociado',
            ),
            RecordCardField(
              label: 'Estado',
              value: cdp.estado.toString().split('.').last.toUpperCase(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRPsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment,
              size: 64,
              color: MerkaThemeTokens.graphite600,
            ),
            const SizedBox(height: 16),
            Text(
              'Registros Presupuestales',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('No hay RPs expedidos'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _expedirRP(),
              icon: Icon(Icons.add),
              label: const Text('Expedir RP'),
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
      itemCount: _rps.length,
      itemBuilder: (context, index) {
        final rp = _rps[index];
        return ExpandableRecordCard(
          actions: [
            traceabilityRecordAction(
              rootEntityType: 'rp',
              rootRecordId: rp.id,
              tenantId: widget.entidadId,
            ),
          ],
          evidenceRequest: EvidenceRequest(
            domain: 'presupuesto',
            recordType: 'rp',
            recordId: rp.id,
          ),
          onEvidenceRequested: _exportarEvidencia,
          criticalFields: [
            RecordCardField(
              label: 'RP',
              value: rp.numeroRP,
              icon: Icons.assignment,
              emphasized: true,
            ),
            RecordCardField(
              label: 'Rubro',
              value: rp.codigoRubro,
              icon: Icons.account_tree,
            ),
            RecordCardField(
              label: 'Valor',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(rp.valorRP),
              ),
              icon: Icons.payments,
              emphasized: true,
            ),
            RecordCardField(
              label: 'Saldo',
              value: CurrencyFormatter.format(
                publicMoneyForDisplay(rp.saldoDisponible),
              ),
              icon: Icons.savings,
              emphasized: true,
            ),
          ],
          secondaryFields: [
            RecordCardField(label: 'CDP asociado', value: rp.numeroCDP),
            RecordCardField(label: 'Contrato', value: rp.contratoNumero),
            RecordCardField(label: 'Vigencia', value: rp.vigencia),
            RecordCardField(
              label: 'Vence',
              value: DateFormatter.format(rp.fechaVigencia),
            ),
            RecordCardField(
              label: 'Funcionario expedidor',
              value: rp.funcionarioExpedidor,
            ),
            RecordCardField(label: 'Objeto del gasto', value: rp.objetoGasto),
            RecordCardField(
              label: 'Estado',
              value: rp.estado.toString().split('.').last.toUpperCase(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildObligacionesTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_obligaciones.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: MerkaThemeTokens.graphite600,
            ),
            const SizedBox(height: 16),
            Text(
              'Obligaciones Presupuestales',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('No hay obligaciones registradas'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _registrarObligacion(),
              icon: Icon(Icons.add),
              label: const Text('Registrar Obligación'),
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
      itemCount: _obligaciones.length,
      itemBuilder: (context, index) {
        final obligacion = _obligaciones[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(obligacion.numeroObligacion),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tercero: ${obligacion.terceroNombre}'),
                Text(
                  'Valor: ${CurrencyFormatter.format(publicMoneyForDisplay(obligacion.valorObligacion))}',
                ),
                Text(
                  'Pendiente: ${CurrencyFormatter.format(publicMoneyForDisplay(obligacion.saldoPendiente))}',
                ),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    obligacion.estado.toString().split('.').last.toUpperCase(),
                  ),
                  backgroundColor:
                      obligacion.estado == EstadoObligacion.pendiente
                      ? MerkaThemeTokens.warning
                      : MerkaThemeTokens.success,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagosTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pagos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment, size: 64, color: MerkaThemeTokens.graphite600),
            const SizedBox(height: 16),
            Text('Pagos', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('No hay pagos programados'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _programarPago(),
              icon: Icon(Icons.add),
              label: const Text('Programar Pago'),
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
      itemCount: _pagos.length,
      itemBuilder: (context, index) {
        final pago = _pagos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(pago.numeroPago),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tercero: ${pago.terceroNombre}'),
                Text(
                  'Valor: ${CurrencyFormatter.format(publicMoneyForDisplay(pago.valorPago))}',
                ),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    pago.estado.toString().split('.').last.toUpperCase(),
                  ),
                  backgroundColor: pago.estado == EstadoPago.programado
                      ? MerkaThemeTokens.navy600
                      : MerkaThemeTokens.success,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoCreacion() {
    switch (_selectedIndex) {
      case 0:
        _crearApropiacion();
        break;
      case 1:
        _expedirCDP();
        break;
      case 2:
        _expedirRP();
        break;
      case 3:
        _registrarObligacion();
        break;
      case 4:
        _programarPago();
        break;
    }
  }

  void _crearApropiacion() {
    showDialog(
      context: context,
      builder: (context) => _ApropiacionForm(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        presupuestoService: _presupuestoService,
        onGuardar: (apropiacion) {
          if (!mounted) return;
          setState(() {
            _apropiaciones = [..._apropiaciones, apropiacion];
            _loading = false;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _expedirCDP() {
    if (_apropiaciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debe crear una apropiación')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _CDPForm(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        presupuestoService: _presupuestoService,
        apropiaciones: _apropiaciones,
        onGuardar: () {
          _cargarDatos();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _expedirRP() {
    if (_cdps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debe expedir un CDP')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _RPForm(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        presupuestoService: _presupuestoService,
        cdps: _cdps,
        onGuardar: () {
          _cargarDatos();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _registrarObligacion() {
    if (_rps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debe expedir un RP')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _ObligacionForm(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        presupuestoService: _presupuestoService,
        rps: _rps,
        onGuardar: () {
          _cargarDatos();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _programarPago() {
    if (_obligaciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debe registrar una obligación')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _PagoForm(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        presupuestoService: _presupuestoService,
        obligaciones: _obligaciones,
        onGuardar: () {
          _cargarDatos();
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    CommandRegistry.instance.clearContext(_commandOwner);
    super.dispose();
  }
}

// ==================== FORMULARIOS ====================

class _ApropiacionForm extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final PresupuestoService presupuestoService;
  final void Function(Apropiacion apropiacion) onGuardar;

  const _ApropiacionForm({
    required this.entidadId,
    required this.usuarioId,
    required this.presupuestoService,
    required this.onGuardar,
  });

  @override
  State<_ApropiacionForm> createState() => _ApropiacionFormState();
}

class _ApropiacionFormState extends State<_ApropiacionForm> {
  final _formKey = GlobalKey<FormState>();
  final _vigenciaController = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final _codigoRubroController = TextEditingController();
  final _nombreRubroController = TextEditingController();
  final _valorController = TextEditingController();
  final _fuenteController = TextEditingController();
  final _sectorController = TextEditingController();
  final _programaController = TextEditingController();
  final _subprogramaController = TextEditingController();
  final _proyectoController = TextEditingController();
  final _actividadController = TextEditingController();
  final _objetoGastoController = TextEditingController();
  final _actoController = TextEditingController();
  DateTime? _fechaAprobacion;

  @override
  void dispose() {
    _vigenciaController.dispose();
    _codigoRubroController.dispose();
    _nombreRubroController.dispose();
    _valorController.dispose();
    _fuenteController.dispose();
    _sectorController.dispose();
    _programaController.dispose();
    _subprogramaController.dispose();
    _proyectoController.dispose();
    _actividadController.dispose();
    _objetoGastoController.dispose();
    _actoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      final apropiacion = await widget.presupuestoService.crearApropiacion(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        vigencia: _vigenciaController.text,
        codigoRubro: _codigoRubroController.text,
        nombreRubro: _nombreRubroController.text,
        valorApropiado: publicMoneyFromMajor(_valorController.text),
        fuenteFinanciacion: _fuenteController.text,
        sector: _sectorController.text,
        programa: _programaController.text,
        subprograma: _subprogramaController.text,
        proyecto: _proyectoController.text,
        actividad: _actividadController.text,
        objetoGasto: _objetoGastoController.text,
        fechaAprobacionConcejo: _fechaAprobacion ?? DateTime.now(),
        actoAdministrativo: _actoController.text,
      );
      widget.onGuardar(apropiacion);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear Apropiación'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _vigenciaController,
                decoration: const InputDecoration(labelText: 'Vigencia (año)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _codigoRubroController,
                decoration: const InputDecoration(labelText: 'Código Rubro'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _nombreRubroController,
                decoration: const InputDecoration(labelText: 'Nombre Rubro'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _valorController,
                decoration: const InputDecoration(labelText: 'Valor Apropiado'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Requerido';
                  if (double.tryParse(value!) == null) return 'Número inválido';
                  return null;
                },
              ),
              TextFormField(
                controller: _fuenteController,
                decoration: const InputDecoration(
                  labelText: 'Fuente de Financiación',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _sectorController,
                decoration: const InputDecoration(labelText: 'Sector'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _programaController,
                decoration: const InputDecoration(labelText: 'Programa'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _subprogramaController,
                decoration: const InputDecoration(labelText: 'Subprograma'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _proyectoController,
                decoration: const InputDecoration(labelText: 'Proyecto'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _actividadController,
                decoration: const InputDecoration(labelText: 'Actividad'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _objetoGastoController,
                decoration: const InputDecoration(labelText: 'Objeto de Gasto'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              ListTile(
                title: const Text('Fecha Aprobación Concejo'),
                subtitle: Text(
                  _fechaAprobacion == null
                      ? 'No seleccionada'
                      : DateFormatter.format(_fechaAprobacion!),
                ),
                trailing: Icon(Icons.calendar_today),
                onTap: () async {
                  final fecha = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (fecha != null) {
                    setState(() => _fechaAprobacion = fecha);
                  }
                },
              ),
              TextFormField(
                controller: _actoController,
                decoration: const InputDecoration(
                  labelText: 'Acto Administrativo (Acuerdo/Ordenanza)',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
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
        ElevatedButton(onPressed: _guardar, child: const Text('Crear')),
      ],
    );
  }
}

class _CDPForm extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final PresupuestoService presupuestoService;
  final List<Apropiacion> apropiaciones;
  final VoidCallback onGuardar;

  const _CDPForm({
    required this.entidadId,
    required this.usuarioId,
    required this.presupuestoService,
    required this.apropiaciones,
    required this.onGuardar,
  });

  @override
  State<_CDPForm> createState() => _CDPFormState();
}

class _CDPFormState extends State<_CDPForm> {
  final _formKey = GlobalKey<FormState>();
  Apropiacion? _apropiacionSeleccionada;
  final _valorController = TextEditingController();
  final _funcionarioExpedidorController = TextEditingController();
  final _funcionarioSolicitanteController = TextEditingController();
  final _objetoGastoController = TextEditingController();
  final _contratoController = TextEditingController();

  @override
  void dispose() {
    _valorController.dispose();
    _funcionarioExpedidorController.dispose();
    _funcionarioSolicitanteController.dispose();
    _objetoGastoController.dispose();
    _contratoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_apropiacionSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar una apropiación')),
      );
      return;
    }

    try {
      await widget.presupuestoService.expedirCDP(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        apropiacionId: _apropiacionSeleccionada!.id,
        valorCDP: publicMoneyFromMajor(_valorController.text),
        funcionarioExpedidor: _funcionarioExpedidorController.text,
        funcionarioSolicitante: _funcionarioSolicitanteController.text,
        objetoGasto: _objetoGastoController.text,
        contratoNumero: _contratoController.text.isEmpty
            ? null
            : _contratoController.text,
      );
      widget.onGuardar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Expedir CDP'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Apropiacion>(
                decoration: const InputDecoration(labelText: 'Apropiación'),
                items: widget.apropiaciones.map((apropiacion) {
                  return DropdownMenuItem(
                    value: apropiacion,
                    child: Text(
                      '${apropiacion.codigoRubro} - ${CurrencyFormatter.format(publicMoneyForDisplay(apropiacion.saldoDisponible))}',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _apropiacionSeleccionada = value);
                },
                validator: (value) => value == null ? 'Requerido' : null,
              ),
              if (_apropiacionSeleccionada != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Saldo disponible: ${CurrencyFormatter.format(publicMoneyForDisplay(_apropiacionSeleccionada!.saldoDisponible))}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              TextFormField(
                controller: _valorController,
                decoration: const InputDecoration(labelText: 'Valor CDP'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Requerido';
                  if (double.tryParse(value!) == null) return 'Número inválido';
                  if (_apropiacionSeleccionada != null) {
                    final valor = publicMoneyFromMajor(value);
                    if (valor > _apropiacionSeleccionada!.saldoDisponible) {
                      return 'Excede saldo disponible';
                    }
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _funcionarioExpedidorController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario Expedidor',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _funcionarioSolicitanteController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario Solicitante',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _objetoGastoController,
                decoration: const InputDecoration(labelText: 'Objeto de Gasto'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _contratoController,
                decoration: const InputDecoration(
                  labelText: 'Número Contrato (opcional)',
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
        ElevatedButton(onPressed: _guardar, child: const Text('Expedir')),
      ],
    );
  }
}

class _RPForm extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final PresupuestoService presupuestoService;
  final List<CDP> cdps;
  final VoidCallback onGuardar;

  const _RPForm({
    required this.entidadId,
    required this.usuarioId,
    required this.presupuestoService,
    required this.cdps,
    required this.onGuardar,
  });

  @override
  State<_RPForm> createState() => _RPFormState();
}

class _RPFormState extends State<_RPForm> {
  final _formKey = GlobalKey<FormState>();
  CDP? _cdpSeleccionado;
  final _valorController = TextEditingController();
  final _contratoIdController = TextEditingController();
  final _contratoNumeroController = TextEditingController();
  final _funcionarioExpedidorController = TextEditingController();
  final _funcionarioSolicitanteController = TextEditingController();
  final _objetoGastoController = TextEditingController();

  @override
  void dispose() {
    _valorController.dispose();
    _contratoIdController.dispose();
    _contratoNumeroController.dispose();
    _funcionarioExpedidorController.dispose();
    _funcionarioSolicitanteController.dispose();
    _objetoGastoController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_cdpSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Debe seleccionar un CDP')));
      return;
    }

    try {
      await widget.presupuestoService.expedirRP(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        cdpId: _cdpSeleccionado!.id,
        contratoId: _contratoIdController.text,
        contratoNumero: _contratoNumeroController.text,
        valorRP: publicMoneyFromMajor(_valorController.text),
        funcionarioExpedidor: _funcionarioExpedidorController.text,
        funcionarioSolicitante: _funcionarioSolicitanteController.text,
        objetoGasto: _objetoGastoController.text,
      );
      widget.onGuardar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cdpsVigentes = widget.cdps.where((cdp) => cdp.estaVigente()).toList();

    return AlertDialog(
      title: const Text('Expedir RP'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<CDP>(
                decoration: const InputDecoration(labelText: 'CDP'),
                items: cdpsVigentes.map((cdp) {
                  return DropdownMenuItem(
                    value: cdp,
                    child: Text(
                      '${cdp.numeroCDP} - ${CurrencyFormatter.format(publicMoneyForDisplay(cdp.saldoDisponible))}',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _cdpSeleccionado = value);
                },
                validator: (value) => value == null ? 'Requerido' : null,
              ),
              if (_cdpSeleccionado != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Saldo disponible: ${CurrencyFormatter.format(publicMoneyForDisplay(_cdpSeleccionado!.saldoDisponible))}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              TextFormField(
                controller: _contratoNumeroController,
                decoration: const InputDecoration(
                  labelText: 'Número Contrato *',
                ),
                validator: (value) => value?.isEmpty ?? true
                    ? 'Requerido (Ley 80/1993 Art. 41)'
                    : null,
              ),
              TextFormField(
                controller: _contratoIdController,
                decoration: const InputDecoration(labelText: 'ID Contrato'),
              ),
              TextFormField(
                controller: _valorController,
                decoration: const InputDecoration(labelText: 'Valor RP'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Requerido';
                  if (double.tryParse(value!) == null) return 'Número inválido';
                  if (_cdpSeleccionado != null) {
                    final valor = publicMoneyFromMajor(value);
                    if (valor > _cdpSeleccionado!.saldoDisponible) {
                      return 'Excede saldo disponible en CDP';
                    }
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _funcionarioExpedidorController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario Expedidor',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _funcionarioSolicitanteController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario Solicitante',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _objetoGastoController,
                decoration: const InputDecoration(labelText: 'Objeto de Gasto'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
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
        ElevatedButton(onPressed: _guardar, child: const Text('Expedir')),
      ],
    );
  }
}

class _ObligacionForm extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final PresupuestoService presupuestoService;
  final List<RP> rps;
  final VoidCallback onGuardar;

  const _ObligacionForm({
    required this.entidadId,
    required this.usuarioId,
    required this.presupuestoService,
    required this.rps,
    required this.onGuardar,
  });

  @override
  State<_ObligacionForm> createState() => _ObligacionFormState();
}

class _ObligacionFormState extends State<_ObligacionForm> {
  final _formKey = GlobalKey<FormState>();
  RP? _rpSeleccionado;
  final _valorController = TextEditingController();
  final _contratoIdController = TextEditingController();
  final _contratoNumeroController = TextEditingController();
  final _terceroIdController = TextEditingController();
  final _terceroNombreController = TextEditingController();
  final _funcionarioReconocioController = TextEditingController();
  final _objetoGastoController = TextEditingController();
  final _actaReciboController = TextEditingController();
  final _facturaController = TextEditingController();
  DateTime? _actaFecha;
  DateTime? _facturaFecha;

  @override
  void dispose() {
    _valorController.dispose();
    _contratoIdController.dispose();
    _contratoNumeroController.dispose();
    _terceroIdController.dispose();
    _terceroNombreController.dispose();
    _funcionarioReconocioController.dispose();
    _objetoGastoController.dispose();
    _actaReciboController.dispose();
    _facturaController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_rpSeleccionado == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Debe seleccionar un RP')));
      return;
    }

    try {
      await widget.presupuestoService.registrarObligacion(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        rpId: _rpSeleccionado!.id,
        contratoId: _contratoIdController.text,
        contratoNumero: _contratoNumeroController.text,
        terceroId: _terceroIdController.text,
        terceroNombre: _terceroNombreController.text,
        valorObligacion: publicMoneyFromMajor(_valorController.text),
        funcionarioReconocio: _funcionarioReconocioController.text,
        objetoGasto: _objetoGastoController.text,
        actaReciboNumero: _actaReciboController.text.isEmpty
            ? null
            : _actaReciboController.text,
        actaReciboFecha: _actaFecha,
        facturaNumero: _facturaController.text.isEmpty
            ? null
            : _facturaController.text,
        facturaFecha: _facturaFecha,
      );
      widget.onGuardar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rpsVigentes = widget.rps.where((rp) => rp.estaVigente()).toList();

    return AlertDialog(
      title: const Text('Registrar Obligación'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<RP>(
                decoration: const InputDecoration(labelText: 'RP'),
                items: rpsVigentes.map((rp) {
                  return DropdownMenuItem(
                    value: rp,
                    child: Text(
                      '${rp.numeroRP} - ${CurrencyFormatter.format(publicMoneyForDisplay(rp.saldoDisponible))}',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _rpSeleccionado = value);
                },
                validator: (value) => value == null ? 'Requerido' : null,
              ),
              if (_rpSeleccionado != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Saldo disponible: ${CurrencyFormatter.format(publicMoneyForDisplay(_rpSeleccionado!.saldoDisponible))}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              TextFormField(
                controller: _contratoNumeroController,
                decoration: const InputDecoration(labelText: 'Número Contrato'),
              ),
              TextFormField(
                controller: _contratoIdController,
                decoration: const InputDecoration(labelText: 'ID Contrato'),
              ),
              TextFormField(
                controller: _terceroIdController,
                decoration: const InputDecoration(labelText: 'ID Tercero'),
              ),
              TextFormField(
                controller: _terceroNombreController,
                decoration: const InputDecoration(labelText: 'Nombre Tercero'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _valorController,
                decoration: const InputDecoration(
                  labelText: 'Valor Obligación',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Requerido';
                  if (double.tryParse(value!) == null) return 'Número inválido';
                  if (_rpSeleccionado != null) {
                    final valor = publicMoneyFromMajor(value);
                    if (valor > _rpSeleccionado!.saldoDisponible) {
                      return 'Excede saldo disponible en RP';
                    }
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _funcionarioReconocioController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario Reconoció',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _objetoGastoController,
                decoration: const InputDecoration(labelText: 'Objeto de Gasto'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _actaReciboController,
                decoration: const InputDecoration(
                  labelText: 'Número Acta Recibo',
                ),
              ),
              ListTile(
                title: const Text('Fecha Acta Recibo'),
                subtitle: Text(
                  _actaFecha == null
                      ? 'No seleccionada'
                      : DateFormatter.format(_actaFecha!),
                ),
                trailing: Icon(Icons.calendar_today),
                onTap: () async {
                  final fecha = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (fecha != null) {
                    setState(() => _actaFecha = fecha);
                  }
                },
              ),
              TextFormField(
                controller: _facturaController,
                decoration: const InputDecoration(labelText: 'Número Factura'),
              ),
              ListTile(
                title: const Text('Fecha Factura'),
                subtitle: Text(
                  _facturaFecha == null
                      ? 'No seleccionada'
                      : DateFormatter.format(_facturaFecha!),
                ),
                trailing: Icon(Icons.calendar_today),
                onTap: () async {
                  final fecha = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (fecha != null) {
                    setState(() => _facturaFecha = fecha);
                  }
                },
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
        ElevatedButton(onPressed: _guardar, child: const Text('Registrar')),
      ],
    );
  }
}

class _PagoForm extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final PresupuestoService presupuestoService;
  final List<Obligacion> obligaciones;
  final VoidCallback onGuardar;

  const _PagoForm({
    required this.entidadId,
    required this.usuarioId,
    required this.presupuestoService,
    required this.obligaciones,
    required this.onGuardar,
  });

  @override
  State<_PagoForm> createState() => _PagoFormState();
}

class _PagoFormState extends State<_PagoForm> {
  final _formKey = GlobalKey<FormState>();
  Obligacion? _obligacionSeleccionada;
  final _valorController = TextEditingController();
  final _bancoController = TextEditingController();
  final _cuentaController = TextEditingController();
  final _tipoCuentaController = TextEditingController();
  final _funcionarioController = TextEditingController();
  final _mesPACController = TextEditingController(
    text: DateTime.now().month.toString(),
  );

  @override
  void dispose() {
    _valorController.dispose();
    _bancoController.dispose();
    _cuentaController.dispose();
    _tipoCuentaController.dispose();
    _funcionarioController.dispose();
    _mesPACController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_obligacionSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar una obligación')),
      );
      return;
    }

    try {
      await widget.presupuestoService.programarPago(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        obligacionId: _obligacionSeleccionada!.id,
        terceroId: _obligacionSeleccionada!.terceroId,
        terceroNombre: _obligacionSeleccionada!.terceroNombre,
        bancoDestino: _bancoController.text,
        cuentaDestino: _cuentaController.text,
        tipoCuenta: _tipoCuentaController.text,
        valorPago: publicMoneyFromMajor(_valorController.text),
        funcionarioProgramo: _funcionarioController.text,
        tipoPago: TipoPago.transferenciaBancaria,
        mesPAC: int.parse(_mesPACController.text),
      );
      widget.onGuardar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final obligacionesPendientes = widget.obligaciones
        .where((obligacion) => obligacion.sePuedePagar())
        .toList();

    return AlertDialog(
      title: const Text('Programar Pago'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Obligacion>(
                decoration: const InputDecoration(labelText: 'Obligación'),
                items: obligacionesPendientes.map((obligacion) {
                  return DropdownMenuItem(
                    value: obligacion,
                    child: Text(
                      '${obligacion.numeroObligacion} - ${CurrencyFormatter.format(publicMoneyForDisplay(obligacion.saldoPendiente))}',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _obligacionSeleccionada = value);
                },
                validator: (value) => value == null ? 'Requerido' : null,
              ),
              if (_obligacionSeleccionada != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Saldo pendiente: ${CurrencyFormatter.format(publicMoneyForDisplay(_obligacionSeleccionada!.saldoPendiente))}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              TextFormField(
                controller: _valorController,
                decoration: const InputDecoration(labelText: 'Valor Pago'),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Requerido';
                  if (double.tryParse(value!) == null) return 'Número inválido';
                  if (_obligacionSeleccionada != null) {
                    final valor = publicMoneyFromMajor(value);
                    if (valor > _obligacionSeleccionada!.saldoPendiente) {
                      return 'Excede saldo pendiente';
                    }
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _bancoController,
                decoration: const InputDecoration(labelText: 'Banco Destino'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _cuentaController,
                decoration: const InputDecoration(labelText: 'Cuenta Destino'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _tipoCuentaController,
                decoration: const InputDecoration(labelText: 'Tipo Cuenta'),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _mesPACController,
                decoration: const InputDecoration(labelText: 'Mes PAC (1-12)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Requerido';
                  final mes = int.tryParse(value!);
                  if (mes == null || mes < 1 || mes > 12) {
                    return 'Mes inválido (1-12)';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _funcionarioController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario Programó',
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Requerido' : null,
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
        ElevatedButton(onPressed: _guardar, child: const Text('Programar')),
      ],
    );
  }
}
