import 'dart:convert';
import '../../app_session.dart';
import '../../db_helper.dart';
import '../../sync/domain/sync_models.dart';
import '../../sync/domain/sync_tenant_scope.dart';

/// Helper para encolar eventos de sincronización del Sector Público (Event-Sourcing).
/// Soporta los agregados: 'cdps', 'rps', 'pagos', 'asientos_contables_sp', 'proyectos_ocad'.
class PublicSectorSyncHelper {
  const PublicSectorSyncHelper._();

  static const List<String> supportedPublicAggregates = [
    'cdps',
    'rps',
    'pagos',
    'asientos_contables_sp',
    'proyectos_ocad',
  ];

  /// Encola un evento de cambio del Sector Público en `sync_outbox`.
  static Future<void> enqueuePublicEvent({
    required String aggregateType,
    required String aggregateId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    String? entidadId,
    String? usuarioId,
  }) async {
    final scope = SyncTenantScope.publicSector(
      entidadId: entidadId ?? AppSession.entidadId,
      usuarioId: usuarioId ?? AppSession.usuarioId,
    );

    final db = await DatabaseHelper.instance.database;

    final idempotencyKey =
        'sp:$aggregateType:$aggregateId:${operation.name}:${DateTime.now().millisecondsSinceEpoch}';

    await db.insert('sync_outbox', {
      'company_id': 0,
      'branch_id': 0,
      'tenant_type': scope.tenantType,
      'entidad_id': scope.entidadId,
      'user_id': scope.usuarioId,
      'aggregate_type': aggregateType,
      'aggregate_id': aggregateId,
      'event_type': operation.name,
      'payload_json': jsonEncode(payload),
      'idempotency_key': idempotencyKey,
      'vector_clock_json': jsonEncode({'node-sp': 1}),
      'status': 'pending',
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
