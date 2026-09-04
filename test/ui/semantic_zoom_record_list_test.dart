import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/ui/widgets/semantic_zoom_record_list.dart';

void main() {
  final records = [
    {'id': 1, 'status': 'Pendiente'},
    {'id': 2, 'status': 'En proceso'},
    {'id': 3, 'status': 'En proceso'},
  ];

  testWidgets('agrupa y desagrupa sin perder ni duplicar registros', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialZoom: 1));
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('En proceso'), findsOneWidget);
    expect(find.text('3'), findsNothing);

    await tester.drag(find.byType(Slider), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(find.text('Registro 1'), findsOneWidget);
    expect(find.text('Registro 2'), findsOneWidget);
    expect(find.text('Registro 3'), findsOneWidget);
    expect(find.text('Registro 4'), findsNothing);
  });

  testWidgets('cambiar zoom no vuelve a cargar desde la fuente', (
    tester,
  ) async {
    var loadCount = 0;
    Future<List<Map<String, Object>>> loadOnce() async {
      loadCount++;
      return records
          .map<Map<String, Object>>(
            (row) => {'id': row['id']!, 'status': row['status']!},
          )
          .toList();
    }

    final loaded = await loadOnce();
    await tester.pumpWidget(_app(records: loaded, initialZoom: 2));
    await tester.drag(find.byType(Slider), const Offset(220, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-160, 0));
    await tester.pumpAndSettle();

    expect(loadCount, 1);
  });
}

Widget _app({List<Map<String, Object>>? records, required int initialZoom}) {
  final rows =
      records ??
      [
        {'id': 1, 'status': 'Pendiente'},
        {'id': 2, 'status': 'En proceso'},
        {'id': 3, 'status': 'En proceso'},
      ];
  return MaterialApp(
    home: Scaffold(
      body: SemanticZoomRecordList<Map<String, Object>>(
        records: rows,
        initialZoom: initialZoom,
        statusOf: (row) => row['status']!.toString(),
        itemBuilder: (context, row, {required initiallyExpanded}) =>
            ListTile(title: Text('Registro ${row['id']}')),
      ),
    ),
  );
}
