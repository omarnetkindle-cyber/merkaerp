import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/evidence/evidence_capsule_service.dart';
import 'package:merka_erp/ui/widgets/expandable_record_card.dart';

void main() {
  testWidgets('una tarjeta UI-3 expone la accion reutilizable de evidencia', (
    tester,
  ) async {
    var exported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableRecordCard(
            evidenceRequest: const EvidenceRequest(
              domain: 'contabilidad',
              recordType: 'asiento_contable_publico',
              recordId: 'A-1',
            ),
            onEvidenceRequested: (_) async => exported = true,
            criticalFields: const [
              RecordCardField(label: 'Asiento', value: 'A-1'),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Exportar evidencia'));
    await tester.pump();
    expect(exported, isTrue);
  });
}
