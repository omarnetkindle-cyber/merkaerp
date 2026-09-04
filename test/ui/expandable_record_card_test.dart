import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/core/commands/command_registry.dart';
import 'package:merka_erp/core/security/action_permission.dart';
import 'package:merka_erp/ui/widgets/expandable_record_card.dart';

CommandDefinition _command(
  String id,
  String label, {
  VoidCallback? onExecute,
}) => CommandDefinition(
  id: id,
  label: label,
  description: label,
  icon: Icons.flash_on,
  color: Colors.blue,
  moduleId: 'test',
  requiredAction: AppAction.view,
  handler: (_, _) => onExecute?.call(),
);

void main() {
  testWidgets('muestra campos criticos y expande detalles en el sitio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableRecordCard(
            criticalFields: const [
              RecordCardField(label: 'Estado', value: 'Pendiente'),
              RecordCardField(label: 'Monto', value: '\$ 100'),
            ],
            secondaryFields: const [
              RecordCardField(label: 'Vigencia', value: '2026'),
              RecordCardField(label: 'Acto', value: 'Resolución 10'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Estado'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Vigencia'), findsNothing);

    await tester.tap(find.byTooltip('Expandir detalles'));
    await tester.pumpAndSettle();
    expect(find.text('Vigencia'), findsOneWidget);
    expect(find.text('Resolución 10'), findsOneWidget);

    await tester.tap(find.byTooltip('Contraer detalles'));
    await tester.pumpAndSettle();
    expect(find.text('Vigencia'), findsNothing);
  });

  testWidgets('oculta acciones sin autorización y muestra las permitidas', (
    tester,
  ) async {
    var executed = false;
    final registry = CommandRegistry(
      authorization: (command, _) => command.id != 'blocked',
    )
      ..register(
        _command(
          'allowed',
          'Acción permitida',
          onExecute: () => executed = true,
        ),
      )
      ..register(_command('blocked', 'Acción bloqueada'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableRecordCard(
            criticalFields: const [
              RecordCardField(label: 'Registro', value: '42'),
            ],
            actions: [
              RecordCardAction(
                id: 'allowed',
                label: 'Acción permitida',
                icon: Icons.check,
                registry: registry,
                commandId: 'allowed',
                onPressed: (_) async => executed = true,
              ),
              RecordCardAction(
                id: 'blocked',
                label: 'Acción bloqueada',
                icon: Icons.block,
                registry: registry,
                commandId: 'blocked',
                onPressed: (_) async => fail('No debe exponerse'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byTooltip('Acción permitida'), findsOneWidget);
    expect(find.byTooltip('Acción bloqueada'), findsNothing);
    await tester.tap(find.byTooltip('Acción permitida'));
    await tester.pump();
    expect(executed, isTrue);
  });

  testWidgets('ejecuta una acción directa visible desde la tarjeta', (
    tester,
  ) async {
    var executed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableRecordCard(
            criticalFields: const [
              RecordCardField(label: 'Registro', value: '42'),
            ],
            actions: [
              RecordCardAction(
                id: 'approve',
                label: 'Aprobar',
                icon: Icons.check,
                onPressed: (_) async => executed = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Aprobar'));
    await tester.pump();
    expect(executed, isTrue);
  });
}
