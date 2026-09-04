// ============================================================
// cache_entry.dart
// Modelo para entradas de caché con TTL
// ============================================================

import 'package:hive/hive.dart';

part 'cache_entry.g.dart';

@HiveType(typeId: 0)
class CacheEntry extends HiveObject {
  @override
  @HiveField(0)
  final String key;

  @HiveField(1)
  final dynamic value;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  final Duration ttl;

  CacheEntry({
    required this.key,
    required this.value,
    required this.createdAt,
    required this.ttl,
  });

  bool get isExpired {
    return DateTime.now().isAfter(createdAt.add(ttl));
  }

  CacheEntry copyWith({
    String? key,
    dynamic value,
    DateTime? createdAt,
    Duration? ttl,
  }) {
    return CacheEntry(
      key: key ?? this.key,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      ttl: ttl ?? this.ttl,
    );
  }
}
