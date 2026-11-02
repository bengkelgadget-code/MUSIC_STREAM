import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/cache_service.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_data_saver_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(SongAdapter());
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

  group('Data Saver & Quota Optimization Tests', () {
    test('auto_cache_enabled defaults to false for quota protection', () {
      final box = Hive.box(BOX_SETTINGS);
      final autoCacheEnabled =
          (box.get('auto_cache_enabled', defaultValue: false) as bool?) ?? false;
      expect(autoCacheEnabled, isFalse);
    });

    test('selectMuxedStreamByFormat caps video quality at <= 750 kbps (360p) to avoid data waste', () {
      final mockStreams = <MuxedStreamInfo>[
        MuxedStreamInfo(
          VideoId('kJQP7kiw5Fk'),
          18,
          Uri.parse('https://example.com/360p.mp4'),
          StreamContainer.mp4,
          FileSize(20 * 1024 * 1024),
          Bitrate(600 * 1000),
          'mp4a.40.2',
          'avc1.42001E',
          '360p',
          VideoQuality.medium360,
          const VideoResolution(640, 360),
          Framerate(30),
          MediaType('video', 'mp4'),
        ),
        MuxedStreamInfo(
          VideoId('kJQP7kiw5Fk'),
          22,
          Uri.parse('https://example.com/720p.mp4'),
          StreamContainer.mp4,
          FileSize(60 * 1024 * 1024),
          Bitrate(2000 * 1000),
          'mp4a.40.2',
          'avc1.64001F',
          '720p',
          VideoQuality.high720,
          const VideoResolution(1280, 720),
          Framerate(30),
          MediaType('video', 'mp4'),
        ),
      ];

      // Tertinggi should pick 360p (<= 750 kbps) because 720p has identical 128k audio but 3x more video waste
      final highest = selectMuxedStreamByFormat(mockStreams, 'Tertinggi');
      expect(highest.tag, 18);
      expect(highest.qualityLabel, '360p');

      // Seimbang should also pick 360p
      final balanced = selectMuxedStreamByFormat(mockStreams, 'Seimbang');
      expect(balanced.tag, 18);

      // Hemat Data picks lowest bitrate
      final low = selectMuxedStreamByFormat(mockStreams, 'Hemat Data');
      expect(low.tag, 18);
    });

    test('CacheServiceImpl.isCached accurately reports file presence', () async {
      final cacheDir = Directory('${tempDir.path}/setel_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      final cacheService = CacheServiceImpl(cacheDirectory: cacheDir);

      const song = Song(
        videoId: 'test_cached_song_1',
        title: 'Song 1',
        artist: 'Artist 1',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      // Not cached initially
      expect(await cacheService.isCached(song), isFalse);

      // Create fake cached file
      final file = File('${cacheDir.path}/${song.videoId}.m4a');
      await file.writeAsBytes([1, 2, 3, 4]);

      expect(await cacheService.isCached(song), isTrue);
    });
  });
}
