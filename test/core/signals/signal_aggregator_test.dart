import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/commands/command_registry.dart';
import 'package:merka_erp/core/security/action_permission.dart';
import 'package:merka_erp/core/signals/signal.dart';
import 'package:merka_erp/core/signals/signal_aggregator.dart';
import 'package:merka_erp/mrp/domain/mrp_work_order.dart';
import 'package:merka_erp/services/merka_intelligence_service.dart';
import 'package:merka_erp/sector_publico/planeacion/services/trazabilidad_plan_presupuesto_service.dart';
import 'package:merka_erp/ui/widgets/expandable_record_card.dart';

void main() {
  test('normaliza alertas comerciales de inteligencia operacional', () async {
    final source = IntelligenceSignalSource(
      loader: () async => [
        const OperationalAlert(
          title: 'Stock crítico',
          detail: 'Quedan 2 unidades.',
          priority: 'warning',
          kind: 'critical_stock',
          entityId: 7,
        ),
      ],
    );

    final signals = await SignalAggregator(sources: [source]).collect();

    expect(signals.single.source, 'intelligence_service');
    expect(signals.single.priority, SignalPriority.high);
    expect(signals.single.entityId, '7');
    expect(signals.single.navigationModuleId, 'inventory');
  });

  test('normaliza aprobaciones HRM con comando y permiso requerido', () async {
    final source = HrmApprovalSignalSource(
      loader: () async => [
        {'id': 12, 'employee_name': 'Ana', 'leave_name': 'Vacaciones'},
      ],
    );

    final signals = await SignalAggregator(sources: [source]).collect();

    expect(signals.single.source, 'hrm.pendingForApproval');
    expect(signals.single.commandId, 'hrm.leave.approve');
    expect(signals.single.requiredPermission, 'Aprobar ausencias');
    expect(signals.single.commandContext?.recordId, '12');
  });

  test('normaliza orden MRP bloqueada por stock insuficiente', () async {
    final order = MrpWorkOrder(
      id: 21,
      companyId: 1,
      productionItemId: 9,
      bomId: 4,
      qtyPlanned: 3,
      wipWarehouseId: 1,
      fgWarehouseId: 2,
      plannedOperatingCost: _zeroMoney(),
      actualOperatingCost: _zeroMoney(),
      rawMaterialCost: _zeroMoney(),
      totalCost: _zeroMoney(),
    );
    final source = MrpStockSignalSource(
      loader: () async => [order],
      stockLoader: (_) async => false,
    );

    final signals = await SignalAggregator(sources: [source]).collect();

    expect(signals.single.source, 'mrp.hasSufficientStock');
    expect(signals.single.entityType, 'mrp_work_order');
    expect(signals.single.navigationModuleId, 'production');
  });

  test('publica una desviación presupuestaria mayor a 20%', () async {
    const followUp = SeguimientoProyectoRubroMeta(
      metaCodigo: 'META-01',
      avanceFisicoPorcentaje: 30,
      ejecucionFinancieraPorcentaje: 55,
      alertaDesviacion: true,
    );

    final signals = await SignalAggregator(
      sources: [
        BudgetDeviationSignalSource(
          entidadId: 'ENT-001',
          loader: () async => [
            BudgetDeviationRecord(projectId: 'PROY-1', followUp: followUp),
          ],
        ),
      ],
    ).collect();

    final signal = signals.single;
    expect(signal.source, 'TrazabilidadPlanPresupuestoService');
    expect(signal.priority, SignalPriority.high);
    expect(signal.title, contains('META-01'));
    expect(signal.description, contains('mayor a 20%'));
    expect(signal.entityId, 'PROY-1');
  });

  test('no publica seguimiento presupuestario sin desviación', () async {
    const followUp = SeguimientoProyectoRubroMeta(
      metaCodigo: 'META-02',
      avanceFisicoPorcentaje: 50,
      ejecucionFinancieraPorcentaje: 55,
      alertaDesviacion: false,
    );

    final signals = await BudgetDeviationSignalSource(
      entidadId: 'ENT-001',
      loader: () async => [
        BudgetDeviationRecord(projectId: 'PROY-1', followUp: followUp),
      ],
    ).load();

    expect(signals, isEmpty);
  });

  test('el agregador continúa con otras fuentes si una falla', () async {
    final aggregator = SignalAggregator(
      sources: [
        _FailingSource(),
        IntelligenceSignalSource(
          loader: () async => [
            const OperationalAlert(
              title: 'Lote',
              detail: 'Por vencer',
              priority: 'urgent',
              kind: 'expiring_product',
            ),
          ],
        ),
      ],
    );

    final signals = await aggregator.collect();

    expect(signals, hasLength(1));
    expect(signals.single.priority, SignalPriority.urgent);
  });

  test('una señal sin permiso no expone acción directa', () {
    final registry = CommandRegistry(authorization: (_, _) => false)
      ..register(
        CommandDefinition(
          id: 'hrm.leave.approve',
          label: 'Aprobar ausencia',
          description: 'Aprobar',
          icon: Icons.check,
          color: Colors.green,
          moduleId: 'hrm',
          requiredAction: AppAction.approve,
          handler: (_, _) {},
        ),
      );
    const signal = Signal(
      id: 'hrm.leave.pending.12',
      source: 'hrm.pendingForApproval',
      priority: SignalPriority.high,
      title: 'Ausencia pendiente',
      description: 'Revisión requerida',
      commandId: 'hrm.leave.approve',
    );
    final action = RecordCardAction(
      id: signal.id,
      label: signal.suggestedAction ?? 'Aprobar ausencia',
      icon: Icons.check,
      commandId: signal.commandId,
      registry: registry,
      commandContext: signal.commandContext,
    );

    expect(action.isVisible(), isFalse);
  });
}

class _FailingSource implements SignalSource {
  @override
  String get id => 'failing';

  @override
  Future<List<Signal>> load() async => throw StateError('source unavailable');
}

MoneyValue _zeroMoney() => MoneyValue(
  minorUnits: 0,
  currency: Currency(code: 'COP', name: 'Peso colombiano', symbol: r'$'),
);
