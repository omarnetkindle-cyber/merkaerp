import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/data_migration/application/tabular_file_parser.dart';

void main() {
  group('TabularFileParser', () {
    test('lee CSV RFC4180 con saltos de línea y comillas escapadas', () async {
      final dir = await Directory.systemTemp.createTemp('merka_parser_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/clientes.csv');
      await file.writeAsString(
        'Nombre;Documento;Observacion\r\n'
        '"Empresa Uno";9001;"Linea 1\nLinea 2"\r\n'
        '"Empresa ""Dos""";9002;Normal\r\n',
        flush: true,
      );

      final datasets = await const TabularFileParser().parse(file);

      expect(datasets, hasLength(1));
      expect(datasets.single.headers, ['Nombre', 'Documento', 'Observacion']);
      expect(datasets.single.rows, hasLength(2));
      expect(datasets.single.rows.first['Observacion'], 'Linea 1\nLinea 2');
      expect(datasets.single.rows[1]['Nombre'], 'Empresa "Dos"');
    });

    test('elimina BOM UTF-8 en encabezados', () async {
      final dir = await Directory.systemTemp.createTemp('merka_parser_bom_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/terceros.csv');
      await file.writeAsBytes(utf8.encode('\uFEFFNombre;Ciudad\r\nPeña;Fundación\r\n'), flush: true);

      final datasets = await const TabularFileParser().parse(file);

      expect(datasets.single.headers.first, 'Nombre');
      expect(datasets.single.rows.single['Nombre'], 'Peña');
    });

    test('recupera exportaciones Latin-1 cuando UTF-8 estricto falla', () async {
      final dir = await Directory.systemTemp.createTemp('merka_parser_latin1_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/terceros.csv');
      await file.writeAsBytes(latin1.encode('Nombre;Ciudad\r\nPeña;Fundación\r\n'), flush: true);

      final datasets = await const TabularFileParser().parse(file);

      expect(datasets.single.rows.single['Nombre'], 'Peña');
      expect(datasets.single.rows.single['Ciudad'], 'Fundación');
    });

    test('rechaza comillas sin cerrar en archivo delimitado', () async {
      final dir = await Directory.systemTemp.createTemp('merka_parser_bad_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/malo.csv');
      await file.writeAsString('Nombre;Nota\nEmpresa;"sin cerrar\n', flush: true);

      await expectLater(
        const TabularFileParser().parse(file),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
