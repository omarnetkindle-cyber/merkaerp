import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'package:sqflite/sqflite.dart';

import '../../app_session.dart';
import '../app/app_version.dart';
import '../../db_helper.dart';
import '../../licensing/domain/product_family.dart';
import '../../services/licencia_service.dart';

class GoLiveCheckDefinition {
  const GoLiveCheckDefinition({
    required this.id,
    required this.area,
    required this.title,
    required this.description,
    this.blocking = true,
    this.automatic = false,
  });

  final String id;
  final String area;
  final String title;
  final String description;
  final bool blocking;
  final bool automatic;
}

class GoLiveCheckState {
  const GoLiveCheckState({
    required this.status,
    this.note = '',
    this.updatedAt,
    this.updatedBy,
  });

  final String status; // pending | pass | fail | na
  final String note;
  final DateTime? updatedAt;
  final String? updatedBy;

  Map<String, Object?> toJson() => {
    'status': status,
    'note': note,
    'updated_at': updatedAt?.toIso8601String(),
    'updated_by': updatedBy,
  };

  factory GoLiveCheckState.fromJson(Object? raw) {
    if (raw is! Map) return const GoLiveCheckState(status: 'pending');
    return GoLiveCheckState(
      status: raw['status']?.toString() ?? 'pending',
      note: raw['note']?.toString() ?? '',
      updatedAt: DateTime.tryParse(raw['updated_at']?.toString() ?? ''),
      updatedBy: raw['updated_by']?.toString(),
    );
  }
}

class GoLiveSnapshot {
  const GoLiveSnapshot({
    required this.family,
    required this.definitions,
    required this.states,
  });

  final ProductFamily family;
  final List<GoLiveCheckDefinition> definitions;
  final Map<String, GoLiveCheckState> states;

  int get passed => definitions.where((item) => states[item.id]?.status == 'pass' || states[item.id]?.status == 'na').length;
  int get total => definitions.length;
  int get blockingFailures => definitions.where((item) => item.blocking && states[item.id]?.status == 'fail').length;
  int get blockingPending => definitions.where((item) => item.blocking && !{'pass', 'na'}.contains(states[item.id]?.status)).length;
  bool get ready => blockingFailures == 0 && blockingPending == 0;
}

class GoLiveReportFiles {
  const GoLiveReportFiles({required this.report, required this.checksum});

  final File report;
  final File checksum;
}

class GoLiveService {
  GoLiveService._();
  static final GoLiveService instance = GoLiveService._();

  Future<GoLiveSnapshot> load() async {
    final license = await LicenciaService.instance.obtenerLicencia();
    final family = license?.productFamily ?? ProductFamily.commercial;
    final definitions = _definitionsFor(family);
    final db = await DatabaseHelper.instance.database;
    final key = await _storageKey(family);
    final rows = await db.query('app_config', where: 'clave = ?', whereArgs: [key], limit: 1);
    Map<String, dynamic> decoded = const {};
    if (rows.isNotEmpty) {
      try {
        final value = jsonDecode(rows.first['valor']?.toString() ?? '{}');
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}
    }
    final states = <String, GoLiveCheckState>{};
    for (final definition in definitions) {
      states[definition.id] = GoLiveCheckState.fromJson(decoded[definition.id]);
    }
    const releaseBuild = bool.fromEnvironment('dart.vm.product');
    const analyzerClean = bool.fromEnvironment('MERKA_ANALYZER_CLEAN', defaultValue: false);
    const testsPassing = bool.fromEnvironment('MERKA_TESTS_PASSING', defaultValue: false);
    states['release_build'] = GoLiveCheckState(
      status: releaseBuild ? 'pass' : 'fail',
      note: releaseBuild ? 'Evidencia automática: la aplicación se ejecuta en modo release.' : 'Evidencia automática ausente: esta ejecución no es release.',
    );
    states['analyze_tests'] = GoLiveCheckState(
      status: analyzerClean && testsPassing ? 'pass' : 'fail',
      note: analyzerClean && testsPassing
          ? 'Evidencia automática inyectada por scripts/build_release.ps1 después de que analyze y test pasaron.'
          : 'El build instalado no contiene evidencia de analyzer + tests aprobados.',
    );
    return GoLiveSnapshot(family: family, definitions: definitions, states: states);
  }

  Future<void> update(String id, String status, {String note = ''}) async {
    _requireAdmin();
    if (!{'pending', 'pass', 'fail', 'na'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'Estado de Go-Live inválido.');
    }
    final snapshot = await load();
    GoLiveCheckDefinition? definition;
    for (final item in snapshot.definitions) {
      if (item.id == id) {
        definition = item;
        break;
      }
    }
    if (definition == null) {
      throw StateError('La verificación no pertenece al producto licenciado.');
    }
    if (definition.automatic) {
      throw StateError('Esta verificación usa evidencia automática del build y no puede marcarse manualmente.');
    }
    final db = await DatabaseHelper.instance.database;
    final key = await _storageKey(snapshot.family);
    final payload = <String, Object?>{
      for (final entry in snapshot.states.entries) entry.key: entry.value.toJson(),
    };
    payload[id] = GoLiveCheckState(
      status: status,
      note: note.trim(),
      updatedAt: DateTime.now().toUtc(),
      updatedBy: AppSession.nombre,
    ).toJson();
    await db.insert(
      'app_config',
      {'clave': key, 'valor': jsonEncode(payload)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'GO_LIVE_CHECK',
      entidad: 'release_readiness',
      detalle: 'check=$id; status=$status',
    );
  }

  Future<GoLiveReportFiles> exportReport() async {
    _requireAdmin();
    final snapshot = await load();
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final generatedAt = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'format': 'MERKAERP_GO_LIVE_REPORT_1',
      'generated_at': generatedAt.toIso8601String(),
      'app_version': AppVersion.display,
      'company_id': companyId,
      'product_family': snapshot.family.storageValue,
      'ready': snapshot.ready,
      'summary': {
        'passed_or_na': snapshot.passed,
        'total': snapshot.total,
        'blocking_pending': snapshot.blockingPending,
        'blocking_failures': snapshot.blockingFailures,
      },
      'checks': snapshot.definitions.map((definition) {
        final state = snapshot.states[definition.id] ?? const GoLiveCheckState(status: 'pending');
        return <String, Object?>{
          'id': definition.id,
          'area': definition.area,
          'title': definition.title,
          'description': definition.description,
          'blocking': definition.blocking,
          'automatic': definition.automatic,
          'status': state.status,
          'evidence': state.note,
          'updated_at': state.updatedAt?.toIso8601String(),
          'updated_by': state.updatedBy,
        };
      }).toList(growable: false),
      'attestation': 'Este reporte refleja la evidencia registrada en la instalación indicada. Los controles automáticos no pueden aprobarse manualmente.',
    };
    final temp = await Directory.systemTemp.createTemp('merkaerp_go_live_');
    final stamp = generatedAt.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final report = File('${temp.path}/go_live_${snapshot.family.storageValue}_$stamp.json');
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(payload));
    await report.writeAsBytes(bytes, flush: true);
    final digest = crypto.sha256.convert(bytes).toString();
    final checksum = File('${report.path}.sha256.txt');
    await checksum.writeAsString('$digest  ${report.uri.pathSegments.last}\n', flush: true);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'EXPORTAR_REPORTE_GO_LIVE',
      entidad: 'release_readiness',
      detalle: 'family=${snapshot.family.storageValue}; ready=${snapshot.ready}; sha256=$digest',
    );
    return GoLiveReportFiles(report: report, checksum: checksum);
  }

  Future<void> reset() async {
    _requireAdmin();
    final license = await LicenciaService.instance.obtenerLicencia();
    final family = license?.productFamily ?? ProductFamily.commercial;
    final db = await DatabaseHelper.instance.database;
    await db.delete('app_config', where: 'clave = ?', whereArgs: [await _storageKey(family)]);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'GO_LIVE_RESET',
      entidad: 'release_readiness',
      detalle: 'family=${family.storageValue}',
    );
  }

  Future<String> _storageKey(ProductFamily family) async {
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return 'go_live_${family.storageValue}_$companyId';
  }

  void _requireAdmin() {
    if (!AppSession.puedeAdministrar()) {
      throw StateError('El checklist de puesta en marcha requiere una sesión administradora.');
    }
  }

  List<GoLiveCheckDefinition> _definitionsFor(ProductFamily family) {
    final common = <GoLiveCheckDefinition>[
      const GoLiveCheckDefinition(id: 'release_build', area: 'Aplicación', title: 'Build release validado', description: 'La edición instalada compila y abre en modo release sin errores.', automatic: true),
      const GoLiveCheckDefinition(id: 'analyze_tests', area: 'Aplicación', title: 'Analyzer y pruebas automatizadas', description: 'flutter analyze y flutter test pasan en la misma versión que se instalará.', automatic: true),
      const GoLiveCheckDefinition(id: 'permissions', area: 'Seguridad', title: 'Roles y permisos', description: 'Se verificó que usuarios sin permiso no puedan ejecutar acciones restringidas.'),
      const GoLiveCheckDefinition(id: 'backup_verify', area: 'Continuidad', title: 'Respaldo integral verificado', description: 'Se creó y verificó un respaldo de base + repositorio documental.'),
      const GoLiveCheckDefinition(id: 'restore_drill', area: 'Continuidad', title: 'Simulacro de restauración', description: 'Una copia de la instalación fue reconstruida desde respaldo y validada.', blocking: true),
      const GoLiveCheckDefinition(id: 'migration_reconcile', area: 'Migración', title: 'Migración conciliada', description: 'Si existía sistema anterior, totales/maestros/saldos fueron conciliados. Marcar N/A si no aplica.'),
      const GoLiveCheckDefinition(id: 'integrations', area: 'Integraciones', title: 'Integraciones requeridas', description: 'Las integraciones necesarias para esta organización fueron configuradas y probadas; las no usadas están deshabilitadas.'),
      const GoLiveCheckDefinition(id: 'users_trained', area: 'Operación', title: 'Usuarios capacitados', description: 'Responsables y suplentes conocen sus flujos, respaldos y canales de soporte.', blocking: false),
    ];
    if (family == ProductFamily.publicSector) {
      return [
        ...common,
        const GoLiveCheckDefinition(id: 'public_budget', area: 'Sector Público', title: 'Cadena presupuestal', description: 'Apropiación → CDP → RP → obligación → pago se probó con trazabilidad completa.'),
        const GoLiveCheckDefinition(id: 'public_accounting', area: 'Sector Público', title: 'Contabilidad pública', description: 'El flujo presupuestal-contable mantiene consistencia y saldos verificables.'),
        const GoLiveCheckDefinition(id: 'sgdea', area: 'SGDEA', title: 'Expediente y radicación', description: 'Radicación, trámite, expediente, versiones, reserva, archivo y consulta fueron validados.'),
        const GoLiveCheckDefinition(id: 'archival_instruments', area: 'SGDEA', title: 'Instrumentos archivísticos parametrizados', description: 'La entidad configuró los instrumentos/políticas aplicables (TRD/TVD/PGD y demás según corresponda).'),
        const GoLiveCheckDefinition(id: 'public_uat', area: 'UAT', title: 'Proceso público extremo a extremo', description: 'Se completó un proceso representativo desde origen presupuestal/documental hasta pago, contabilidad y archivo.'),
      ];
    }
    return [
      ...common,
      const GoLiveCheckDefinition(id: 'sale_cash', area: 'Comercial', title: 'Venta de contado', description: 'Venta, stock, caja, documento y asiento quedaron consistentes.'),
      const GoLiveCheckDefinition(id: 'sale_credit_mixed', area: 'Comercial', title: 'Crédito y pago mixto', description: 'Cartera, caja/banco, inventario y contabilidad cuadran en ventas a crédito y mixtas.'),
      const GoLiveCheckDefinition(id: 'purchase', area: 'Comercial', title: 'Compra y proveedor', description: 'Compra, inventario, cuenta por pagar y contabilidad quedaron consistentes.'),
      const GoLiveCheckDefinition(id: 'cash_close', area: 'Comercial', title: 'Cierre de caja', description: 'Apertura, movimientos, arqueo, diferencia, autorización y cierre fueron probados.'),
      const GoLiveCheckDefinition(id: 'commercial_uat', area: 'UAT', title: 'Proceso comercial extremo a extremo', description: 'Se completó un ciclo representativo compra → inventario → venta → recaudo → cierre → reportes.'),
    ];
  }
}
