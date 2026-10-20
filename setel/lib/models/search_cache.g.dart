// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SearchCacheAdapter extends TypeAdapter<SearchCache> {
  @override
  final int typeId = 3;

  @override
  SearchCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SearchCache(
      query: fields[0] as String,
      videoIds: (fields[1] as List).cast<String>(),
      cachedAt: fields[2] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SearchCache obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.query)
      ..writeByte(1)
      ..write(obj.videoIds)
      ..writeByte(2)
      ..write(obj.cachedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
