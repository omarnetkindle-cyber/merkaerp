import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';

class PdfLayoutSettings {
  const PdfLayoutSettings({
    this.paperSize = 'a4',
    this.showLogo = true,
    this.showInternalQr = true,
    this.footerText = 'Documento generado por MerkaERP.',
    this.signatureLabel = 'Responsable / autorizado',
  });

  final String paperSize; // a4 | letter
  final bool showLogo;
  final bool showInternalQr;
  final String footerText;
  final String signatureLabel;
}

class PdfLayoutSettingsService {
  PdfLayoutSettingsService._();
  static final instance = PdfLayoutSettingsService._();

  Future<void> _ensure(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_pdf_settings(
        company_id INTEGER PRIMARY KEY,
        paper_size TEXT NOT NULL DEFAULT 'a4',
        show_logo INTEGER NOT NULL DEFAULT 1,
        show_internal_qr INTEGER NOT NULL DEFAULT 1,
        footer_text TEXT,
        signature_label TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<PdfLayoutSettings> load() async {
    final db = await DatabaseHelper.instance.database;
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query('document_pdf_settings', where: 'company_id = ?', whereArgs: [companyId], limit: 1);
    if (rows.isEmpty) return const PdfLayoutSettings();
    final r = rows.first;
    return PdfLayoutSettings(
      paperSize: r['paper_size']?.toString() == 'letter' ? 'letter' : 'a4',
      showLogo: (r['show_logo'] as num?)?.toInt() != 0,
      showInternalQr: (r['show_internal_qr'] as num?)?.toInt() != 0,
      footerText: r['footer_text']?.toString() ?? 'Documento generado por MerkaERP.',
      signatureLabel: r['signature_label']?.toString() ?? 'Responsable / autorizado',
    );
  }

  Future<void> save(PdfLayoutSettings value) async {
    final db = await DatabaseHelper.instance.database;
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.insert('document_pdf_settings', {
      'company_id': companyId,
      'paper_size': value.paperSize == 'letter' ? 'letter' : 'a4',
      'show_logo': value.showLogo ? 1 : 0,
      'show_internal_qr': value.showInternalQr ? 1 : 0,
      'footer_text': value.footerText.trim(),
      'signature_label': value.signatureLabel.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CONFIGURAR_DISENO_PDF',
      entidad: 'document_pdf_settings',
      detalle: 'Formato ${value.paperSize}; logo ${value.showLogo}; QR interno ${value.showInternalQr}.',
    );
  }
}
