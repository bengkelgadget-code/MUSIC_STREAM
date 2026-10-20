import 'package:flutter_test/flutter_test.dart';
import 'package:setel/core/utils.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';

void main() {
  group('Fase 0 - Fondasi Tests', () {
    test('formatDuration formats mm:ss correctly', () {
      expect(formatDuration(const Duration(minutes: 3, seconds: 45)), '3:45');
      expect(formatDuration(const Duration(minutes: 0, seconds: 5)), '0:05');
      expect(formatDuration(const Duration(seconds: 125)), '2:05');
    });

    test('Song model instantiates and copyWith works without streamUrl', () {
      const song = Song(
        videoId: 'abc12345',
        title: 'Song Title',
        artist: 'Artist Name',
        durationMs: 180000,
        thumbnailUrl: 'https://img.youtube.com/vi/abc12345/hqdefault.jpg',
      );

      expect(song.videoId, 'abc12345');
      expect(song.title, 'Song Title');
      expect(song.artist, 'Artist Name');
      expect(song.durationMs, 180000);
      expect(song.cachedPath, isNull);

      final updated = song.copyWith(cachedPath: '/path/to/cache.m4a');
      expect(updated.cachedPath, '/path/to/cache.m4a');
      expect(updated.videoId, song.videoId);
    });

    test('Playlist, HistoryEntry, SearchCache, and Settings instantiate', () {
      final now = DateTime.now();
      final playlist = Playlist(
        id: 'p1',
        name: 'My Playlist',
        createdAt: now,
        songIds: const ['s1', 's2'],
      );
      expect(playlist.name, 'My Playlist');
      expect(playlist.songIds.length, 2);

      final history = HistoryEntry(videoId: 's1', playedAt: now);
      expect(history.videoId, 's1');

      final cache = SearchCache(
        query: 'tulus',
        videoIds: const ['s1'],
        cachedAt: now,
      );
      expect(cache.isExpired(), isFalse);

      const settings = Settings(cacheLimitMB: 500);
      expect(settings.cacheLimitMB, 500);
    });
  });
}
