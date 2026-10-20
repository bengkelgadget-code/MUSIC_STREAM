import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:setel/ui/widgets/song_tile.dart';

class TestYouTubeService implements YouTubeService {
  int apiCalls = 0;

  @override
  Future<List<Song>> search(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    final cacheBox = Hive.box<SearchCache>(BOX_SEARCH_CACHE);
    final songsBox = Hive.box<Song>(BOX_SONGS);

    final cached = cacheBox.get(cleanQuery);
    if (cached != null && !cached.isExpired(ttl: SEARCH_CACHE_TTL)) {
      final cachedSongs = <Song>[];
      for (final id in cached.videoIds) {
        final s = songsBox.get(id);
        if (s != null) cachedSongs.add(s);
      }
      if (cachedSongs.isNotEmpty) return cachedSongs;
    }

    apiCalls++;
    final result = [
      Song(
        videoId: 'vid_$cleanQuery',
        title: 'Hasil $query',
        artist: 'Artis $query',
        durationMs: 180000,
        thumbnailUrl: 'https://example.com/thumb.jpg',
      ),
    ];

    for (final s in result) {
      await songsBox.put(s.videoId, s);
    }
    await cacheBox.put(
      cleanQuery,
      SearchCache(
        query: cleanQuery,
        videoIds: result.map((s) => s.videoId).toList(),
        cachedAt: DateTime.now(),
      ),
    );

    return result;
  }

  @override
  Future<Uri> resolveStreamUrl(String videoId) async {
    return Uri.parse('https://example.com/stream.m4a');
  }

  @override
  Future<Song> fetchMetadata(String videoId) async {
    return Song(
      videoId: videoId,
      title: 'Title',
      artist: 'Artist',
      durationMs: 0,
      thumbnailUrl: '',
    );
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_fase1_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(SongAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PlaylistAdapter());
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(HistoryEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(SearchCacheAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(SettingsAdapter());

    await Hive.openBox<Song>(BOX_SONGS);
    await Hive.openBox<SearchCache>(BOX_SEARCH_CACHE);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Fase 1 - SearchCache & YouTube Service Tests', () {
    test('SearchCache TTL 24 jam prevents duplicate network calls', () async {
      final service = TestYouTubeService();

      // Panggilan pertama -> Cache MISS (apiCalls = 1)
      final results1 = await service.search('tulus');
      expect(results1.length, 1);
      expect(service.apiCalls, 1);

      // Panggilan kedua -> Cache HIT (apiCalls tetap 1)
      final results2 = await service.search('Tulus ');
      expect(results2.length, 1);
      expect(results2.first.title, results1.first.title);
      expect(service.apiCalls, 1,
          reason: 'Harus mengambil dari SearchCache tanpa call API ulang');
    });

    test('PlayerState handles repeat mode cycle and queue copy', () {
      const state = PlayerState();
      expect(state.repeatMode, RepeatMode.off);

      final stateAll = state.copyWith(repeatMode: RepeatMode.all);
      expect(stateAll.repeatMode, RepeatMode.all);

      final stateOne = stateAll.copyWith(repeatMode: RepeatMode.one);
      expect(stateOne.repeatMode, RepeatMode.one);
    });

    testWidgets('SongTile renders title, artist, and duration',
        (WidgetTester tester) async {
      const song = Song(
        videoId: 'v123',
        title: 'Hati-Hati di Jalan',
        artist: 'Tulus',
        durationMs: 242000,
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(song: song),
          ),
        ),
      );

      expect(find.text('Hati-Hati di Jalan'), findsOneWidget);
      expect(find.text('Tulus'), findsOneWidget);
      expect(find.text('4:02'), findsOneWidget);
    });
  });
}
