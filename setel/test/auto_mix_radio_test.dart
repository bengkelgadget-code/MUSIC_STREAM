import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/audio_player_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_automix_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(SongAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SearchCacheAdapter());

    await Hive.openBox<Song>(BOX_SONGS);
    await Hive.openBox<SearchCache>(BOX_SEARCH_CACHE);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AutoMix & Radio Queue Tests', () {
    test('PlayerState initial state has isAutoMix = false and mixSeedTitle = null', () {
      const state = PlayerState();
      expect(state.isAutoMix, isFalse);
      expect(state.mixSeedTitle, isNull);
    });

    test('PlayerState.copyWith updates isAutoMix and mixSeedTitle correctly', () {
      const state = PlayerState();
      final updated = state.copyWith(
        isAutoMix: true,
        mixSeedTitle: 'Sewindu - Tulus',
      );
      expect(updated.isAutoMix, isTrue);
      expect(updated.mixSeedTitle, 'Sewindu - Tulus');

      // Clear autoMix
      final cleared = updated.copyWith(
        isAutoMix: false,
        clearMixSeed: true,
      );
      expect(cleared.isAutoMix, isFalse);
      expect(cleared.mixSeedTitle, isNull);
    });

    test('SearchCache supports related video caching with TTL', () async {
      final cacheBox = Hive.box<SearchCache>(BOX_SEARCH_CACHE);
      final songsBox = Hive.box<Song>(BOX_SONGS);

      const song1 = Song(
        videoId: 'rel_1',
        title: 'Marcell - Semusim',
        artist: 'Marcell',
        durationMs: 240000,
        thumbnailUrl: '',
      );
      const song2 = Song(
        videoId: 'rel_2',
        title: 'Juicy Luicy - Lantas',
        artist: 'Juicy Luicy',
        durationMs: 210000,
        thumbnailUrl: '',
      );

      await songsBox.put(song1.videoId, song1);
      await songsBox.put(song2.videoId, song2);

      const cacheKey = 'related:sewindu_123';
      await cacheBox.put(
        cacheKey,
        SearchCache(
          query: cacheKey,
          videoIds: [song1.videoId, song2.videoId],
          cachedAt: DateTime.now(),
        ),
      );

      final cached = cacheBox.get(cacheKey);
      expect(cached, isNotNull);
      expect(cached!.isExpired(ttl: SEARCH_CACHE_TTL), isFalse);
      expect(cached.videoIds.length, 2);
      expect(cached.videoIds, contains('rel_1'));
      expect(cached.videoIds, contains('rel_2'));
    });
  });
}
