import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/core/discovery_config.dart';
import 'package:setel/models/song.dart';
import 'package:setel/models/song_chapter.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/cache_service.dart';
import 'package:setel/services/youtube_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_chapters_config_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(BOX_SONG_CHAPTERS);
    await Hive.openBox(BOX_DISCOVERY_CONFIG);
    await Hive.openBox(BOX_SETTINGS);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await Hive.box(BOX_SONG_CHAPTERS).clear();
    await Hive.box(BOX_DISCOVERY_CONFIG).clear();
  });

  group('SongChapter & Description Parsing Tests', () {
    test('SongChapter toMap and fromMap serialization', () {
      const chapter = SongChapter(title: 'Intro & Prelude', positionMs: 125000);
      final map = chapter.toMap();
      final restored = SongChapter.fromMap(map);

      expect(restored.title, 'Intro & Prelude');
      expect(restored.positionMs, 125000);
      expect(restored, equals(chapter));
      expect(restored.hashCode, equals(chapter.hashCode));
    });

    test('parseChaptersFromDescription returns empty for empty or < 2 chapters', () {
      expect(parseChaptersFromDescription(''), isEmpty);
      expect(parseChaptersFromDescription('Hanya video biasa tanpa timestamp'), isEmpty);
      expect(parseChaptersFromDescription('00:00 Hanya ada satu timestamp di sini'), isEmpty);
    });

    test('parseChaptersFromDescription parses mm:ss and hh:mm:ss correctly', () {
      const sample = '''
Daftar Lagu Terbaik:
00:00 Intro Pembuka
3:42 - Lagu Pertama (Akustik)
[07:15] | Lagu Kedua • Spesial
(12:30) : Lagu Ketiga
1:02:15 Lagu Kompilasi Penutup
''';

      final chapters = parseChaptersFromDescription(sample);
      expect(chapters.length, 5);

      expect(chapters[0].positionMs, 0);
      expect(chapters[0].title, 'Intro Pembuka');

      expect(chapters[1].positionMs, 222000); // 3*60 + 42 = 222s
      expect(chapters[1].title, 'Lagu Pertama (Akustik)');

      expect(chapters[2].positionMs, 435000); // 7*60 + 15 = 435s
      expect(chapters[2].title, 'Lagu Kedua • Spesial');

      expect(chapters[3].positionMs, 750000); // 12*60 + 30 = 750s
      expect(chapters[3].title, 'Lagu Ketiga');

      expect(chapters[4].positionMs, 3735000); // 1*3600 + 2*60 + 15 = 3735s
      expect(chapters[4].title, 'Lagu Kompilasi Penutup');
    });

    test('parseChaptersFromDescription handles escaped literal \\n and Windows \\r\\n', () {
      // String dengan literal \n escaped dan \r\n
      final escapedSample = '00:00 Intro\\n04:15 Lagu Kedua\\r\\n08:30 Lagu Ketiga';
      final chapters = parseChaptersFromDescription(escapedSample);
      expect(chapters.length, 3);
      expect(chapters[0].title, 'Intro');
      expect(chapters[1].title, 'Lagu Kedua');
      expect(chapters[2].title, 'Lagu Ketiga');
    });

    test('parseChaptersFromDescription extracts titles placed before timestamp', () {
      const sample = '''
01. Intro Lagu - 00:00
02. Lagu Akustik Pilihan - 03:45
03. Lagu Penutup (08:20)
''';
      final chapters = parseChaptersFromDescription(sample);
      expect(chapters.length, 3);
      expect(chapters[0].title, 'Intro Lagu');
      expect(chapters[1].title, 'Lagu Akustik Pilihan');
      expect(chapters[2].title, 'Lagu Penutup');
    });

    test('parseChaptersFromDescription parses 79-minute compilation with 10 songs correctly', () {
      const compilation79Min = '''
KOMPILASI LAGU TERBAIK 2026 (79 Menit)
00:00 Track 1 - Awal Cerita
07:30 Track 2 - Melodi Rindu
15:45 Track 3 - Senja di Jakarta
23:10 Track 4 - Pelita Harapan
31:00 Track 5 - Nada Asmara
39:20 Track 6 - Jejak Langkah
47:50 Track 7 - Bintang Kejora
56:15 Track 8 - Suara Hati
1:04:30 Track 9 - Selamanya Indah
1:12:00 Track 10 - Penutup Manis
''';

      final chapters = parseChaptersFromDescription(compilation79Min);
      expect(chapters.length, 10);
      expect(chapters[0].title, 'Track 1 - Awal Cerita');
      expect(chapters[0].positionMs, 0);

      expect(chapters[1].title, 'Track 2 - Melodi Rindu');
      expect(chapters[1].positionMs, (7 * 60 + 30) * 1000);

      expect(chapters[2].title, 'Track 3 - Senja di Jakarta');
      expect(chapters[2].positionMs, (15 * 60 + 45) * 1000);

      expect(chapters[3].title, 'Track 4 - Pelita Harapan');
      expect(chapters[3].positionMs, (23 * 60 + 10) * 1000);

      expect(chapters[9].title, 'Track 10 - Penutup Manis');
      expect(chapters[9].positionMs, (1 * 3600 + 12 * 60) * 1000); // 72 menit = 4320000ms
    });

    test('parseChaptersFromDescription sorts by timestamp and removes duplicates', () {
      const sample = '''
10:00 Bagian Kedua
00:00 Bagian Pertama
10:00 Bagian Duplikat
05:00 Bagian Tengah
''';

      final chapters = parseChaptersFromDescription(sample);
      expect(chapters.length, 3);
      expect(chapters[0].positionMs, 0);
      expect(chapters[0].title, 'Bagian Pertama');
      expect(chapters[1].positionMs, 300000);
      expect(chapters[1].title, 'Bagian Tengah');
      expect(chapters[2].positionMs, 600000);
      expect(chapters[2].title, 'Bagian Kedua');
    });
  });

  group('PlayerState Chapter Support & 79-min Navigation Simulation Tests', () {
    const compilation79Min = [
      SongChapter(title: 'Track 1', positionMs: 0),
      SongChapter(title: 'Track 2', positionMs: 450000), // 07:30
      SongChapter(title: 'Track 3', positionMs: 945000), // 15:45
      SongChapter(title: 'Track 4', positionMs: 1390000), // 23:10
      SongChapter(title: 'Track 5', positionMs: 1860000),
      SongChapter(title: 'Track 6', positionMs: 2360000),
      SongChapter(title: 'Track 7', positionMs: 2870000),
      SongChapter(title: 'Track 8', positionMs: 3375000),
      SongChapter(title: 'Track 9', positionMs: 3870000),
      SongChapter(title: 'Track 10', positionMs: 4320000),
    ];

    const compilationSong = Song(
      videoId: 'comp79min',
      title: 'Kompilasi Santai 79 Menit',
      artist: 'Various Artists',
      durationMs: 79 * 60 * 1000,
      thumbnailUrl: '',
    );

    test('PlayerState detects hasChapters and currentChapter correctly for 79-min compilation', () {
      final state = PlayerState(
        currentSong: compilationSong,
        isPlaying: true,
        position: const Duration(milliseconds: 500000),
        duration: const Duration(milliseconds: 79 * 60 * 1000),
        chapters: compilation79Min,
        chapterIndex: 1,
      );

      expect(state.hasChapters, isTrue);
      expect(state.chapters.length, 10);
      expect(state.currentChapter?.title, 'Track 2');
      expect(state.currentChapter?.positionMs, 450000);
    });

    test('Simulasi tap next 3x pada kompilasi 79 menit berpindah antar bab DALAM file yang sama', () {
      // Mulai di Track 1 (Index 0, Posisi 0)
      var currentChapterIndex = 0;
      var currentPositionMs = compilation79Min[currentChapterIndex].positionMs;
      expect(compilation79Min[currentChapterIndex].title, 'Track 1');
      expect(currentPositionMs, 0);

      // Tap Next #1 -> Pindah ke Track 2
      if (currentChapterIndex < compilation79Min.length - 1) {
        currentChapterIndex++;
        currentPositionMs = compilation79Min[currentChapterIndex].positionMs;
      }
      expect(currentChapterIndex, 1);
      expect(compilation79Min[currentChapterIndex].title, 'Track 2');
      expect(currentPositionMs, 450000); // 07:30

      // Tap Next #2 -> Pindah ke Track 3
      if (currentChapterIndex < compilation79Min.length - 1) {
        currentChapterIndex++;
        currentPositionMs = compilation79Min[currentChapterIndex].positionMs;
      }
      expect(currentChapterIndex, 2);
      expect(compilation79Min[currentChapterIndex].title, 'Track 3');
      expect(currentPositionMs, 945000); // 15:45

      // Tap Next #3 -> Pindah ke Track 4
      if (currentChapterIndex < compilation79Min.length - 1) {
        currentChapterIndex++;
        currentPositionMs = compilation79Min[currentChapterIndex].positionMs;
      }
      expect(currentChapterIndex, 3);
      expect(compilation79Min[currentChapterIndex].title, 'Track 4');
      expect(currentPositionMs, 1390000); // 23:10
    });
  });

  group('CacheService Limitation & Cleanup Tests', () {
    test('CacheServiceImpl ignores auto-cache for duration > 15 minutes', () async {
      final cacheDir = await Directory.systemTemp.createTemp('setel_cache_limit_test_');
      final cacheService = CacheServiceImpl(cacheDirectory: cacheDir);

      const longSong = Song(
        videoId: 'long_compilation_1',
        title: 'Album 2 Jam',
        artist: 'Various',
        durationMs: 7200000, // 2 jam > 15 menit
        thumbnailUrl: '',
      );

      final file = await cacheService.cacheSong(
        longSong,
        Uri.parse('https://example.com/audio.m4a'),
      );

      // Harus mengembalikan file kosong (dilewati)
      expect(file.path, isEmpty);

      if (cacheDir.existsSync()) {
        await cacheDir.delete(recursive: true);
      }
    });

    test('CacheServiceImpl.cancelCache deletes temporary .tmp file', () async {
      final cacheDir = await Directory.systemTemp.createTemp('setel_cancel_cache_test_');
      final cacheService = CacheServiceImpl(cacheDirectory: cacheDir);

      const song = Song(
        videoId: 'cancel_me_1',
        title: 'Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      // Buat file .tmp tiruan seolah-olah sedang download
      final tmpFile = File('${cacheDir.path}/${song.videoId}.tmp');
      await tmpFile.writeAsString('partial download chunk data');
      expect(tmpFile.existsSync(), isTrue);

      // Panggil cancelCache
      await cacheService.cancelCache(song);
      expect(tmpFile.existsSync(), isFalse);

      if (cacheDir.existsSync()) {
        await cacheDir.delete(recursive: true);
      }
    });
  });

  group('DiscoveryConfigService & DiscoveryCategory Tests', () {
    test('DiscoveryCategory parses JSON and resolves icons and gradients', () {
      final json = {
        'id': 'koplo_hits',
        'title': 'Dangdut Koplo',
        'group': 'indo',
        'query': 'dangdut koplo terbaru',
        'icon': 'celebration',
      };

      final cat = DiscoveryCategory.fromJson(json);
      expect(cat.id, 'koplo_hits');
      expect(cat.title, 'Dangdut Koplo');
      expect(cat.group, 'INDO');
      expect(cat.searchQuery, 'dangdut koplo terbaru');
      expect(cat.icon, Icons.celebration);
      expect(cat.gradientColors.length, 2);
    });

    test('DiscoveryConfigService.validateAndParse validates structure correctly', () {
      expect(DiscoveryConfigService.validateAndParse('bukan json'), isNull);
      expect(DiscoveryConfigService.validateAndParse('{"categories": "bukan list"}'), isNull);
      expect(DiscoveryConfigService.validateAndParse('{"categories": []}'), isNull);

      const validJson = '''
      {
        "version": 1,
        "categories": [
          {"id": "c1", "title": "Cat 1", "query": "q1", "group": "INDO", "icon": "music_note"},
          {"id": "c2", "title": "Cat 2", "query": "q2", "group": "MANCA", "icon": "public"}
        ]
      }
      ''';

      final result = DiscoveryConfigService.validateAndParse(validJson);
      expect(result, isNotNull);
      expect(result!.length, 2);
      expect(result[0].id, 'c1');
      expect(result[0].group, 'INDO');
      expect(result[1].id, 'c2');
      expect(result[1].group, 'MANCA');
    });

    test('DiscoveryConfigService caches and reads from Hive', () async {
      final box = Hive.box(BOX_DISCOVERY_CONFIG);
      const validJson = '''
      {
        "categories": [
          {"id": "c1", "title": "Cached Cat", "query": "query cached", "group": "INDO"}
        ]
      }
      ''';

      await box.put('categories_raw', validJson);
      await box.put('categories_fetched_at', DateTime.now().millisecondsSinceEpoch);

      final service = DiscoveryConfigService();
      final categories = await service.getCategories();
      expect(categories.length, 1);
      expect(categories.first.id, 'c1');
      expect(categories.first.title, 'Cached Cat');
    });

    test('YouTubeService.getChapters respects 24h cache in Hive', () async {
      final box = Hive.box(BOX_SONG_CHAPTERS);
      final fakeChapters = [
        {'title': 'Chapter 1', 'positionMs': 0},
        {'title': 'Chapter 2', 'positionMs': 60000},
      ];

      // Simpan cache valid (baru saja di-fetch)
      await box.put('test_video_123', {
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        'chapters': fakeChapters,
      });

      final ytService = YouTubeServiceImpl();
      final chapters = await ytService.getChapters('test_video_123');

      expect(chapters.length, 2);
      expect(chapters[0].title, 'Chapter 1');
      expect(chapters[1].title, 'Chapter 2');
      expect(chapters[1].positionMs, 60000);
    });
  });
}
