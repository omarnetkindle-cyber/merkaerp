import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../../app_session.dart';
import '../../../db_helper.dart';
import '../../../integrations/application/integration_settings_service.dart';
import '../../../integrations/domain/integration_definition.dart';

class ElectronicPayrollService {
  ElectronicPayrollService._();
  static final ElectronicPayrollService instance = ElectronicPayrollService._();

  Future<void> _ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS electronic_payroll_transmissions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        liquidation_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'prepared',
        request_hash TEXT NOT NULL,
        external_id TEXT,
        response_json TEXT,
        submitted_at TEXT,
        verified_at TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(company_id, liquidation_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_epayroll_company_status ON electronic_payroll_transmissions(company_id, status)');
  }

  Future<List<Map<String, dynamic>>> listDocuments() async {
    final db = await DatabaseHelper.instance.database;
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    return db.rawQuery('''
      SELECT n.*, t.status AS electronic_status, t.external_id, t.verified_at
      FROM nomina_liquidaciones n
      LEFT JOIN electronic_payroll_transmissions t
        ON t.company_id = n.company_id AND t.liquidation_id = n.id
      WHERE n.company_id = ? AND LOWER(n.estado) != 'anulada'
      ORDER BY n.fecha DESC, n.id DESC
    ''', [companyId]);
  }

  Future<Map<String, dynamic>> _payload(int liquidationId) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.rawQuery('''
      SELECT n.*, e.documento, e.tipo_documento, e.cargo, e.eps, e.fondo_pension
      FROM nomina_liquidaciones n
      LEFT JOIN empleados e ON e.id = n.empleado_id AND e.company_id = n.company_id
      WHERE n.company_id = ? AND n.id = ? LIMIT 1
    ''', [companyId, liquidationId]);
    if (rows.isEmpty) throw StateError('No se encontró la liquidación.');
    final row = rows.first;
    if ((row['estado']?.toString().toLowerCase() ?? '') == 'anulada') {
      throw StateError('Una liquidación anulada no puede transmitirse.');
    }
    return {
      'source': 'MerkaERP',
      'liquidation_id': liquidationId,
      'period': row['periodo'],
      'employee': {
        'name': row['empleado'], 'document_type': row['tipo_documento'],
        'document': row['documento'], 'position': row['cargo'],
        'eps': row['eps'], 'pension_fund': row['fondo_pension'],
      },
      'amounts_minor': {
        'base_salary': row['salario_base'], 'earned': row['total_devengado'],
        'deductions': row['total_deducciones'], 'net': row['neto_pagar'],
        'employer_contributions': row['aportes_empleador'],
      },
      'calculation': _decodeJson(row['calculo_json']),
      'hrm_events': _decodeJson(row['novedades_hrm']),
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> submit(int liquidationId) async {
    final definition = IntegrationRegistry.byKey('payroll_electronic');
    final profile = await IntegrationSettingsService.instance.load(definition.key);
    if (!profile.enabled) throw StateError('Configura y habilita Nómina electrónica en Integraciones.');
    final values = await IntegrationSettingsService.instance.loadValues(definition);
    final base = Uri.parse(values['base_url'] ?? '');
    _requireSecure(base);
    final path = values['submission_path']?.trim().isNotEmpty == true ? values['submission_path']!.trim() : '/payroll';
    final uri = base.resolve(path);
    final payload = await _payload(liquidationId);
    final body = jsonEncode(payload);
    final headers = <String, String>{'content-type': 'application/json', 'accept': 'application/json'};
    _applyAuth(headers, values);
    final response = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('El proveedor rechazó la transmisión (${response.statusCode}).');
    }
    Map<String, dynamic> decoded = {};
    try { final value = jsonDecode(response.body); if (value is Map) decoded = Map<String,dynamic>.from(value); } catch (_) {}
    final externalId = (decoded['id'] ?? decoded['document_id'] ?? decoded['uuid'])?.toString();
    if (externalId == null || externalId.trim().isEmpty) {
      throw StateError('El proveedor respondió sin identificador verificable del documento.');
    }
    final db = await DatabaseHelper.instance.database;
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('electronic_payroll_transmissions', {
      'company_id': companyId, 'liquidation_id': liquidationId,
      'status': 'submitted', 'request_hash': sha256.convert(utf8.encode(body)).toString(),
      'external_id': externalId, 'response_json': response.body,
      'submitted_at': now, 'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'TRANSMITIR_NOMINA_ELECTRONICA', entidad: 'nomina_liquidaciones', entidadId: liquidationId,
      detalle: 'Documento enviado al proveedor por ${AppSession.nombre}; pendiente de confirmación externa. ID: $externalId',
    );
  }

  Future<void> verify(int liquidationId) async {
    final db = await DatabaseHelper.instance.database;
    await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query('electronic_payroll_transmissions', where: 'company_id = ? AND liquidation_id = ?', whereArgs: [companyId, liquidationId], limit: 1);
    if (rows.isEmpty || rows.first['external_id'] == null) throw StateError('Primero transmite el documento.');
    final externalId = rows.first['external_id'].toString();
    final definition = IntegrationRegistry.byKey('payroll_electronic');
    final values = await IntegrationSettingsService.instance.loadValues(definition);
    final base = Uri.parse(values['base_url'] ?? '');
    _requireSecure(base);
    final template = values['status_path']?.trim().isNotEmpty == true ? values['status_path']!.trim() : '/payroll/{id}';
    final uri = base.resolve(template.replaceAll('{id}', Uri.encodeComponent(externalId)));
    final headers = <String, String>{'accept': 'application/json'}; _applyAuth(headers, values);
    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) throw StateError('No fue posible verificar el documento (${response.statusCode}).');
    Map<String, dynamic> decoded = {};
    try { final value = jsonDecode(response.body); if (value is Map) decoded = Map<String,dynamic>.from(value); } catch (_) {}
    final remote = (decoded['status'] ?? decoded['state'] ?? decoded['estado'])?.toString().toLowerCase() ?? '';
    final accepted = const {'accepted','aceptada','validated','validada','success','approved'}.contains(remote);
    final rejected = const {'rejected','rechazada','error','failed','invalid'}.contains(remote);
    final status = accepted ? 'accepted' : rejected ? 'rejected' : 'submitted';
    await db.update('electronic_payroll_transmissions', {
      'status': status, 'response_json': response.body,
      'verified_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'company_id = ? AND liquidation_id = ?', whereArgs: [companyId, liquidationId]);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'VERIFICAR_NOMINA_ELECTRONICA', entidad: 'nomina_liquidaciones', entidadId: liquidationId,
      detalle: 'Estado confirmado por proveedor: $status ($remote).',
    );
  }

  Object? _decodeJson(Object? raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    try { return jsonDecode(raw.toString()); } catch (_) { return raw.toString(); }
  }

  void _requireSecure(Uri uri) {
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (!uri.hasScheme || (!local && uri.scheme.toLowerCase() != 'https')) {
      throw StateError('La integración remota debe usar HTTPS.');
    }
  }

  void _applyAuth(Map<String,String> headers, Map<String,String> values) {
    final type = (values['auth_type'] ?? 'BEARER').toUpperCase();
    final user = values['username'] ?? '';
    final credential = values['credential'] ?? '';
    if (type == 'BEARER' && credential.isNotEmpty) headers['authorization'] = 'Bearer $credential';
    if (type == 'API_KEY' && credential.isNotEmpty) headers[user.isEmpty ? 'x-api-key' : user] = credential;
    if (type == 'BASIC' && credential.isNotEmpty) headers['authorization'] = 'Basic ${base64Encode(utf8.encode('$user:$credential'))}';
  }
}
