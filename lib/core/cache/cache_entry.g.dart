// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CacheEntryAdapter extends TypeAdapter<CacheEntry> {
  @override
  final int typeId = 0;

  @override
  CacheEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CacheEntry(
      key: fields[0] as String,
      value: fields[1] as dynamic,
      createdAt: fields[2] as DateTime,
      ttl: fields[3] as Duration,
    );
  }

  @override
  void write(BinaryWriter writer, CacheEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.ttl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CacheEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
