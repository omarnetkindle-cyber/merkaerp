import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A source row captured in an evidence capsule.
class EvidenceSourceRecord {
  const EvidenceSourceRecord({
    required this.table,
    required this.id,
    required this.values,
  });

  final String table;
  final String id;
  final Map<String, dynamic> values;

  Map<String, dynamic> toJson() => {'table': table, 'id': id, 'values': values};
}

/// A deterministic, offline-verifiable explanation of a system result.
///
/// The hash covers every field except [integritySha256]. Source records and
/// audit rows are sorted by the service before construction so two captures
/// made at the same instant have the same digest.
class EvidenceCapsule {
  const EvidenceCapsule({
    required this.capsuleVersion,
    required this.generatedAt,
    required this.domain,
    required this.recordType,
    required this.recordId,
    required this.sourceRecords,
    required this.calculations,
    required this.monetaryConversions,
    required this.actor,
    required this.schemaVersion,
    required this.auditRecords,
    required this.result,
    required this.integritySha256,
  });

  factory EvidenceCapsule.create({
    required DateTime generatedAt,
    required String domain,
    required String recordType,
    required String recordId,
    required List<EvidenceSourceRecord> sourceRecords,
    required List<Map<String, dynamic>> calculations,
    required List<Map<String, dynamic>> monetaryConversions,
    required Map<String, dynamic> actor,
    required int schemaVersion,
    required List<Map<String, dynamic>> auditRecords,
    required Map<String, dynamic> result,
  }) {
    final capsule = EvidenceCapsule(
      capsuleVersion: 1,
      generatedAt: generatedAt.toUtc().toIso8601String(),
      domain: domain,
      recordType: recordType,
      recordId: recordId,
      sourceRecords: List<EvidenceSourceRecord>.unmodifiable(
        [
          ...sourceRecords,
        ]..sort((a, b) => '${a.table}:${a.id}'.compareTo('${b.table}:${b.id}')),
      ),
      calculations: List<Map<String, dynamic>>.unmodifiable(
        calculations.map(_jsonSafeMap).toList(),
      ),
      monetaryConversions: List<Map<String, dynamic>>.unmodifiable(
        monetaryConversions.map(_jsonSafeMap).toList(),
      ),
      actor: _jsonSafeMap(actor),
      schemaVersion: schemaVersion,
      auditRecords: List<Map<String, dynamic>>.unmodifiable(
        [...auditRecords]..sort(
          (a, b) => '${a['fecha_hora']}:${a['id']}'.compareTo(
            '${b['fecha_hora']}:${b['id']}',
          ),
        ),
      ),
      result: _jsonSafeMap(result),
      integritySha256: '',
    );
    return capsule._withHash(capsule._hashForContent());
  }

  final int capsuleVersion;
  final String generatedAt;
  final String domain;
  final String recordType;
  final String recordId;
  final List<EvidenceSourceRecord> sourceRecords;
  final List<Map<String, dynamic>> calculations;
  final List<Map<String, dynamic>> monetaryConversions;
  final Map<String, dynamic> actor;
  final int schemaVersion;
  final List<Map<String, dynamic>> auditRecords;
  final Map<String, dynamic> result;
  final String integritySha256;

  Map<String, dynamic> toJsonMap({bool includeIntegrity = true}) {
    final map = <String, dynamic>{
      'capsule_version': capsuleVersion,
      'generated_at': generatedAt,
      'domain': domain,
      'record_type': recordType,
      'record_id': recordId,
      'source_records': sourceRecords.map((row) => row.toJson()).toList(),
      'calculations': calculations,
      'monetary_conversions': monetaryConversions,
      'actor': actor,
      'schema_version': schemaVersion,
      'audit_records': auditRecords,
      'result': result,
    };
    if (includeIntegrity) map['integrity_sha256'] = integritySha256;
    return map;
  }

  /// Canonical JSON is suitable for export, hashing, and later verification.
  String toJson() => jsonEncode(_canonicalize(toJsonMap()));

  bool verifyIntegrity() {
    return _hashForContent() == integritySha256;
  }

  EvidenceCapsule _withHash(String hash) => EvidenceCapsule(
    capsuleVersion: capsuleVersion,
    generatedAt: generatedAt,
    domain: domain,
    recordType: recordType,
    recordId: recordId,
    sourceRecords: sourceRecords,
    calculations: calculations,
    monetaryConversions: monetaryConversions,
    actor: actor,
    schemaVersion: schemaVersion,
    auditRecords: auditRecords,
    result: result,
    integritySha256: hash,
  );

  String _hashForContent() {
    final content = jsonEncode(
      _canonicalize(toJsonMap(includeIntegrity: false)),
    );
    return sha256.convert(utf8.encode(content)).toString();
  }
}

Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> input) =>
    Map<String, dynamic>.from(_jsonSafe(input) as Map);

dynamic _jsonSafe(dynamic value) {
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _jsonSafe(entry.value),
    };
  }
  if (value is Iterable) return value.map(_jsonSafe).toList();
  return value;
}

dynamic _canonicalize(dynamic value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return {
      for (final entry in entries)
        entry.key.toString(): _canonicalize(entry.value),
    };
  }
  if (value is Iterable) return value.map(_canonicalize).toList();
  return value;
}
