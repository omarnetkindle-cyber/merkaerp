import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/db_helper.dart';

class _Reference {
  const _Reference(this.file, this.line, this.table, this.column, this.kind);

  final String file;
  final int line;
  final String table;
  final String column;
  final String kind;
}

final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final _whereColumn = RegExp(
  r'(?<![A-Za-z0-9_$])([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|\bIS\b|\bIN\b|\bLIKE\b|>|<)',
  caseSensitive: false,
);
const _sqlKeywords = {
  'AND',
  'OR',
  'NOT',
  'NULL',
  'IS',
  'IN',
  'LIKE',
  'BETWEEN',
};

String _cleanColumn(String value) {
  var column = value.trim();
  column = column.replaceFirst(
    RegExp(r'\s+AS\s+\w+\s*$', caseSensitive: false),
    '',
  );
  column = column.split('.').last.trim();
  return column.replaceAll(RegExp(r'[\s\n\r]'), '');
}

Iterable<String> _simpleColumns(String value) sync* {
  for (final raw in value.split(',')) {
    if (raw.contains('.')) continue;
    final column = _cleanColumn(raw);
    if (_identifier.hasMatch(column)) yield column;
  }
}

Iterable<(String, String)> _qualifiedColumns(String value) sync* {
  for (final raw in value.split(',')) {
    final cleaned = raw
        .trim()
        .split(RegExp(r'\s+AS\s+', caseSensitive: false))
        .first;
    final pieces = cleaned.split('.');
    if (pieces.length != 2) continue;
    final table = pieces.first.trim();
    final column = pieces.last.trim();
    if (_identifier.hasMatch(table) && _identifier.hasMatch(column)) {
      yield (table, column);
    }
  }
}

int _lineNumber(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

void main() {
  test('las consultas estáticas referencian el esquema fresco', runAudit);
}

Future<void> runAudit() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await DatabaseHelper.resetForTests();
  final dbDirectory = await Directory.systemTemp.createTemp(
    'merka_schema_audit_',
  );
  await databaseFactory.setDatabasesPath(dbDirectory.path);
  final db = await DatabaseHelper.instance.database;
  final tableRows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  final schema = <String, Set<String>>{};
  for (final row in tableRows) {
    final table = row['name'].toString();
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    schema[table] = columns.map((column) => column['name'].toString()).toSet();
  }

  final references = <_Reference>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  for (final file in files) {
    final source = file.readAsStringSync();
    final patterns = <RegExp, String>{
      RegExp(
        r'SELECT\s+([A-Za-z0-9_.*,\s]+?)\s+FROM\s+([A-Za-z_][A-Za-z0-9_]*)',
        caseSensitive: false,
      ): 'SELECT',
      RegExp(
        r'INSERT\s+INTO\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)',
        caseSensitive: false,
      ): 'INSERT',
      RegExp(
        r'UPDATE\s+([A-Za-z_][A-Za-z0-9_]*)\s+SET\s+([^;\n]+)',
        caseSensitive: false,
      ): 'UPDATE',
    };
    for (final entry in patterns.entries) {
      for (final match in entry.key.allMatches(source)) {
        final table = entry.value == 'SELECT'
            ? match.group(2)!
            : match.group(1)!;
        final rawColumns = entry.value == 'SELECT'
            ? match.group(1)!
            : match.group(2)!;
        if (table == 'sqlite_master') continue;
        if (entry.value == 'SELECT') {
          for (final (qualifiedTable, qualifiedColumn) in _qualifiedColumns(
            rawColumns,
          )) {
            if (schema.containsKey(qualifiedTable)) {
              references.add(
                _Reference(
                  file.path,
                  _lineNumber(source, match.start),
                  qualifiedTable,
                  qualifiedColumn,
                  entry.value,
                ),
              );
            }
          }
        }
        for (final column in _simpleColumns(rawColumns)) {
          if (column == 'rowid') continue;
          references.add(
            _Reference(
              file.path,
              _lineNumber(source, match.start),
              table,
              column,
              entry.value,
            ),
          );
        }
      }
    }
    final queryStartPattern = RegExp(
      r"\.query\(\s*'([^']+)'",
      caseSensitive: false,
    );
    for (final match in queryStartPattern.allMatches(source)) {
      final end = source.indexOf(');', match.end);
      if (end < 0) continue;
      final call = source.substring(match.start, end + 2);
      final whereMatch = RegExp(
        r"where:\s*'([^']+)'",
        caseSensitive: false,
      ).firstMatch(call);
      if (whereMatch == null) continue;
      final table = match.group(1)!;
      if (!schema.containsKey(table)) continue;
      for (final columnMatch in _whereColumn.allMatches(whereMatch.group(1)!)) {
        final column = columnMatch.group(1)!;
        if (_sqlKeywords.contains(column.toUpperCase())) continue;
        references.add(
          _Reference(
            file.path,
            _lineNumber(source, match.start),
            table,
            column,
            'QUERY_WHERE',
          ),
        );
      }
    }
  }

  final discrepancies = <_Reference>[];
  for (final reference in references) {
    final columns = schema[reference.table];
    if (columns == null || !columns.contains(reference.column)) {
      discrepancies.add(reference);
    }
  }

  for (final discrepancy in discrepancies) {
    stdout.writeln(
      '${discrepancy.file}:${discrepancy.line} '
      '${discrepancy.kind} ${discrepancy.table}.${discrepancy.column} '
      'no existe en el esquema actual',
    );
  }
  stdout.writeln(
    'SUMMARY tables=${schema.length} references=${references.length} '
    'discrepancies=${discrepancies.length}',
  );
  final reason = discrepancies
      .map((item) => '${item.file}:${item.line} ${item.table}.${item.column}')
      .join('\n');
  await DatabaseHelper.resetForTests();
  await dbDirectory.delete(recursive: true);
  expect(discrepancies, isEmpty, reason: reason);
}
