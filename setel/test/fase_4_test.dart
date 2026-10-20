import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/audio_handler.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/cache_service.dart';
import 'package:setel/services/youtube_service.dart';

class DummyYouTubeService implements YouTubeService {
  @override
  Future<List<Song>> search(String query) async => [];

  @override
  Future<AudioStreamResult> resolveStreamUrl(String videoId,
          {int clientStartIndex = 0}) async =>
      AudioStreamResult(
        url: Uri.parse('https://example.com/audio.m4a'),
        headers: {'User-Agent': 'test'},
      );

  @override
  Future<List<String>> getSuggestions(String query) async => [];

  @override
  Future<Song> fetchMetadata(String videoId) async => const Song(
        videoId: 'm1',
        title: 'Title',
        artist: 'Artist',
        durationMs: 0,
        thumbnailUrl: '',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Directory cacheDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_fase4_test_');
    cacheDir = Directory('${tempDir.path}/cache');
    await cacheDir.create();

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
    await Hive.openBox(BOX_SETTINGS);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Fase 4 - Offline Cache & Sleep Timer Tests', () {
    late CacheServiceImpl cacheService;

    setUp(() {
      cacheService = CacheServiceImpl(cacheDirectory: cacheDir);
    });

    test('getCached returns file if cached file exists', () async {
      const song = Song(
        videoId: 'test_vid_1',
        title: 'Test Song 1',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      // Sebelum ada file
      expect(await cacheService.getCached(song), isNull);

      // Buat file cache dummy
      final file = File('${cacheDir.path}/${song.videoId}.m4a');
      await file.writeAsBytes([1, 2, 3, 4, 5]);

      final cached = await cacheService.getCached(song);
      expect(cached, isNotNull);
      expect(cached!.path, file.path);
    });

    test('cacheSizeBytes and clearCache work properly', () async {
      final file1 = File('${cacheDir.path}/song_a.m4a');
      await file1.writeAsBytes(List.filled(1024, 0)); // 1 KB
      final file2 = File('${cacheDir.path}/song_b.m4a');
      await file2.writeAsBytes(List.filled(2048, 0)); // 2 KB

      final total = await cacheService.cacheSizeBytes();
      expect(total, greaterThanOrEqualTo(3072));

      await cacheService.clearCache();
      final afterClear = await cacheService.cacheSizeBytes();
      expect(afterClear, 0);
    });

    test('LRU enforceLimit evicts oldest files when exceeding cache limit',
        () async {
      final settingsBox = Hive.box(BOX_SETTINGS);
      // Set limit ke 1 MB (untuk testing)
      await settingsBox.put(0, const Settings(cacheLimitMB: 1));

      // Buat 3 file dengan total 1.5 MB
      final fileOld = File('${cacheDir.path}/old_vid.m4a');
      await fileOld.writeAsBytes(List.filled(700 * 1024, 0));
      await fileOld.setLastModified(
          DateTime.now().subtract(const Duration(hours: 5)));

      final fileNew1 = File('${cacheDir.path}/new_vid_1.m4a');
      await fileNew1.writeAsBytes(List.filled(500 * 1024, 0));

      final fileNew2 = File('${cacheDir.path}/new_vid_2.m4a');
      await fileNew2.writeAsBytes(List.filled(400 * 1024, 0));

      // Total ~ 1.6 MB > 1 MB limit
      await cacheService.enforceLimit();

      // File terlama (old_vid) harus terhapus lebih dulu
      expect(fileOld.existsSync(), isFalse,
          reason: 'File terlama harus terhapus oleh aturan LRU');
      expect(fileNew1.existsSync() || fileNew2.existsSync(), isTrue);
    });

    test('Sleep timer setting and cancellation', () {
      final handler = SetelAudioHandler();
      final ytService = DummyYouTubeService();
      final playerService = AudioPlayerServiceImpl(
        youTubeService: ytService,
        audioHandler: handler,
        cacheService: cacheService,
      );

      // Set timer 30 menit
      playerService.setSleepTimer(const Duration(minutes: 30));

      // Batalkan timer
      playerService.cancelSleepTimer();

      // Set timer "Habis lagu ini"
      playerService.setSleepTimer(null, afterCurrentTrack: true);

      playerService.dispose();
    });

    test(
        'Setelah evict LRU dan clearCache, entry songsBox harus memiliki cachedPath == null',
        () async {
      final songsBox = Hive.box<Song>(BOX_SONGS);
      final settingsBox = Hive.box(BOX_SETTINGS);

      // 1. Uji LRU eviction membersihkan cachedPath
      await settingsBox.put(0, const Settings(cacheLimitMB: 1));

      final fileOld = File('${cacheDir.path}/evict_test.m4a');
      await fileOld.writeAsBytes(List.filled(700 * 1024, 0));
      await fileOld.setLastModified(
          DateTime.now().subtract(const Duration(days: 1)));

      final fileOther = File('${cacheDir.path}/keep_test.m4a');
      await fileOther.writeAsBytes(List.filled(600 * 1024, 0));

      // Simpan Song di songsBox dengan cachedPath
      const songToEvict = Song(
        videoId: 'evict_test',
        title: 'Song to Evict',
        artist: 'Artist',
        durationMs: 120000,
        thumbnailUrl: '',
        cachedPath: '/some/path/evict_test.m4a',
      );
      await songsBox.put('evict_test', songToEvict);
      expect(songsBox.get('evict_test')?.cachedPath, isNotNull);

      // Jalankan enforceLimit
      await cacheService.enforceLimit();

      // Pastikan entry songsBox sekarang cachedPath == null
      final evictedSongInBox = songsBox.get('evict_test');
      expect(evictedSongInBox, isNotNull);
      expect(evictedSongInBox?.cachedPath, isNull,
          reason: 'cachedPath harus null setelah LRU eviction');

      // 2. Uji clearCache membersihkan cachedPath
      const songToClear = Song(
        videoId: 'clear_test',
        title: 'Song to Clear',
        artist: 'Artist',
        durationMs: 150000,
        thumbnailUrl: '',
        cachedPath: '/some/path/clear_test.m4a',
      );
      await songsBox.put('clear_test', songToClear);
      expect(songsBox.get('clear_test')?.cachedPath, isNotNull);

      // Jalankan clearCache
      await cacheService.clearCache();

      // Pastikan entry songsBox sekarang cachedPath == null
      final clearedSongInBox = songsBox.get('clear_test');
      expect(clearedSongInBox, isNotNull);
      expect(clearedSongInBox?.cachedPath, isNull,
          reason: 'cachedPath harus null setelah clearCache');
    });
  });
}
