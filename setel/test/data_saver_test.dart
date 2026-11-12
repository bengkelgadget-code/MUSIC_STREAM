import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
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

class MockConnectivity implements Connectivity {
  final List<ConnectivityResult> results;
  MockConnectivity(this.results);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value(results);
}

AudioOnlyStreamInfo createMockAudioStream({
  required int tag,
  required StreamContainer container,
  required String audioCodec,
  required double kbps,
}) {
  return AudioOnlyStreamInfo(
    VideoId('kJQP7kiw5Fk'),
    tag,
    Uri.parse('https://example.com/audio_$tag'),
    container,
    FileSize((kbps * 1000 / 8 * 180).round()),
    Bitrate((kbps * 1000).round()),
    audioCodec,
    '${kbps.round()}kbps',
    const [],
    MediaType('audio', container.name),
    null,
  );
}

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

    test(
        'selectMuxedStreamByFormat caps video quality at <= 750 kbps (360p) to avoid data waste',
        () {
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

      final highest = selectMuxedStreamByFormat(mockStreams, 'Tertinggi');
      expect(highest.tag, 18);
      expect(highest.qualityLabel, '360p');

      final balanced = selectMuxedStreamByFormat(mockStreams, 'Seimbang');
      expect(balanced.tag, 18);

      final low = selectMuxedStreamByFormat(mockStreams, 'Hemat Data');
      expect(low.tag, 18);
    });

    test('selectStreamByFormat prefers Opus codec with correct bitrate rules', () {
      final aacLow = createMockAudioStream(
        tag: 139,
        container: StreamContainer.mp4,
        audioCodec: 'mp4a.40.2',
        kbps: 48,
      );
      final opusLow = createMockAudioStream(
        tag: 249,
        container: StreamContainer.webM,
        audioCodec: 'opus',
        kbps: 50,
      );
      final opusMid = createMockAudioStream(
        tag: 250,
        container: StreamContainer.webM,
        audioCodec: 'opus',
        kbps: 70,
      );
      final aacMid = createMockAudioStream(
        tag: 140,
        container: StreamContainer.mp4,
        audioCodec: 'mp4a.40.2',
        kbps: 128,
      );
      final opusHigh = createMockAudioStream(
        tag: 251,
        container: StreamContainer.webM,
        audioCodec: 'opus',
        kbps: 160,
      );

      final allStreams = [aacLow, opusLow, opusMid, aacMid, opusHigh];

      // 1. Hemat Data: pilih bitrate terendah DI ANTARA stream Opus (container webm / codec opus) bila ada.
      // Meskipun aacLow adalah 48k, Opus terendah adalah opusLow (50k).
      final dataSaver = selectStreamByFormat(allStreams, 'Hemat Data');
      expect(dataSaver.tag, 249);
      expect(dataSaver.audioCodec, 'opus');

      // Bila tak ada Opus, baru bitrate terendah apa pun:
      final fallbackDataSaver =
          selectStreamByFormat([aacLow, aacMid], 'Hemat Data');
      expect(fallbackDataSaver.tag, 139);

      // 2. Seimbang: pilih bitrate tertinggi <=128 kbps DI ANTARA stream Opus bila ada.
      // Opus <= 128 kbps adalah opusLow (50k) dan opusMid (70k) -> pilih opusMid (70k).
      final balanced = selectStreamByFormat(allStreams, 'Seimbang');
      expect(balanced.tag, 250);
      expect(balanced.audioCodec, 'opus');

      // Bila tak ada Opus, fallback ke aturan lama (tertinggi <= 128 kbps apa pun):
      final fallbackBalanced =
          selectStreamByFormat([aacLow, aacMid], 'Seimbang');
      expect(fallbackBalanced.tag, 140);

      // 3. Tertinggi: tetap bitrate tertinggi (tanpa preferensi codec):
      final highest = selectStreamByFormat(allStreams, 'Tertinggi');
      expect(highest.tag, 251);
      expect(highest.bitrate.bitsPerSecond, 160 * 1000);
    });

    test('cache_wifi_only toggle skips caching when not connected to WiFi', () async {
      final cacheDir = Directory('${tempDir.path}/wifi_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_CACHE_WIFI_ONLY, true);

      // Koneksi seluler (bukan WiFi)
      final mobileConnectivity =
          MockConnectivity([ConnectivityResult.mobile]);
      final cacheServiceMobile = CacheServiceImpl(
        cacheDirectory: cacheDir,
        connectivity: mobileConnectivity,
      );

      const song = Song(
        videoId: 'wifi_test_song_1',
        title: 'WiFi Song',
        artist: 'WiFi Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      final result = await cacheServiceMobile.cacheSong(
        song,
        Uri.parse('https://example.com/stream.m4a'),
      );

      // Harus di-skip (mengembalikan File kosong '')
      expect(result.path, isEmpty);
      expect(await cacheServiceMobile.isCached(song), isFalse);

      // Reset pengaturan
      await box.put(KEY_CACHE_WIFI_ONLY, false);
    });

    test('cacheSkipReason returns WiFi message when toggle active + mobile, null when on WiFi', () async {
      final cacheDir = Directory('${tempDir.path}/wifi_reason_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_CACHE_WIFI_ONLY, true);

      final mobileConnectivity = MockConnectivity([ConnectivityResult.mobile]);
      final cacheServiceMobile = CacheServiceImpl(
        cacheDirectory: cacheDir,
        connectivity: mobileConnectivity,
      );

      final wifiConnectivity = MockConnectivity([ConnectivityResult.wifi]);
      final cacheServiceWifi = CacheServiceImpl(
        cacheDirectory: cacheDir,
        connectivity: wifiConnectivity,
      );

      const normalSong = Song(
        videoId: 'normal_song_1',
        title: 'Normal Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      // On mobile + toggle on -> returns WiFi warning message
      final reasonMobile = await cacheServiceMobile.cacheSkipReason(normalSong);
      expect(
        reasonMobile,
        'Unduhan dilewati: aktifkan WiFi atau matikan "Cache hanya via WiFi" di Pengaturan.',
      );

      // On WiFi + toggle on -> returns null
      final reasonWifi = await cacheServiceWifi.cacheSkipReason(normalSong);
      expect(reasonWifi, isNull);

      await box.put(KEY_CACHE_WIFI_ONLY, false);
    });

    test('cacheSkipReason returns duration message when durationMs > 15 min (without needing connectivity)', () async {
      final cacheDir = Directory('${tempDir.path}/duration_reason_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      // Default constructor without connectivity mock (proves no connectivity needed)
      final cacheService = CacheServiceImpl(cacheDirectory: cacheDir);

      const longCompilation = Song(
        videoId: 'compilation_long_1',
        title: '79 Min Compilation',
        artist: 'Various',
        durationMs: 79 * 60 * 1000,
        thumbnailUrl: '',
      );

      final reason = await cacheService.cacheSkipReason(longCompilation);
      expect(reason, 'Kompilasi di atas 15 menit tidak bisa di-cache.');
    });

    test('cacheSkipReason returns null for normal song on WiFi', () async {
      final cacheDir = Directory('${tempDir.path}/normal_wifi_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_CACHE_WIFI_ONLY, true);

      final wifiConnectivity = MockConnectivity([ConnectivityResult.wifi]);
      final cacheService = CacheServiceImpl(
        cacheDirectory: cacheDir,
        connectivity: wifiConnectivity,
      );

      const normalSong = Song(
        videoId: 'normal_wifi_song',
        title: 'Normal Song',
        artist: 'Normal Artist',
        durationMs: 200000,
        thumbnailUrl: '',
      );

      final reason = await cacheService.cacheSkipReason(normalSong);
      expect(reason, isNull);

      await box.put(KEY_CACHE_WIFI_ONLY, false);
    });

    test('cacheSong returns File("") on both skip conditions (WiFi & duration)', () async {
      final cacheDir = Directory('${tempDir.path}/skip_empty_file_cache');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_CACHE_WIFI_ONLY, true);

      final mobileConnectivity = MockConnectivity([ConnectivityResult.mobile]);
      final cacheServiceMobile = CacheServiceImpl(
        cacheDirectory: cacheDir,
        connectivity: mobileConnectivity,
      );

      const normalSong = Song(
        videoId: 'skip_test_normal',
        title: 'Normal Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );
      const longSong = Song(
        videoId: 'skip_test_long',
        title: 'Long Compilation',
        artist: 'Artist',
        durationMs: 20 * 60 * 1000,
        thumbnailUrl: '',
      );

      // Condition 1: cellular connection when WiFi-only toggle is active
      final resMobile = await cacheServiceMobile.cacheSong(
        normalSong,
        Uri.parse('https://example.com/audio1.m4a'),
      );
      expect(resMobile.path, isEmpty);
      expect(await cacheServiceMobile.isCached(normalSong), isFalse);

      // Condition 2: song duration > 15 minutes
      final resLong = await cacheServiceMobile.cacheSong(
        longSong,
        Uri.parse('https://example.com/audio2.m4a'),
      );
      expect(resLong.path, isEmpty);
      expect(await cacheServiceMobile.isCached(longSong), isFalse);

      await box.put(KEY_CACHE_WIFI_ONLY, false);
    });

    test('recordDataUsage accumulates bytes and resets accurately', () async {
      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_DATA_USED_BYTES, 0);

      expect(box.get(KEY_DATA_USED_BYTES), 0);

      // Catat streaming: 5 MB
      recordDataUsage(5 * 1024 * 1024);
      expect(box.get(KEY_DATA_USED_BYTES), 5 * 1024 * 1024);

      // Catat unduhan cache: 3 MB
      recordDataUsage(3 * 1024 * 1024);
      expect(box.get(KEY_DATA_USED_BYTES), 8 * 1024 * 1024);

      // Reset ke 0
      await box.put(KEY_DATA_USED_BYTES, 0);
      expect(box.get(KEY_DATA_USED_BYTES), 0);
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
