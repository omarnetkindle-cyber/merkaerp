import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/release/release_readiness.dart';
import 'package:merka_erp/core/security/action_permission.dart';
import 'package:merka_erp/core/security/enterprise_security_policy.dart';
import 'package:merka_erp/inventory/application/inventory_control_service.dart';
import 'package:merka_erp/inventory/domain/product.dart';
import 'package:merka_erp/purchases/domain/procurement_workflow.dart';
import 'package:merka_erp/sales/domain/sales_workflow.dart';

import 'support/test_money.dart';

void main() {
  group('Complementos ERP', () {
    test('calcula reposicion y costo promedio ponderado', () {
      const service = InventoryControlService(reorderPoint: 5, targetStock: 20);
      final report = service.analyze([
        Product(
          id: 1,
          name: 'Pan',
          unit: 'und',
          stock: 3,
          cost: testMoney('1000'),
          price: testMoney('1500'),
          taxRate: 0,
        ),
      ]);

      expect(report.suggestions.single.recommendedQuantity, 17);
      expect(
        service.weightedAverageCost(
          currentStock: 10,
          currentCost: testMoney('1000'),
          incomingQuantity: 10,
          incomingCost: testMoney('1400'),
        ),
        testMoney('1200'),
      );
    });

    test('construye flujo empresarial de compras', () {
      const workflow = ProcurementWorkflowService();
      final steps = workflow.build(
        const ProcurementSnapshot(requested: true, approved: true),
      );

      expect(steps.first.status, WorkflowStepStatus.completed);
      expect(
        steps
            .firstWhere((step) => step.stage == ProcurementStage.purchaseOrder)
            .status,
        WorkflowStepStatus.current,
      );
    });

    test('construye flujo comercial de ventas a credito', () {
      const workflow = SalesWorkflowService();
      final steps = workflow.build(
        const SalesSnapshot(
          quoted: true,
          ordered: true,
          delivered: true,
          invoiced: true,
          creditSale: true,
        ),
      );

      expect(
        steps.firstWhere((step) => step.stage == SalesStage.receivable).status,
        SalesWorkflowStatus.current,
      );
      expect(
        steps.firstWhere((step) => step.stage == SalesStage.collection).status,
        SalesWorkflowStatus.blocked,
      );
    });

    test('release readiness bloquea produccion sin firma', () {
      const service = ReleaseReadinessService();
      final report = service.evaluate(
        releaseBuild: true,
        analyzerClean: true,
        testsPassing: true,
        databaseHealthClean: true,
      );

      expect(report.readyForProduction, isFalse);
      expect(
        report.blockingIssues.map((check) => check.id),
        contains('production_signature'),
      );
    });

    test('seguridad expone matriz y acciones sensibles', () {
      final policy = EnterpriseSecurityPolicyService();
      final matrix = policy.matrix();

      expect(matrix.map((profile) => profile.role), contains('administrador'));
      expect(policy.sensitiveActions().first.action, AppAction.cancel);
    });
  });
}
