import '../../app_session.dart';
import '../../db_helper.dart';
import '../../hrm/application/hrm_leave_service.dart';
import '../../mrp/application/mrp_services.dart';
import '../../mrp/domain/mrp_work_order.dart';
import '../../services/merka_intelligence_service.dart';
import '../../sector_publico/planeacion/services/trazabilidad_plan_presupuesto_service.dart';
import '../commands/command_registry.dart';
import '../security/action_permission.dart';
import 'signal.dart';

typedef OperationalAlertLoader = Future<List<OperationalAlert>> Function();
typedef PendingLeaveLoader = Future<List<Map<String, dynamic>>> Function();
typedef WorkOrderLoader = Future<List<MrpWorkOrder>> Function();
typedef StockAvailabilityLoader = Future<bool> Function(int orderId);
typedef BudgetFollowUpLoader = Future<List<BudgetDeviationRecord>> Function();

class SignalAggregator {
  SignalAggregator({Iterable<SignalSource> sources = const []})
    : _sources = [...sources];

  factory SignalAggregator.forCurrentSession({
    DatabaseHelper? database,
    String? entidadId,
  }) {
    return SignalAggregator(
      sources: [
        IntelligenceSignalSource(),
        MrpStockSignalSource(),
        HrmApprovalSignalSource(),
        BudgetDeviationSignalSource(
          database: database,
          entidadId: entidadId ?? AppSession.entidadId,
        ),
      ],
    );
  }

  final List<SignalSource> _sources;

  List<SignalSource> get sources => List.unmodifiable(_sources);

  void registerSource(SignalSource source) {
    _sources.add(source);
  }

  Future<List<Signal>> collect() async {
    final signals = <Signal>[];
    for (final source in _sources) {
      try {
        signals.addAll(await source.load());
      } catch (_) {
        // A source must not hide the signals produced by other local modules.
      }
    }
    signals.sort((a, b) {
      final priority = a.priority.sortWeight.compareTo(b.priority.sortWeight);
      if (priority != 0) return priority;
      return a.title.compareTo(b.title);
    });
    return signals;
  }
}

class IntelligenceSignalSource implements SignalSource {
  IntelligenceSignalSource({
    MerkaIntelligenceService? service,
    OperationalAlertLoader? loader,
  }) : _service = service,
       _loader = loader;

  final MerkaIntelligenceService? _service;
  final OperationalAlertLoader? _loader;

  @override
  String get id => 'intelligence_service';

  @override
  Future<List<Signal>> load() async {
    final alerts =
        await (_loader ??
            (_service ?? MerkaIntelligenceService()).operationalAlerts)();
    return alerts.map(fromAlert).toList();
  }

  static Signal fromAlert(OperationalAlert alert) {
    final navigation = switch (alert.kind) {
      'overdue_receivable' => 'receivables',
      'payable' => 'payables',
      'cash_difference' => 'cash_closings',
      'electronic_invoice_pending' => 'electronic_invoice',
      'backup_missing' || 'backup_stale' => 'backups',
      'license_expiry' => 'licensing',
      'low_margin' => 'sales',
      'critical_stock' || 'negative_stock' || 'expiring_product' => 'inventory',
      _ => 'support_center',
    };
    return Signal(
      id: 'intelligence.${alert.kind}.${alert.entityId ?? alert.title}',
      source: 'intelligence_service',
      priority: _priority(alert.priority),
      title: alert.title,
      description: alert.detail,
      entityType: alert.kind,
      entityId: alert.entityId?.toString(),
      navigationModuleId: navigation,
    );
  }

  static SignalPriority _priority(String value) => switch (value) {
    'urgent' => SignalPriority.urgent,
    'warning' => SignalPriority.high,
    _ => SignalPriority.info,
  };
}

class HrmApprovalSignalSource implements SignalSource {
  HrmApprovalSignalSource({
    HrmLeaveService? service,
    PendingLeaveLoader? loader,
  }) : _service = service,
       _loader = loader;

  final HrmLeaveService? _service;
  final PendingLeaveLoader? _loader;

  @override
  String get id => 'hrm';

  @override
  Future<List<Signal>> load() async {
    final service = _service ?? HrmLeaveService();
    final rows = await (_loader ?? service.pendingForApproval)();
    return rows.map((row) => fromRow(row, service: service)).toList();
  }

  static Signal fromRow(Map<String, dynamic> row, {HrmLeaveService? service}) {
    final leaveId = (row['id'] as num?)?.toInt();
    final employee = row['employee_name']?.toString() ?? 'Empleado';
    final leaveName = row['leave_name']?.toString() ?? 'Ausencia';
    final context = leaveId == null || service == null
        ? null
        : CommandContext(
            moduleId: 'hrm',
            recordType: 'hrm_leave',
            recordId: '$leaveId',
            label: '$employee - $leaveName',
            actions: {
              'approve': (context, _) async {
                final actor = int.tryParse(AppSession.usuarioId ?? '');
                if (actor == null) {
                  throw StateError('No hay un aprobador valido en la sesion.');
                }
                await service.approve(leaveId: leaveId, approvedBy: actor);
              },
            },
          );
    return Signal(
      id: 'hrm.leave.pending.${leaveId ?? employee}',
      source: 'hrm.pendingForApproval',
      priority: SignalPriority.high,
      title: 'Ausencia pendiente: $employee',
      description:
          '$leaveName - ${row['date'] ?? ''} - ${row['length_days'] ?? ''} dia(s).',
      entityType: 'hrm_leave',
      entityId: leaveId?.toString(),
      navigationModuleId: 'hrm',
      suggestedAction: 'Aprobar ausencia',
      commandId: context == null ? null : 'hrm.leave.approve',
      permissionModuleId: 'hrm',
      requiredPermission: 'Aprobar ausencias',
      requiredAction: AppAction.approve,
      commandContext: context,
    );
  }
}

class MrpStockSignalSource implements SignalSource {
  MrpStockSignalSource({
    MrpWorkOrderService? service,
    WorkOrderLoader? loader,
    StockAvailabilityLoader? stockLoader,
  }) : _service = service,
       _loader = loader,
       _stockLoader = stockLoader;

  final MrpWorkOrderService? _service;
  final WorkOrderLoader? _loader;
  final StockAvailabilityLoader? _stockLoader;

  @override
  String get id => 'mrp';

  @override
  Future<List<Signal>> load() async {
    final service = _service ?? MrpWorkOrderService();
    final orders = await (_loader ?? service.list)();
    final signals = <Signal>[];
    for (final order in orders) {
      if (order.id == null ||
          (order.status != MrpWorkOrderStatus.borrador &&
              order.status != MrpWorkOrderStatus.noIniciada)) {
        continue;
      }
      final enough = await (_stockLoader ?? service.hasSufficientStock)(
        order.id!,
      );
      if (!enough) signals.add(fromOrder(order));
    }
    return signals;
  }

  static Signal fromOrder(MrpWorkOrder order) => Signal(
    id: 'mrp.work_order.stock.${order.id}',
    source: 'mrp.hasSufficientStock',
    priority: SignalPriority.high,
    title: 'Stock insuficiente en orden #${order.id}',
    description:
        'La orden del producto #${order.productionItemId} no puede iniciar con el inventario disponible.',
    entityType: 'mrp_work_order',
    entityId: order.id?.toString(),
    navigationModuleId: 'production',
    requiredPermission: 'Consultar producción',
    requiredAction: AppAction.view,
  );
}

class BudgetDeviationSignalSource implements SignalSource {
  BudgetDeviationSignalSource({
    DatabaseHelper? database,
    required this.entidadId,
    TrazabilidadPlanPresupuestoService? service,
    BudgetFollowUpLoader? loader,
  }) : _database = database ?? DatabaseHelper.instance,
       _service = service,
       _loader = loader;

  final DatabaseHelper _database;
  final TrazabilidadPlanPresupuestoService? _service;
  final BudgetFollowUpLoader? _loader;
  final String entidadId;

  @override
  String get id => 'presupuesto';

  @override
  Future<List<Signal>> load() async {
    final loader = _loader;
    if (loader != null) {
      final rows = await loader();
      return rows
          .where((row) => row.followUp.alertaDesviacion)
          .map((row) => fromSeguimiento(row.projectId, row.followUp))
          .toList();
    }
    final db = await _database.database;
    final service = _service ?? TrazabilidadPlanPresupuestoService(db);
    final projects = await db.query(
      'proyectos_mga',
      columns: ['id'],
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
    );
    final signals = <Signal>[];
    for (final project in projects) {
      final projectId = project['id']?.toString();
      if (projectId == null || projectId.isEmpty) continue;
      final rows = await service.consultarSeguimiento(
        entidadId: entidadId,
        proyectoId: projectId,
      );
      signals.addAll(
        rows
            .where((row) => row.alertaDesviacion)
            .map((row) => fromSeguimiento(projectId, row)),
      );
    }
    return signals;
  }

  static Signal fromSeguimiento(
    String projectId,
    SeguimientoProyectoRubroMeta row,
  ) => Signal(
    id: 'presupuesto.desviacion.$projectId.${row.metaCodigo}',
    source: 'TrazabilidadPlanPresupuestoService',
    priority: SignalPriority.high,
    title: 'Desviación presupuestaria: ${row.metaCodigo}',
    description:
        'Ejecución financiera ${row.ejecucionFinancieraPorcentaje.toStringAsFixed(1)}% vs avance físico ${row.avanceFisicoPorcentaje.toStringAsFixed(1)}%; diferencia mayor a 20%.',
    entityType: 'proyecto_mga',
    entityId: projectId,
    navigationModuleId: 'planeacion',
    requiredPermission: 'Consultar planeación y presupuesto',
    requiredAction: AppAction.view,
  );
}

class BudgetDeviationRecord {
  const BudgetDeviationRecord({
    required this.projectId,
    required this.followUp,
  });

  final String projectId;
  final SeguimientoProyectoRubroMeta followUp;
}
