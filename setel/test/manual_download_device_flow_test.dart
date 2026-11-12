import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/cache_service.dart';

class MockConnectivity implements Connectivity {
  final List<ConnectivityResult> results;
  MockConnectivity(this.results);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value(results);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('manual_download_flow_test_');
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

  group('Uji Alur Device Skenario 1 - 4:', () {
    const normalSong = Song(
      videoId: 'sample_normal_song',
      title: 'Normal Song 3m',
      artist: 'Artist',
      durationMs: 180000,
      thumbnailUrl: '',
    );

    const longCompilation = Song(
      videoId: 'sample_compilation_79m',
      title: 'Kompilasi Lagu Terbaik',
      artist: 'Various Artists',
      durationMs: 79 * 60 * 1000,
      thumbnailUrl: '',
    );

    test('Skenario 1: Toggle WiFi-only AKTIF + Seluler -> muncul pesan dilewati, TIDAK berhasil, TIDAK masuk cache', () async {
      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_CACHE_WIFI_ONLY, true);

      final mobileCache = CacheServiceImpl(
        cacheDirectory: Directory('${tempDir.path}/s1'),
        connectivity: MockConnectivity([ConnectivityResult.mobile]),
      );

      // Cek skip reason sebelum resolve
      final reason = await mobileCache.cacheSkipReason(normalSong);
      expect(reason, isNotNull);
      expect(
        reason,
        'Unduhan dilewati: aktifkan WiFi atau matikan "Cache hanya via WiFi" di Pengaturan.',
      );

      // Lagu tidak boleh masuk cache
      expect(await mobileCache.isCached(normalSong), isFalse);
    });

    test('Skenario 2: WiFi nyala -> skip reason null, unduhan berhasil & terverifikasi di cache offline', () async {
      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_CACHE_WIFI_ONLY, true);

      final wifiCache = CacheServiceImpl(
        cacheDirectory: Directory('${tempDir.path}/s2'),
        connectivity: MockConnectivity([ConnectivityResult.wifi]),
      );

      // Cek skip reason sebelum resolve
      final reason = await wifiCache.cacheSkipReason(normalSong);
      expect(reason, isNull);

      // Simulasi file terunduh
      final cacheDir = Directory('${tempDir.path}/s2');
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      final cachedFile = File('${cacheDir.path}/${normalSong.videoId}.m4a');
      await cachedFile.writeAsBytes([1, 2, 3, 4]);

      // Verifikasi file ada untuk pemutaran offline (mode pesawat)
      expect(await wifiCache.isCached(normalSong), isTrue);
      final offlineFile = await wifiCache.getCached(normalSong);
      expect(offlineFile, isNotNull);
      expect(offlineFile!.existsSync(), isTrue);
    });

    test('Skenario 3: Kompilasi >15 menit (di WiFi) -> muncul pesan kompilasi tidak bisa di-cache', () async {
      final wifiCache = CacheServiceImpl(
        cacheDirectory: Directory('${tempDir.path}/s3'),
        connectivity: MockConnectivity([ConnectivityResult.wifi]),
      );

      final reason = await wifiCache.cacheSkipReason(longCompilation);
      expect(reason, 'Kompilasi di atas 15 menit tidak bisa di-cache.');
      expect(await wifiCache.isCached(longCompilation), isFalse);
    });

    test('Skenario 4: Toggle WiFi-only MATI + Seluler -> skip reason null (berhasil normal tanpa dilewati)', () async {
      final box = Hive.box(BOX_SETTINGS);
      await box.put(KEY_CACHE_WIFI_ONLY, false);

      final mobileCache = CacheServiceImpl(
        cacheDirectory: Directory('${tempDir.path}/s4'),
        connectivity: MockConnectivity([ConnectivityResult.mobile]),
      );

      // Dengan toggle mati, data seluler diizinkan
      final reason = await mobileCache.cacheSkipReason(normalSong);
      expect(reason, isNull);
    });
  });
}
