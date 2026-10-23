import 'package:hive/hive.dart';

part 'history_entry.g.dart';

@HiveType(typeId: 2)
class HistoryEntry {
  @HiveField(0)
  final String videoId;

  @HiveField(1)
  final DateTime playedAt;

  @HiveField(2)
  final int lastPositionMs;

  const HistoryEntry({
    required this.videoId,
    required this.playedAt,
    this.lastPositionMs = 0,
  });

  HistoryEntry copyWith({
    String? videoId,
    DateTime? playedAt,
    int? lastPositionMs,
  }) {
    return HistoryEntry(
      videoId: videoId ?? this.videoId,
      playedAt: playedAt ?? this.playedAt,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryEntry &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId &&
          playedAt == other.playedAt &&
          lastPositionMs == other.lastPositionMs;

  @override
  int get hashCode => Object.hash(videoId, playedAt, lastPositionMs);
}
