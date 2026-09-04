import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/hrm/pages/hrm_leave_approval_page.dart';

void main() {
  testWidgets('la bandeja de aprobaciones queda cerrada sin permiso', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: HrmLeaveApprovalPage(canApprove: false)),
    );

    expect(
      find.text('No tienes permiso para aprobar solicitudes de ausencia.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.cancel), findsNothing);
  });
}
