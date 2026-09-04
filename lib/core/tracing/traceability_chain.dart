import 'package:sqflite/sqflite.dart';

import '../commands/command_registry.dart';

enum TraceabilityStepState { complete, blocked, pending }

extension TraceabilityStepStateLabel on TraceabilityStepState {
  String get label => switch (this) {
    TraceabilityStepState.complete => 'Completo',
    TraceabilityStepState.blocked => 'Bloqueado',
    TraceabilityStepState.pending => 'Pendiente',
  };
}

/// A persisted record in a causal business chain.
class ChainStep {
  const ChainStep({
    required this.id,
    required this.label,
    required this.entityType,
    required this.state,
    this.recordId,
    this.blockingRule,
    this.requiredRole,
    this.navigationModuleId,
    this.commandId,
    this.commandContext,
    this.evidenceRecordType,
  });

  final String id;
  final String label;
  final String entityType;
  final TraceabilityStepState state;
  final String? recordId;
  final String? blockingRule;
  final String? requiredRole;
  final String? navigationModuleId;
  final String? commandId;
  final CommandContext? commandContext;
  final String? evidenceRecordType;

  bool get isComplete => state == TraceabilityStepState.complete;
  bool get isBlocked => state == TraceabilityStepState.blocked;

  /// The action is filtered through the same registry used by Cmd/Ctrl+K.
  bool actionAvailable(CommandRegistry registry) {
    if (commandId == null) return false;
    return registry
        .available(commandContext: commandContext)
        .any((command) => command.id == commandId);
  }
}

class TraceabilityChain {
  const TraceabilityChain({
    required this.id,
    required this.title,
    required this.rootEntityType,
    required this.rootRecordId,
    required this.steps,
  });

  final String id;
  final String title;
  final String rootEntityType;
  final String rootRecordId;
  final List<ChainStep> steps;

  bool get isComplete => steps.every((step) => step.isComplete);
}

class TraceabilityBuildContext {
  const TraceabilityBuildContext({
    required this.db,
    required this.rootEntityType,
    required this.rootRecordId,
    this.tenantId,
    this.commandContext,
  });

  final DatabaseExecutor db;
  final String rootEntityType;
  final String rootRecordId;
  final String? tenantId;
  final CommandContext? commandContext;
}

abstract interface class TraceabilityChainProvider {
  String get id;

  bool supports(String rootEntityType);

  Future<TraceabilityChain> build(TraceabilityBuildContext context);
}

/// Extensible registry for causal chains. Providers read existing services'
/// persisted results; they do not reimplement mutation or accounting rules.
class TraceabilityChainService {
  TraceabilityChainService({
    Iterable<TraceabilityChainProvider> providers = const [],
  }) : _providers = [...providers];

  factory TraceabilityChainService.standard() => TraceabilityChainService(
    providers: const [
      PublicBudgetTraceabilityProvider(),
      CommercialTraceabilityProvider(),
    ],
  );

  final List<TraceabilityChainProvider> _providers;

  List<TraceabilityChainProvider> get providers =>
      List.unmodifiable(_providers);

  void register(TraceabilityChainProvider provider) {
    _providers.add(provider);
  }

  Future<TraceabilityChain> build({
    required String rootEntityType,
    required String rootRecordId,
    required DatabaseExecutor db,
    String? tenantId,
    CommandContext? commandContext,
  }) async {
    final provider = _providers.cast<TraceabilityChainProvider?>().firstWhere(
      (candidate) => candidate!.supports(rootEntityType),
      orElse: () => null,
    );
    if (provider == null) {
      throw ArgumentError(
        'No hay proveedor de trazabilidad para $rootEntityType.',
      );
    }
    return provider.build(
      TraceabilityBuildContext(
        db: db,
        rootEntityType: rootEntityType,
        rootRecordId: rootRecordId,
        tenantId: tenantId,
        commandContext: commandContext,
      ),
    );
  }
}

class PublicBudgetTraceabilityProvider implements TraceabilityChainProvider {
  const PublicBudgetTraceabilityProvider();

  @override
  String get id => 'public_budget';

  @override
  bool supports(String rootEntityType) => const {
    'apropiacion',
    'cdp',
    'rp',
    'obligacion',
    'pago_publico',
  }.contains(rootEntityType);

  @override
  Future<TraceabilityChain> build(TraceabilityBuildContext context) async {
    final db = context.db;
    Map<String, dynamic>? appropriation;
    Map<String, dynamic>? cdp;
    Map<String, dynamic>? rp;
    Map<String, dynamic>? obligation;
    Map<String, dynamic>? payment;
    Future<Map<String, dynamic>?> publicRow(String table, String? id) => _row(
      db,
      table,
      id,
      tenantColumn: 'entidad_id',
      tenantId: context.tenantId,
    );
    Future<Map<String, dynamic>?> publicFirst(
      String table, {
      required String where,
      required List<Object?> args,
    }) => _first(
      db,
      table,
      where: where,
      args: args,
      tenantColumn: 'entidad_id',
      tenantId: context.tenantId,
    );

    switch (context.rootEntityType) {
      case 'apropiacion':
        appropriation = await publicRow('apropiaciones', context.rootRecordId);
      case 'cdp':
        cdp = await publicRow('cdps', context.rootRecordId);
        appropriation = await publicRow(
          'apropiaciones',
          cdp?['apropiacion_id']?.toString(),
        );
      case 'rp':
        rp = await publicRow('rps', context.rootRecordId);
        cdp = await publicRow('cdps', rp?['cdp_id']?.toString());
        appropriation = await publicRow(
          'apropiaciones',
          cdp?['apropiacion_id']?.toString(),
        );
      case 'obligacion':
        obligation = await publicRow('obligaciones', context.rootRecordId);
        rp = await publicRow('rps', obligation?['rp_id']?.toString());
        cdp = await publicRow('cdps', rp?['cdp_id']?.toString());
        appropriation = await publicRow(
          'apropiaciones',
          cdp?['apropiacion_id']?.toString(),
        );
      case 'pago_publico':
        payment = await publicRow('pagos', context.rootRecordId);
        obligation = await publicRow(
          'obligaciones',
          payment?['obligacion_id']?.toString(),
        );
        rp = await publicRow('rps', obligation?['rp_id']?.toString());
        cdp = await publicRow('cdps', rp?['cdp_id']?.toString());
        appropriation = await publicRow(
          'apropiaciones',
          cdp?['apropiacion_id']?.toString(),
        );
    }

    // Complete the forward chain after resolving any requested root. The
    // provider only reads persisted links; all creation/validation remains in
    // PresupuestoService and PACService.
    cdp ??= appropriation == null
        ? null
        : await publicFirst(
            'cdps',
            where: 'apropiacion_id = ?',
            args: [appropriation['id']],
          );
    rp ??= cdp == null
        ? null
        : await publicFirst('rps', where: 'cdp_id = ?', args: [cdp['id']]);
    obligation ??= rp == null
        ? null
        : await publicFirst(
            'obligaciones',
            where: 'rp_id = ?',
            args: [rp['id']],
          );
    payment ??= obligation == null
        ? null
        : await publicFirst(
            'pagos',
            where: 'obligacion_id = ?',
            args: [obligation['id']],
          );

    final nicsp = payment == null
        ? null
        : await publicFirst(
            'asientos_contables_sp',
            where:
                'referencia_origen = ? OR (tipo_documento_origen = ? AND referencia_origen = ?)',
            args: [payment['id'], 'pago', payment['numero_pago']],
          );
    final steps = <ChainStep>[
      _step(
        id: 'appropriation',
        label: 'Apropiación',
        entityType: 'apropiacion',
        row: appropriation,
        missing:
            'La cadena no puede continuar: no existe una apropiación presupuestal.',
        role: 'jefePresupuesto',
        commandId: 'public.budget.create_appropriation',
        context: context.commandContext,
        evidenceType: 'apropiacion',
      ),
      _step(
        id: 'cdp',
        label: 'CDP',
        entityType: 'cdp',
        row: cdp,
        missing: 'No existe un CDP expedido contra la apropiación.',
        role: 'jefePresupuesto',
        commandId: 'public.budget.create_cdp',
        context: context.commandContext,
        evidenceType: 'cdp',
      ),
      _step(
        id: 'rp',
        label: 'RP',
        entityType: 'rp',
        row: rp,
        missing: 'No existe un RP asociado al CDP y al contrato.',
        role: 'jefePresupuesto',
        commandId: 'public.budget.create_rp',
        context: context.commandContext,
        evidenceType: 'rp',
      ),
      _step(
        id: 'obligation',
        label: 'Obligación',
        entityType: 'obligacion',
        row: obligation,
        missing: 'No existe una obligación reconocida contra el RP.',
        role: 'jefePresupuesto',
        context: context.commandContext,
      ),
      _step(
        id: 'payment',
        label: 'Pago / PAC',
        entityType: 'pago_publico',
        row: payment,
        missing:
            'No existe un pago ejecutado contra la obligación y el cupo PAC.',
        role: 'tesorero',
        context: context.commandContext,
      ),
      _step(
        id: 'nicsp',
        label: 'Asiento NICSP',
        entityType: 'asiento_contable_publico',
        row: nicsp,
        missing: 'No existe el asiento NICSP generado para el pago.',
        role: 'contador',
        context: context.commandContext,
      ),
    ];
    return TraceabilityChain(
      id: 'public_budget:${context.rootRecordId}',
      title: 'Cadena presupuestal pública',
      rootEntityType: context.rootEntityType,
      rootRecordId: context.rootRecordId,
      steps: steps,
    );
  }
}

class CommercialTraceabilityProvider implements TraceabilityChainProvider {
  const CommercialTraceabilityProvider();

  @override
  String get id => 'commercial_sale';

  @override
  bool supports(String rootEntityType) =>
      const {'venta', 'sale', 'cuenta_por_cobrar'}.contains(rootEntityType);

  @override
  Future<TraceabilityChain> build(TraceabilityBuildContext context) async {
    final db = context.db;
    Future<Map<String, dynamic>?> commercialRow(String table, String? id) =>
        _row(
          db,
          table,
          id,
          tenantColumn: 'company_id',
          tenantId: context.tenantId,
        );
    Future<Map<String, dynamic>?> commercialFirst(
      String table, {
      required String where,
      required List<Object?> args,
    }) => _first(
      db,
      table,
      where: where,
      args: args,
      tenantColumn: 'company_id',
      tenantId: context.tenantId,
    );
    String? saleId;
    if (context.rootEntityType == 'cuenta_por_cobrar') {
      final account = await commercialRow(
        'cuentas_por_cobrar',
        context.rootRecordId,
      );
      saleId = account?['venta_id']?.toString();
    } else {
      saleId = context.rootRecordId;
    }
    final sale = await commercialRow('ventas', saleId);
    final receivable = sale == null
        ? null
        : await commercialFirst(
            'cuentas_por_cobrar',
            where: 'venta_id = ?',
            args: [sale['id']],
          );
    final payment = receivable == null
        ? null
        : await commercialFirst(
            'abonos_cxc',
            where: 'cuenta_id = ?',
            args: [receivable['id']],
          );
    final inventory = sale == null
        ? null
        : await commercialFirst(
            'movimientos_inventario',
            where: "motivo LIKE ?",
            args: ['%POS #${sale['id']}%'],
          );
    return TraceabilityChain(
      id: 'commercial_sale:${context.rootRecordId}',
      title: 'Cadena comercial de venta',
      rootEntityType: context.rootEntityType,
      rootRecordId: context.rootRecordId,
      steps: [
        _step(
          id: 'sale',
          label: 'Venta',
          entityType: 'venta',
          row: sale,
          missing: 'No existe la venta solicitada.',
          role: 'vendedor',
          context: context.commandContext,
        ),
        _step(
          id: 'receivable',
          label: 'Cartera',
          entityType: 'cuenta_por_cobrar',
          row: receivable,
          missing: 'La venta no tiene una cuenta por cobrar registrada.',
          role: 'cartera',
          context: context.commandContext,
        ),
        _step(
          id: 'payment',
          label: 'Pago',
          entityType: 'abono_cxc',
          row: payment,
          missing: 'La cuenta por cobrar todavía no tiene un abono registrado.',
          role: 'cartera',
          context: context.commandContext,
        ),
        _step(
          id: 'inventory',
          label: 'Inventario',
          entityType: 'movimiento_inventario',
          row: inventory,
          missing: 'La venta no tiene salida de inventario registrada.',
          role: 'inventario',
          context: context.commandContext,
        ),
      ],
    );
  }
}

ChainStep _step({
  required String id,
  required String label,
  required String entityType,
  required Map<String, dynamic>? row,
  required String missing,
  required String role,
  String? commandId,
  CommandContext? context,
  String? evidenceType,
}) {
  final status = row?['estado']?.toString().toLowerCase();
  final blocked =
      status == 'rechazado' || status == 'anulado' || status == 'cancelado';
  final pending =
      status == 'borrador' || status == 'pendiente' || status == 'programado';
  return ChainStep(
    id: id,
    label: label,
    entityType: entityType,
    state: row == null
        ? TraceabilityStepState.blocked
        : blocked
        ? TraceabilityStepState.blocked
        : pending
        ? TraceabilityStepState.pending
        : TraceabilityStepState.complete,
    recordId: row?['id']?.toString(),
    blockingRule: row == null
        ? missing
        : blocked
        ? 'El registro está en estado ${row['estado']} y no puede continuar.'
        : null,
    requiredRole: role,
    commandId: commandId,
    commandContext: context,
    navigationModuleId: _moduleFor(entityType),
    evidenceRecordType: evidenceType,
  );
}

String _moduleFor(String entityType) => switch (entityType) {
  'apropiacion' ||
  'cdp' ||
  'rp' ||
  'obligacion' ||
  'pago_publico' => 'presupuesto_publico',
  'asiento_contable_publico' => 'contabilidad_publica',
  'venta' => 'sales',
  'cuenta_por_cobrar' || 'abono_cxc' => 'receivables',
  'movimiento_inventario' => 'inventory',
  _ => 'workspace',
};

Future<Map<String, dynamic>?> _row(
  DatabaseExecutor db,
  String table,
  String? id, {
  String? tenantColumn,
  String? tenantId,
}) async {
  if (id == null || id.trim().isEmpty) return null;
  return _first(
    db,
    table,
    where: 'id = ?',
    args: [id],
    tenantColumn: tenantColumn,
    tenantId: tenantId,
  );
}

Future<Map<String, dynamic>?> _first(
  DatabaseExecutor db,
  String table, {
  required String where,
  required List<Object?> args,
  String? tenantColumn,
  String? tenantId,
}) async {
  final scopedArgs = [...args];
  var scopedWhere = where;
  if (tenantColumn != null && tenantId != null) {
    scopedWhere += ' AND $tenantColumn = ?';
    scopedArgs.add(tenantId);
  }
  final rows = await db.query(
    table,
    where: scopedWhere,
    whereArgs: scopedArgs,
    limit: 1,
  );
  return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
}
