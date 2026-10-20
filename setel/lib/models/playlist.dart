import 'package:hive/hive.dart';

part 'playlist.g.dart';

@HiveType(typeId: 1)
class Playlist {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  final List<String> songIds;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.songIds,
  });

  Playlist copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    List<String>? songIds,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      songIds: songIds ?? this.songIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
