import 'package:sqflite/sqflite.dart';

import '../../app_session.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';

class CashShift {
  const CashShift({
    required this.id,
    required this.userId,
    required this.userName,
    required this.openedAt,
    required this.openingFund,
    required this.status,
    this.closedAt,
    this.closeId,
    this.reopenedAt,
    this.reopenedBy,
    this.reopenReason,
  });

  final int id;
  final String userId;
  final String userName;
  final DateTime openedAt;
  final MoneyValue openingFund;
  final String status;
  final DateTime? closedAt;
  final int? closeId;
  final DateTime? reopenedAt;
  final String? reopenedBy;
  final String? reopenReason;

  bool get isOpen => status == 'open';

  factory CashShift.fromRow(Map<String, Object?> row, Currency currency) {
    return CashShift(
      id: (row['id'] as num).toInt(),
      userId: row['user_id']?.toString() ?? '',
      userName: row['user_name']?.toString() ?? 'Usuario',
      openedAt: DateTime.parse(row['opened_at']!.toString()),
      openingFund: MoneyValue.fromSql(
        row['opening_fund'],
        currency: currency,
        nullableAsZero: true,
      ),
      status: row['status']?.toString() ?? 'open',
      closedAt: DateTime.tryParse(row['closed_at']?.toString() ?? ''),
      closeId: (row['close_id'] as num?)?.toInt(),
      reopenedAt: DateTime.tryParse(row['reopened_at']?.toString() ?? ''),
      reopenedBy: row['reopened_by']?.toString(),
      reopenReason: row['reopen_reason']?.toString(),
    );
  }
}

/// Control de turnos de caja.
///
/// El turno NO crea un segundo libro de caja. La verdad monetaria continúa en
/// `movimientos_caja`; esta tabla agrega responsabilidad operativa, apertura,
/// cierre y autorización de reapertura alrededor del libro existente.
class CashShiftService {
  CashShiftService._();
  static final CashShiftService instance = CashShiftService._();

  Future<Database> _db() => DatabaseHelper.instance.database;

  Future<void> _ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_shifts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        opened_at TEXT NOT NULL,
        opening_fund INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'open',
        closed_at TEXT,
        close_id INTEGER,
        closed_by TEXT,
        reopened_at TEXT,
        reopened_by TEXT,
        reopen_reason TEXT,
        notes TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_shifts_company_status ON cash_shifts(company_id, status, opened_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cash_shifts_user ON cash_shifts(company_id, user_id, opened_at)',
    );
  }

  Future<CashShift?> currentShift(Currency currency) async {
    final db = await _db();
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final userId = AppSession.usuarioId ?? 'local';
    final rows = await db.query(
      'cash_shifts',
      where: "company_id = ? AND user_id = ? AND status = 'open'",
      whereArgs: [companyId, userId],
      orderBy: 'opened_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CashShift.fromRow(rows.first, currency);
  }

  Future<List<CashShift>> history(Currency currency, {int limit = 50}) async {
    final db = await _db();
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query(
      'cash_shifts',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'opened_at DESC',
      limit: limit,
    );
    return rows.map((row) => CashShift.fromRow(row, currency)).toList();
  }

  Future<CashShift> openShift({
    required MoneyValue openingFund,
    String notes = '',
  }) async {
    if (AppSession.usuarioActual == null) {
      throw StateError('Debes iniciar sesión para abrir un turno de caja.');
    }
    final db = await _db();
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final userId = AppSession.usuarioId ?? 'local';
    final existing = await db.query(
      'cash_shifts',
      where: "company_id = ? AND user_id = ? AND status = 'open'",
      whereArgs: [companyId, userId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw StateError('Ya tienes un turno de caja abierto.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('cash_shifts', {
      'company_id': companyId,
      'user_id': userId,
      'user_name': AppSession.nombre,
      'opened_at': now,
      'opening_fund': openingFund.toSql(),
      'status': 'open',
      'notes': notes.trim(),
    });
    await DatabaseHelper.instance.cambiarBloqueoOperativo(false);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'APERTURA_TURNO_CAJA',
      entidad: 'cash_shifts',
      entidadId: id,
      detalle:
          'Turno abierto por ${AppSession.nombre}. Fondo declarado: ${openingFund.format()}. ${notes.trim()}',
      oldValues: 'status=none',
      newValues: 'status=open; opening_fund_minor=${openingFund.toSql()}',
    );
    final rows = await db.query('cash_shifts', where: 'id = ?', whereArgs: [id]);
    return CashShift.fromRow(rows.single, openingFund.currency);
  }

  Future<void> closeCurrentShift({
    required int closeId,
    required Currency currency,
  }) async {
    final shift = await currentShift(currency);
    if (shift == null) {
      throw StateError('No hay un turno abierto para el usuario actual.');
    }
    final db = await _db();
    await db.update(
      'cash_shifts',
      {
        'status': 'closed',
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'close_id': closeId,
        'closed_by': AppSession.nombre,
      },
      where: 'id = ?',
      whereArgs: [shift.id],
    );
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CONFIRMAR_CIERRE_TURNO_CAJA',
      entidad: 'cash_shifts',
      entidadId: shift.id,
      detalle:
          'Cierre #$closeId confirmado por el usuario autenticado ${AppSession.nombre}.',
      oldValues: 'status=open',
      newValues: 'status=closed; close_id=$closeId',
    );
  }

  Future<void> reopenLastShift({required String reason}) async {
    if (!AppSession.puedeAdministrar()) {
      throw StateError('Solo un administrador puede reabrir una caja cerrada.');
    }
    final cleanReason = reason.trim();
    if (cleanReason.length < 8) {
      throw ArgumentError('La reapertura exige un motivo de al menos 8 caracteres.');
    }
    final db = await _db();
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query(
      'cash_shifts',
      where: "company_id = ? AND status = 'closed'",
      whereArgs: [companyId],
      orderBy: 'closed_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('No existe un turno cerrado para reabrir.');
    }
    final id = (rows.first['id'] as num).toInt();
    await db.update(
      'cash_shifts',
      {
        'status': 'open',
        'reopened_at': DateTime.now().toUtc().toIso8601String(),
        'reopened_by': AppSession.nombre,
        'reopen_reason': cleanReason,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await DatabaseHelper.instance.cambiarBloqueoOperativo(false);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'REAPERTURA_CAJA_AUTORIZADA',
      entidad: 'cash_shifts',
      entidadId: id,
      detalle: 'Administrador: ${AppSession.nombre}. Motivo: $cleanReason',
      oldValues: 'status=closed',
      newValues: 'status=open; reason=$cleanReason',
    );
  }
}
