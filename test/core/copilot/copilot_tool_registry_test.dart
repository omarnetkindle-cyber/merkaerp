import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/copilot/copilot_models.dart';
import 'package:merka_erp/core/copilot/copilot_tool_registry.dart';

void main() {
  const restricted = CopilotIdentity(
    userId: 'USR-1',
    userName: 'Consulta',
    role: 'consulta',
    allowedModuleIds: {'inventory'},
  );

  test('oculta y rechaza herramientas fuera del RBAC', () async {
    final registry = CopilotToolRegistry()
      ..register(
        CopilotToolDefinition(
          id: 'sales_today',
          description: 'Ventas de hoy',
          moduleId: 'sales',
          handler: (_, _) async => const CopilotResponse(
            intent: 'sales_today',
            text: r'$99.999',
            provider: 'tool',
          ),
        ),
      )
      ..register(
        CopilotToolDefinition(
          id: 'critical_stock',
          description: 'Stock critico',
          moduleId: 'inventory',
          handler: (_, _) async => const CopilotResponse(
            intent: 'critical_stock',
            text: 'Sin alertas',
            provider: 'tool',
          ),
        ),
      );

    expect(registry.available(restricted).map((tool) => tool.id), [
      'critical_stock',
    ]);
    await expectLater(
      registry.execute(const CopilotToolCall(name: 'sales_today'), restricted),
      throwsA(isA<StateError>()),
    );
  });
}
