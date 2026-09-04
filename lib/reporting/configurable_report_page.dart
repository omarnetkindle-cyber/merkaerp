import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sqflite/sqflite.dart';

import '../db_helper.dart';

class ConfigurableReportPage extends StatefulWidget {
  const ConfigurableReportPage({super.key});

  @override
  State<ConfigurableReportPage> createState() => _ConfigurableReportPageState();
}

class _ConfigurableReportPageState extends State<ConfigurableReportPage> {
  static const _sources = <String, String>{
    'ventas': 'Ventas',
    'ventas_detalle': 'Detalle de ventas',
    'compras': 'Compras',
    'compras_detalle': 'Detalle de compras',
    'productos': 'Inventario / productos',
    'clientes': 'Clientes',
    'proveedores': 'Proveedores',
    'movimientos_caja': 'Movimientos de caja',
    'cuentas_por_cobrar': 'Cuentas por cobrar',
    'cuentas_por_pagar': 'Cuentas por pagar',
    'auditoria_eventos': 'Auditoría',
  };

  String _source = 'ventas';
  List<_ColumnInfo> _columns = [];
  final Set<String> _selectedFields = {};
  final Set<String> _totalFields = {};
  String? _filterField;
  final _filterValue = TextEditingController();
  String? _groupField;
  String? _orderField;
  bool _descending = true;
  bool _loading = false;
  List<Map<String, Object?>> _rows = [];
  List<Map<String, Object?>> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadSource();
    _loadSaved();
  }

  @override
  void dispose() {
    _filterValue.dispose();
    super.dispose();
  }

  Future<void> _ensureSchema() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_report_definitions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        definition_json TEXT NOT NULL,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, name)
      )
    ''');
  }

  Future<void> _loadSaved() async {
    await _ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final rows = await db.query(
      'saved_report_definitions',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'name',
    );
    if (mounted) setState(() => _saved = rows);
  }

  Future<void> _loadSource() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;
    final pragma = await db.rawQuery('PRAGMA table_info($_source)');
    final columns = pragma
        .map(
          (row) => _ColumnInfo(
            name: row['name'].toString(),
            type: row['type']?.toString().toUpperCase() ?? '',
          ),
        )
        .where((c) => c.name != 'company_id')
        .toList();
    final preferred = columns
        .where((c) => const {'id', 'fecha', 'nombre', 'total', 'saldo', 'estado', 'producto', 'cliente', 'proveedor'}.contains(c.name))
        .map((c) => c.name)
        .take(6)
        .toSet();
    if (mounted) {
      setState(() {
        _columns = columns;
        _selectedFields
          ..clear()
          ..addAll(preferred.isEmpty ? columns.take(5).map((c) => c.name) : preferred);
        _totalFields
          ..clear()
          ..addAll(_selectedFields.where((name) => columns.any((c) => c.name == name && c.numeric)));
        _filterField = null;
        _groupField = null;
        _orderField = columns.any((c) => c.name == 'fecha') ? 'fecha' : (columns.isEmpty ? null : columns.first.name);
        _rows = [];
        _loading = false;
      });
    }
  }

  Future<void> _run() async {
    if (_selectedFields.isEmpty) {
      _message('Selecciona al menos un campo.');
      return;
    }
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      final allowed = _columns.map((c) => c.name).toSet();
      final fields = _selectedFields.where(allowed.contains).toList();
      final group = _groupField != null && allowed.contains(_groupField) ? _groupField : null;
      final numeric = fields
          .where((f) => _column(f)?.numeric == true && _totalFields.contains(f))
          .toList();
      final select = group == null
          ? fields.map(_quote).join(', ')
          : [
              _quote(group),
              for (final field in numeric) 'SUM(${_quote(field)}) AS ${_quote(field)}',
              'COUNT(*) AS "registros"',
            ].join(', ');
      var sql = 'SELECT $select FROM ${_quote(_source)} WHERE company_id = ?';
      final args = <Object?>[companyId];
      final filter = _filterValue.text.trim();
      if (_filterField != null && allowed.contains(_filterField) && filter.isNotEmpty) {
        final column = _column(_filterField!);
        if (column?.numeric == true) {
          final number = num.tryParse(filter.replaceAll(',', '.'));
          if (number == null) throw ArgumentError('El filtro numérico no es válido.');
          sql += ' AND ${_quote(_filterField!)} = ?';
          args.add(number);
        } else {
          sql += ' AND CAST(${_quote(_filterField!)} AS TEXT) LIKE ?';
          args.add('%$filter%');
        }
      }
      if (group != null) sql += ' GROUP BY ${_quote(group)}';
      final order = _orderField != null && (group == null ? fields.contains(_orderField) : (_orderField == group || numeric.contains(_orderField)))
          ? _orderField
          : (group ?? fields.first);
      sql += ' ORDER BY ${_quote(order!)} ${_descending ? 'DESC' : 'ASC'} LIMIT 5000';
      final rows = await db.rawQuery(sql, args);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _ColumnInfo? _column(String name) {
    for (final column in _columns) {
      if (column.name == name) return column;
    }
    return null;
  }

  String _quote(String identifier) {
    final allowed = {..._sources.keys, ..._columns.map((c) => c.name), 'registros'};
    if (!allowed.contains(identifier)) throw StateError('Identificador de reporte no permitido.');
    return '"${identifier.replaceAll('"', '""')}"';
  }

  Future<void> _saveDefinition() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar reporte'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del reporte'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final now = DateTime.now().toIso8601String();
    final definition = jsonEncode({
      'source': _source,
      'fields': _selectedFields.toList(),
      'total_fields': _totalFields.toList(),
      'filter_field': _filterField,
      'filter_value': _filterValue.text,
      'group_field': _groupField,
      'order_field': _orderField,
      'descending': _descending,
    });
    await db.insert(
      'saved_report_definitions',
      {
        'company_id': companyId,
        'name': name,
        'definition_json': definition,
        'created_by': 'local',
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'GUARDAR_REPORTE_CONFIGURABLE',
      entidad: 'saved_report_definitions',
      detalle: name,
    );
    await _loadSaved();
  }

  Future<void> _loadDefinition(Map<String, Object?> row) async {
    final raw = jsonDecode(row['definition_json'].toString()) as Map<String, dynamic>;
    final source = raw['source']?.toString();
    if (source == null || !_sources.containsKey(source)) return;
    _source = source;
    await _loadSource();
    final allowed = _columns.map((c) => c.name).toSet();
    final fields = (raw['fields'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where(allowed.contains)
        .toSet();
    final totalFields = (raw['total_fields'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((name) => allowed.contains(name) && _column(name)?.numeric == true)
        .toSet();
    setState(() {
      _selectedFields
        ..clear()
        ..addAll(fields);
      _totalFields
        ..clear()
        ..addAll(totalFields);
      _filterField = allowed.contains(raw['filter_field']) ? raw['filter_field']?.toString() : null;
      _filterValue.text = raw['filter_value']?.toString() ?? '';
      _groupField = allowed.contains(raw['group_field']) ? raw['group_field']?.toString() : null;
      _orderField = allowed.contains(raw['order_field']) ? raw['order_field']?.toString() : _orderField;
      _descending = raw['descending'] != false;
    });
  }

  List<String> get _resultColumns => _rows.isEmpty ? _selectedFields.toList() : _rows.first.keys.toList();

  Map<String, num> get _resultTotals {
    final totals = <String, num>{};
    for (final field in _totalFields) {
      if (!_resultColumns.contains(field)) continue;
      num total = 0;
      var found = false;
      for (final row in _rows) {
        final value = row[field];
        if (value is num) {
          total += value;
          found = true;
        } else if (value != null) {
          final parsed = num.tryParse(value.toString());
          if (parsed != null) {
            total += parsed;
            found = true;
          }
        }
      }
      if (found) totals[field] = total;
    }
    return totals;
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar reporte Excel',
      fileName: 'reporte_${_source}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      allowedExtensions: ['xlsx'],
      type: FileType.custom,
    );
    if (path == null) return;
    final book = xls.Excel.createExcel();
    final sheet = book['Reporte'];
    final columns = _resultColumns;
    sheet.appendRow(columns.map((e) => xls.TextCellValue(_label(e))).toList());
    for (final row in _rows) {
      sheet.appendRow(
        columns.map((c) => xls.TextCellValue(row[c]?.toString() ?? '')).toList(),
      );
    }
    final totals = _resultTotals;
    if (totals.isNotEmpty) {
      sheet.appendRow([
        for (var i = 0; i < columns.length; i++)
          xls.TextCellValue(
            i == 0 ? 'TOTAL' : (totals[columns[i]]?.toString() ?? ''),
          ),
      ]);
    }
    final bytes = book.encode();
    if (bytes == null) throw StateError('No se pudo generar el Excel.');
    await File(path).writeAsBytes(bytes, flush: true);
    _message('Excel guardado correctamente.');
  }

  Future<Uint8List> _pdfBytes() async {
    final doc = pw.Document();
    final columns = _resultColumns;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) => [
          pw.Text('MerkaERP · ${_sources[_source]}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: columns.map(_label).toList(),
            data: [
              for (final row in _rows)
                [for (final c in columns) row[c]?.toString() ?? ''],
              if (_resultTotals.isNotEmpty)
                [
                  for (var i = 0; i < columns.length; i++)
                    i == 0 ? 'TOTAL' : (_resultTotals[columns[i]]?.toString() ?? ''),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> _printPdf() async {
    if (_rows.isEmpty) return;
    await Printing.layoutPdf(onLayout: (_) => _pdfBytes());
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _label(String field) => field.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diseñador de reportes'),
        actions: [
          IconButton(tooltip: 'Guardar definición', onPressed: _saveDefinition, icon: const Icon(Icons.save_outlined)),
          PopupMenuButton<int>(
            tooltip: 'Reportes guardados',
            icon: const Icon(Icons.folder_open),
            itemBuilder: (_) => [
              for (var i = 0; i < _saved.length; i++)
                PopupMenuItem(value: i, child: Text(_saved[i]['name'].toString())),
            ],
            onSelected: (index) => _loadDefinition(_saved[index]),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _source,
                                decoration: const InputDecoration(labelText: 'Origen'),
                                items: [
                                  for (final entry in _sources.entries)
                                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                                ],
                                onChanged: (value) async {
                                  if (value == null) return;
                                  _source = value;
                                  await _loadSource();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: _groupField,
                                decoration: const InputDecoration(labelText: 'Agrupar por (opcional)'),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Sin agrupación')),
                                  for (final c in _columns)
                                    DropdownMenuItem<String?>(value: c.name, child: Text(_label(c.name))),
                                ],
                                onChanged: (value) => setState(() => _groupField = value),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: _orderField,
                                decoration: const InputDecoration(labelText: 'Ordenar por'),
                                items: [
                                  for (final c in _columns)
                                    DropdownMenuItem<String?>(value: c.name, child: Text(_label(c.name))),
                                ],
                                onChanged: (value) => setState(() => _orderField = value),
                              ),
                            ),
                            IconButton(
                              tooltip: _descending ? 'Orden descendente' : 'Orden ascendente',
                              onPressed: () => setState(() => _descending = !_descending),
                              icon: Icon(_descending ? Icons.arrow_downward : Icons.arrow_upward),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final column in _columns)
                                FilterChip(
                                  label: Text(_label(column.name)),
                                  selected: _selectedFields.contains(column.name),
                                  onSelected: (selected) => setState(() {
                                    if (selected) {
                                      _selectedFields.add(column.name);
                                    } else {
                                      _selectedFields.remove(column.name);
                                      _totalFields.remove(column.name);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Totales', style: Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final column in _columns.where((c) => c.numeric && _selectedFields.contains(c.name)))
                                    FilterChip(
                                      avatar: const Icon(Icons.functions, size: 16),
                                      label: Text(_label(column.name)),
                                      selected: _totalFields.contains(column.name),
                                      onSelected: (selected) => setState(() {
                                        if (selected) {
                                          _totalFields.add(column.name);
                                        } else {
                                          _totalFields.remove(column.name);
                                        }
                                      }),
                                    ),
                                ],
                              ),
                              if (_groupField != null)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Al agrupar, los campos marcados se suman por grupo. Sin agrupación, se muestran como totales generales.',
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: _filterField,
                                decoration: const InputDecoration(labelText: 'Campo a filtrar'),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Sin filtro')),
                                  for (final c in _columns)
                                    DropdownMenuItem<String?>(value: c.name, child: Text(_label(c.name))),
                                ],
                                onChanged: (value) => setState(() => _filterField = value),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _filterValue,
                                enabled: _filterField != null,
                                decoration: const InputDecoration(labelText: 'Valor del filtro'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(onPressed: _run, icon: const Icon(Icons.play_arrow), label: const Text('Generar')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('${_rows.length} fila(s)'),
                      const Spacer(),
                      OutlinedButton.icon(onPressed: _rows.isEmpty ? null : _exportExcel, icon: const Icon(Icons.table_view), label: const Text('Excel')),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(onPressed: _rows.isEmpty ? null : _printPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF / Imprimir')),
                    ],
                  ),
                ),
                if (_rows.isNotEmpty && _resultTotals.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in _resultTotals.entries)
                            Chip(
                              avatar: const Icon(Icons.functions, size: 16),
                              label: Text('${_label(entry.key)}: ${entry.value}'),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(child: Text('Configura los campos y pulsa Generar.'))
                      : Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                columns: [for (final c in _resultColumns) DataColumn(label: Text(_label(c)))],
                                rows: [
                                  for (final row in _rows)
                                    DataRow(cells: [for (final c in _resultColumns) DataCell(Text(row[c]?.toString() ?? ''))]),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _ColumnInfo {
  const _ColumnInfo({required this.name, required this.type});
  final String name;
  final String type;

  bool get numeric => type.contains('INT') || type.contains('REAL') || type.contains('NUM') || type.contains('DEC');
}
