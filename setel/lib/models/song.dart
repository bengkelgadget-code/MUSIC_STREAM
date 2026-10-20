import 'package:hive/hive.dart';

part 'song.g.dart';

@HiveType(typeId: 0)
class Song {
  @HiveField(0)
  final String videoId;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String artist;

  @HiveField(3)
  final int durationMs;

  @HiveField(4)
  final String thumbnailUrl;

  @HiveField(5)
  final String? cachedPath;

  const Song({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.thumbnailUrl,
    this.cachedPath,
  });

  Song copyWith({
    String? videoId,
    String? title,
    String? artist,
    int? durationMs,
    String? thumbnailUrl,
    String? cachedPath,
  }) {
    return Song(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      durationMs: durationMs ?? this.durationMs,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      cachedPath: cachedPath ?? this.cachedPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId;

  @override
  int get hashCode => videoId.hashCode;
}
