import 'dart:convert';

import '../../licensing/domain/product_family.dart';

enum MigrationDuplicatePolicy { skip, merge }

enum MigrationFieldType { text, integer, decimal, money, date, email, boolean }

class MigrationFieldDefinition {
  const MigrationFieldDefinition({
    required this.key,
    required this.label,
    this.required = false,
    this.type = MigrationFieldType.text,
    this.aliases = const [],
    this.description,
  });

  final String key;
  final String label;
  final bool required;
  final MigrationFieldType type;
  final List<String> aliases;
  final String? description;
}

class MigrationEntityDefinition {
  const MigrationEntityDefinition({
    required this.key,
    required this.label,
    required this.productFamilies,
    required this.fields,
    required this.description,
  });

  final String key;
  final String label;
  final Set<ProductFamily> productFamilies;
  final List<MigrationFieldDefinition> fields;
  final String description;
}

class TabularDataset {
  const TabularDataset({
    required this.name,
    required this.headers,
    required this.rows,
  });

  final String name;
  final List<String> headers;
  final List<Map<String, String>> rows;
}

class MigrationPreviewIssue {
  const MigrationPreviewIssue({
    required this.rowNumber,
    required this.severity,
    required this.message,
    this.field,
    this.rawValue,
  });

  final int rowNumber;
  final String severity;
  final String message;
  final String? field;
  final String? rawValue;
}

class MigrationPreview {
  const MigrationPreview({
    required this.entity,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.mapping,
    required this.normalizedRows,
    required this.issues,
  });

  final MigrationEntityDefinition entity;
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final Map<String, String?> mapping;
  final List<Map<String, Object?>> normalizedRows;
  final List<MigrationPreviewIssue> issues;

  bool get canImport => totalRows > 0 && validRows > 0;
}

class MigrationImportResult {
  const MigrationImportResult({
    required this.jobId,
    required this.runId,
    required this.imported,
    required this.skipped,
    required this.errors,
    required this.backupPath,
  });

  final String jobId;
  final int runId;
  final int imported;
  final int skipped;
  final int errors;
  final String? backupPath;
}

class MigrationJobSummary {
  const MigrationJobSummary({
    required this.id,
    required this.sourceName,
    required this.productFamily,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.rolledBackAt,
    this.backupPath,
    this.summary = const {},
  });

  final String id;
  final String sourceName;
  final String productFamily;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final DateTime? rolledBackAt;
  final String? backupPath;
  final Map<String, Object?> summary;

  factory MigrationJobSummary.fromMap(Map<String, Object?> row) {
    final rawSummary = row['summary_json']?.toString();
    Map<String, Object?> summary = const {};
    if (rawSummary != null && rawSummary.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSummary);
        if (decoded is Map) summary = Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return MigrationJobSummary(
      id: row['id']?.toString() ?? '',
      sourceName: row['source_name']?.toString() ?? 'Migración',
      productFamily: row['product_family']?.toString() ?? '',
      status: row['status']?.toString() ?? 'unknown',
      startedAt: DateTime.tryParse(row['started_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: DateTime.tryParse(row['completed_at']?.toString() ?? ''),
      rolledBackAt: DateTime.tryParse(row['rolled_back_at']?.toString() ?? ''),
      backupPath: row['backup_path']?.toString(),
      summary: summary,
    );
  }
}
