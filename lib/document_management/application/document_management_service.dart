import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../app_session.dart';
import '../../db_helper.dart';
import '../../core/security/action_permission.dart';
import '../../sector_publico/security/roles_permisos_service.dart';
import '../../licensing/domain/product_family.dart';
import '../../services/licencia_service.dart';
import '../../integrations/application/institutional_connector_service.dart';
import '../../integrations/application/integration_settings_service.dart';
import '../../integrations/domain/integration_definition.dart';
import '../database/schema_document_management.dart';
import '../domain/document_models.dart';

class DocumentManagementService {
  DocumentManagementService._();
  static final DocumentManagementService instance = DocumentManagementService._();
  static const _uuid = Uuid();

  Future<void> ensureInitialized([DatabaseExecutor? executor]) async {
    final db = executor ?? await DatabaseHelper.instance.database;
    await SchemaDocumentManagement.createTables(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await _seedSettings(db, companyId);
    await _seedInstruments(db, companyId);
  }

  Future<bool> get isPublicSector async {
    final license = await LicenciaService.instance.obtenerLicencia();
    return license?.productFamily == ProductFamily.publicSector;
  }


  Future<bool> _hasFullDocumentAccess() async {
    if (AppSession.puedeAdministrar()) return true;
    if (await isPublicSector) {
      return AppSession.puedeEjecutarPermiso(Permiso.administrarGestionDocumental) ||
          AppSession.puedeEjecutarPermiso(Permiso.consultarTodo);
    }
    return false;
  }

  Future<void> _requireDocumentPermission({
    required AppAction commercialAction,
    required Permiso publicPermission,
  }) async {
    if (AppSession.puedeAdministrar()) return;
    if (await isPublicSector) {
      if (AppSession.puedeEjecutarPermiso(publicPermission) ||
          AppSession.puedeEjecutarPermiso(Permiso.administrarGestionDocumental)) {
        return;
      }
    } else if (AppSession.puedeEjecutarAccion('document_management', commercialAction)) {
      return;
    }
    throw StateError('El usuario no tiene permiso para esta operación documental.');
  }

  Future<void> _requirePublicDocumentPermission(Permiso permission) async {
    if (!await isPublicSector) {
      throw StateError('Esta operación archivística institucional solo está disponible en MerkaERP Público.');
    }
    await _requireDocumentPermission(
      commercialAction: AppAction.configure,
      publicPermission: permission,
    );
  }

  Future<void> _requireDocumentAdministrator() async {
    if (await _hasFullDocumentAccess()) return;
    if (!await isPublicSector &&
        AppSession.puedeEjecutarAccion('document_management', AppAction.configure)) {
      return;
    }
    throw StateError('La operación requiere administración de gestión documental.');
  }

  bool _rowVisibleToCurrentUser(Map<String, Object?> row, {required bool fullAccess}) {
    if (fullAccess) return true;
    final access = row['access_level']?.toString().trim().toLowerCase() ?? 'public';
    if (access == 'public') return true;
    final userId = AppSession.usuarioId;
    if (userId == null || userId.isEmpty) return false;
    return row['created_by']?.toString() == userId ||
        row['assigned_user_id']?.toString() == userId;
  }

  Future<void> _seedSettings(DatabaseExecutor db, int companyId) async {
    const defaults = <String, String>{
      'incoming_pattern': 'E-{YEAR}-{SEQ6}',
      'outgoing_pattern': 'S-{YEAR}-{SEQ6}',
      'internal_pattern': 'I-{YEAR}-{SEQ6}',
      'case_pattern': 'EXP-{YEAR}-{SEQ6}',
      'transfer_pattern': 'TR-{YEAR}-{SEQ6}',
      'work_weekdays': '1,2,3,4,5',
      'require_comment_on_close': 'true',
      'allow_delete_originals': 'false',
      'default_access_level': 'public',
      'document_repository_version': '1',
    };
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in defaults.entries) {
      await db.insert(
        'gd_settings',
        {
          'company_id': companyId,
          'setting_key': entry.key,
          'setting_value': entry.value,
          'updated_at': now,
          'updated_by': 'system',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _seedInstruments(DatabaseExecutor db, int companyId) async {
    final public = await isPublicSector;
    final common = <String, String>{
      'document_policy': 'Política de gestión documental',
      'information_security': 'Política de seguridad y acceso documental',
      'retention_policy': 'Política de conservación y retención',
      'metadata_scheme': 'Esquema institucional de metadatos',
    };
    final publicInstruments = <String, String>{
      'pgd': 'Programa de Gestión Documental (PGD)',
      'pinar': 'Plan Institucional de Archivos (PINAR)',
      'ccd': 'Cuadro de Clasificación Documental (CCD)',
      'trd': 'Tablas de Retención Documental (TRD)',
      'tvd': 'Tablas de Valoración Documental (TVD)',
      'sic': 'Sistema Integrado de Conservación (SIC)',
      'fuid': 'Formato Único de Inventario Documental (FUID)',
      'terminology_bank': 'Banco terminológico de series y subseries',
      'sgdea_requirements': 'Modelo de requisitos del SGDEA',
      'information_assets': 'Registro de Activos de Información',
      'classified_index': 'Índice de Información Clasificada y Reservada',
      'publication_scheme': 'Esquema de Publicación de Información',
    };
    final now = DateTime.now().toUtc().toIso8601String();
    final all = <String, String>{...common, if (public) ...publicInstruments};
    for (final entry in all.entries) {
      await db.insert(
        'gd_instruments',
        {
          'company_id': companyId,
          'instrument_key': entry.key,
          'name': entry.value,
          'status': 'pending',
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<DocumentDashboardSnapshot> dashboard() async {
    await _requireDocumentPermission(
      commercialAction: AppAction.view,
      publicPermission: Permiso.consultarGestionDocumental,
    );
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final tomorrowStart = DateTime(now.year, now.month, now.day + 1).toUtc().toIso8601String();
    final nowIso = now.toUtc().toIso8601String();
    final fullAccess = await _hasFullDocumentAccess();
    final userId = AppSession.usuarioId ?? '';

    Future<int> count(String table, String where, List<Object?> args) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table WHERE $where', args);
      return Sqflite.firstIntValue(rows) ?? 0;
    }

    String radVisibility(String predicate) => fullAccess
        ? 'company_id = ? AND $predicate'
        : "company_id = ? AND (access_level = 'public' OR created_by = ? OR assigned_user_id = ?) AND $predicate";
    List<Object?> radArgs(List<Object?> tail) => fullAccess
        ? <Object?>[companyId, ...tail]
        : <Object?>[companyId, userId, userId, ...tail];
    String caseVisibility(String predicate) => fullAccess
        ? 'company_id = ? AND $predicate'
        : "company_id = ? AND (access_level = 'public' OR created_by = ?) AND $predicate";
    List<Object?> caseArgs(List<Object?> tail) => fullAccess
        ? <Object?>[companyId, ...tail]
        : <Object?>[companyId, userId, ...tail];

    return DocumentDashboardSnapshot(
      today: await count(
        'gd_radicados',
        radVisibility('received_at >= ? AND received_at < ?'),
        radArgs([todayStart, tomorrowStart]),
      ),
      pending: await count(
        'gd_radicados',
        radVisibility("status NOT IN ('closed','archived','cancelled')"),
        radArgs(const []),
      ),
      overdue: await count(
        'gd_radicados',
        radVisibility("due_at IS NOT NULL AND due_at < ? AND status NOT IN ('closed','archived','cancelled')"),
        radArgs([nowIso]),
      ),
      forSignature: await count(
        'gd_radicados',
        radVisibility("status = 'for_signature'"),
        radArgs(const []),
      ),
      openCases: await count(
        'gd_expedientes',
        caseVisibility("status = 'open'"),
        caseArgs(const []),
      ),
      activeLoans: await count(
        'gd_loans',
        fullAccess ? "company_id = ? AND status = 'active'" : "company_id = ? AND borrower_user_id = ? AND status = 'active'",
        fullAccess ? [companyId] : [companyId, userId],
      ),
      transfersPending: fullAccess
          ? await count('gd_transfers', "company_id = ? AND status NOT IN ('completed','cancelled')", [companyId])
          : 0,
    );
  }

  Future<CreatedRadicado> registerRadicado(RadicadoInput input) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.create,
      publicPermission: Permiso.radicarDocumentos,
    );
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final subject = input.subject.trim();
    if (subject.isEmpty) throw ArgumentError('El asunto es obligatorio.');
    if (input.senderName.trim().isEmpty) throw ArgumentError('El remitente es obligatorio.');
    if (input.recipientName.trim().isEmpty) throw ArgumentError('El destinatario es obligatorio.');

    return db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final now = DateTime.now().toUtc();
      final patternKey = switch (input.direction) {
        DocumentDirection.incoming => 'incoming_pattern',
        DocumentDirection.outgoing => 'outgoing_pattern',
        DocumentDirection.internal => 'internal_pattern',
      };
      final pattern = await _setting(txn, companyId, patternKey) ?? '${input.direction.wire}-{YEAR}-{SEQ6}';
      final number = await _nextNumber(txn, companyId, 'rad_${input.direction.wire}', pattern, now.year);
      final due = input.termBusinessDays == null
          ? null
          : await calculateBusinessDeadline(
              start: now,
              businessDays: input.termBusinessDays!,
              executor: txn,
              companyId: companyId,
            );
      final id = await txn.insert('gd_radicados', {
        'company_id': companyId,
        'number': number,
        'direction': input.direction.wire,
        'document_class': input.documentClass,
        'subject': subject,
        'description': input.description?.trim(),
        'sender_name': input.senderName.trim(),
        'recipient_name': input.recipientName.trim(),
        'channel': input.channel,
        'received_at': now.toIso8601String(),
        'due_at': due?.toIso8601String(),
        'term_business_days': input.termBusinessDays,
        'priority': input.priority,
        'access_level': input.accessLevel,
        'status': input.assignedUserId != null || input.assignedDependencyId != null ? 'assigned' : 'registered',
        'assigned_dependency_id': input.assignedDependencyId,
        'assigned_user_id': input.assignedUserId,
        'response_to_id': input.responseToId,
        'metadata_json': jsonEncode(input.metadata),
        'created_by': AppSession.usuarioId,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await txn.insert('gd_workflow_events', {
        'company_id': companyId,
        'radicado_id': id,
        'action': 'registered',
        'to_status': input.assignedUserId != null || input.assignedDependencyId != null ? 'assigned' : 'registered',
        'to_dependency_id': input.assignedDependencyId,
        'to_user_id': input.assignedUserId,
        'comment': 'Radicación creada',
        'actor_user_id': AppSession.usuarioId,
        'created_at': now.toIso8601String(),
      });
      await _accessLog(txn, companyId, 'radicado', id.toString(), 'create');
      return CreatedRadicado(id: id, number: number, dueAt: due);
    }).then((created) async {
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'GD_RADICAR_DOCUMENTO',
        entidad: 'gd_radicados',
        entidadId: created.id,
        detalle: created.number,
      );
      return created;
    });
  }

  Future<List<Map<String, Object?>>> listRadicados({
    String? search,
    String? status,
    String? assignedUserId,
    int limit = 250,
  }) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.view,
      publicPermission: Permiso.consultarGestionDocumental,
    );
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final where = <String>['company_id = ?'];
    final args = <Object?>[companyId];
    final fullAccess = await _hasFullDocumentAccess();
    if (!fullAccess) {
      final userId = AppSession.usuarioId ?? '';
      where.add("(access_level = 'public' OR created_by = ? OR assigned_user_id = ?)");
      args.addAll([userId, userId]);
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      where.add('status = ?');
      args.add(status);
    }
    if (assignedUserId != null && assignedUserId.isNotEmpty) {
      where.add('assigned_user_id = ?');
      args.add(assignedUserId);
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim()}%';
      where.add('(number LIKE ? OR subject LIKE ? OR sender_name LIKE ? OR recipient_name LIKE ?)');
      args.addAll([q, q, q, q]);
    }
    return db.query(
      'gd_radicados',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'received_at DESC, id DESC',
      limit: limit,
    );
  }

  Future<Map<String, Object?>?> getRadicado(int id) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.view,
      publicPermission: Permiso.consultarGestionDocumental,
    );
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query('gd_radicados', where: 'company_id = ? AND id = ?', whereArgs: [companyId, id], limit: 1);
    if (rows.isEmpty) return null;
    if (!_rowVisibleToCurrentUser(rows.first, fullAccess: await _hasFullDocumentAccess())) {
      await _accessLog(db, companyId, 'radicado', id.toString(), 'access_denied');
      return null;
    }
    await _accessLog(db, companyId, 'radicado', id.toString(), 'view');
    return rows.first;
  }

  Future<List<Map<String, Object?>>> workflow(int radicadoId) async {
    final visible = await getRadicado(radicadoId);
    if (visible == null) return const [];
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_workflow_events', where: 'company_id = ? AND radicado_id = ?', whereArgs: [companyId, radicadoId], orderBy: 'created_at ASC, id ASC');
  }

  Future<void> assignRadicado(
    int radicadoId, {
    int? dependencyId,
    String? userId,
    String? comment,
  }) => _transitionRadicado(
        radicadoId,
        toStatus: 'assigned',
        action: 'assigned',
        dependencyId: dependencyId,
        userId: userId,
        comment: comment,
      );

  Future<void> markInProgress(int radicadoId, {String? comment}) =>
      _transitionRadicado(radicadoId, toStatus: 'in_progress', action: 'started', comment: comment);

  Future<void> markForSignature(int radicadoId, {String? comment}) =>
      _transitionRadicado(radicadoId, toStatus: 'for_signature', action: 'for_signature', comment: comment);

  Future<void> markResponded(int radicadoId, {String? comment}) =>
      _transitionRadicado(radicadoId, toStatus: 'responded', action: 'responded', comment: comment);

  Future<void> closeRadicado(int radicadoId, {required String comment}) async {
    final trimmed = comment.trim();
    if (trimmed.isEmpty) throw ArgumentError('Debe registrar la actuación o motivo de cierre.');
    await _transitionRadicado(radicadoId, toStatus: 'closed', action: 'closed', comment: trimmed, close: true);
  }

  Future<void> _transitionRadicado(
    int radicadoId, {
    required String toStatus,
    required String action,
    int? dependencyId,
    String? userId,
    String? comment,
    bool close = false,
  }) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.update,
      publicPermission: Permiso.tramitarDocumentos,
    );
    final visible = await getRadicado(radicadoId);
    if (visible == null) throw StateError('Radicado no encontrado o sin autorización.');
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    await db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final rows = await txn.query('gd_radicados', where: 'company_id = ? AND id = ?', whereArgs: [companyId, radicadoId], limit: 1);
      if (rows.isEmpty) throw StateError('Radicado no encontrado.');
      final current = rows.first;
      final now = DateTime.now().toUtc().toIso8601String();
      final updates = <String, Object?>{
        'status': toStatus,
        'updated_at': now,
        'assigned_dependency_id': ?dependencyId,
        'assigned_user_id': ?userId,
        if (close) 'closed_at': now,
      };
      await txn.update('gd_radicados', updates, where: 'company_id = ? AND id = ?', whereArgs: [companyId, radicadoId]);
      await txn.insert('gd_workflow_events', {
        'company_id': companyId,
        'radicado_id': radicadoId,
        'action': action,
        'from_status': current['status'],
        'to_status': toStatus,
        'from_dependency_id': current['assigned_dependency_id'],
        'to_dependency_id': dependencyId ?? current['assigned_dependency_id'],
        'from_user_id': current['assigned_user_id'],
        'to_user_id': userId ?? current['assigned_user_id'],
        'comment': comment,
        'actor_user_id': AppSession.usuarioId,
        'created_at': now,
      });
      await _accessLog(txn, companyId, 'radicado', radicadoId.toString(), action);
    });
  }

  Future<int> createCase({
    required String title,
    String? description,
    int? dependencyId,
    int? seriesId,
    int? subseriesId,
    int? trdEntryId,
    String accessLevel = 'public',
  }) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.create,
      publicPermission: Permiso.tramitarDocumentos,
    );
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    return db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final now = DateTime.now().toUtc();
      final pattern = await _setting(txn, companyId, 'case_pattern') ?? 'EXP-{YEAR}-{SEQ6}';
      final code = await _nextNumber(txn, companyId, 'case', pattern, now.year);
      final retention = trdEntryId == null ? null : await _trdEntry(txn, companyId, trdEntryId);
      final id = await txn.insert('gd_expedientes', {
        'company_id': companyId,
        'code': code,
        'title': title.trim(),
        'description': description?.trim(),
        'dependency_id': dependencyId,
        'series_id': seriesId,
        'subseries_id': subseriesId,
        'trd_entry_id': trdEntryId,
        'status': 'open',
        'access_level': accessLevel,
        'opened_at': now.toIso8601String(),
        'current_archive_stage': 'management',
        'created_by': AppSession.usuarioId,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      if (retention != null) {
        // Las fechas definitivas se recalculan al cerrar el expediente, cuando
        // comienza el cómputo archivístico configurado por la entidad.
      }
      await _accessLog(txn, companyId, 'expediente', id.toString(), 'create');
      return id;
    });
  }

  Future<void> closeCase(int caseId) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.close,
      publicPermission: Permiso.tramitarDocumentos,
    );
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    await db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final rows = await txn.query('gd_expedientes', where: 'company_id = ? AND id = ?', whereArgs: [companyId, caseId], limit: 1);
      if (rows.isEmpty) throw StateError('Expediente no encontrado.');
      final row = rows.first;
      final now = DateTime.now().toUtc();
      DateTime? transferDue;
      DateTime? dispositionDue;
      final trdEntryId = row['trd_entry_id'] as int?;
      if (trdEntryId != null) {
        final trd = await _trdEntry(txn, companyId, trdEntryId);
        if (trd != null) {
          final mgmt = (trd['management_retention_years'] as num?)?.toInt() ?? 0;
          final central = (trd['central_retention_years'] as num?)?.toInt() ?? 0;
          transferDue = DateTime.utc(now.year + mgmt, now.month, now.day);
          dispositionDue = DateTime.utc(now.year + mgmt + central, now.month, now.day);
        }
      }
      await txn.update(
        'gd_expedientes',
        {
          'status': 'closed',
          'closed_at': now.toIso8601String(),
          'transfer_due_at': transferDue?.toIso8601String(),
          'disposition_due_at': dispositionDue?.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
        where: 'company_id = ? AND id = ?',
        whereArgs: [companyId, caseId],
      );
      await _accessLog(txn, companyId, 'expediente', caseId.toString(), 'close');
    });
  }

  Future<List<Map<String, Object?>>> listCases({String? search, String? status}) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.view,
      publicPermission: Permiso.consultarGestionDocumental,
    );
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final where = <String>['company_id = ?'];
    final args = <Object?>[companyId];
    if (!await _hasFullDocumentAccess()) {
      where.add("(access_level = 'public' OR created_by = ?)");
      args.add(AppSession.usuarioId ?? '');
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      where.add('status = ?');
      args.add(status);
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim()}%';
      where.add('(code LIKE ? OR title LIKE ? OR description LIKE ?)');
      args.addAll([q, q, q]);
    }
    return db.query('gd_expedientes', where: where.join(' AND '), whereArgs: args, orderBy: 'opened_at DESC', limit: 250);
  }


  Future<Map<String, Object?>?> _visibleCase(int caseId) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query(
      'gd_expedientes',
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, caseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final visible = _rowVisibleToCurrentUser(
      rows.first,
      fullAccess: await _hasFullDocumentAccess(),
    );
    if (!visible) {
      await _accessLog(db, companyId, 'expediente', caseId.toString(), 'access_denied');
      return null;
    }
    return rows.first;
  }

  Future<String> attachFile({
    required String sourcePath,
    required String title,
    int? radicadoId,
    int? caseId,
    int? documentTypeId,
    String? logicalDocumentId,
    String accessLevel = 'public',
    bool isOriginal = true,
  }) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.create,
      publicPermission: Permiso.tramitarDocumentos,
    );
    final source = File(sourcePath);
    if (!await source.exists()) throw ArgumentError('El archivo seleccionado no existe.');
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final sizeBytes = await source.length();
    final hash = (await sha256.bind(source.openRead()).first).toString();
    final logicalId = logicalDocumentId ?? _uuid.v4();
    final versionRows = await db.rawQuery(
      'SELECT COALESCE(MAX(version_number), 0) AS v FROM gd_documents WHERE company_id = ? AND logical_document_id = ?',
      [companyId, logicalId],
    );
    final version = (Sqflite.firstIntValue(versionRows) ?? 0) + 1;
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(root.path, 'gestion_documental', companyId.toString(), now.year.toString(), now.month.toString().padLeft(2, '0')));
    if (!await folder.exists()) await folder.create(recursive: true);
    final safeName = '${id}_${p.basename(source.path).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
    final target = File(p.join(folder.path, safeName));
    await source.copy(target.path);
    final mime = _mimeFromExtension(p.extension(source.path));

    await db.transaction((txn) async {
      await txn.insert('gd_documents', {
        'id': id,
        'company_id': companyId,
        'radicado_id': radicadoId,
        'expediente_id': caseId,
        'logical_document_id': logicalId,
        'document_type_id': documentTypeId,
        'title': title.trim().isEmpty ? p.basename(source.path) : title.trim(),
        'file_name': p.basename(source.path),
        'file_path': target.path,
        'mime_type': mime,
        'size_bytes': sizeBytes,
        'sha256': hash,
        'version_number': version,
        'is_original': isOriginal ? 1 : 0,
        'is_signed': 0,
        'access_level': accessLevel,
        'created_by': AppSession.usuarioId,
        'created_at': now.toIso8601String(),
      });
      if (caseId != null) {
        final orderRows = await txn.rawQuery('SELECT COALESCE(MAX(order_number), 0) AS v FROM gd_expediente_documents WHERE company_id = ? AND expediente_id = ?', [companyId, caseId]);
        final order = (Sqflite.firstIntValue(orderRows) ?? 0) + 1;
        await txn.insert('gd_expediente_documents', {
          'company_id': companyId,
          'expediente_id': caseId,
          'document_id': id,
          'order_number': order,
          'included_at': now.toIso8601String(),
          'included_by': AppSession.usuarioId,
        });
      }
      await _accessLog(txn, companyId, 'documento', id, 'create');
    });
    return id;
  }

  Future<bool> verifyDocumentIntegrity(String documentId) async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query('gd_documents', where: 'company_id = ? AND id = ?', whereArgs: [companyId, documentId], limit: 1);
    if (rows.isEmpty) return false;
    final row = rows.first;
    final file = File(row['file_path']!.toString());
    if (!await file.exists()) return false;
    final current = (await sha256.bind(file.openRead()).first).toString();
    final valid = current == row['sha256'];
    await _accessLog(db, companyId, 'documento', documentId, valid ? 'integrity_ok' : 'integrity_failed');
    return valid;
  }

  Future<Map<String, Object?>> requestConfiguredSignature({
    required String documentId,
    required String signerName,
    String? signerIdentification,
    String? purpose,
  }) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.update,
      publicPermission: Permiso.tramitarDocumentos,
    );
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query(
      'gd_documents',
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, documentId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Documento no encontrado.');
    final row = rows.first;
    if (!_rowVisibleToCurrentUser(row, fullAccess: await _hasFullDocumentAccess())) {
      await _accessLog(db, companyId, 'documento', documentId, 'access_denied');
      throw StateError('No tiene acceso a este documento.');
    }
    if (!await verifyDocumentIntegrity(documentId)) {
      throw StateError('La integridad del archivo no coincide con el hash registrado. No se solicitará firma.');
    }
    if (!await IntegrationSettingsService.instance.isConfigured('signature_provider')) {
      throw StateError('Configura y habilita primero Firma digital / sello de tiempo en Integraciones.');
    }
    final definition = IntegrationRegistry.byKey('signature_provider');
    final settings = await IntegrationSettingsService.instance.loadValues(definition);
    final providerName = (settings['provider_name'] ?? '').trim();
    final result = await InstitutionalConnectorService.instance.postJson(
      'signature_provider',
      pathField: 'submission_path',
      payload: {
        'document_id': documentId,
        'logical_document_id': row['logical_document_id'],
        'file_name': row['file_name'],
        'sha256': row['sha256'],
        'mime_type': row['mime_type'],
        'signer': {
          'name': signerName.trim(),
          if ((signerIdentification ?? '').trim().isNotEmpty)
            'identification': signerIdentification!.trim(),
        },
        if ((purpose ?? '').trim().isNotEmpty) 'purpose': purpose!.trim(),
        if ((settings['certificate_alias'] ?? '').trim().isNotEmpty)
          'certificate_alias': settings['certificate_alias']!.trim(),
      },
    );
    if (!result.ok) throw StateError(result.message);
    final externalRef = _externalReference(result.data);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'gd_documents',
      {
        'signature_provider': providerName.isEmpty ? definition.name : providerName,
        'signature_metadata_json': jsonEncode({
          'status': 'requested',
          'requested_at': now,
          'requested_by': AppSession.usuarioId,
          'signer_name': signerName.trim(),
          if ((signerIdentification ?? '').trim().isNotEmpty)
            'signer_identification': signerIdentification!.trim(),
          if ((purpose ?? '').trim().isNotEmpty) 'purpose': purpose!.trim(),
          'external_reference': ?externalRef,
          'signed_sha256': row['sha256'],
        }),
      },
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, documentId],
    );
    await _accessLog(db, companyId, 'documento', documentId, 'signature_requested');
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'DOCUMENTO_FIRMA_SOLICITADA',
      entidad: 'gd_documents',
      detalle: '$documentId; provider=${providerName.isEmpty ? definition.name : providerName}; ref=${externalRef ?? ''}',
    );
    return {
      'ok': true,
      'message': result.message,
      'external_reference': ?externalRef,
    };
  }

  Future<void> registerSignatureEvidence({
    required String documentId,
    required String provider,
    required String signerName,
    required String externalReference,
    DateTime? signedAt,
    String? signerIdentification,
    String? timestampReference,
    Map<String, Object?> additionalMetadata = const {},
  }) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.approve,
      publicPermission: Permiso.tramitarDocumentos,
    );
    final reference = externalReference.trim();
    if (provider.trim().isEmpty || signerName.trim().isEmpty || reference.isEmpty) {
      throw ArgumentError('Proveedor, firmante y referencia externa son obligatorios.');
    }
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query(
      'gd_documents',
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, documentId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Documento no encontrado.');
    final row = rows.first;
    if (!_rowVisibleToCurrentUser(row, fullAccess: await _hasFullDocumentAccess())) {
      await _accessLog(db, companyId, 'documento', documentId, 'access_denied');
      throw StateError('No tiene acceso a este documento.');
    }
    if (!await verifyDocumentIntegrity(documentId)) {
      throw StateError('El archivo fue alterado respecto del hash registrado; no puede marcarse como firmado.');
    }
    final date = (signedAt ?? DateTime.now()).toUtc();
    await db.update(
      'gd_documents',
      {
        'is_signed': 1,
        'signature_provider': provider.trim(),
        'signature_metadata_json': jsonEncode({
          'status': 'confirmed',
          'signed_at': date.toIso8601String(),
          'registered_at': DateTime.now().toUtc().toIso8601String(),
          'registered_by': AppSession.usuarioId,
          'signer_name': signerName.trim(),
          if ((signerIdentification ?? '').trim().isNotEmpty)
            'signer_identification': signerIdentification!.trim(),
          'external_reference': reference,
          if ((timestampReference ?? '').trim().isNotEmpty)
            'timestamp_reference': timestampReference!.trim(),
          'signed_sha256': row['sha256'],
          ...additionalMetadata,
        }),
        // Un original con evidencia de firma no debe quedar sujeto a reemplazo
        // silencioso por políticas de retención o disposición.
        'retention_frozen': 1,
      },
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, documentId],
    );
    await _accessLog(db, companyId, 'documento', documentId, 'signature_confirmed');
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'DOCUMENTO_FIRMA_CONFIRMADA',
      entidad: 'gd_documents',
      detalle: '$documentId; provider=${provider.trim()}; ref=$reference; sha256=${row['sha256']}',
    );
  }

  String? _externalReference(Object? data) {
    if (data is! Map) return null;
    for (final key in const ['id', 'reference', 'reference_id', 'request_id', 'transaction_id', 'signature_id']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<List<Map<String, Object?>>> documentsFor({int? radicadoId, int? caseId}) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.view,
      publicPermission: Permiso.consultarGestionDocumental,
    );
    if (radicadoId != null && await getRadicado(radicadoId) == null) return const [];
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    if (caseId != null && await _visibleCase(caseId) == null) return const [];
    final clauses = <String>['company_id = ?'];
    final args = <Object?>[companyId];
    if (radicadoId != null) {
      clauses.add('radicado_id = ?');
      args.add(radicadoId);
    }
    if (caseId != null) {
      clauses.add('expediente_id = ?');
      args.add(caseId);
    }
    final rows = await db.query('gd_documents', where: clauses.join(' AND '), whereArgs: args, orderBy: 'created_at DESC');
    final fullAccess = await _hasFullDocumentAccess();
    return rows.where((row) => _rowVisibleToCurrentUser(row, fullAccess: fullAccess)).toList();
  }

  Future<void> linkRadicadoToCase({
    required int radicadoId,
    required int caseId,
    String relationType = 'related',
  }) async {
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final radicado = await db.query(
      'gd_radicados',
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, radicadoId],
      limit: 1,
    );
    final expediente = await db.query(
      'gd_expedientes',
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, caseId],
      limit: 1,
    );
    if (radicado.isEmpty) throw StateError('Radicado no encontrado.');
    if (expediente.isEmpty) throw StateError('Expediente no encontrado.');
    await db.insert(
      'gd_expediente_radicados',
      {
        'company_id': companyId,
        'expediente_id': caseId,
        'radicado_id': radicadoId,
        'relation_type': relationType.trim().isEmpty ? 'related' : relationType.trim(),
        'included_at': DateTime.now().toUtc().toIso8601String(),
        'included_by': AppSession.usuarioId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _accessLog(
      db,
      companyId,
      'expediente',
      caseId.toString(),
      'radicado_linked',
      reason: radicado.first['number']?.toString(),
    );
  }

  Future<List<Map<String, Object?>>> radicadosForCase(int caseId) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.view,
      publicPermission: Permiso.consultarGestionDocumental,
    );
    if (await _visibleCase(caseId) == null) return const [];
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.rawQuery('''
      SELECT r.*
      FROM gd_expediente_radicados er
      JOIN gd_radicados r ON r.id = er.radicado_id AND r.company_id = er.company_id
      WHERE er.company_id = ? AND er.expediente_id = ?
      ORDER BY er.included_at ASC, er.id ASC
    ''', [companyId, caseId]);
    final fullAccess = await _hasFullDocumentAccess();
    return rows.where((row) => _rowVisibleToCurrentUser(row, fullAccess: fullAccess)).toList();
  }

  Future<List<Map<String, Object?>>> documentTypes() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query(
      'gd_document_types',
      where: 'company_id = ? AND active = 1',
      whereArgs: [companyId],
      orderBy: 'name',
    );
  }

  Future<int> createDocumentType({
    required String name,
    String? code,
    String? description,
  }) async {
    await _requireDocumentPermission(
      commercialAction: AppAction.configure,
      publicPermission: Permiso.administrarInstrumentosArchivisticos,
    );
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('El nombre del tipo documental es obligatorio.');
    }
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedCode = code?.trim();
    final normalizedDescription = description?.trim();
    return db.insert(
      'gd_document_types',
      {
        'company_id': companyId,
        'name': normalizedName,
        'code': normalizedCode == null || normalizedCode.isEmpty ? null : normalizedCode,
        'description': normalizedDescription == null || normalizedDescription.isEmpty
            ? null
            : normalizedDescription,
        'active': 1,
        'created_at': now,
        'updated_at': now,
      },
    );
  }

  Future<int> createDependency({required String code, required String name, int? parentId}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_dependencies', {'company_id': companyId, 'code': code.trim(), 'name': name.trim(), 'parent_id': parentId, 'active': 1, 'created_at': now, 'updated_at': now});
  }

  Future<List<Map<String, Object?>>> dependencies() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_dependencies', where: 'company_id = ? AND active = 1', whereArgs: [companyId], orderBy: 'name');
  }

  Future<int> createTrdVersion({required String code, String? description}) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_trd_versions', {'company_id': companyId, 'version_code': code.trim(), 'description': description?.trim(), 'status': 'draft', 'created_at': now, 'updated_at': now});
  }

  Future<void> updateTrdVersion(
    int id, {
    required String status,
    String? adoptionAct,
    DateTime? adoptionDate,
    String? convalidationAct,
    DateTime? convalidationDate,
    String? rusdCertificate,
  }) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.update('gd_trd_versions', {
      'status': status,
      'adoption_act': adoptionAct,
      'adoption_date': adoptionDate?.toIso8601String(),
      'convalidation_act': convalidationAct,
      'convalidation_date': convalidationDate?.toIso8601String(),
      'rusd_certificate': rusdCertificate,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'company_id = ? AND id = ?', whereArgs: [companyId, id]);
  }

  Future<List<Map<String, Object?>>> trdVersions() async {
    await _requirePublicDocumentPermission(Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_trd_versions', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'created_at DESC');
  }

  Future<int> createSeries({required String code, required String name, int? dependencyId}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_series', {'company_id': companyId, 'dependency_id': dependencyId, 'code': code.trim(), 'name': name.trim(), 'active': 1, 'created_at': now, 'updated_at': now});
  }

  Future<int> createSubseries({required int seriesId, required String code, required String name}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_subseries', {'company_id': companyId, 'series_id': seriesId, 'code': code.trim(), 'name': name.trim(), 'active': 1, 'created_at': now, 'updated_at': now});
  }

  Future<List<Map<String, Object?>>> series() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_series', where: 'company_id = ? AND active = 1', whereArgs: [companyId], orderBy: 'code');
  }

  Future<List<Map<String, Object?>>> subseries([int? seriesId]) async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_subseries', where: seriesId == null ? 'company_id = ? AND active = 1' : 'company_id = ? AND series_id = ? AND active = 1', whereArgs: seriesId == null ? [companyId] : [companyId, seriesId], orderBy: 'code');
  }

  Future<int> saveTrdEntry({
    required int versionId,
    required int seriesId,
    int? subseriesId,
    int? dependencyId,
    int managementYears = 0,
    int centralYears = 0,
    required String finalDisposition,
    String medium = 'mixed',
    String? procedure,
    bool essential = false,
  }) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_trd_entries', {
      'company_id': companyId,
      'trd_version_id': versionId,
      'dependency_id': dependencyId,
      'series_id': seriesId,
      'subseries_id': subseriesId,
      'management_retention_years': managementYears,
      'central_retention_years': centralYears,
      'final_disposition': finalDisposition,
      'medium': medium,
      'procedure': procedure,
      'essential': essential ? 1 : 0,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, Object?>>> trdEntries({int? versionId}) async {
    await _requirePublicDocumentPermission(Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final args = <Object?>[companyId, ?versionId];
    final filter = versionId == null ? '' : ' AND e.trd_version_id = ?';
    return db.rawQuery('''
      SELECT e.*, s.code AS series_code, s.name AS series_name,
             ss.code AS subseries_code, ss.name AS subseries_name,
             d.name AS dependency_name, v.version_code
      FROM gd_trd_entries e
      JOIN gd_series s ON s.id = e.series_id
      LEFT JOIN gd_subseries ss ON ss.id = e.subseries_id
      LEFT JOIN gd_dependencies d ON d.id = e.dependency_id
      JOIN gd_trd_versions v ON v.id = e.trd_version_id
      WHERE e.company_id = ? AND e.active = 1$filter
      ORDER BY d.name, s.code, ss.code
    ''', args);
  }

  Future<List<Map<String, Object?>>> instruments() async {
    await _requirePublicDocumentPermission(Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_instruments', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'name');
  }

  Future<void> updateInstrument({
    required int id,
    required String status,
    String? versionCode,
    String? adoptionAct,
    DateTime? adoptionDate,
    String? responsibleDependency,
    String? notes,
  }) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.update('gd_instruments', {
      'status': status,
      'version_code': versionCode,
      'adoption_act': adoptionAct,
      'adoption_date': adoptionDate?.toIso8601String(),
      'responsible_dependency': responsibleDependency,
      'notes': notes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'company_id = ? AND id = ?', whereArgs: [companyId, id]);
  }

  Future<void> attachInstrumentFile(int instrumentId, String sourcePath) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final source = File(sourcePath);
    if (!await source.exists()) throw ArgumentError('Archivo no encontrado.');
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final sourceHash = (await sha256.bind(source.openRead()).first).toString();
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'gestion_documental', companyId.toString(), 'instrumentos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = File(p.join(dir.path, '${instrumentId}_${p.basename(source.path).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}'));
    await source.copy(target.path);
    await db.update('gd_instruments', {
      'file_path': target.path,
      'file_hash': sourceHash,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'company_id = ? AND id = ?', whereArgs: [companyId, instrumentId]);
  }

  Future<Map<String, String>> settings() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query('gd_settings', where: 'company_id = ?', whereArgs: [companyId]);
    return {for (final row in rows) row['setting_key'].toString(): row['setting_value'].toString()};
  }

  Future<void> saveSetting(String key, String value) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await db.query('gd_settings', where: 'company_id = ? AND setting_key = ?', whereArgs: [companyId, key], limit: 1);
    final data = {'setting_value': value, 'updated_at': now, 'updated_by': AppSession.usuarioId};
    if (existing.isEmpty) {
      await db.insert('gd_settings', {'company_id': companyId, 'setting_key': key, ...data});
    } else {
      await db.update('gd_settings', data, where: 'company_id = ? AND setting_key = ?', whereArgs: [companyId, key]);
    }
  }

  Future<void> addNonWorkingDay(DateTime day, {String? description}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final date = _dateOnly(day);
    await db.insert('gd_non_working_days', {'company_id': companyId, 'day': date, 'description': description, 'recurring': 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> nonWorkingDays() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_non_working_days', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'day');
  }

  Future<DateTime> calculateBusinessDeadline({
    required DateTime start,
    required int businessDays,
    DatabaseExecutor? executor,
    int? companyId,
  }) async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    if (businessDays < 0) throw ArgumentError('El término no puede ser negativo.');
    final db = executor ?? await DatabaseHelper.instance.database;
    final cid = companyId ?? await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final weekdaysRaw = await _setting(db, cid, 'work_weekdays') ?? '1,2,3,4,5';
    final weekdays = weekdaysRaw.split(',').map(int.tryParse).whereType<int>().toSet();
    final days = await db.query('gd_non_working_days', columns: ['day'], where: 'company_id = ?', whereArgs: [cid]);
    final holidays = days.map((row) => row['day'].toString()).toSet();
    var current = DateTime.utc(start.year, start.month, start.day);
    var remaining = businessDays;
    while (remaining > 0) {
      current = current.add(const Duration(days: 1));
      if (!weekdays.contains(current.weekday)) continue;
      if (holidays.contains(_dateOnly(current))) continue;
      remaining--;
    }
    return current.add(const Duration(hours: 23, minutes: 59, seconds: 59));
  }

  Future<int> createPhysicalLocation({
    required String archiveStage,
    String? building,
    String? room,
    String? shelf,
    String? body,
    String? tray,
    String? boxCode,
    String? folderCode,
    String? label,
  }) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_physical_locations', {
      'company_id': companyId,
      'archive_stage': archiveStage,
      'building': building,
      'room': room,
      'shelf': shelf,
      'body': body,
      'tray': tray,
      'box_code': boxCode,
      'folder_code': folderCode,
      'label': label,
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, Object?>>> physicalLocations() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_physical_locations', where: 'company_id = ? AND active = 1', whereArgs: [companyId], orderBy: 'archive_stage, building, room, shelf, box_code');
  }

  Future<int> loan({
    int? caseId,
    String? documentId,
    required String borrowerUserId,
    required String borrowerName,
    required String purpose,
    required DateTime dueAt,
  }) async {
    await _requireDocumentPermission(commercialAction: AppAction.update, publicPermission: Permiso.administrarArchivo);
    if (caseId == null && documentId == null) throw ArgumentError('Debe seleccionar expediente o documento.');
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_loans', {
      'company_id': companyId,
      'expediente_id': caseId,
      'document_id': documentId,
      'borrower_user_id': borrowerUserId,
      'borrower_name': borrowerName,
      'purpose': purpose,
      'loaned_at': now,
      'due_at': dueAt.toUtc().toIso8601String(),
      'status': 'active',
      'authorized_by': AppSession.usuarioId,
      'created_at': now,
    });
  }

  Future<void> returnLoan(int loanId) async {
    await _requireDocumentPermission(commercialAction: AppAction.update, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.update('gd_loans', {'status': 'returned', 'returned_at': DateTime.now().toUtc().toIso8601String()}, where: 'company_id = ? AND id = ?', whereArgs: [companyId, loanId]);
  }

  Future<List<Map<String, Object?>>> loans({bool activeOnly = true}) async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_loans', where: activeOnly ? "company_id = ? AND status = 'active'" : 'company_id = ?', whereArgs: [companyId], orderBy: 'loaned_at DESC');
  }

  Future<int> createTransfer({required String type, required String fromStage, required String toStage, String? notes}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    return db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final now = DateTime.now().toUtc();
      final pattern = await _setting(txn, companyId, 'transfer_pattern') ?? 'TR-{YEAR}-{SEQ6}';
      final number = await _nextNumber(txn, companyId, 'transfer', pattern, now.year);
      return txn.insert('gd_transfers', {
        'company_id': companyId,
        'transfer_number': number,
        'transfer_type': type,
        'from_stage': fromStage,
        'to_stage': toStage,
        'status': 'draft',
        'requested_at': now.toIso8601String(),
        'requested_by': AppSession.usuarioId,
        'notes': notes,
      });
    });
  }

  Future<void> addCaseToTransfer(int transferId, int caseId) async {
    await _requireDocumentPermission(commercialAction: AppAction.update, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.insert('gd_transfer_items', {'company_id': companyId, 'transfer_id': transferId, 'expediente_id': caseId}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> completeTransfer(int transferId, {required String actReference}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    await db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final transferRows = await txn.query('gd_transfers', where: 'company_id = ? AND id = ?', whereArgs: [companyId, transferId], limit: 1);
      if (transferRows.isEmpty) throw StateError('Transferencia no encontrada.');
      final transfer = transferRows.first;
      final items = await txn.query('gd_transfer_items', where: 'company_id = ? AND transfer_id = ?', whereArgs: [companyId, transferId]);
      if (items.isEmpty) throw StateError('La transferencia no contiene expedientes.');
      final pending = items.where((item) => item['accepted'] != 1).length;
      if (pending > 0) {
        throw StateError('La transferencia tiene $pending ítem(s) sin aceptación de inventario.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      for (final item in items) {
        await txn.update('gd_expedientes', {'current_archive_stage': transfer['to_stage'], 'status': 'transferred', 'updated_at': now}, where: 'company_id = ? AND id = ?', whereArgs: [companyId, item['expediente_id']]);
      }
      await txn.update('gd_transfers', {'status': 'completed', 'act_reference': actReference, 'approved_at': now, 'completed_at': now, 'approved_by': AppSession.usuarioId}, where: 'company_id = ? AND id = ?', whereArgs: [companyId, transferId]);
    });
  }

  Future<List<Map<String, Object?>>> transfers() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_transfers', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'requested_at DESC');
  }

  Future<int> createTvdVersion({required String code, String? notes}) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_tvd_versions', {
      'company_id': companyId, 'version_code': code.trim(), 'status': 'draft',
      'notes': notes?.trim(), 'created_at': now, 'updated_at': now,
    });
  }

  Future<void> updateTvdVersion(int id, {required String status, String? adoptionAct,
      DateTime? adoptionDate, String? convalidationAct, DateTime? convalidationDate,
      String? rusdCertificate}) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.update('gd_tvd_versions', {
      'status': status, 'adoption_act': adoptionAct,
      'adoption_date': adoptionDate?.toUtc().toIso8601String(),
      'convalidation_act': convalidationAct,
      'convalidation_date': convalidationDate?.toUtc().toIso8601String(),
      'rusd_certificate': rusdCertificate,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'company_id = ? AND id = ?', whereArgs: [companyId, id]);
  }

  Future<List<Map<String, Object?>>> tvdVersions() async {
    await _requirePublicDocumentPermission(Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_tvd_versions', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'created_at DESC');
  }

  Future<int> saveTvdEntry({required int versionId, required String seriesName,
      String? sourceOffice, String? subseriesName, int? startYear, int? endYear,
      int centralRetentionYears = 0, String finalDisposition = 'selection', String? procedure}) async {
    await _requirePublicDocumentPermission(Permiso.administrarInstrumentosArchivisticos);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('gd_tvd_entries', {
      'company_id': companyId, 'tvd_version_id': versionId,
      'source_office': sourceOffice?.trim(), 'series_name': seriesName.trim(),
      'subseries_name': subseriesName?.trim(), 'start_year': startYear, 'end_year': endYear,
      'central_retention_years': centralRetentionYears, 'final_disposition': finalDisposition,
      'procedure': procedure?.trim(), 'created_at': now, 'updated_at': now,
    });
  }

  Future<List<Map<String, Object?>>> tvdEntries({int? versionId}) async {
    await _requirePublicDocumentPermission(Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_tvd_entries',
      where: versionId == null ? 'company_id = ?' : 'company_id = ? AND tvd_version_id = ?',
      whereArgs: versionId == null ? [companyId] : [companyId, versionId],
      orderBy: 'source_office, series_name, subseries_name');
  }

  Future<void> archiveRadicado(int radicadoId, {int? physicalLocationId, String? comment}) async {
    await _requireDocumentPermission(commercialAction: AppAction.update, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    await db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final rows = await txn.query('gd_radicados', where: 'company_id = ? AND id = ?', whereArgs: [companyId, radicadoId], limit: 1);
      if (rows.isEmpty) throw StateError('Radicado no encontrado.');
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update('gd_radicados', {
        'status': 'archived', 'archived_at': now,
        'physical_location_id': ?physicalLocationId,
        'updated_at': now,
      }, where: 'company_id = ? AND id = ?', whereArgs: [companyId, radicadoId]);
      await txn.insert('gd_workflow_events', {
        'company_id': companyId, 'radicado_id': radicadoId, 'action': 'archived',
        'from_status': rows.first['status'], 'to_status': 'archived', 'comment': comment,
        'actor_user_id': AppSession.usuarioId, 'created_at': now,
      });
      await _accessLog(txn, companyId, 'radicado', radicadoId.toString(), 'archive');
    });
  }

  Future<void> assignCasePhysicalLocation(int caseId, int physicalLocationId) async {
    await _requireDocumentPermission(commercialAction: AppAction.update, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.update('gd_expedientes', {
      'physical_location_id': physicalLocationId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'company_id = ? AND id = ?', whereArgs: [companyId, caseId]);
    await _accessLog(db, companyId, 'expediente', caseId.toString(), 'physical_location_assigned');
  }

  Future<int> proposeDisposition({required int caseId, required String disposition, String? notes}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarArchivo);
    const allowed = {'total_conservation', 'selection', 'elimination', 'reproduction'};
    if (!allowed.contains(disposition)) throw ArgumentError('Disposición final no válida.');
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query('gd_expedientes', where: 'company_id = ? AND id = ?', whereArgs: [companyId, caseId], limit: 1);
    if (rows.isEmpty) throw StateError('Expediente no encontrado.');
    return db.insert('gd_disposition_actions', {
      'company_id': companyId, 'expediente_id': caseId, 'disposition': disposition,
      'status': 'proposed', 'notes': notes?.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> executeDisposition(int actionId, {required String authorizationReference,
      String? committeeAct, String? eliminationAct}) async {
    await _requireDocumentPermission(commercialAction: AppAction.configure, publicPermission: Permiso.administrarArchivo);
    if (authorizationReference.trim().isEmpty) throw ArgumentError('La disposición final exige una referencia de autorización.');
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    await db.transaction((txn) async {
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(txn);
      final actions = await txn.query('gd_disposition_actions', where: 'company_id = ? AND id = ?', whereArgs: [companyId, actionId], limit: 1);
      if (actions.isEmpty) throw StateError('Acción de disposición no encontrada.');
      final action = actions.first;
      if (action['status'] == 'executed') throw StateError('La disposición ya fue ejecutada.');
      final disposition = action['disposition']?.toString() ?? '';
      if (disposition == 'elimination' && (eliminationAct ?? '').trim().isEmpty) {
        throw ArgumentError('La eliminación documental exige registrar el acta de eliminación.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      // Nunca se borra físicamente un original desde esta operación: se preservan metadatos,
      // hash, bitácora y evidencia del acto/autoridad que dispuso el documento.
      await txn.update('gd_disposition_actions', {
        'status': 'executed', 'committee_act': committeeAct?.trim(),
        'elimination_act': eliminationAct?.trim(),
        'authorization_reference': authorizationReference.trim(),
        'executed_at': now, 'executed_by': AppSession.usuarioId,
      }, where: 'company_id = ? AND id = ?', whereArgs: [companyId, actionId]);
      await txn.update('gd_expedientes', {'status': 'disposed', 'updated_at': now},
        where: 'company_id = ? AND id = ?', whereArgs: [companyId, action['expediente_id']]);
      await _accessLog(txn, companyId, 'expediente', action['expediente_id'].toString(),
        'disposition_$disposition', reason: authorizationReference.trim());
    });
  }

  Future<List<Map<String, Object?>>> dispositions() async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.rawQuery('SELECT d.*, e.code AS expediente_code, e.title AS expediente_title '
        'FROM gd_disposition_actions d JOIN gd_expedientes e ON e.id = d.expediente_id AND e.company_id = d.company_id '
        'WHERE d.company_id = ? ORDER BY d.created_at DESC', [companyId]);
  }

  Future<List<Map<String, Object?>>> accessLog({int limit = 300}) async {
    await _requireDocumentAdministrator();
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_access_log', where: 'company_id = ?', whereArgs: [companyId], orderBy: 'created_at DESC', limit: limit);
  }

  Future<List<Map<String, Object?>>> transferItems(int transferId) async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.rawQuery('SELECT i.*, e.code AS expediente_code, e.title AS expediente_title, '
        'e.current_archive_stage, e.closed_at FROM gd_transfer_items i '
        'JOIN gd_expedientes e ON e.id = i.expediente_id AND e.company_id = i.company_id '
        'WHERE i.company_id = ? AND i.transfer_id = ? ORDER BY e.code', [companyId, transferId]);
  }

  Future<void> updateTransferItem(int itemId, {required bool accepted, String? observation}) async {
    await _requireDocumentPermission(commercialAction: AppAction.update, publicPermission: Permiso.administrarArchivo);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.update('gd_transfer_items', {'accepted': accepted ? 1 : 0, 'observation': observation?.trim()},
      where: 'company_id = ? AND id = ?', whereArgs: [companyId, itemId]);
  }

  Future<void> linkEntity({
    required String entityType,
    required String entityId,
    int? radicadoId,
    int? caseId,
    String? documentId,
  }) async {
    await _requireDocumentPermission(commercialAction: AppAction.update, publicPermission: Permiso.tramitarDocumentos);
    if (radicadoId == null && caseId == null && documentId == null) {
      throw ArgumentError('Debe vincular al menos un recurso documental.');
    }
    final db = await DatabaseHelper.instance.database;
    await ensureInitialized(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.insert('gd_entity_links', {
      'company_id': companyId,
      'entity_type': entityType,
      'entity_id': entityId,
      'radicado_id': radicadoId,
      'expediente_id': caseId,
      'document_id': documentId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> linksForEntity(String entityType, String entityId) async {
    await _requireDocumentPermission(commercialAction: AppAction.view, publicPermission: Permiso.consultarGestionDocumental);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.query('gd_entity_links', where: 'company_id = ? AND entity_type = ? AND entity_id = ?', whereArgs: [companyId, entityType, entityId], orderBy: 'created_at DESC');
  }

  Future<Map<String, Object?>?> _trdEntry(DatabaseExecutor db, int companyId, int id) async {
    final rows = await db.query('gd_trd_entries', where: 'company_id = ? AND id = ? AND active = 1', whereArgs: [companyId, id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<String?> _setting(DatabaseExecutor db, int companyId, String key) async {
    final rows = await db.query('gd_settings', columns: ['setting_value'], where: 'company_id = ? AND setting_key = ?', whereArgs: [companyId, key], limit: 1);
    return rows.isEmpty ? null : rows.first['setting_value']?.toString();
  }

  Future<String> _nextNumber(DatabaseExecutor db, int companyId, String sequenceKey, String pattern, int year) async {
    final rows = await db.query('gd_sequences', where: 'company_id = ? AND sequence_key = ? AND year = ?', whereArgs: [companyId, sequenceKey, year], limit: 1);
    final next = rows.isEmpty ? 1 : ((rows.first['current_value'] as num?)?.toInt() ?? 0) + 1;
    final now = DateTime.now().toUtc().toIso8601String();
    if (rows.isEmpty) {
      await db.insert('gd_sequences', {'company_id': companyId, 'sequence_key': sequenceKey, 'year': year, 'current_value': next, 'updated_at': now});
    } else {
      await db.update('gd_sequences', {'current_value': next, 'updated_at': now}, where: 'company_id = ? AND sequence_key = ? AND year = ?', whereArgs: [companyId, sequenceKey, year]);
    }
    var result = pattern.replaceAll('{YEAR}', year.toString()).replaceAll('{SEQ}', next.toString());
    for (var digits = 2; digits <= 10; digits++) {
      result = result.replaceAll('{SEQ$digits}', next.toString().padLeft(digits, '0'));
    }
    return result;
  }

  Future<void> _accessLog(DatabaseExecutor db, int companyId, String resourceType, String resourceId, String action, {String? reason}) async {
    await db.insert('gd_access_log', {
      'company_id': companyId,
      'resource_type': resourceType,
      'resource_id': resourceId,
      'action': action,
      'user_id': AppSession.usuarioId,
      'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  String _dateOnly(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _mimeFromExtension(String extension) => switch (extension.toLowerCase()) {
        '.pdf' => 'application/pdf',
        '.doc' => 'application/msword',
        '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        '.xls' => 'application/vnd.ms-excel',
        '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.txt' => 'text/plain',
        '.xml' => 'application/xml',
        '.json' => 'application/json',
        _ => 'application/octet-stream',
      };
}
