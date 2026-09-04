import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'sync_auth.dart';

class SyncEventValidationException implements Exception {
  const SyncEventValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SyncEvent {
  const SyncEvent({
    required this.eventId,
    required this.tenantKind,
    required this.tenantId,
    required this.companyId,
    required this.branchId,
    required this.aggregateType,
    required this.aggregateId,
    required this.operation,
    required this.eventName,
    required this.eventVersion,
    required this.payload,
    required this.payloadChecksum,
    required this.idempotencyKey,
    required this.sourceDeviceId,
    required this.sourceUserId,
    required this.createdAt,
  });

  final String eventId;
  final String tenantKind;
  final String tenantId;
  final int? companyId;
  final int? branchId;
  final String aggregateType;
  final String aggregateId;
  final String operation;
  final String eventName;
  final int eventVersion;
  final Map<String, Object?> payload;
  final String payloadChecksum;
  final String idempotencyKey;
  final String sourceDeviceId;
  final String? sourceUserId;
  final DateTime? createdAt;

  factory SyncEvent.fromJson(Map<String, Object?> json) {
    final payload = _requiredMap(json, 'payload');
    final event = SyncEvent(
      eventId: _requiredString(json, 'event_id'),
      tenantKind: _requiredString(json, 'tenant_kind'),
      tenantId: _requiredString(json, 'tenant_id'),
      companyId: _intValue(json['company_id']),
      branchId: _intValue(json['branch_id']),
      aggregateType: _requiredString(json, 'aggregate_type'),
      aggregateId: _requiredString(json, 'aggregate_id'),
      operation: _requiredString(json, 'operation'),
      eventName: _requiredString(json, 'event_name'),
      eventVersion: _intValue(json['event_version']) ?? 1,
      payload: payload,
      payloadChecksum: _requiredString(json, 'payload_checksum'),
      idempotencyKey: _requiredString(json, 'idempotency_key'),
      sourceDeviceId: _requiredString(json, 'source_device_id'),
      sourceUserId: _stringValue(json['source_user_id']),
      createdAt: DateTime.tryParse(_stringValue(json['created_at']) ?? ''),
    );
    event.validatePayloadChecksum();
    return event;
  }

  void authorize(SyncAuthContext auth) {
    if (auth.tenantKind != tenantKind) {
      throw const SyncAuthException('tenant_kind no coincide con el JWT.');
    }
    if (auth.tenantId != tenantId) {
      throw const SyncAuthException('tenant_id no coincide con el JWT.');
    }
    if (auth.deviceId != sourceDeviceId) {
      throw const SyncAuthException('source_device_id no coincide con el JWT.');
    }
  }

  void validatePayloadChecksum() {
    final computed =
        sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    if (computed != payloadChecksum) {
      throw const SyncEventValidationException('payload_checksum inválido.');
    }
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = _stringValue(json[key]);
    if (value == null) {
      throw SyncEventValidationException('$key requerido.');
    }
    return value;
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw SyncEventValidationException('$key debe ser objeto JSON.');
  }

  static int? _intValue(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
