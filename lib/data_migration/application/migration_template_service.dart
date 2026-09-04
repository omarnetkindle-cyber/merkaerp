import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/migration_models.dart';

class MigrationTemplateService {
  const MigrationTemplateService();

  Future<File> createTemplate(MigrationEntityDefinition entity) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'migracion', 'plantillas'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'plantilla_${entity.key}.xlsx'));

    final excel = Excel.createExcel();
    final sheet = excel['Datos'];
    sheet.appendRow(entity.fields.map((field) => TextCellValue(field.label)).toList());
    sheet.appendRow(entity.fields.map((field) => TextCellValue(_example(field))).toList());

    final help = excel['Instrucciones'];
    help.appendRow([
      TextCellValue('Campo'),
      TextCellValue('Obligatorio'),
      TextCellValue('Tipo'),
      TextCellValue('Descripción / equivalencias'),
    ]);
    for (final field in entity.fields) {
      help.appendRow([
        TextCellValue(field.label),
        TextCellValue(field.required ? 'Sí' : 'No'),
        TextCellValue(field.type.name),
        TextCellValue([
          if (field.description != null && field.description!.trim().isNotEmpty) field.description!,
          if (field.aliases.isNotEmpty) 'También se reconoce: ${field.aliases.join(', ')}',
        ].join(' · ')),
      ]);
    }
    help.appendRow([TextCellValue('')]);
    help.appendRow([
      TextCellValue('Nota'),
      TextCellValue('La plantilla es opcional. MerkaERP también puede leer la exportación original y mapear sus columnas sin modificarla.'),
    ]);

    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Datos' && defaultSheet != 'Instrucciones') {
      excel.delete(defaultSheet);
    }
    final bytes = excel.encode();
    if (bytes == null) throw StateError('No fue posible generar la plantilla Excel.');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _example(MigrationFieldDefinition field) {
    return switch (field.type) {
      MigrationFieldType.money => '100000.00',
      MigrationFieldType.integer => '2026',
      MigrationFieldType.decimal => '10.5',
      MigrationFieldType.date => '2026-08-17',
      MigrationFieldType.email => 'correo@empresa.com',
      MigrationFieldType.boolean => 'Sí',
      MigrationFieldType.text => field.required ? 'Ejemplo' : '',
    };
  }
}
