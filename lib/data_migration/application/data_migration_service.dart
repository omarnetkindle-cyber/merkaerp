import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../app_session.dart';
import '../../core/audit/audit_identity.dart';
import '../../core/backup/full_backup_service.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../licensing/domain/product_family.dart';
import '../../document_management/application/document_management_service.dart';
import '../database/schema_data_migration.dart';
import '../domain/migration_catalog.dart';
import '../domain/migration_models.dart';

class LegacyDocumentImportResult {
  const LegacyDocumentImportResult({
    required this.jobId,
    required this.caseId,
    required this.filesImported,
    required this.totalBytes,
    required this.manifestSha256,
    required this.backupPath,
  });

  final String jobId;
  final int caseId;
  final int filesImported;
  final int totalBytes;
  final String manifestSha256;
  final String backupPath;
}

class DataMigrationService {
  DataMigrationService._();
  static final DataMigrationService instance = DataMigrationService._();

  static const _uuid = Uuid();

  Future<void> ensureSchema() async {
    final db = await DatabaseHelper.instance.database;
    await SchemaDataMigration.createTables(db);
  }

  List<MigrationEntityDefinition> entitiesFor(ProductFamily family) =>
      MigrationCatalog.forFamily(family);

  Map<String, String?> suggestMapping(
    MigrationEntityDefinition entity,
    List<String> sourceHeaders,
  ) {
    final normalizedHeaders = <String, String>{
      for (final header in sourceHeaders) _normalize(header): header,
    };
    final result = <String, String?>{};
    for (final field in entity.fields) {
      String? match;
      final candidates = [field.label, field.key, ...field.aliases];
      for (final candidate in candidates) {
        final normalizedCandidate = _normalize(candidate);
        if (normalizedHeaders.containsKey(normalizedCandidate)) {
          match = normalizedHeaders[normalizedCandidate];
          break;
        }
      }
      if (match == null) {
        for (final candidate in candidates) {
          final needle = _normalize(candidate);
          for (final entry in normalizedHeaders.entries) {
            if (entry.key.contains(needle) || needle.contains(entry.key)) {
              match = entry.value;
              break;
            }
          }
          if (match != null) break;
        }
      }
      result[field.key] = match;
    }
    return result;
  }

  MigrationPreview preview({
    required MigrationEntityDefinition entity,
    required TabularDataset dataset,
    required Map<String, String?> mapping,
  }) {
    final issues = <MigrationPreviewIssue>[];
    final normalizedRows = <Map<String, Object?>>[];
    var validRows = 0;

    for (var index = 0; index < dataset.rows.length; index++) {
      final rowNumber = index + 2;
      final source = dataset.rows[index];
      final normalized = <String, Object?>{'__row_number': rowNumber};
      var valid = true;

      for (final field in entity.fields) {
        final header = mapping[field.key];
        final raw = header == null ? '' : (source[header] ?? '').trim();
        if (field.required && raw.isEmpty) {
          valid = false;
          issues.add(MigrationPreviewIssue(
            rowNumber: rowNumber,
            severity: 'error',
            field: field.key,
            rawValue: raw,
            message: 'El campo ${field.label} es obligatorio.',
          ));
          normalized[field.key] = '';
          continue;
        }
        if (raw.isEmpty) {
          normalized[field.key] = '';
          continue;
        }
        try {
          normalized[field.key] = _normalizeValue(raw, field.type);
        } catch (error) {
          valid = false;
          normalized[field.key] = raw;
          issues.add(MigrationPreviewIssue(
            rowNumber: rowNumber,
            severity: 'error',
            field: field.key,
            rawValue: raw,
            message: '${field.label}: $error',
          ));
        }
      }

      if (entity.key == 'accounting_opening' || entity.key == 'public_accounting_opening') {
        final debit = _moneyString(normalized['debit']);
        final credit = _moneyString(normalized['credit']);
        if ((debit == null || debit == '0') && (credit == null || credit == '0')) {
          valid = false;
          issues.add(MigrationPreviewIssue(
            rowNumber: rowNumber,
            severity: 'error',
            message: 'La línea contable debe tener débito o crédito.',
          ));
        }
        if (debit != null && debit != '0' && credit != null && credit != '0') {
          valid = false;
          issues.add(MigrationPreviewIssue(
            rowNumber: rowNumber,
            severity: 'error',
            message: 'Una línea contable no puede tener débito y crédito simultáneamente.',
          ));
        }
      }

      if (entity.key == 'public_budget_opening') {
        final initial = _decimalValue(normalized['initial_value']);
        final current = _decimalValue(normalized['current_appropriation'], fallback: initial);
        final cdp = _decimalValue(normalized['cdp_accumulated']);
        final rp = _decimalValue(normalized['rp_accumulated']);
        final obligated = _decimalValue(normalized['obligated_accumulated']);
        final paid = _decimalValue(normalized['paid_accumulated']);
        final values = [initial, current, cdp, rp, obligated, paid];
        if (values.any((value) => value < 0)) {
          valid = false;
          issues.add(MigrationPreviewIssue(
            rowNumber: rowNumber,
            severity: 'error',
            message: 'Los valores presupuestales acumulados no pueden ser negativos.',
          ));
        } else if (!(paid <= obligated && obligated <= rp && rp <= cdp && cdp <= current)) {
          valid = false;
          issues.add(MigrationPreviewIssue(
            rowNumber: rowNumber,
            severity: 'error',
            message: 'La ejecución debe cumplir Pagado ≤ Obligado ≤ RP ≤ CDP ≤ Apropiación vigente.',
          ));
        }
      }

      normalized['__valid'] = valid;
      normalizedRows.add(normalized);
      if (valid) validRows++;
    }

    return MigrationPreview(
      entity: entity,
      totalRows: dataset.rows.length,
      validRows: validRows,
      invalidRows: dataset.rows.length - validRows,
      mapping: mapping,
      normalizedRows: normalizedRows,
      issues: issues,
    );
  }

  Future<MigrationImportResult> importDataset({
    required File sourceFile,
    required TabularDataset dataset,
    required MigrationPreview preview,
    required ProductFamily productFamily,
    required MigrationDuplicatePolicy duplicatePolicy,
    String? publicEntityId,
  }) async {
    _requireAdmin();
    if (!preview.canImport) {
      throw StateError('No hay filas válidas para importar.');
    }
    if (!preview.entity.productFamilies.contains(productFamily)) {
      throw StateError('La entidad seleccionada no pertenece a la familia licenciada.');
    }
    if (productFamily == ProductFamily.publicSector &&
        (publicEntityId == null || publicEntityId.trim().isEmpty)) {
      throw StateError('No se pudo resolver la entidad pública activa.');
    }

    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final backup = await FullBackupService.instance.createFullBackup(label: 'pre_migracion');
    final jobId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final fileHash = (await crypto.sha256.bind(sourceFile.openRead()).first).toString();

    await db.insert('data_migration_jobs', {
      'id': jobId,
      'company_id': companyId,
      'public_entity_id': publicEntityId,
      'product_family': productFamily.storageValue,
      'source_name': sourceFile.uri.pathSegments.isEmpty ? sourceFile.path : sourceFile.uri.pathSegments.last,
      'source_type': sourceFile.path.split('.').last.toLowerCase(),
      'source_file_name': sourceFile.uri.pathSegments.isEmpty ? sourceFile.path : sourceFile.uri.pathSegments.last,
      'source_sha256': fileHash,
      'status': 'running',
      'duplicate_policy': duplicatePolicy.name,
      'backup_path': backup.path,
      'summary_json': '{}',
      'started_at': now,
      'created_by': AuditIdentity.current,
    });

    int runId = 0;
    var imported = 0;
    var skipped = 0;
    var errors = preview.invalidRows;

    try {
      await db.transaction((txn) async {
        runId = await txn.insert('data_migration_runs', {
          'job_id': jobId,
          'target_entity': preview.entity.key,
          'source_sheet': dataset.name,
          'mapping_json': jsonEncode(preview.mapping),
          'rows_total': preview.totalRows,
          'rows_valid': preview.validRows,
          'rows_imported': 0,
          'rows_skipped': 0,
          'rows_errors': preview.invalidRows,
          'started_at': now,
        });

        for (final issue in preview.issues) {
          await txn.insert('data_migration_issues', {
            'job_id': jobId,
            'run_id': runId,
            'row_number': issue.rowNumber,
            'severity': issue.severity,
            'field_name': issue.field,
            'message': issue.message,
            'raw_value': issue.rawValue,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        if (preview.entity.key == 'accounting_opening' || preview.entity.key == 'public_accounting_opening') {
          for (var index = 0; index < dataset.rows.length; index++) {
            final raw = dataset.rows[index];
            final normalized = preview.normalizedRows[index];
            await txn.insert('data_migration_legacy_records', {
              'job_id': jobId,
              'run_id': runId,
              'row_number': normalized['__row_number'] as int,
              'target_entity': preview.entity.key,
              'raw_json': jsonEncode(_sanitizeLegacyRow(raw)),
              'normalized_json': jsonEncode(normalized),
              'imported': 0,
              'created_at': DateTime.now().toIso8601String(),
            });
          }
          final valid = preview.normalizedRows.where((row) => row['__valid'] == true).toList();
          final result = preview.entity.key == 'public_accounting_opening'
              ? await _importPublicAccountingOpening(
                  txn: txn,
                  jobId: jobId,
                  runId: runId,
                  companyId: companyId,
                  entityId: publicEntityId!,
                  rows: valid,
                )
              : await _importAccountingOpening(
                  txn: txn,
                  jobId: jobId,
                  runId: runId,
                  companyId: companyId,
                  rows: valid,
                );
          imported += result.$1;
          skipped += result.$2;
        } else {
          for (var index = 0; index < dataset.rows.length; index++) {
            final raw = dataset.rows[index];
            final normalized = preview.normalizedRows[index];
            final rowNumber = normalized['__row_number'] as int;
            final legacyRecordId = await txn.insert('data_migration_legacy_records', {
              'job_id': jobId,
              'run_id': runId,
              'row_number': rowNumber,
              'target_entity': preview.entity.key,
              'raw_json': jsonEncode(_sanitizeLegacyRow(raw)),
              'normalized_json': jsonEncode(normalized),
              'imported': 0,
              'created_at': DateTime.now().toIso8601String(),
            });
            if (normalized['__valid'] != true) continue;
            try {
              if (preview.entity.key == 'legacy_archive') {
                imported++;
                await txn.update('data_migration_legacy_records', {
                  'imported': 1,
                  'target_table': 'legacy_archive',
                  'target_pk': '$legacyRecordId',
                }, where: 'id = ?', whereArgs: [legacyRecordId]);
                continue;
              }
              final target = await _importRow(
                txn: txn,
                jobId: jobId,
                runId: runId,
                companyId: companyId,
                publicEntityId: publicEntityId,
                entityKey: preview.entity.key,
                row: normalized,
                duplicatePolicy: duplicatePolicy,
              );
              if (target == null) {
                skipped++;
              } else {
                imported++;
                await txn.update('data_migration_legacy_records', {
                  'imported': 1,
                  'target_table': target.$1,
                  'target_pk': target.$2,
                }, where: 'id = ?', whereArgs: [legacyRecordId]);
              }
            } catch (error) {
              errors++;
              await txn.insert('data_migration_issues', {
                'job_id': jobId,
                'run_id': runId,
                'row_number': rowNumber,
                'severity': 'error',
                'message': 'No se importó la fila: $error',
                'raw_value': jsonEncode(raw),
                'created_at': DateTime.now().toIso8601String(),
              });
            }
          }
        }

        await txn.update('data_migration_runs', {
          'rows_imported': imported,
          'rows_skipped': skipped,
          'rows_errors': errors,
          'completed_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [runId]);
      });

      final summary = <String, Object?>{
        'entity': preview.entity.key,
        'sheet': dataset.name,
        'rows_total': preview.totalRows,
        'rows_imported': imported,
        'rows_skipped': skipped,
        'rows_errors': errors,
        'source_sha256': fileHash,
      };
      await db.update('data_migration_jobs', {
        'status': errors == 0 ? 'completed' : 'completed_with_issues',
        'summary_json': jsonEncode(summary),
        'completed_at': DateTime.now().toIso8601String(),
      }, where: 'id = ? AND company_id = ?', whereArgs: [jobId, companyId]);
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'MIGRACION_DATOS',
        entidad: 'data_migration_jobs',
        detalle: 'job=$jobId; entity=${preview.entity.key}; imported=$imported; skipped=$skipped; errors=$errors; backup=${backup.path}',
      );
      return MigrationImportResult(
        jobId: jobId,
        runId: runId,
        imported: imported,
        skipped: skipped,
        errors: errors,
        backupPath: backup.path,
      );
    } catch (error) {
      await db.update('data_migration_jobs', {
        'status': 'failed',
        'summary_json': jsonEncode({'error': error.toString()}),
        'completed_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [jobId]);
      rethrow;
    }
  }

  Future<List<MigrationJobSummary>> history() async {
    _requireAdmin();
    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final rows = await db.query(
      'data_migration_jobs',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'started_at DESC',
      limit: 100,
    );
    return rows.map((row) => MigrationJobSummary.fromMap(Map<String, Object?>.from(row))).toList();
  }

  Future<List<Map<String, Object?>>> searchLegacyRecords({String query = '', int limit = 200}) async {
    _requireAdmin();
    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final safeLimit = limit.clamp(1, 1000).toInt();
    final needle = query.trim();
    final args = <Object?>[companyId];
    var where = 'j.company_id = ?';
    if (needle.isNotEmpty) {
      where += ' AND (r.raw_json LIKE ? OR r.normalized_json LIKE ? OR run.source_sheet LIKE ? OR j.source_name LIKE ?)';
      final like = '%$needle%';
      args.addAll([like, like, like, like]);
    }
    args.add(safeLimit);
    final rows = await db.rawQuery("""
      SELECT r.id, r.job_id, r.run_id, r.row_number, r.target_entity,
             r.raw_json, r.normalized_json, r.imported, r.target_table, r.target_pk,
             run.source_sheet, j.source_name, j.started_at, j.status
      FROM data_migration_legacy_records r
      JOIN data_migration_runs run ON run.id = r.run_id
      JOIN data_migration_jobs j ON j.id = r.job_id
      WHERE $where
      ORDER BY j.started_at DESC, run.id DESC, r.row_number ASC
      LIMIT ?
    """, args);
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  Future<List<Map<String, Object?>>> issuesForJob(String jobId) async {
    _requireAdmin();
    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final owned = await db.query(
      'data_migration_jobs',
      columns: ['id'],
      where: 'id = ? AND company_id = ?',
      whereArgs: [jobId, companyId],
      limit: 1,
    );
    if (owned.isEmpty) throw StateError('La migración no pertenece a la organización activa.');
    return (await db.query(
      'data_migration_issues',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'row_number ASC, id ASC',
    )).map((row) => Map<String, Object?>.from(row)).toList();
  }

  Future<void> rollback(String jobId) async {
    _requireAdmin();
    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final jobRows = await db.query(
      'data_migration_jobs',
      where: 'id = ? AND company_id = ?',
      whereArgs: [jobId, companyId],
      limit: 1,
    );
    if (jobRows.isEmpty) throw StateError('No existe la migración solicitada para la organización activa.');
    final job = jobRows.first;
    if (job['rolled_back_at'] != null) throw StateError('Esta migración ya fue revertida.');
    if (job['status'] == 'running') throw StateError('No se puede revertir una migración en ejecución.');

    final documentPathsToDelete = <String>[];
    await db.transaction((txn) async {
      final changes = await txn.query(
        'data_migration_changes',
        where: 'job_id = ?',
        whereArgs: [jobId],
        orderBy: 'sequence_no DESC, id DESC',
      );

      // Antes de tocar relaciones documentales comprobamos que ningún
      // documento creado por esta migración haya sido reutilizado después en
      // otro expediente. La consulta debe hacerse antes del bucle porque las
      // relaciones creadas por la migración se eliminan primero al recorrer
      // los cambios en orden inverso.
      final migratedDocumentIds = <String>{};
      final migratedRelationIds = <String>{};
      for (final change in changes) {
        if (change['operation']?.toString() != 'insert') continue;
        final table = change['table_name']?.toString();
        if (table == 'gd_documents') {
          migratedDocumentIds.add(change['pk_value']?.toString() ?? '');
        } else if (table == 'gd_expediente_documents') {
          migratedRelationIds.add(change['pk_value']?.toString() ?? '');
        }
      }
      migratedDocumentIds.remove('');
      migratedRelationIds.remove('');
      for (final documentId in migratedDocumentIds) {
        final links = await txn.query(
          'gd_expediente_documents',
          columns: ['id'],
          where: 'company_id = ? AND document_id = ?',
          whereArgs: [companyId, documentId],
        );
        final externalLinks = links.where(
          (row) => !migratedRelationIds.contains(row['id']?.toString() ?? ''),
        );
        if (externalLinks.isNotEmpty) {
          throw StateError(
            'El documento migrado $documentId fue vinculado posteriormente a otro expediente; rollback detenido.',
          );
        }
      }

      for (final change in changes) {
        final table = change['table_name']?.toString() ?? '';
        final pkColumn = change['pk_column']?.toString() ?? 'id';
        final pkValue = change['pk_value']?.toString() ?? '';
        final operation = change['operation']?.toString() ?? '';
        if (!_safeIdentifier(table) || !_safeIdentifier(pkColumn)) {
          throw StateError('Cambio de migración inválido; rollback detenido.');
        }
        if (operation == 'insert') {
          final rawAfter = change['after_json']?.toString();
          final currentRows = await txn.query(
            table,
            where: '$pkColumn = ?',
            whereArgs: [pkValue],
            limit: 1,
          );
          if (currentRows.isEmpty) {
            if (job['status'] == 'failed') continue;
            throw StateError('El registro $table/$pkValue ya no existe; rollback detenido.');
          }
          if (rawAfter != null && rawAfter.isNotEmpty) {
            final after = Map<String, Object?>.from(jsonDecode(rawAfter) as Map);
            for (final entry in after.entries) {
              if (entry.key == pkColumn) continue;
              if (_normalizeComparable(currentRows.first[entry.key]) != _normalizeComparable(entry.value)) {
                throw StateError(
                  'El registro $table/$pkValue fue modificado después de la migración; rollback detenido para preservar el trabajo posterior.',
                );
              }
            }
          }
          if (table == 'gd_documents' && currentRows.first['file_path'] != null) {
            documentPathsToDelete.add(currentRows.first['file_path'].toString());
          }
          await txn.delete(table, where: '$pkColumn = ?', whereArgs: [pkValue]);
        } else if (operation == 'update') {
          final rawBefore = change['before_json']?.toString();
          final rawAfter = change['after_json']?.toString();
          if (rawBefore == null || rawBefore.isEmpty) continue;
          final before = Map<String, Object?>.from(jsonDecode(rawBefore) as Map);
          if (rawAfter != null && rawAfter.isNotEmpty) {
            final after = Map<String, Object?>.from(jsonDecode(rawAfter) as Map);
            final currentRows = await txn.query(table, where: '$pkColumn = ?', whereArgs: [pkValue], limit: 1);
            if (currentRows.isEmpty) throw StateError('El registro $table/$pkValue ya no existe; rollback detenido.');
            for (final entry in after.entries) {
              if (entry.key == pkColumn) continue;
              if (_normalizeComparable(currentRows.first[entry.key]) != _normalizeComparable(entry.value)) {
                throw StateError('El registro $table/$pkValue cambió después de la migración; no se sobrescribirá automáticamente.');
              }
            }
          }
          before.remove(pkColumn);
          await txn.update(table, before, where: '$pkColumn = ?', whereArgs: [pkValue]);
        }
      }
      await txn.update('data_migration_jobs', {
        'status': 'rolled_back',
        'rolled_back_at': DateTime.now().toIso8601String(),
      }, where: 'id = ? AND company_id = ?', whereArgs: [jobId, companyId]);
    });
    for (final filePath in documentPathsToDelete) {
      try {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'REVERTIR_MIGRACION_DATOS',
      entidad: 'data_migration_jobs',
      detalle: 'job=$jobId',
    );
  }

  Future<Map<String, Object?>> reconcileJob(String jobId) async {
    _requireAdmin();
    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final jobs = await db.query(
      'data_migration_jobs',
      where: 'id = ? AND company_id = ?',
      whereArgs: [jobId, companyId],
      limit: 1,
    );
    if (jobs.isEmpty) throw StateError('La migración no pertenece a la organización activa.');
    final changes = await db.query(
      'data_migration_changes',
      where: 'job_id = ?',
      whereArgs: [jobId],
      orderBy: 'sequence_no ASC',
    );
    var ok = 0;
    var missing = 0;
    var changed = 0;
    final findings = <Map<String, Object?>>[];
    for (final change in changes) {
      final table = change['table_name']?.toString() ?? '';
      final pkColumn = change['pk_column']?.toString() ?? '';
      final pkValue = change['pk_value']?.toString() ?? '';
      if (!_safeIdentifier(table) || !_safeIdentifier(pkColumn)) {
        changed++;
        findings.add({'table': table, 'pk': pkValue, 'status': 'invalid_trace'});
        continue;
      }
      final rows = await db.query(table, where: '$pkColumn = ?', whereArgs: [pkValue], limit: 1);
      if (rows.isEmpty) {
        missing++;
        findings.add({'table': table, 'pk': pkValue, 'status': 'missing'});
        continue;
      }
      final rawAfter = change['after_json']?.toString();
      if (rawAfter == null || rawAfter.isEmpty) {
        ok++;
        continue;
      }
      final after = Map<String, Object?>.from(jsonDecode(rawAfter) as Map);
      var same = true;
      for (final entry in after.entries) {
        if (entry.key == pkColumn || !rows.first.containsKey(entry.key)) continue;
        if (_normalizeComparable(rows.first[entry.key]) != _normalizeComparable(entry.value)) {
          same = false;
          break;
        }
      }
      if (same) {
        ok++;
      } else {
        changed++;
        findings.add({'table': table, 'pk': pkValue, 'status': 'changed_after_migration'});
      }
    }
    final legacyCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM data_migration_legacy_records WHERE job_id = ?',
          [jobId],
        )) ??
        0;
    final importedCount = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM data_migration_legacy_records WHERE job_id = ? AND imported = 1',
          [jobId],
        )) ??
        0;
    return {
      'job_id': jobId,
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'trace_changes': changes.length,
      'trace_ok': ok,
      'missing': missing,
      'changed_after_migration': changed,
      'legacy_rows_preserved': legacyCount,
      'legacy_rows_imported': importedCount,
      'ok': missing == 0 && changed == 0,
      'findings': findings.take(100).toList(),
    };
  }

  Future<Map<String, Object?>> reconcileAllJobs() async {
    _requireAdmin();
    final jobs = await history();
    final candidates = jobs
        .where((job) => job.status == 'completed' || job.status == 'completed_with_issues')
        .toList();
    if (candidates.isEmpty) {
      return {
        'ok': true,
        'has_migrations': false,
        'jobs_checked': 0,
        'jobs_ok': 0,
        'jobs_failed': 0,
        'results': const <Object?>[],
      };
    }
    final results = <Map<String, Object?>>[];
    var okCount = 0;
    for (final job in candidates) {
      final result = await reconcileJob(job.id);
      final ok = result['ok'] == true;
      if (ok) okCount++;
      results.add({
        'job_id': job.id,
        'source': job.sourceName,
        'ok': ok,
        'missing': result['missing'] ?? 0,
        'changed_after_migration': result['changed_after_migration'] ?? 0,
      });
    }
    return {
      'ok': okCount == candidates.length,
      'has_migrations': true,
      'jobs_checked': candidates.length,
      'jobs_ok': okCount,
      'jobs_failed': candidates.length - okCount,
      'results': results,
    };
  }

  Future<File> exportJobReport(String jobId) async {
    _requireAdmin();
    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final jobs = await db.query(
      'data_migration_jobs',
      where: 'id = ? AND company_id = ?',
      whereArgs: [jobId, companyId],
      limit: 1,
    );
    if (jobs.isEmpty) throw StateError('La migración no pertenece a la organización activa.');
    final runs = await db.query('data_migration_runs', where: 'job_id = ?', whereArgs: [jobId], orderBy: 'id ASC');
    final issues = await db.query('data_migration_issues', where: 'job_id = ?', whereArgs: [jobId], orderBy: 'row_number ASC, id ASC');
    final reconciliation = await reconcileJob(jobId);
    final root = await Directory.systemTemp.createTemp('merkaerp_migration_report_');
    final file = File('${root.path}/migracion_$jobId.json');
    final safeJob = Map<String, Object?>.from(jobs.first)..remove('source_file_name')..remove('backup_path');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'format': 'MERKAERP_MIGRATION_REPORT_1',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'job': safeJob,
      'runs': runs,
      'issues': issues,
      'reconciliation': reconciliation,
      'privacy_note': 'El reporte no incluye la ruta local del archivo fuente ni el respaldo. Las filas de negocio permanecen en el historial interno de migración.',
    }), flush: true);
    return file;
  }

  /// Imports an entire legacy document directory into one controlled SGDEA case.
  ///
  /// The source hierarchy is preserved in each document title, every file is
  /// hashed by the document service, and a migration trace links the original
  /// relative path with its MerkaERP document id. Symbolic links are never
  /// followed. A full backup is created before the first document is copied.
  Future<LegacyDocumentImportResult> importLegacyDocumentFolder({
    required Directory sourceDirectory,
    required ProductFamily productFamily,
    String? publicEntityId,
    String accessLevel = 'restricted',
  }) async {
    _requireAdmin();
    await ensureSchema();
    if (!await sourceDirectory.exists()) {
      throw StateError('La carpeta documental seleccionada no existe.');
    }
    if (!{'public', 'restricted', 'confidential', 'reserved', 'personal_data'}.contains(accessLevel)) {
      throw ArgumentError.value(accessLevel, 'accessLevel', 'Nivel de acceso documental inválido.');
    }

    const maxFiles = 25000;
    final files = <File>[];
    await for (final entity in sourceDirectory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files.add(entity);
        if (files.length > maxFiles) {
          throw StateError('La carpeta supera el límite de seguridad de $maxFiles archivos por lote. Divídela en varios expedientes de migración.');
        }
      }
    }
    if (files.isEmpty) throw StateError('La carpeta seleccionada no contiene archivos.');
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final backup = await FullBackupService.instance.createFullBackup(label: 'pre_documentos_legados');
    final folderName = p.basename(p.normalize(sourceDirectory.path)).trim().isEmpty
        ? 'Documentos heredados'
        : p.basename(p.normalize(sourceDirectory.path));
    final caseId = await DocumentManagementService.instance.createCase(
      title: 'Migración documental · $folderName',
      description: 'Expediente creado por el asistente de migración. Conserva documentos digitales heredados de un sistema anterior; los títulos mantienen la ruta relativa original.',
      accessLevel: accessLevel,
    );
    final jobId = _uuid.v4();
    final startedAt = DateTime.now().toUtc().toIso8601String();
    final createdDocIds = <String>[];
    final manifest = <String>[];
    var totalBytes = 0;
    var runId = 0;
    var sequence = 0;

    await db.insert('data_migration_jobs', {
      'id': jobId,
      'company_id': companyId,
      'public_entity_id': publicEntityId,
      'product_family': productFamily.storageValue,
      'source_name': folderName,
      'source_type': 'directory',
      'source_file_name': folderName,
      'source_sha256': null,
      'status': 'running',
      'duplicate_policy': MigrationDuplicatePolicy.skip.name,
      'backup_path': backup.path,
      'summary_json': '{}',
      'started_at': startedAt,
      'created_by': AuditIdentity.current,
    });

    try {
      runId = await db.insert('data_migration_runs', {
        'job_id': jobId,
        'target_entity': 'legacy_documents',
        'source_sheet': folderName,
        'mapping_json': jsonEncode({'strategy': 'relative_path_to_document_title', 'access_level': accessLevel}),
        'rows_total': files.length,
        'rows_valid': files.length,
        'rows_imported': 0,
        'rows_skipped': 0,
        'rows_errors': 0,
        'started_at': startedAt,
      });

      final caseRows = await db.query('gd_expedientes', where: 'company_id = ? AND id = ?', whereArgs: [companyId, caseId], limit: 1);
      if (caseRows.isEmpty) throw StateError('No fue posible crear el expediente documental de migración.');
      sequence++;
      await db.insert('data_migration_changes', {
        'job_id': jobId,
        'run_id': runId,
        'sequence_no': sequence,
        'target_entity': 'legacy_documents',
        'table_name': 'gd_expedientes',
        'pk_column': 'id',
        'pk_value': '$caseId',
        'operation': 'insert',
        'before_json': null,
        'after_json': jsonEncode(caseRows.first),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final relativePath = p.relative(file.path, from: sourceDirectory.path).replaceAll('\\', '/');
        final documentId = await DocumentManagementService.instance.attachFile(
          sourcePath: file.path,
          title: relativePath,
          caseId: caseId,
          accessLevel: accessLevel,
          isOriginal: true,
        );
        createdDocIds.add(documentId);
        final rows = await db.query('gd_documents', where: 'company_id = ? AND id = ?', whereArgs: [companyId, documentId], limit: 1);
        if (rows.isEmpty) throw StateError('El documento $relativePath no quedó registrado en SGDEA.');
        final row = rows.first;
        final size = (row['size_bytes'] as num?)?.toInt() ?? await file.length();
        final hash = row['sha256']?.toString() ?? '';
        totalBytes += size;
        manifest.add('$relativePath\u0000$size\u0000$hash');

        final legacyId = await db.insert('data_migration_legacy_records', {
          'job_id': jobId,
          'run_id': runId,
          'row_number': index + 1,
          'target_entity': 'legacy_documents',
          'raw_json': jsonEncode({
            'relative_path': relativePath,
            'file_name': p.basename(file.path),
            'size_bytes': size,
            'sha256': hash,
          }),
          'normalized_json': jsonEncode({'case_id': caseId, 'document_id': documentId}),
          'imported': 1,
          'target_table': 'gd_documents',
          'target_pk': documentId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        if (legacyId <= 0) throw StateError('No se pudo registrar la trazabilidad del documento $relativePath.');

        sequence++;
        await db.insert('data_migration_changes', {
          'job_id': jobId,
          'run_id': runId,
          'sequence_no': sequence,
          'target_entity': 'legacy_documents',
          'table_name': 'gd_documents',
          'pk_column': 'id',
          'pk_value': documentId,
          'operation': 'insert',
          'before_json': null,
          'after_json': jsonEncode(row),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        final linkRows = await db.query(
          'gd_expediente_documents',
          where: 'company_id = ? AND expediente_id = ? AND document_id = ?',
          whereArgs: [companyId, caseId, documentId],
          limit: 1,
        );
        if (linkRows.isNotEmpty) {
          sequence++;
          await db.insert('data_migration_changes', {
            'job_id': jobId,
            'run_id': runId,
            'sequence_no': sequence,
            'target_entity': 'legacy_documents',
            'table_name': 'gd_expediente_documents',
            'pk_column': 'id',
            'pk_value': '${linkRows.first['id']}',
            'operation': 'insert',
            'before_json': null,
            'after_json': jsonEncode(linkRows.first),
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }

      manifest.sort();
      final manifestSha = crypto.sha256.convert(utf8.encode(manifest.join('\n'))).toString();
      final completedAt = DateTime.now().toUtc().toIso8601String();
      await db.update('data_migration_runs', {
        'rows_imported': files.length,
        'completed_at': completedAt,
      }, where: 'id = ? AND job_id = ?', whereArgs: [runId, jobId]);
      final summary = {
        'entity': 'legacy_documents',
        'case_id': caseId,
        'files_imported': files.length,
        'total_bytes': totalBytes,
        'manifest_sha256': manifestSha,
        'access_level': accessLevel,
      };
      await db.update('data_migration_jobs', {
        'status': 'completed',
        'source_sha256': manifestSha,
        'summary_json': jsonEncode(summary),
        'completed_at': completedAt,
      }, where: 'id = ? AND company_id = ?', whereArgs: [jobId, companyId]);
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'MIGRAR_DOCUMENTOS_LEGADOS',
        entidad: 'gd_expedientes',
        detalle: 'job=$jobId; expediente=$caseId; archivos=${files.length}; manifest=$manifestSha',
      );
      return LegacyDocumentImportResult(
        jobId: jobId,
        caseId: caseId,
        filesImported: files.length,
        totalBytes: totalBytes,
        manifestSha256: manifestSha,
        backupPath: backup.path,
      );
    } catch (error) {
      await _cleanupLegacyDocumentImport(companyId: companyId, caseId: caseId, documentIds: createdDocIds);
      await db.update('data_migration_jobs', {
        'status': 'failed',
        'summary_json': jsonEncode({'error': error.toString(), 'files_copied_before_failure': createdDocIds.length}),
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'id = ? AND company_id = ?', whereArgs: [jobId, companyId]);
      rethrow;
    }
  }

  Future<void> _cleanupLegacyDocumentImport({
    required int companyId,
    required int caseId,
    required List<String> documentIds,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final paths = <String>[];
    for (final id in documentIds) {
      final rows = await db.query('gd_documents', columns: ['file_path'], where: 'company_id = ? AND id = ?', whereArgs: [companyId, id], limit: 1);
      if (rows.isNotEmpty && rows.first['file_path'] != null) paths.add(rows.first['file_path'].toString());
    }
    await db.transaction((txn) async {
      if (documentIds.isNotEmpty) {
        final placeholders = List.filled(documentIds.length, '?').join(',');
        await txn.delete('gd_expediente_documents', where: 'company_id = ? AND document_id IN ($placeholders)', whereArgs: [companyId, ...documentIds]);
        await txn.delete('gd_documents', where: 'company_id = ? AND id IN ($placeholders)', whereArgs: [companyId, ...documentIds]);
      }
      await txn.delete('gd_expedientes', where: 'company_id = ? AND id = ?', whereArgs: [companyId, caseId]);
    });
    for (final filePath in paths) {
      try {
        final file = File(filePath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<MigrationImportResult> archiveAllDatasets({
    required File sourceFile,
    required List<TabularDataset> datasets,
    required ProductFamily productFamily,
    String? publicEntityId,
  }) async {
    _requireAdmin();
    if (datasets.isEmpty) throw StateError('No hay hojas o tablas para conservar.');
    await ensureSchema();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final backup = await FullBackupService.instance.createFullBackup(label: 'pre_archivo_legado');
    final jobId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final fileHash = (await crypto.sha256.bind(sourceFile.openRead()).first).toString();
    await db.insert('data_migration_jobs', {
      'id': jobId,
      'company_id': companyId,
      'public_entity_id': publicEntityId,
      'product_family': productFamily.storageValue,
      'source_name': sourceFile.uri.pathSegments.isEmpty ? sourceFile.path : sourceFile.uri.pathSegments.last,
      'source_type': sourceFile.path.split('.').last.toLowerCase(),
      'source_file_name': sourceFile.uri.pathSegments.isEmpty ? sourceFile.path : sourceFile.uri.pathSegments.last,
      'source_sha256': fileHash,
      'status': 'running',
      'duplicate_policy': MigrationDuplicatePolicy.skip.name,
      'backup_path': backup.path,
      'summary_json': '{}',
      'started_at': now,
      'created_by': AuditIdentity.current,
    });
    var imported = 0;
    var firstRun = 0;
    try {
      await db.transaction((txn) async {
        for (final dataset in datasets) {
          final runId = await txn.insert('data_migration_runs', {
            'job_id': jobId,
            'target_entity': 'legacy_archive',
            'source_sheet': dataset.name,
            'mapping_json': '{}',
            'rows_total': dataset.rows.length,
            'rows_valid': dataset.rows.length,
            'rows_imported': dataset.rows.length,
            'rows_skipped': 0,
            'rows_errors': 0,
            'started_at': now,
            'completed_at': DateTime.now().toIso8601String(),
          });
          if (firstRun == 0) firstRun = runId;
          for (var index = 0; index < dataset.rows.length; index++) {
            await txn.insert('data_migration_legacy_records', {
              'job_id': jobId,
              'run_id': runId,
              'row_number': index + 2,
              'target_entity': 'legacy_archive',
              'raw_json': jsonEncode(_sanitizeLegacyRow(dataset.rows[index])),
              'normalized_json': null,
              'imported': 1,
              'target_table': 'legacy_archive',
              'target_pk': '${dataset.name}:${index + 2}',
              'created_at': DateTime.now().toIso8601String(),
            });
            imported++;
          }
        }
      });
      final summary = {
        'entity': 'legacy_archive',
        'datasets': datasets.length,
        'rows_total': imported,
        'rows_imported': imported,
        'rows_skipped': 0,
        'rows_errors': 0,
        'source_sha256': fileHash,
      };
      await db.update('data_migration_jobs', {
        'status': 'completed',
        'summary_json': jsonEncode(summary),
        'completed_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [jobId]);
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'ARCHIVAR_SISTEMA_LEGADO',
        entidad: 'data_migration_jobs',
        detalle: 'job=$jobId; datasets=${datasets.length}; rows=$imported',
      );
      return MigrationImportResult(jobId: jobId, runId: firstRun, imported: imported, skipped: 0, errors: 0, backupPath: backup.path);
    } catch (error) {
      await db.update('data_migration_jobs', {
        'status': 'failed',
        'summary_json': jsonEncode({'error': error.toString()}),
        'completed_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [jobId]);
      rethrow;
    }
  }

  Future<(String, String)?> _importRow({
    required Transaction txn,
    required String jobId,
    required int runId,
    required int companyId,
    required String? publicEntityId,
    required String entityKey,
    required Map<String, Object?> row,
    required MigrationDuplicatePolicy duplicatePolicy,
  }) async {
    return switch (entityKey) {
      'customers' => _importCustomer(txn, jobId, runId, companyId, row, duplicatePolicy),
      'suppliers' => _importSupplier(txn, jobId, runId, companyId, row, duplicatePolicy),
      'products' => _importProduct(txn, jobId, runId, companyId, row, duplicatePolicy),
      'ar_opening' => _importReceivable(txn, jobId, runId, companyId, row),
      'ap_opening' => _importPayable(txn, jobId, runId, companyId, row),
      'public_third_parties' => _importPublicThirdParty(txn, jobId, runId, publicEntityId!, row, duplicatePolicy),
      'public_chart_accounts' => _importPublicAccount(txn, jobId, runId, publicEntityId!, row, duplicatePolicy),
      'public_budget_opening' => _importPublicBudget(txn, jobId, runId, publicEntityId!, row, duplicatePolicy),
      'public_accounting_opening' => throw StateError('Los saldos contables públicos se importan como un asiento de apertura único.'),
      _ => throw UnsupportedError('Destino de migración no implementado: $entityKey'),
    };
  }

  Future<(String, String)?> _importCustomer(Transaction txn, String jobId, int runId, int companyId, Map<String, Object?> row, MigrationDuplicatePolicy policy) async {
    final document = _text(row['document']);
    final name = _text(row['name']);
    final existing = document.isNotEmpty
        ? await txn.query('clientes', where: 'company_id = ? AND documento = ?', whereArgs: [companyId, document], limit: 1)
        : await txn.query('clientes', where: 'company_id = ? AND lower(nombre) = lower(?)', whereArgs: [companyId, name], limit: 1);
    final values = <String, Object?>{
      'company_id': companyId,
      'nombre': name,
      'documento': document,
      'telefono': _text(row['phone']),
      'direccion': _text(row['address']),
      'email': _text(row['email']),
      'estado': 'activo',
      'fecha': DateTime.now().toIso8601String(),
    };
    if (existing.isNotEmpty) {
      if (policy == MigrationDuplicatePolicy.skip) return null;
      final id = existing.first['id'].toString();
      final merged = _mergeNonEmpty(existing.first, values);
      await txn.update('clientes', merged, where: 'id = ?', whereArgs: [id]);
      await _recordChange(txn, jobId, runId, 'customers', 'clientes', 'id', id, 'update', existing.first, merged);
      return ('clientes', id);
    }
    final id = await txn.insert('clientes', values);
    await _recordChange(txn, jobId, runId, 'customers', 'clientes', 'id', '$id', 'insert', null, {...values, 'id': id});
    return ('clientes', '$id');
  }

  Future<(String, String)?> _importSupplier(Transaction txn, String jobId, int runId, int companyId, Map<String, Object?> row, MigrationDuplicatePolicy policy) async {
    final document = _text(row['document']);
    final name = _text(row['name']);
    final existing = document.isNotEmpty
        ? await txn.query('proveedores', where: 'company_id = ? AND nit = ?', whereArgs: [companyId, document], limit: 1)
        : await txn.query('proveedores', where: 'company_id = ? AND lower(nombre) = lower(?)', whereArgs: [companyId, name], limit: 1);
    final values = <String, Object?>{
      'company_id': companyId,
      'nombre': name,
      'nit': document,
      'telefono': _text(row['phone']),
      'direccion': _text(row['address']),
      'email': _text(row['email']),
      'contacto': _text(row['contact']),
      'estado': 'activo',
      'fecha': DateTime.now().toIso8601String(),
    };
    if (existing.isNotEmpty) {
      if (policy == MigrationDuplicatePolicy.skip) return null;
      final id = existing.first['id'].toString();
      final merged = _mergeNonEmpty(existing.first, values);
      await txn.update('proveedores', merged, where: 'id = ?', whereArgs: [id]);
      await _recordChange(txn, jobId, runId, 'suppliers', 'proveedores', 'id', id, 'update', existing.first, merged);
      return ('proveedores', id);
    }
    final id = await txn.insert('proveedores', values);
    await _recordChange(txn, jobId, runId, 'suppliers', 'proveedores', 'id', '$id', 'insert', null, {...values, 'id': id});
    return ('proveedores', '$id');
  }

  Future<(String, String)?> _importProduct(Transaction txn, String jobId, int runId, int companyId, Map<String, Object?> row, MigrationDuplicatePolicy policy) async {
    final currency = await MoneyCurrencyResolver.resolve(txn, companyId: companyId);
    final code = _text(row['code']);
    final barcode = _text(row['barcode']);
    final name = _text(row['name']);
    List<Map<String, Object?>> existing;
    if (barcode.isNotEmpty) {
      existing = await txn.query('productos', where: 'company_id = ? AND codigo_barras = ?', whereArgs: [companyId, barcode], limit: 1);
    } else if (code.isNotEmpty) {
      existing = await txn.query('productos', where: 'company_id = ? AND (codigo = ? OR referencia = ?)', whereArgs: [companyId, code, code], limit: 1);
    } else {
      existing = await txn.query('productos', where: 'company_id = ? AND lower(nombre) = lower(?)', whereArgs: [companyId, name], limit: 1);
    }
    final stock = _double(row['stock']);
    final values = <String, Object?>{
      'company_id': companyId,
      'codigo': code,
      'referencia': code,
      'nombre': name,
      'unidad_base': _text(row['unit']).isEmpty ? 'UND' : _text(row['unit']),
      'stock': stock,
      'costo': MoneyValue.fromMajorUnits(_moneyString(row['cost']) ?? '0', currency: currency).toSql(),
      'precio': MoneyValue.fromMajorUnits(_moneyString(row['price']) ?? '0', currency: currency).toSql(),
      'impuesto_pct': _double(row['tax']),
      'codigo_barras': barcode,
      'descripcion': _text(row['description']),
      'tipo_item': 'producto',
    };
    String id;
    if (existing.isNotEmpty) {
      if (policy == MigrationDuplicatePolicy.skip) return null;
      id = existing.first['id'].toString();
      final merged = _mergeNonEmpty(existing.first, values, allowZeroKeys: {'stock', 'costo', 'precio', 'impuesto_pct'});
      await txn.update('productos', merged, where: 'id = ?', whereArgs: [id]);
      await _recordChange(txn, jobId, runId, 'products', 'productos', 'id', id, 'update', existing.first, merged);
    } else {
      final inserted = await txn.insert('productos', values);
      id = '$inserted';
      await _recordChange(txn, jobId, runId, 'products', 'productos', 'id', id, 'insert', null, {...values, 'id': inserted});
    }
    final previousStock = existing.isEmpty ? 0.0 : _double(existing.first['stock']);
    final stockDelta = stock - previousStock;
    if (stockDelta != 0) {
      final movement = <String, Object?>{
        'company_id': companyId,
        'producto_id': int.tryParse(id),
        'tipo': 'MIGRACION_INICIAL',
        'cantidad': stockDelta,
        'stock_anterior': previousStock,
        'stock_nuevo': stock,
        'motivo': 'Existencia inicial importada desde sistema legado',
        'fecha': DateTime.now().toIso8601String(),
      };
      final movementId = await txn.insert('movimientos_inventario', movement);
      await _recordChange(txn, jobId, runId, 'products', 'movimientos_inventario', 'id', '$movementId', 'insert', null, {...movement, 'id': movementId});
    }
    return ('productos', id);
  }

  Future<(String, String)> _importReceivable(Transaction txn, String jobId, int runId, int companyId, Map<String, Object?> row) async {
    final currency = await MoneyCurrencyResolver.resolve(txn, companyId: companyId);
    final customerId = await _resolveCommercialParty(txn, companyId, true, _text(row['customer_document']), _text(row['customer_name']), jobId, runId);
    final amount = MoneyValue.fromMajorUnits(_moneyString(row['balance']) ?? '0', currency: currency).toSql();
    if ((amount as num).toInt() <= 0) throw StateError('El saldo por cobrar debe ser mayor que cero.');
    final values = <String, Object?>{
      'company_id': companyId,
      'cliente_id': customerId,
      'cliente': _text(row['customer_name']),
      'venta_id': null,
      'total': amount,
      'saldo': amount,
      'estado': 'pendiente',
      'fecha': _date(row['date']) ?? DateTime.now().toIso8601String(),
      'vencimiento': _date(row['due_date']),
      'descripcion': _withLegacyReference(_text(row['document_number']), _text(row['description'])),
    };
    final id = await txn.insert('cuentas_por_cobrar', values);
    await _recordChange(txn, jobId, runId, 'ar_opening', 'cuentas_por_cobrar', 'id', '$id', 'insert', null, {...values, 'id': id});
    return ('cuentas_por_cobrar', '$id');
  }

  Future<(String, String)> _importPayable(Transaction txn, String jobId, int runId, int companyId, Map<String, Object?> row) async {
    final currency = await MoneyCurrencyResolver.resolve(txn, companyId: companyId);
    final supplierId = await _resolveCommercialParty(txn, companyId, false, _text(row['supplier_document']), _text(row['supplier_name']), jobId, runId);
    final amount = MoneyValue.fromMajorUnits(_moneyString(row['balance']) ?? '0', currency: currency).toSql();
    if ((amount as num).toInt() <= 0) throw StateError('El saldo por pagar debe ser mayor que cero.');
    final values = <String, Object?>{
      'company_id': companyId,
      'proveedor': _text(row['supplier_name']),
      'proveedor_id': supplierId,
      'compra_id': null,
      'numero_factura': _text(row['document_number']),
      'total': amount,
      'saldo': amount,
      'estado': 'pendiente',
      'fecha': _date(row['date']) ?? DateTime.now().toIso8601String(),
      'descripcion': _text(row['description']).isEmpty ? 'Saldo inicial migrado' : _text(row['description']),
    };
    final id = await txn.insert('cuentas_por_pagar', values);
    await _recordChange(txn, jobId, runId, 'ap_opening', 'cuentas_por_pagar', 'id', '$id', 'insert', null, {...values, 'id': id});
    return ('cuentas_por_pagar', '$id');
  }

  Future<(String, String)?> _importPublicThirdParty(Transaction txn, String jobId, int runId, String entityId, Map<String, Object?> row, MigrationDuplicatePolicy policy) async {
    final document = _text(row['document']);
    final idType = _text(row['id_type']).isEmpty ? _guessIdType(document) : _text(row['id_type']).toUpperCase();
    final existing = await txn.query(
      'terceros_sector_publico',
      where: 'entidad_id = ? AND numero_identificacion = ?',
      whereArgs: [entityId, document],
      limit: 1,
    );
    final values = <String, Object?>{
      'entidad_id': entityId,
      'tipo_identificacion': idType,
      'numero_identificacion': document,
      'digito_verificacion': _text(row['check_digit']),
      'razon_social': _text(row['name']),
      'tipo_tercero': _text(row['third_party_type']).isEmpty ? 'proveedor' : _text(row['third_party_type']),
      'direccion': _text(row['address']),
      'telefono': _text(row['phone']),
      'email': _text(row['email']),
      'municipio': _text(row['city']),
      'departamento': _text(row['department']),
      'activo': 1,
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    };
    if (existing.isNotEmpty) {
      if (policy == MigrationDuplicatePolicy.skip) return null;
      final id = existing.first['id'].toString();
      final merged = _mergeNonEmpty(existing.first, values);
      await txn.update('terceros_sector_publico', merged, where: 'id = ?', whereArgs: [id]);
      await _recordChange(txn, jobId, runId, 'public_third_parties', 'terceros_sector_publico', 'id', id, 'update', existing.first, merged);
      return ('terceros_sector_publico', id);
    }
    final id = _uuid.v4();
    await txn.insert('terceros_sector_publico', {...values, 'id': id});
    await _recordChange(txn, jobId, runId, 'public_third_parties', 'terceros_sector_publico', 'id', id, 'insert', null, {...values, 'id': id});
    return ('terceros_sector_publico', id);
  }

  Future<(String, String)?> _importPublicAccount(Transaction txn, String jobId, int runId, String entityId, Map<String, Object?> row, MigrationDuplicatePolicy policy) async {
    final code = _text(row['code']);
    final clean = code.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final existing = await txn.query('plan_cuentas_cgc', where: 'entidad_id = ? AND codigo_cuenta = ?', whereArgs: [entityId, code], limit: 1);
    final values = <String, Object?>{
      'entidad_id': entityId,
      'codigo_cuenta': code,
      'nombre_cuenta': _text(row['name']),
      'clase': _normalizePublicClass(_text(row['class']), code),
      'grupo': _text(row['group']).isEmpty ? _prefix(clean, 1) : _text(row['group']),
      'subgrupo': _text(row['subgroup']).isEmpty ? _prefix(clean, 2) : _text(row['subgroup']),
      'cuenta': _prefix(clean, 4),
      'subcuenta': clean.length >= 6 ? _prefix(clean, 6) : null,
      'auxiliar': clean.length > 6 ? clean : null,
      'naturaleza': _normalizePublicNature(_text(row['nature']), code),
      'activa': 1,
    };
    if (existing.isNotEmpty) {
      if (policy == MigrationDuplicatePolicy.skip) return null;
      final id = existing.first['id'].toString();
      final merged = _mergeNonEmpty(existing.first, values);
      await txn.update('plan_cuentas_cgc', merged, where: 'id = ?', whereArgs: [id]);
      await _recordChange(txn, jobId, runId, 'public_chart_accounts', 'plan_cuentas_cgc', 'id', id, 'update', existing.first, merged);
      return ('plan_cuentas_cgc', id);
    }
    final id = _uuid.v4();
    await txn.insert('plan_cuentas_cgc', {...values, 'id': id});
    await _recordChange(txn, jobId, runId, 'public_chart_accounts', 'plan_cuentas_cgc', 'id', id, 'insert', null, {...values, 'id': id});
    return ('plan_cuentas_cgc', id);
  }

  Future<(String, String)?> _importPublicBudget(Transaction txn, String jobId, int runId, String entityId, Map<String, Object?> row, MigrationDuplicatePolicy policy) async {
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
    final currency = await MoneyCurrencyResolver.resolve(txn, companyId: companyId);
    final year = _int(row['year']);
    final code = _text(row['code']);
    final existing = await txn.query('apropiaciones', where: 'entidad_id = ? AND vigencia = ? AND codigo_rubro = ?', whereArgs: [entityId, '$year', code], limit: 1);
    final initial = MoneyValue.fromMajorUnits(_moneyString(row['initial_value']) ?? '0', currency: currency).toSql();
    final currentRaw = _moneyString(row['current_appropriation']);
    final current = MoneyValue.fromMajorUnits(currentRaw == null || currentRaw.isEmpty ? _moneyString(row['initial_value']) ?? '0' : currentRaw, currency: currency).toSql();
    final cdp = MoneyValue.fromMajorUnits(_moneyString(row['cdp_accumulated']) ?? '0', currency: currency).toSql();
    final rp = MoneyValue.fromMajorUnits(_moneyString(row['rp_accumulated']) ?? '0', currency: currency).toSql();
    final obligated = MoneyValue.fromMajorUnits(_moneyString(row['obligated_accumulated']) ?? '0', currency: currency).toSql();
    final paid = MoneyValue.fromMajorUnits(_moneyString(row['paid_accumulated']) ?? '0', currency: currency).toSql();
    if ([initial, current, cdp, rp, obligated, paid].any((value) => value < 0)) {
      throw StateError('Los valores presupuestales no pueden ser negativos.');
    }
    if (!(paid <= obligated && obligated <= rp && rp <= cdp && cdp <= current)) {
      throw StateError('El rubro $code viola Pagado ≤ Obligado ≤ RP ≤ CDP ≤ Apropiación vigente.');
    }
    final approvalDate = _date(row['approval_date']) ?? DateTime(year, 1, 1).toIso8601String();
    final values = <String, Object?>{
      'entidad_id': entityId,
      'vigencia': '$year',
      'codigo_rubro': code,
      'nombre_rubro': _text(row['name']),
      'valor_inicial': initial,
      'valor_apropiado': current,
      'valor_cdp': cdp,
      'valor_rp': rp,
      'valor_obligado': obligated,
      'valor_pagado': paid,
      'saldo_disponible': current - cdp,
      'fuente_financiacion': _text(row['funding_source']),
      'sector': _text(row['sector']),
      'programa': _text(row['program']),
      'subprograma': _text(row['subprogram']),
      'proyecto': _text(row['project']),
      'actividad': _text(row['activity']),
      'objeto_gasto': _text(row['expense_object']),
      'fecha_creacion': DateTime.now().toIso8601String(),
      'fecha_aprobacion_concejo': approvalDate,
      'acto_administrativo': _text(row['administrative_act']).isEmpty ? 'MIGRACIÓN DE SISTEMA LEGADO' : _text(row['administrative_act']),
      'activo': 1,
      'observaciones': cdp == 0 && rp == 0 && obligated == 0 && paid == 0
          ? 'Apropiación importada mediante asistente de migración MerkaERP.'
          : 'Snapshot de apertura migrado. La ejecución acumulada no reconstruye documentos históricos CDP/RP/obligación/pago; éstos deben conservarse en Archivo Legado/SGDEA.',
    };
    if (existing.isNotEmpty) {
      if (policy == MigrationDuplicatePolicy.skip) return null;
      final id = existing.first['id'].toString();
      if ((_int(existing.first['valor_cdp']) != 0) || (_int(existing.first['valor_rp']) != 0) || (_int(existing.first['valor_obligado']) != 0) || (_int(existing.first['valor_pagado']) != 0)) {
        throw StateError('El rubro $code ya tiene ejecución en MerkaERP; no puede fusionarse desde una migración.');
      }
      final merged = _mergeNonEmpty(existing.first, values, allowZeroKeys: {'valor_inicial', 'valor_apropiado', 'valor_cdp', 'valor_rp', 'valor_obligado', 'valor_pagado', 'saldo_disponible'});
      await txn.update('apropiaciones', merged, where: 'id = ?', whereArgs: [id]);
      await _recordChange(txn, jobId, runId, 'public_budget_opening', 'apropiaciones', 'id', id, 'update', existing.first, merged);
      return ('apropiaciones', id);
    }
    final id = _uuid.v4();
    await txn.insert('apropiaciones', {...values, 'id': id});
    await _recordChange(txn, jobId, runId, 'public_budget_opening', 'apropiaciones', 'id', id, 'insert', null, {...values, 'id': id});
    return ('apropiaciones', id);
  }

  Future<(int, int)> _importPublicAccountingOpening({
    required Transaction txn,
    required String jobId,
    required int runId,
    required int companyId,
    required String entityId,
    required List<Map<String, Object?>> rows,
  }) async {
    if (rows.isEmpty) throw StateError('El asiento público de apertura está vacío.');
    final currency = await MoneyCurrencyResolver.resolve(txn, companyId: companyId);
    final years = rows.map((row) => _int(row['year'])).toSet();
    if (years.length != 1 || years.first <= 0) {
      throw StateError('Todas las líneas del asiento público de apertura deben pertenecer a una única vigencia válida.');
    }
    final year = years.first;
    var debitTotal = MoneyValue.fromMajorUnits('0', currency: currency);
    var creditTotal = MoneyValue.fromMajorUnits('0', currency: currency);
    final accountTotals = <String, ({int debit, int credit, String name})>{};
    for (final row in rows) {
      final code = _text(row['account_code']);
      if (code.isEmpty) throw StateError('Existe una línea contable pública sin código de cuenta.');
      final debitMoney = MoneyValue.fromMajorUnits(_moneyString(row['debit']) ?? '0', currency: currency);
      final creditMoney = MoneyValue.fromMajorUnits(_moneyString(row['credit']) ?? '0', currency: currency);
      debitTotal += debitMoney;
      creditTotal += creditMoney;
      final previous = accountTotals[code];
      accountTotals[code] = (
        debit: (previous?.debit ?? 0) + debitMoney.toSql(),
        credit: (previous?.credit ?? 0) + creditMoney.toSql(),
        name: _text(row['account_name']).isEmpty ? (previous?.name ?? '') : _text(row['account_name']),
      );
    }
    if (debitTotal.minorUnits != creditTotal.minorUnits) {
      throw StateError('El asiento público inicial no cuadra: débitos ${debitTotal.format()} vs créditos ${creditTotal.format()}.');
    }
    if (debitTotal.minorUnits == 0) throw StateError('El asiento público inicial está vacío.');

    // Antes de crear cualquier línea se verifica que la vigencia no tenga
    // saldos operativos para las cuentas de apertura. Así nunca se mezcla una
    // migración con movimientos ya registrados en MerkaERP.
    for (final code in accountTotals.keys) {
      final balanceRows = await txn.query(
        'saldos_cuentas',
        where: 'entidad_id = ? AND cuenta_codigo = ? AND vigencia = ?',
        whereArgs: [entityId, code, '$year'],
        limit: 1,
      );
      if (balanceRows.isNotEmpty &&
          (_int(balanceRows.first['saldo_deudor']) != 0 || _int(balanceRows.first['saldo_acreedor']) != 0)) {
        throw StateError('La cuenta $code ya tiene saldo en la vigencia $year; no se mezclará con una apertura migrada.');
      }
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final entryId = _uuid.v4();
    final entry = <String, Object?>{
      'id': entryId,
      'entidad_id': entityId,
      'numero_asiento': 'MIG-AP-$year-$stamp',
      'fecha_asiento': DateTime(year, 1, 1).toIso8601String(),
      'descripcion': 'Saldos iniciales públicos migrados desde sistema legado',
      'tipo_asiento': 'manual',
      'estado': 'registrado',
      'total_debito': debitTotal.toSql(),
      'total_credito': creditTotal.toSql(),
      'usuario_creo': AuditIdentity.current,
      'referencia_origen': 'MIGRACION-$jobId',
      'tipo_documento_origen': 'MIGRACION_APERTURA',
      'observaciones': 'Asiento de apertura creado por el asistente de migración; el histórico fuente se conserva por separado.',
    };
    await txn.insert('asientos_contables_sp', entry);
    await _recordChange(txn, jobId, runId, 'public_accounting_opening', 'asientos_contables_sp', 'id', entryId, 'insert', null, entry);

    var imported = 0;
    final resolvedNames = <String, String>{};
    for (final row in rows) {
      final rowNumber = row['__row_number'] as int;
      final code = _text(row['account_code']);
      final name = resolvedNames[code] ??= await _resolvePublicAccount(
        txn,
        entityId,
        code,
        _text(row['account_name']),
        _text(row['nature']),
        jobId,
        runId,
      );
      final debit = MoneyValue.fromMajorUnits(_moneyString(row['debit']) ?? '0', currency: currency).toSql();
      final credit = MoneyValue.fromMajorUnits(_moneyString(row['credit']) ?? '0', currency: currency).toSql();
      final detailId = _uuid.v4();
      final detail = <String, Object?>{
        'id': detailId,
        'asiento_id': entryId,
        'cuenta_codigo': code,
        'cuenta_nombre': name,
        'debito': debit,
        'credito': credit,
        'referencia_id': 'MIGRACION:$jobId:$rowNumber',
      };
      await txn.insert('detalles_asientos', detail);
      await _recordChange(txn, jobId, runId, 'public_accounting_opening', 'detalles_asientos', 'id', detailId, 'insert', null, detail);
      await txn.update('data_migration_legacy_records', {
        'imported': 1,
        'target_table': 'detalles_asientos',
        'target_pk': detailId,
      }, where: 'job_id = ? AND run_id = ? AND row_number = ?', whereArgs: [jobId, runId, rowNumber]);
      imported++;
    }

    for (final entry in accountTotals.entries) {
      final code = entry.key;
      final total = entry.value;
      final balanceRows = await txn.query(
        'saldos_cuentas',
        where: 'entidad_id = ? AND cuenta_codigo = ? AND vigencia = ?',
        whereArgs: [entityId, code, '$year'],
        limit: 1,
      );
      final balanceId = balanceRows.isEmpty ? _uuid.v4() : balanceRows.first['id'].toString();
      final name = resolvedNames[code] ?? total.name;
      final balance = <String, Object?>{
        'id': balanceId,
        'entidad_id': entityId,
        'cuenta_codigo': code,
        'cuenta_nombre': name,
        'saldo_deudor': total.debit,
        'saldo_acreedor': total.credit,
        'saldo_neto': total.debit - total.credit,
        'fecha_ultimo_movimiento': DateTime(year, 1, 1).toIso8601String(),
        'vigencia': '$year',
      };
      if (balanceRows.isEmpty) {
        await txn.insert('saldos_cuentas', balance);
        await _recordChange(txn, jobId, runId, 'public_accounting_opening', 'saldos_cuentas', 'id', balanceId, 'insert', null, balance);
      } else {
        await txn.update('saldos_cuentas', balance, where: 'id = ?', whereArgs: [balanceId]);
        await _recordChange(txn, jobId, runId, 'public_accounting_opening', 'saldos_cuentas', 'id', balanceId, 'update', balanceRows.first, balance);
      }
    }
    return (imported, 0);
  }

  Future<String> _resolvePublicAccount(Transaction txn, String entityId, String code, String name, String nature, String jobId, int runId) async {
    final existing = await txn.query('plan_cuentas_cgc', where: 'entidad_id = ? AND codigo_cuenta = ?', whereArgs: [entityId, code], limit: 1);
    if (existing.isNotEmpty) return existing.first['nombre_cuenta']?.toString() ?? name;
    if (name.trim().isEmpty) throw StateError('La cuenta pública $code no existe y no se suministró nombre para crearla.');
    final clean = code.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final values = <String, Object?>{
      'id': _uuid.v4(),
      'entidad_id': entityId,
      'codigo_cuenta': code,
      'nombre_cuenta': name,
      'clase': _normalizePublicClass('', code),
      'grupo': _prefix(clean, 1),
      'subgrupo': _prefix(clean, 2),
      'cuenta': _prefix(clean, 4),
      'subcuenta': clean.length >= 6 ? _prefix(clean, 6) : null,
      'auxiliar': clean.length > 6 ? clean : null,
      'naturaleza': _normalizePublicNature(nature, code),
      'activa': 1,
    };
    await txn.insert('plan_cuentas_cgc', values);
    await _recordChange(txn, jobId, runId, 'public_accounting_opening', 'plan_cuentas_cgc', 'id', values['id'].toString(), 'insert', null, values);
    return name;
  }

  Future<(int, int)> _importAccountingOpening({
    required Transaction txn,
    required String jobId,
    required int runId,
    required int companyId,
    required List<Map<String, Object?>> rows,
  }) async {
    final currency = await MoneyCurrencyResolver.resolve(txn, companyId: companyId);
    var debitTotal = MoneyValue.fromMajorUnits('0', currency: currency);
    var creditTotal = MoneyValue.fromMajorUnits('0', currency: currency);
    for (final row in rows) {
      debitTotal += MoneyValue.fromMajorUnits(_moneyString(row['debit']) ?? '0', currency: currency);
      creditTotal += MoneyValue.fromMajorUnits(_moneyString(row['credit']) ?? '0', currency: currency);
    }
    if (debitTotal.minorUnits != creditTotal.minorUnits) {
      throw StateError('El asiento inicial no cuadra: débitos ${debitTotal.format()} vs créditos ${creditTotal.format()}.');
    }
    if (debitTotal.minorUnits == 0) throw StateError('El asiento inicial está vacío.');

    final entry = <String, Object?>{
      'company_id': companyId,
      'fecha': DateTime.now().toIso8601String(),
      'concepto': 'Saldos iniciales migrados desde sistema legado',
      'referencia': 'MIGRACION-$jobId',
      'origen': 'migracion',
      'estado': 'registrado',
    };
    final entryId = await txn.insert('asientos_contables', entry);
    await _recordChange(txn, jobId, runId, 'accounting_opening', 'asientos_contables', 'id', '$entryId', 'insert', null, {...entry, 'id': entryId});

    var imported = 0;
    for (final row in rows) {
      final rowNumber = row['__row_number'] as int;
      final accountCode = _text(row['account_code']);
      final accountId = await _resolveCommercialAccount(txn, companyId, accountCode, _text(row['account_name']), _text(row['nature']), jobId, runId);
      final debit = MoneyValue.fromMajorUnits(_moneyString(row['debit']) ?? '0', currency: currency).toSql();
      final credit = MoneyValue.fromMajorUnits(_moneyString(row['credit']) ?? '0', currency: currency).toSql();
      final line = <String, Object?>{
        'company_id': companyId,
        'asiento_id': entryId,
        'cuenta_id': accountId,
        'descripcion': _text(row['description']).isEmpty ? 'Saldo inicial $accountCode' : _text(row['description']),
        'debito': debit,
        'credito': credit,
        'tercero': _text(row['third_party']),
      };
      final lineId = await txn.insert('asiento_lineas', line);
      await _recordChange(txn, jobId, runId, 'accounting_opening', 'asiento_lineas', 'id', '$lineId', 'insert', null, {...line, 'id': lineId});
      await txn.update('data_migration_legacy_records', {
        'imported': 1,
        'target_table': 'asiento_lineas',
        'target_pk': '$lineId',
      }, where: 'job_id = ? AND run_id = ? AND row_number = ?', whereArgs: [jobId, runId, rowNumber]);
      imported++;
    }
    return (imported, 0);
  }

  Future<int> _resolveCommercialParty(Transaction txn, int companyId, bool customer, String document, String name, String jobId, int runId) async {
    final table = customer ? 'clientes' : 'proveedores';
    final documentColumn = customer ? 'documento' : 'nit';
    List<Map<String, Object?>> rows = const [];
    if (document.isNotEmpty) {
      rows = await txn.query(table, where: 'company_id = ? AND $documentColumn = ?', whereArgs: [companyId, document], limit: 1);
    }
    if (rows.isEmpty) {
      rows = await txn.query(table, where: 'company_id = ? AND lower(nombre) = lower(?)', whereArgs: [companyId, name], limit: 1);
    }
    if (rows.isNotEmpty) return (rows.first['id'] as num).toInt();
    final values = customer
        ? <String, Object?>{'company_id': companyId, 'nombre': name, 'documento': document, 'estado': 'activo', 'fecha': DateTime.now().toIso8601String()}
        : <String, Object?>{'company_id': companyId, 'nombre': name, 'nit': document, 'estado': 'activo', 'fecha': DateTime.now().toIso8601String()};
    final id = await txn.insert(table, values);
    await _recordChange(txn, jobId, runId, customer ? 'ar_opening' : 'ap_opening', table, 'id', '$id', 'insert', null, {...values, 'id': id});
    return id;
  }

  Future<int> _resolveCommercialAccount(Transaction txn, int companyId, String code, String name, String nature, String jobId, int runId) async {
    final existing = await txn.query('cuentas_contables', where: 'company_id = ? AND codigo = ?', whereArgs: [companyId, code], limit: 1);
    if (existing.isNotEmpty) return (existing.first['id'] as num).toInt();
    if (name.trim().isEmpty) throw StateError('La cuenta $code no existe y no se suministró nombre para crearla.');
    final values = <String, Object?>{
      'company_id': companyId,
      'codigo': code,
      'nombre': name,
      'tipo': _accountTypeFromCode(code),
      'naturaleza': _normalizeNature(nature.isEmpty ? _defaultNatureFromCode(code) : nature),
      'activa': 1,
    };
    final id = await txn.insert('cuentas_contables', values);
    await _recordChange(txn, jobId, runId, 'accounting_opening', 'cuentas_contables', 'id', '$id', 'insert', null, {...values, 'id': id});
    return id;
  }

  Future<void> _recordChange(
    Transaction txn,
    String jobId,
    int runId,
    String entity,
    String table,
    String pkColumn,
    String pkValue,
    String operation,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  ) async {
    final count = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM data_migration_changes WHERE job_id = ?', [jobId])) ?? 0;
    await txn.insert('data_migration_changes', {
      'job_id': jobId,
      'run_id': runId,
      'sequence_no': count + 1,
      'target_entity': entity,
      'table_name': table,
      'pk_column': pkColumn,
      'pk_value': pkValue,
      'operation': operation,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Map<String, Object?> _mergeNonEmpty(Map<String, Object?> existing, Map<String, Object?> incoming, {Set<String> allowZeroKeys = const {}}) {
    final merged = <String, Object?>{};
    for (final entry in incoming.entries) {
      final value = entry.value;
      final nonEmpty = value != null && (value is! String || value.trim().isNotEmpty);
      final numericZeroAllowed = allowZeroKeys.contains(entry.key) && value is num;
      if (nonEmpty || numericZeroAllowed) merged[entry.key] = value;
    }
    return merged;
  }

  Object? _normalizeValue(String raw, MigrationFieldType type) {
    return switch (type) {
      MigrationFieldType.text => raw.trim(),
      MigrationFieldType.email => _validateEmail(raw),
      MigrationFieldType.integer => _parseInt(raw),
      MigrationFieldType.decimal => _parseDecimal(raw),
      MigrationFieldType.money => _normalizeMoney(raw),
      MigrationFieldType.date => _parseDate(raw),
      MigrationFieldType.boolean => _parseBoolean(raw),
    };
  }

  String _validateEmail(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      throw const FormatException('correo electrónico inválido');
    }
    return value;
  }

  int _parseInt(String raw) {
    final normalized = raw.replaceAll(RegExp(r'[^0-9\-]'), '');
    final value = int.tryParse(normalized);
    if (value == null) throw const FormatException('entero inválido');
    return value;
  }

  double _parseDecimal(String raw) {
    final normalized = _normalizeNumber(raw, money: false);
    final value = double.tryParse(normalized);
    if (value == null) throw const FormatException('número inválido');
    return value;
  }

  String _normalizeMoney(String raw) {
    final normalized = _normalizeNumber(raw, money: true);
    if (double.tryParse(normalized) == null) throw const FormatException('valor monetario inválido');
    return normalized;
  }

  String _normalizeNumber(String raw, {required bool money}) {
    final trimmed = raw.trim();
    final negativeByParentheses = trimmed.startsWith('(') && trimmed.endsWith(')');
    var value = trimmed.replaceAll(RegExp(r'[^0-9,\.\-]'), '');
    if (value.isEmpty || value == '-') return '0';
    if (negativeByParentheses && !value.startsWith('-')) value = '-$value';
    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      final decimalSeparator = comma > dot ? ',' : '.';
      final thousandSeparator = decimalSeparator == ',' ? '.' : ',';
      value = value.replaceAll(thousandSeparator, '');
      if (decimalSeparator == ',') value = value.replaceAll(',', '.');
      return value;
    }
    if (comma >= 0) {
      final digitsAfter = value.length - comma - 1;
      if (digitsAfter <= 2 || !money) {
        return value.replaceAll(',', '.');
      }
      return value.replaceAll(',', '');
    }
    if (dot >= 0 && money) {
      final digitsAfter = value.length - dot - 1;
      if (digitsAfter == 3 && value.indexOf('.') == dot) {
        return value.replaceAll('.', '');
      }
    }
    return value;
  }

  String _parseDate(String raw) {
    final value = raw.trim();
    final serial = int.tryParse(value);
    if (serial != null && serial >= 1 && serial <= 100000) {
      // Serial de fechas usado por Excel (compatibilidad 1900, incluyendo su
      // convención histórica): 1899-12-30 produce la fecha esperada.
      return DateTime(1899, 12, 30).add(Duration(days: serial)).toIso8601String();
    }
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toIso8601String();
    for (final format in ['dd/MM/yyyy', 'd/M/yyyy', 'dd-MM-yyyy', 'd-M-yyyy', 'MM/dd/yyyy']) {
      try {
        return DateFormat(format).parseStrict(value).toIso8601String();
      } catch (_) {}
    }
    throw const FormatException('fecha inválida; usa AAAA-MM-DD o DD/MM/AAAA');
  }

  int _parseBoolean(String raw) {
    final value = _normalize(raw);
    if ({'1', 'si', 'sí', 'true', 'verdadero', 'activo'}.contains(value)) return 1;
    if ({'0', 'no', 'false', 'falso', 'inactivo'}.contains(value)) return 0;
    throw const FormatException('valor lógico inválido');
  }

  String _normalize(String value) {
    var result = value.trim().toLowerCase();
    const replacements = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    replacements.forEach((from, to) => result = result.replaceAll(from, to));
    return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _text(Object? value) => value?.toString().trim() ?? '';
  String? _moneyString(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }
  double _double(Object? value) => value is num ? value.toDouble() : double.tryParse(_text(value).replaceAll(',', '.')) ?? 0;
  double _decimalValue(Object? value, {double fallback = 0}) {
    final text = _text(value);
    if (text.isEmpty) return fallback;
    return double.tryParse(text.replaceAll(',', '.')) ?? fallback;
  }
  int _int(Object? value) => value is num ? value.toInt() : int.tryParse(_text(value)) ?? 0;
  String? _date(Object? value) => _text(value).isEmpty ? null : _text(value);

  String _withLegacyReference(String document, String description) {
    final parts = <String>['Saldo inicial migrado'];
    if (document.isNotEmpty) parts.add('documento $document');
    if (description.isNotEmpty) parts.add(description);
    return parts.join(' · ');
  }

  String _guessIdType(String document) => document.length == 9 ? 'NIT' : 'CC';

  String _normalizeNature(String raw) {
    final value = _normalize(raw);
    if (value.startsWith('cred') || value == 'haber') return 'credito';
    return 'debito';
  }

  String _prefix(String value, int length) {
    if (value.isEmpty) return '';
    return value.substring(0, value.length < length ? value.length : length);
  }

  String _normalizePublicNature(String raw, String code) {
    final value = _normalize(raw);
    if (value.startsWith('acre') || value.startsWith('cred') || value == 'haber') return 'acreedora';
    if (value.startsWith('deud') || value.startsWith('deb') || value == 'debe') return 'deudora';
    return {'2', '3', '4', '9'}.contains(code.isEmpty ? '' : code.substring(0, 1)) ? 'acreedora' : 'deudora';
  }

  String _normalizePublicClass(String raw, String code) {
    final value = _normalize(raw);
    if (value.contains('activo')) return 'activo';
    if (value.contains('pasivo')) return 'pasivo';
    if (value.contains('patrimonio')) return 'patrimonio';
    if (value.contains('ingreso')) return 'ingresos';
    if (value.contains('gasto')) return 'gastos';
    if (value.contains('costo')) return 'costoVentas';
    if (value.contains('orden') && (value.contains('acre') || value.contains('9'))) return 'cuentasOrdenAcreedoras';
    if (value.contains('orden')) return 'cuentasOrdenDeudoras';
    if (code.isEmpty) return 'activo';
    return switch (code.substring(0, 1)) {
      '1' => 'activo',
      '2' => 'pasivo',
      '3' => 'patrimonio',
      '4' => 'ingresos',
      '5' => 'gastos',
      '6' || '7' => 'costoVentas',
      '8' => 'cuentasOrdenDeudoras',
      '9' => 'cuentasOrdenAcreedoras',
      _ => 'activo',
    };
  }

  String _accountTypeFromCode(String code) {
    if (code.isEmpty) return 'activo';
    return switch (code.substring(0, 1)) {
      '1' => 'activo',
      '2' => 'pasivo',
      '3' => 'patrimonio',
      '4' => 'ingreso',
      '5' || '6' || '7' => 'gasto',
      _ => 'orden',
    };
  }

  String _defaultNatureFromCode(String code) {
    if (code.isEmpty) return 'debito';
    return {'2', '3', '4'}.contains(code.substring(0, 1)) ? 'credito' : 'debito';
  }

  void _requireAdmin() {
    if (!AppSession.puedeAdministrar()) {
      throw StateError('La migración de datos requiere una sesión administradora.');
    }
  }

  Map<String, Object?> _sanitizeLegacyRow(Map<String, Object?> row) {
    final sensitive = RegExp(
      r'(password|passwd|contrasena|contraseña|secret|token|authorization|cookie|api[_ -]?key|client[_ -]?secret|private[_ -]?key|pin|credential|certificado|certificate|hmac)',
      caseSensitive: false,
    );
    return <String, Object?>{
      for (final entry in row.entries)
        entry.key: sensitive.hasMatch(entry.key) ? '<redacted>' : entry.value,
    };
  }

  bool _safeIdentifier(String value) => RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  String _normalizeComparable(Object? value) {
    if (value == null) return '<null>';
    if (value is int) return 'num:$value';
    if (value is double) {
      if (value.isNaN) return 'num:nan';
      if (value.isInfinite) return value.isNegative ? 'num:-inf' : 'num:inf';
      if (value == value.truncateToDouble()) return 'num:${value.toStringAsFixed(0)}';
      var text = value.toStringAsPrecision(15);
      if (!text.contains('e') && !text.contains('E') && text.contains('.')) {
        text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
      return 'num:$text';
    }
    if (value is bool) return 'bool:$value';
    return 'text:${value.toString()}';
  }
}
