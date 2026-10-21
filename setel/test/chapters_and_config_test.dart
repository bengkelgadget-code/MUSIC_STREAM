import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/core/discovery_config.dart';
import 'package:setel/models/song.dart';
import 'package:setel/models/song_chapter.dart';
import 'package:setel/services/audio_player_service.dart';
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

  group('PlayerState Chapter Support Tests', () {
    const chapters = [
      SongChapter(title: 'Bab 1', positionMs: 0),
      SongChapter(title: 'Bab 2', positionMs: 180000),
      SongChapter(title: 'Bab 3', positionMs: 360000),
    ];

    const song = Song(
      videoId: 'comp1',
      title: 'Full Album Kompilasi',
      artist: 'Various Artists',
      durationMs: 720000,
      thumbnailUrl: '',
    );

    test('PlayerState detects hasChapters and currentChapter correctly', () {
      final stateNoChapters = PlayerState(
        currentSong: song,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(milliseconds: 720000),
      );
      expect(stateNoChapters.hasChapters, isFalse);
      expect(stateNoChapters.currentChapter, isNull);

      final stateWithChapters = PlayerState(
        currentSong: song,
        isPlaying: true,
        position: const Duration(milliseconds: 200000),
        duration: const Duration(milliseconds: 720000),
        chapters: chapters,
        chapterIndex: 1,
      );
      expect(stateWithChapters.hasChapters, isTrue);
      expect(stateWithChapters.currentChapter?.title, 'Bab 2');
      expect(stateWithChapters.currentChapter?.positionMs, 180000);
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
