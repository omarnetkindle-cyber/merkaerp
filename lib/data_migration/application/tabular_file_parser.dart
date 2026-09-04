import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/migration_models.dart';

/// Lector genérico de exportaciones de sistemas legados.
///
/// Formatos soportados:
/// - CSV/TSV/TXT/PSV delimitado, con comillas RFC4180 básicas.
/// - XLSX con una fuente por hoja.
/// - JSON: lista de objetos o mapa cuyas propiedades contienen listas.
/// - SQLite (.db/.sqlite/.sqlite3): una fuente por tabla de usuario.
///
/// El lector nunca modifica la fuente. Para SQLite se abre en modo solo lectura.
class TabularFileParser {
  const TabularFileParser({this.maxRowsPerDataset = 250000});

  /// Protección contra exportaciones accidentalmente gigantes que podrían
  /// agotar la memoria de una estación de trabajo. No se trunca silenciosamente:
  /// se detiene y exige dividir/exportar la fuente.
  final int maxRowsPerDataset;

  Future<List<TabularDataset>> parse(File file) async {
    if (!await file.exists()) {
      throw StateError('El archivo seleccionado ya no existe.');
    }
    final extension = p.extension(file.path).toLowerCase();
    if (extension == '.csv' || extension == '.txt' || extension == '.tsv' || extension == '.psv') {
      return [_parseDelimited(await _readText(file), p.basenameWithoutExtension(file.path))];
    }
    if (extension == '.xlsx') {
      return _parseXlsx(await file.readAsBytes());
    }
    if (extension == '.json') {
      return _parseJson(await _readText(file), p.basenameWithoutExtension(file.path));
    }
    if (extension == '.db' || extension == '.sqlite' || extension == '.sqlite3') {
      return _parseSqlite(file);
    }
    throw UnsupportedError(
      'Formato no soportado: $extension. Usa CSV, TSV, TXT, PSV, XLSX, JSON o SQLite.',
    );
  }

  TabularDataset _parseDelimited(String content, String name) {
    if (content.trim().isEmpty) {
      return TabularDataset(name: name, headers: const [], rows: const []);
    }
    final delimiter = _detectDelimiterFromContent(content);
    final records = _parseDelimitedRecords(content, delimiter);
    if (records.isEmpty) return TabularDataset(name: name, headers: const [], rows: const []);
    if (records.length - 1 > maxRowsPerDataset) {
      throw StateError('La fuente “$name” supera $maxRowsPerDataset filas. Divide el archivo en lotes para migrarlo de forma segura.');
    }
    final headers = _uniqueHeaders(records.first);
    final rows = <Map<String, String>>[];
    for (final values in records.skip(1)) {
      final row = <String, String>{};
      for (var index = 0; index < headers.length; index++) {
        row[headers[index]] = index < values.length ? values[index].trim() : '';
      }
      if (row.values.any((value) => value.trim().isNotEmpty)) rows.add(row);
    }
    return TabularDataset(name: name, headers: headers, rows: rows);
  }

  Future<String> _readText(File file) async {
    final bytes = await file.readAsBytes();
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      // Muchos ERP/contables antiguos exportan CSV en Windows-1252/Latin-1.
      // latin1 conserva los bytes de forma determinística; el usuario puede
      // revisar el resultado en la vista previa antes de confirmar.
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  String _detectDelimiterFromContent(String content) {
    final firstRecord = _firstLogicalRecord(content);
    return _detectDelimiter(firstRecord);
  }

  String _firstLogicalRecord(String content) {
    final buffer = StringBuffer();
    var quoted = false;
    for (var index = 0; index < content.length; index++) {
      final char = content[index];
      if (char == '"') {
        if (quoted && index + 1 < content.length && content[index + 1] == '"') {
          buffer.write('""');
          index++;
          continue;
        }
        quoted = !quoted;
      }
      if (!quoted && (char == '\n' || char == '\r')) break;
      buffer.write(char);
    }
    return buffer.toString();
  }

  List<List<String>> _parseDelimitedRecords(String content, String delimiter) {
    final records = <List<String>>[];
    var record = <String>[];
    final cell = StringBuffer();
    var quoted = false;

    void finishCell() {
      record.add(cell.toString());
      cell.clear();
    }

    void finishRecord() {
      finishCell();
      if (record.any((value) => value.trim().isNotEmpty)) records.add(record);
      record = <String>[];
    }

    for (var index = 0; index < content.length; index++) {
      final char = content[index];
      if (char == '"') {
        if (quoted && index + 1 < content.length && content[index + 1] == '"') {
          cell.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
        continue;
      }
      if (!quoted && char == delimiter) {
        finishCell();
        continue;
      }
      if (!quoted && (char == '\n' || char == '\r')) {
        if (char == '\r' && index + 1 < content.length && content[index + 1] == '\n') index++;
        finishRecord();
        if (records.length > maxRowsPerDataset + 1) {
          throw StateError('La fuente supera $maxRowsPerDataset filas. Divídela en lotes para migrarla de forma segura.');
        }
        continue;
      }
      cell.write(char);
    }
    if (quoted) {
      throw const FormatException('El archivo delimitado contiene una comilla sin cerrar.');
    }
    if (cell.isNotEmpty || record.isNotEmpty) finishRecord();
    return records;
  }

  List<TabularDataset> _parseXlsx(List<int> bytes) {
    final workbook = Excel.decodeBytes(bytes);
    final result = <TabularDataset>[];
    for (final entry in workbook.tables.entries) {
      final table = entry.value;
      if (table.rows.isEmpty) continue;
      if (table.rows.length - 1 > maxRowsPerDataset) {
        throw StateError('La hoja “${entry.key}” supera $maxRowsPerDataset filas. Divídela en lotes para migrarla de forma segura.');
      }
      final headerCells = table.rows.first;
      final headers = _uniqueHeaders(headerCells.asMap().entries.map((entry) {
        final raw = entry.value?.value?.toString().trim() ?? '';
        return raw.isEmpty ? 'columna_${entry.key + 1}' : raw;
      }).toList());
      final rows = <Map<String, String>>[];
      for (final cells in table.rows.skip(1)) {
        final row = <String, String>{};
        for (var index = 0; index < headers.length; index++) {
          row[headers[index]] = index < cells.length
              ? cells[index]?.value?.toString().trim() ?? ''
              : '';
        }
        if (row.values.any((value) => value.trim().isNotEmpty)) rows.add(row);
      }
      result.add(TabularDataset(name: entry.key, headers: headers, rows: rows));
    }
    return result;
  }

  List<TabularDataset> _parseJson(String content, String fallbackName) {
    final decoded = jsonDecode(content);
    if (decoded is List) {
      return [_datasetFromJsonList(fallbackName, decoded)];
    }
    if (decoded is Map) {
      final datasets = <TabularDataset>[];
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List) {
          datasets.add(_datasetFromJsonList(entry.key.toString(), value));
        }
      }
      if (datasets.isNotEmpty) return datasets;
      return [_datasetFromJsonList(fallbackName, [decoded])];
    }
    throw const FormatException('El JSON debe contener objetos o listas de objetos.');
  }

  TabularDataset _datasetFromJsonList(String name, List<dynamic> values) {
    if (values.length > maxRowsPerDataset) {
      throw StateError('La colección “$name” supera $maxRowsPerDataset registros. Divídela en lotes para migrarla de forma segura.');
    }
    final maps = values.whereType<Map>().map((row) => Map<Object?, Object?>.from(row)).toList();
    if (maps.isEmpty) return TabularDataset(name: name, headers: const [], rows: const []);
    final headerSet = <String>{};
    for (final row in maps) {
      for (final key in row.keys) {
        headerSet.add(_cleanHeader(key?.toString() ?? 'columna'));
      }
    }
    final headers = _uniqueHeaders(headerSet.toList());
    final rows = <Map<String, String>>[];
    for (final source in maps) {
      final normalized = <String, String>{};
      for (final header in headers) {
        Object? value;
        for (final entry in source.entries) {
          if (_cleanHeader(entry.key?.toString() ?? '') == header || entry.key?.toString() == header) {
            value = entry.value;
            break;
          }
        }
        normalized[header] = _jsonCell(value);
      }
      if (normalized.values.any((value) => value.trim().isNotEmpty)) rows.add(normalized);
    }
    return TabularDataset(name: name, headers: headers, rows: rows);
  }

  Future<List<TabularDataset>> _parseSqlite(File file) async {
    Database? source;
    try {
      source = await openDatabase(file.path, readOnly: true, singleInstance: false);
      final tableRows = await source.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final result = <TabularDataset>[];
      for (final row in tableRows) {
        final table = row['name']?.toString() ?? '';
        if (!_safeSqlIdentifier(table)) continue;
        final count = Sqflite.firstIntValue(await source.rawQuery('SELECT COUNT(*) FROM "$table"')) ?? 0;
        if (count > maxRowsPerDataset) {
          throw StateError('La tabla “$table” contiene $count filas y supera el límite seguro de $maxRowsPerDataset. Expórtala o divídela en lotes.');
        }
        final pragma = await source.rawQuery('PRAGMA table_info("$table")');
        final headers = _uniqueHeaders(
          pragma.map((column) => column['name']?.toString() ?? 'columna').toList(),
        );
        if (headers.isEmpty) continue;
        final rawRows = await source.rawQuery('SELECT * FROM "$table"');
        final rows = <Map<String, String>>[];
        for (final raw in rawRows) {
          final normalized = <String, String>{};
          for (final header in headers) {
            normalized[header] = _sqliteCell(raw[header]);
          }
          if (normalized.values.any((value) => value.trim().isNotEmpty)) rows.add(normalized);
        }
        result.add(TabularDataset(name: table, headers: headers, rows: rows));
      }
      if (result.isEmpty) {
        throw StateError('La base SQLite no contiene tablas de usuario legibles.');
      }
      return result;
    } finally {
      await source?.close();
    }
  }

  String _jsonCell(Object? value) {
    if (value == null) return '';
    if (value is String || value is num || value is bool) return value.toString();
    return jsonEncode(value);
  }

  String _sqliteCell(Object? value) {
    if (value == null) return '';
    if (value is List<int>) return base64Encode(value);
    return value.toString();
  }

  String _detectDelimiter(String line) {
    const candidates = [',', ';', '\t', '|'];
    var best = ',';
    var bestCount = -1;
    for (final candidate in candidates) {
      final count = _parseLine(line, candidate).length;
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }
    return best;
  }

  List<String> _parseLine(String line, String delimiter) {
    final values = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var index = 0; index < line.length; index++) {
      final char = line[index];
      if (char == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          current.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && char == delimiter) {
        values.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    values.add(current.toString());
    return values;
  }

  List<String> _uniqueHeaders(List<String> rawHeaders) {
    final counts = <String, int>{};
    return rawHeaders.asMap().entries.map((entry) {
      final base = _cleanHeader(entry.value.isEmpty ? 'columna_${entry.key + 1}' : entry.value);
      final count = (counts[base] ?? 0) + 1;
      counts[base] = count;
      return count == 1 ? base : '${base}_$count';
    }).toList();
  }

  String _cleanHeader(String value) {
    final trimmed = value.replaceFirst('\uFEFF', '').trim();
    return trimmed.isEmpty ? 'columna' : trimmed;
  }

  bool _safeSqlIdentifier(String value) => RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
}
