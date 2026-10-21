class SongChapter {
  final String title;
  final int positionMs;

  const SongChapter({
    required this.title,
    required this.positionMs,
  });

  Map<String, dynamic> toMap() => {
        'title': title,
        'positionMs': positionMs,
      };

  factory SongChapter.fromMap(Map<dynamic, dynamic> map) {
    return SongChapter(
      title: (map['title'] as String?) ?? '',
      positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'SongChapter(title: $title, positionMs: $positionMs)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongChapter &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          positionMs == other.positionMs;

  @override
  int get hashCode => title.hashCode ^ positionMs.hashCode;
}
