import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/crm/application/crm_opportunity_service.dart';
import 'package:merka_erp/crm/domain/crm_opportunity.dart';
import 'package:merka_erp/crm/pages/crm_pipeline_page.dart';

class _FakeOpportunityService extends CrmOpportunityService {
  _FakeOpportunityService(this.items);

  final List<CrmOpportunity> items;
  final moves = <String>[];

  @override
  Future<List<CrmOpportunity>> list() async => items;

  @override
  Future<void> moveToStage(String id, CrmSalesStage next) async {
    moves.add('$id:${next.value}');
  }
}

void main() {
  testWidgets('el pipeline muestra tarjetas arrastrables e indicadores', (
    tester,
  ) async {
    final cop = Currency(
      code: 'COP',
      name: 'Peso colombiano',
      symbol: r'$',
      decimalPlaces: 2,
    );
    final service = _FakeOpportunityService([
      CrmOpportunity(
        id: 'crm-ui-1',
        companyId: 1,
        accountId: 7,
        accountName: 'Cuenta UI',
        name: 'Oportunidad UI',
        amount: MoneyValue.fromMajorUnits('1250.50', currency: cop),
        salesStage: CrmSalesStage.prospecting,
        nextFollowUpAt: DateTime(2026, 8, 20),
        assignedUserId: 42,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: CrmPipelinePage(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Oportunidad UI'), findsOneWidget);
    expect(find.text(r'$125050'), findsNothing);
    expect(find.text(r'$1250.50'), findsOneWidget);
    expect(find.text('10% probable'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Draggable<CrmOpportunity>), findsOneWidget);
    expect(find.byType(DragTarget<CrmOpportunity>), findsNWidgets(7));
  });
}
