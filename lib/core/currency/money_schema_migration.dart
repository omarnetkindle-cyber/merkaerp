import 'package:sqflite/sqflite.dart';

import 'money_schema_manifest.g.dart';

class MoneyTableMigrationResult {
  const MoneyTableMigrationResult({
    required this.table,
    required this.columns,
    required this.rowsBefore,
    required this.rowsAfter,
    required this.alreadyMigrated,
  });

  final String table;
  final int columns;
  final int rowsBefore;
  final int rowsAfter;
  final bool alreadyMigrated;
}

class MoneySchemaMigrationResult {
  const MoneySchemaMigrationResult(this.tables);

  final List<MoneyTableMigrationResult> tables;

  int get columnCount => tables.fold(0, (sum, table) => sum + table.columns);
  int get rowCountBefore =>
      tables.fold(0, (sum, table) => sum + table.rowsBefore);
  int get rowCountAfter =>
      tables.fold(0, (sum, table) => sum + table.rowsAfter);
}

/// Migrates every monetary REAL column in the frozen v74 manifest to INTEGER.
class MoneySchemaMigration {
  static Future<MoneySchemaMigrationResult> migrateV75(
    DatabaseExecutor db,
  ) async {
    final context = await _CurrencyContext.load(db);
    final results = <MoneyTableMigrationResult>[];

    final triggers = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'trigger' "
      "AND sql IS NOT NULL ORDER BY name",
    );
    final views = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type = 'view' "
      "AND sql IS NOT NULL ORDER BY name",
    );

    await db.execute('PRAGMA defer_foreign_keys = ON');
    for (final trigger in triggers) {
      await db.execute('DROP TRIGGER ${_quote(trigger['name']! as String)}');
    }
    for (final view in views) {
      await db.execute('DROP VIEW ${_quote(view['name']! as String)}');
    }
    for (final entry in moneySchemaColumns.entries) {
      results.add(
        await _migrateTable(
          db,
          table: entry.key,
          moneyColumns: entry.value,
          currencies: context,
        ),
      );
    }
    for (final view in views) {
      await db.execute(view['sql']! as String);
    }
    for (final trigger in triggers) {
      await db.execute(trigger['sql']! as String);
    }

    if (results.fold<int>(0, (sum, item) => sum + item.columns) !=
        moneySchemaColumnCount) {
      throw StateError('Money schema manifest is incomplete');
    }

    final foreignKeyErrors = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeyErrors.isNotEmpty) {
      throw StateError('Foreign key check failed: $foreignKeyErrors');
    }
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.length != 1 || integrity.first.values.first != 'ok') {
      throw StateError('SQLite integrity check failed: $integrity');
    }

    return MoneySchemaMigrationResult(results);
  }

  static Future<MoneyTableMigrationResult> _migrateTable(
    DatabaseExecutor db, {
    required String table,
    required Set<String> moneyColumns,
    required _CurrencyContext currencies,
  }) async {
    final info = await db.rawQuery('PRAGMA table_info(${_quote(table)})');
    if (info.isEmpty) throw StateError('Manifest table does not exist: $table');

    final types = <String, String>{
      for (final column in info)
        column['name']! as String: column['type'].toString().toUpperCase(),
    };
    final missing = moneyColumns.where((column) => !types.containsKey(column));
    if (missing.isNotEmpty) {
      throw StateError('Missing monetary columns in $table: $missing');
    }

    final integerColumns = moneyColumns
        .where((column) => types[column] == 'INTEGER')
        .toSet();
    if (integerColumns.length == moneyColumns.length) {
      final count = await _rowCount(db, table);
      return MoneyTableMigrationResult(
        table: table,
        columns: moneyColumns.length,
        rowsBefore: count,
        rowsAfter: count,
        alreadyMigrated: true,
      );
    }
    final invalidTypes = moneyColumns.where(
      (column) => types[column] != 'REAL' && types[column] != 'INTEGER',
    );
    if (invalidTypes.isNotEmpty) {
      throw StateError('Unexpected monetary types in $table: $invalidTypes');
    }

    final schemaRows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    final createSql = schemaRows.single['sql']?.toString();
    if (createSql == null || createSql.isEmpty) {
      throw StateError('Missing CREATE TABLE SQL for $table');
    }
    final dependentSql = await db.rawQuery(
      "SELECT type, name, sql FROM sqlite_master "
      "WHERE tbl_name = ? AND type = 'index' "
      "AND sql IS NOT NULL ORDER BY type, name",
      [table],
    );
    final rows = await db.query(table);
    final tempTable = '__money_v75_$table';
    await db.execute('DROP TABLE IF EXISTS ${_quote(tempTable)}');
    await db.execute(_rewriteCreateTable(createSql, tempTable, moneyColumns));

    for (final sourceRow in rows) {
      final migrated = Map<String, Object?>.from(sourceRow);
      for (final column in moneyColumns) {
        final value = sourceRow[column];
        if (value == null) continue;
        if (value is! num) {
          throw StateError('$table.$column is not numeric: $value');
        }
        final currency = currencies.resolve(
          table: table,
          column: column,
          row: sourceRow,
          allowUnresolvedZero: value == 0,
        );
        migrated[column] = types[column] == 'INTEGER'
            ? value.toInt()
            : value == 0
            ? 0
            : _legacyNumberToMinorUnits(value, currency.decimalPlaces);
      }
      await db.insert(
        tempTable,
        migrated,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    final rowsBefore = rows.length;
    final rowsCopied = await _rowCount(db, tempTable);
    if (rowsCopied != rowsBefore) {
      throw StateError(
        'Row count changed while copying $table: $rowsBefore -> $rowsCopied',
      );
    }

    await db.execute('DROP TABLE ${_quote(table)}');
    await db.execute(
      'ALTER TABLE ${_quote(tempTable)} RENAME TO ${_quote(table)}',
    );
    for (final dependent in dependentSql) {
      await db.execute(dependent['sql']! as String);
    }

    final rowsAfter = await _rowCount(db, table);
    if (rowsAfter != rowsBefore) {
      throw StateError(
        'Row count changed after replacing $table: $rowsBefore -> $rowsAfter',
      );
    }
    final migratedInfo = await db.rawQuery(
      'PRAGMA table_info(${_quote(table)})',
    );
    final migratedTypes = <String, String>{
      for (final column in migratedInfo)
        column['name']! as String: column['type'].toString().toUpperCase(),
    };
    final notInteger = moneyColumns.where(
      (column) => migratedTypes[column] != 'INTEGER',
    );
    if (notInteger.isNotEmpty) {
      throw StateError(
        'Columns did not migrate to INTEGER in $table: $notInteger',
      );
    }

    return MoneyTableMigrationResult(
      table: table,
      columns: moneyColumns.length,
      rowsBefore: rowsBefore,
      rowsAfter: rowsAfter,
      alreadyMigrated: false,
    );
  }

  static int _legacyNumberToMinorUnits(num value, int decimalPlaces) {
    final match = RegExp(
      r'^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$',
    ).firstMatch(value.toString());
    if (match == null) {
      throw StateError('Invalid legacy monetary value: $value');
    }

    final negative = match.group(1) == '-';
    final whole = match.group(2)!;
    final fraction = match.group(3) ?? '';
    final exponent = int.parse(match.group(4) ?? '0');
    var numerator = BigInt.parse('$whole$fraction');
    var denominator = BigInt.from(10).pow(fraction.length);
    if (exponent >= 0) {
      numerator *= BigInt.from(10).pow(exponent);
    } else {
      denominator *= BigInt.from(10).pow(-exponent);
    }
    numerator *= BigInt.from(10).pow(decimalPlaces);
    if (negative) numerator = -numerator;

    final minorUnits = _divideRounded(numerator, denominator);
    const minInt64 = -9223372036854775808;
    const maxInt64 = 9223372036854775807;
    if (minorUnits < BigInt.from(minInt64) ||
        minorUnits > BigInt.from(maxInt64)) {
      throw RangeError('Migrated monetary value exceeds SQLite INTEGER range');
    }
    return minorUnits.toInt();
  }

  static BigInt _divideRounded(BigInt numerator, BigInt denominator) {
    final quotient = numerator ~/ denominator;
    final remainder = numerator.remainder(denominator);
    if (remainder == BigInt.zero) return quotient;
    if (remainder.abs() * BigInt.two < denominator.abs()) return quotient;
    return numerator.isNegative ? quotient - BigInt.one : quotient + BigInt.one;
  }

  static Future<int> _rowCount(DatabaseExecutor db, String table) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM ${_quote(table)}',
    );
    return (result.single['count']! as num).toInt();
  }

  static String _rewriteCreateTable(
    String sql,
    String tempTable,
    Set<String> moneyColumns,
  ) {
    final tablePattern = RegExp(
      r'^(\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?)(?:"[^"]+"|`[^`]+`|\[[^\]]+\]|[A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false,
    );
    final tableMatch = tablePattern.firstMatch(sql);
    if (tableMatch == null) throw StateError('Unsupported CREATE TABLE: $sql');
    var rewritten =
        '${tableMatch.group(1)}${_quote(tempTable)}${sql.substring(tableMatch.end)}';

    final open = rewritten.indexOf('(');
    final close = rewritten.lastIndexOf(')');
    if (open < 0 || close <= open) {
      throw StateError('Malformed CREATE TABLE: $sql');
    }
    final definitions = _splitTopLevel(rewritten.substring(open + 1, close));
    final columnPattern = RegExp(
      r'^(\s*)(?:"([^"]+)"|`([^`]+)`|\[([^\]]+)\]|([A-Za-z_][A-Za-z0-9_]*))(\s+)(REAL|INTEGER)\b',
      caseSensitive: false,
    );
    final converted = <String>{};
    for (var index = 0; index < definitions.length; index++) {
      final definition = definitions[index];
      final match = columnPattern.firstMatch(definition);
      if (match == null) continue;
      final name =
          match.group(2) ?? match.group(3) ?? match.group(4) ?? match.group(5)!;
      if (!moneyColumns.contains(name)) continue;
      if (match.group(7)!.toUpperCase() == 'REAL') {
        definitions[index] = definition.replaceFirst(
          RegExp(r'\bREAL\b', caseSensitive: false),
          'INTEGER',
        );
      }
      converted.add(name);
    }
    if (converted.length != moneyColumns.length) {
      throw StateError(
        'Could not rewrite all monetary definitions. Expected $moneyColumns, '
        'converted $converted',
      );
    }
    rewritten =
        '${rewritten.substring(0, open + 1)}${definitions.join(',')}${rewritten.substring(close)}';
    return rewritten;
  }

  static List<String> _splitTopLevel(String source) {
    final result = <String>[];
    var start = 0;
    var depth = 0;
    String? quote;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (quote != null) {
        if (char == quote) {
          if (index + 1 < source.length && source[index + 1] == quote) {
            index++;
          } else {
            quote = null;
          }
        }
        continue;
      }
      if (char == "'" || char == '"' || char == '`') {
        quote = char;
      } else if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
      } else if (char == ',' && depth == 0) {
        result.add(source.substring(start, index));
        start = index + 1;
      }
    }
    result.add(source.substring(start));
    return result;
  }

  static String _quote(String identifier) {
    return '"${identifier.replaceAll('"', '""')}"';
  }
}

class _ResolvedCurrency {
  const _ResolvedCurrency(this.code, this.decimalPlaces);

  final String code;
  final int decimalPlaces;
}

class _CurrencyContext {
  const _CurrencyContext({
    required this.scales,
    required this.companyCurrencies,
    required this.empresaCurrencies,
    required this.journalEntryCompanies,
    required this.singleDatabaseCurrency,
  });

  final Map<String, int> scales;
  final Map<int, String> companyCurrencies;
  final Map<int, String> empresaCurrencies;
  final Map<int, int> journalEntryCompanies;
  final String? singleDatabaseCurrency;

  static Future<_CurrencyContext> load(DatabaseExecutor db) async {
    final scales = <String, int>{};
    if (await _tableExists(db, 'app_currencies')) {
      for (final row in await db.query('app_currencies')) {
        final code = row['code']?.toString().trim();
        final scale = (row['decimal_places'] as num?)?.toInt();
        if (code != null && code.isNotEmpty && scale != null) {
          scales[code] = scale;
        }
      }
    }
    final companyCurrencies = await _idCurrencyMap(
      db,
      table: 'companies',
      currencyColumn: 'currency',
    );
    final empresaCurrencies = await _idCurrencyMap(
      db,
      table: 'empresas',
      currencyColumn: 'moneda',
    );
    final allConfigured = <String>{
      ...companyCurrencies.values,
      ...empresaCurrencies.values,
    };
    final journalEntryCompanies = <int, int>{};
    if (await _tableExists(db, 'accounting_journal_entries')) {
      for (final row in await db.query('accounting_journal_entries')) {
        final id = (row['id'] as num?)?.toInt();
        final companyId = (row['company_id'] as num?)?.toInt();
        if (id != null && companyId != null) {
          journalEntryCompanies[id] = companyId;
        }
      }
    }
    return _CurrencyContext(
      scales: scales,
      companyCurrencies: companyCurrencies,
      empresaCurrencies: empresaCurrencies,
      journalEntryCompanies: journalEntryCompanies,
      singleDatabaseCurrency: allConfigured.length == 1
          ? allConfigured.single
          : null,
    );
  }

  _ResolvedCurrency resolve({
    required String table,
    required String column,
    required Map<String, Object?> row,
    required bool allowUnresolvedZero,
  }) {
    String? code;
    if (publicMoneyTables.contains(table)) {
      code = 'COP';
    } else if (table == 'accounting_journal_lines' &&
        (column == 'local_debit' || column == 'local_credit')) {
      final entryId = (row['entry_id'] as num?)?.toInt();
      final companyId = entryId == null ? null : journalEntryCompanies[entryId];
      code = companyId == null ? null : companyCurrencies[companyId];
    } else {
      for (final key in const ['currency', 'moneda', 'currency_code']) {
        final candidate = row[key]?.toString().trim();
        if (candidate != null && candidate.isNotEmpty) {
          code = candidate;
          break;
        }
      }
      final companyId = (row['company_id'] as num?)?.toInt();
      final empresaId = (row['empresa_id'] as num?)?.toInt();
      code ??= companyId == null ? null : companyCurrencies[companyId];
      code ??= empresaId == null ? null : empresaCurrencies[empresaId];
      code ??= singleDatabaseCurrency;
    }

    if (code == null && allowUnresolvedZero) {
      return const _ResolvedCurrency('UNRESOLVED_ZERO', 0);
    }
    if (code == null) {
      throw StateError('Cannot resolve currency for $table.$column row $row');
    }
    final scale = scales[code];
    if (scale == null || scale < 0 || scale > 18) {
      throw StateError('Missing or invalid decimal scale for currency $code');
    }
    return _ResolvedCurrency(code, scale);
  }

  static Future<Map<int, String>> _idCurrencyMap(
    DatabaseExecutor db, {
    required String table,
    required String currencyColumn,
  }) async {
    if (!await _tableExists(db, table)) return const {};
    final result = <int, String>{};
    for (final row in await db.query(table)) {
      final id = (row['id'] as num?)?.toInt();
      final currency = row[currencyColumn]?.toString().trim();
      if (id != null && currency != null && currency.isNotEmpty) {
        result[id] = currency;
      }
    }
    return result;
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }
}
