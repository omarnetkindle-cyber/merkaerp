import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/app_session.dart';
import 'package:merka_erp/core/copilot/copilot_models.dart';
import 'package:merka_erp/core/copilot/copilot_orchestrator.dart';
import 'package:merka_erp/features/module_definition.dart';
import 'package:merka_erp/services/merka_intelligence_service.dart';
import 'package:merka_erp/ui/copilot_panel.dart';

class _FakeOrchestrator extends CopilotOrchestrator {
  @override
  Future<void> auditAction({
    required CopilotActionProposal action,
    required CopilotIdentity identity,
    required String outcome,
  }) async {}

  @override
  Future<List<OperationalAlert>> authorizedAlerts(
    CopilotIdentity identity,
  ) async => [];

  @override
  Future<CopilotResponse> respond({
    required String prompt,
    required CopilotIdentity identity,
    List<CopilotConversationTurn> history = const [],
  }) async => const CopilotResponse(
    intent: 'prepare_sale',
    text: 'Borrador listo para preparar.',
    provider: 'deterministic',
    actions: [
      CopilotActionProposal(
        id: 'prepare.sale',
        label: 'Preparar en Ventas',
        kind: CopilotActionKind.prepareSale,
        moduleId: 'sales',
        arguments: {'query': 'Cafe'},
        requiresConfirmation: true,
      ),
    ],
  );
}

void main() {
  setUp(() {
    AppSession.iniciar({
      'id': 'USR-1',
      'nombre': 'Omar QA',
      'rol': 'administrador',
    });
  });

  tearDown(AppSession.cerrar);

  testWidgets('una accion sensible no se ejecuta antes de confirmar', (
    tester,
  ) async {
    var prepared = false;
    final sales = ModuleDefinition(
      id: 'sales',
      title: 'Ventas',
      icon: Icons.point_of_sale,
      color: Colors.blue,
      category: ModuleCategory.operation,
      builder: (_) => const SizedBox(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CopilotPanel(
            modules: [sales],
            orchestrator: _FakeOrchestrator(),
            onClose: () {},
            onNavigateToModule: (_) {},
            onLoadSaleProduct: (_) => prepared = true,
            onLoadClientPayment: () {},
            onLoadPurchaseOrder: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'vender Cafe');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    expect(prepared, isFalse);
    await tester.tap(find.text('Preparar en Ventas'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar accion'), findsOneWidget);
    expect(prepared, isFalse);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(prepared, isTrue);
  });
}
