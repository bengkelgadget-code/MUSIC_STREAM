import 'package:hive/hive.dart';

part 'history_entry.g.dart';

@HiveType(typeId: 2)
class HistoryEntry {
  @HiveField(0)
  final String videoId;

  @HiveField(1)
  final DateTime playedAt;

  const HistoryEntry({
    required this.videoId,
    required this.playedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryEntry &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId &&
          playedAt == other.playedAt;

  @override
  int get hashCode => Object.hash(videoId, playedAt);
}
