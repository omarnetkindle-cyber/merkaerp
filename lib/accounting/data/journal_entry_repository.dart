import 'package:sqflite/sqflite.dart';

import '../../core/branch/branch_context.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../core/database/database_gateway.dart';
import '../../db_helper.dart';
import '../domain/journal_entry.dart';

abstract class JournalEntryRepository {
  Future<void> savePosted(JournalEntry entry, {required BranchScope scope});

  Future<List<JournalEntry>> findPosted({
    required int companyId,
    required int branchId,
    DateTime? from,
    DateTime? to,
  });
}

class SqliteJournalEntryRepository implements JournalEntryRepository {
  SqliteJournalEntryRepository({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    DatabaseHelper? db,
  }) : _gateway = gateway,
       _db = db ?? DatabaseHelper.instance;

  final DatabaseGateway _gateway;
  final DatabaseHelper _db;

  @override
  Future<void> savePosted(JournalEntry entry, {required BranchScope scope}) {
    if (entry.status != JournalEntryStatus.posted) {
      throw StateError('Solo se persisten asientos contabilizados.');
    }
    return _gateway.transaction((txn) async {
      await txn.insert('accounting_journal_entries', {
        'id': entry.id,
        'company_id': scope.companyId,
        'branch_id': scope.branchId,
        'consecutive': entry.consecutive,
        'entry_date': entry.date.toIso8601String(),
        'concept': entry.concept,
        'reference': entry.reference,
        'origin': entry.origin,
        'status': JournalEntryStatus.draft.name,
        'reversed_entry_id': entry.reversedEntryId,
        'correlation_id': entry.correlationId,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      for (final line in entry.lines) {
        final dimension = line.dimension;
        await txn.insert('accounting_journal_lines', {
          'entry_id': entry.id,
          'company_id': scope.companyId,
          'branch_id': dimension.branchId ?? scope.branchId,
          'warehouse_id': dimension.warehouseId ?? scope.warehouseId,
          'cost_center_id': dimension.costCenterId ?? scope.costCenterId,
          'account_code': line.accountCode,
          'description': line.description,
          'debit': line.debit.toSql(),
          'credit': line.credit.toSql(),
          'local_debit': line.localDebit.toSql(),
          'local_credit': line.localCredit.toSql(),
          'third_party': dimension.thirdParty,
          'currency': dimension.currency,
          'exchange_rate': dimension.exchangeRate,
        });
      }

      await txn.update(
        'accounting_journal_entries',
        {'status': entry.status.name},
        where: 'id = ?',
        whereArgs: [entry.id],
      );
    });
  }

  @override
  Future<List<JournalEntry>> findPosted({
    required int companyId,
    required int branchId,
    DateTime? from,
    DateTime? to,
  }) async {
    final currency = await _currencyFor(companyId);
    final filters = <String>['company_id = ?', 'branch_id = ?', 'status = ?'];
    final args = <Object?>[companyId, branchId, JournalEntryStatus.posted.name];
    if (from != null) {
      filters.add('entry_date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      filters.add('entry_date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await _gateway.query(
      'accounting_journal_entries',
      where: filters.join(' AND '),
      whereArgs: args,
      orderBy: 'entry_date ASC, consecutive ASC',
    );

    final entries = <JournalEntry>[];
    for (final row in rows) {
      final entryId = row['id']?.toString() ?? '';
      final lines = await _gateway.query(
        'accounting_journal_lines',
        where: 'entry_id = ?',
        whereArgs: [entryId],
        orderBy: 'id ASC',
      );
      entries.add(_entryFromRows(row, lines, currency));
    }
    return entries;
  }

  JournalEntry _entryFromRows(
    Map<String, Object?> row,
    List<Map<String, Object?>> lines,
    Currency currency,
  ) {
    final statusName = row['status']?.toString() ?? '';
    final status = JournalEntryStatus.values.firstWhere(
      (item) => item.name == statusName,
      orElse: () => JournalEntryStatus.posted,
    );
    return JournalEntry(
      id: row['id']?.toString() ?? '',
      consecutive: row['consecutive']?.toString() ?? '',
      date:
          DateTime.tryParse(row['entry_date']?.toString() ?? '') ??
          DateTime.now(),
      concept: row['concept']?.toString() ?? '',
      reference: row['reference']?.toString() ?? '',
      origin: row['origin']?.toString() ?? '',
      status: status,
      reversedEntryId: row['reversed_entry_id']?.toString(),
      correlationId: row['correlation_id']?.toString(),
      lines: lines.map((line) => _lineFromRow(line, currency)).toList(),
    );
  }

  JournalLine _lineFromRow(Map<String, Object?> row, Currency currency) {
    final storedCurrency = row['currency']?.toString();
    if (storedCurrency != null &&
        storedCurrency.isNotEmpty &&
        storedCurrency != currency.code) {
      throw StateError(
        'La moneda del asiento $storedCurrency no coincide con ${currency.code}.',
      );
    }
    return JournalLine(
      accountCode: row['account_code']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      debit: MoneyValue.fromSql(
        row['debit'],
        currency: currency,
        nullableAsZero: true,
      ),
      credit: MoneyValue.fromSql(
        row['credit'],
        currency: currency,
        nullableAsZero: true,
      ),
      dimension: AccountingDimensionValue(
        companyId: (row['company_id'] as num?)?.toInt(),
        branchId: (row['branch_id'] as num?)?.toInt(),
        warehouseId: (row['warehouse_id'] as num?)?.toInt(),
        costCenterId: (row['cost_center_id'] as num?)?.toInt(),
        thirdParty: row['third_party']?.toString(),
        currency: row['currency']?.toString() ?? 'COP',
        exchangeRate: (row['exchange_rate'] as num?)?.toDouble() ?? 1,
      ),
    );
  }

  Future<Currency> _currencyFor(int companyId) async {
    final database = await _db.database;
    return MoneyCurrencyResolver.resolve(database, companyId: companyId);
  }
}
