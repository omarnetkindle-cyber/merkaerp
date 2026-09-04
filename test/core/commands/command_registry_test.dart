import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/core/commands/command_registry.dart';
import 'package:merka_erp/core/security/action_permission.dart';

CommandDefinition _definition({
  required String id,
  required String label,
  required CommandHandler handler,
  bool contextual = false,
  String? contextType,
  String? actionKey,
  int priority = 0,
}) => CommandDefinition(
  id: id,
  label: label,
  description: label,
  icon: Icons.flash_on,
  color: Colors.blue,
  moduleId: 'test',
  handler: handler,
  requiredAction: AppAction.view,
  contextual: contextual,
  contextType: contextType,
  actionKey: actionKey,
  priority: priority,
);

void main() {
  test('prioriza comandos del registro activo', () {
    final registry = CommandRegistry();
    registry.register(
      _definition(
        id: 'generic.open',
        label: 'Abrir modulo',
        handler: (_, _) {},
        priority: 10,
      ),
    );
    registry.register(
      _definition(
        id: 'record.approve',
        label: 'Aprobar registro',
        handler: (_, _) {},
        contextual: true,
        contextType: 'record',
        actionKey: 'approve',
        priority: 1,
      ),
    );

    expect(registry.available(), hasLength(1));
    registry.setContext(
      const CommandContext(
        moduleId: 'test',
        recordType: 'record',
        recordId: '42',
        actions: {'approve': _noopHandler},
      ),
    );

    final commands = registry.available();
    expect(commands.map((command) => command.id), <String>[
      'record.approve',
      'generic.open',
    ]);
  });

  testWidgets('filtra y bloquea ejecucion por RBAC', (tester) async {
    var executed = false;
    final registry =
        CommandRegistry(
            authorization: (command, _) => command.id != 'restricted',
          )
          ..register(
            _definition(
              id: 'allowed',
              label: 'Accion permitida',
              handler: (_, _) => executed = true,
            ),
          )
          ..register(
            _definition(
              id: 'restricted',
              label: 'Accion restringida',
              handler: (_, _) => fail('Un comando oculto no debe ejecutarse'),
            ),
          );

    late BuildContext buildContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            buildContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(registry.available().map((command) => command.id), <String>[
      'allowed',
    ]);
    await registry.execute('allowed', buildContext);
    expect(executed, isTrue);
    await expectLater(
      registry.execute('restricted', buildContext),
      throwsStateError,
    );
  });
}

Future<void> _noopHandler(BuildContext context, CommandContext command) async {}
