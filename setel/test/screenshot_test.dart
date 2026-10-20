import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:setel/app.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/state/providers.dart';

class DummyAudioPlayerService implements AudioPlayerService {
  @override
  Stream<PlayerState> get playerState => const Stream<PlayerState>.empty();
  @override
  Future<void> addToQueueNext(Song song) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {}
  @override
  Future<void> playSong(Song song) async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setRepeatMode(RepeatMode mode) async {}
  @override
  Future<void> setShuffle(bool enabled) async {}
  @override
  Future<void> togglePlayPause() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Setel',
      packageName: 'com.bengkelgadget.setel',
      version: '1.1.1',
      buildNumber: '3',
      buildSignature: '',
    );
    tempDir = await Directory.systemTemp.createTemp('setel_screenshot_test_');
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
    await Hive.openBox<Playlist>(BOX_PLAYLISTS);
    await Hive.openBox<String>(BOX_FAVORITES);
    await Hive.openBox<HistoryEntry>(BOX_HISTORY);
    await Hive.openBox<SearchCache>(BOX_SEARCH_CACHE);
    await Hive.openBox<Settings>(BOX_SETTINGS);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Capture Homescreen Screenshot', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;

    await tester.runAsync(() async {
      try {
        final robotoLoader = FontLoader('Roboto');
        final robotoFile = File('C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf');
        if (robotoFile.existsSync()) {
          final bytes = await robotoFile.readAsBytes();
          robotoLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
          await robotoLoader.load();
        }

        final iconLoader = FontLoader('MaterialIcons');
        final iconFile = File('C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
        if (iconFile.existsSync()) {
          final bytes = await iconFile.readAsBytes();
          iconLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
          await iconLoader.load();
        }
      } catch (e) {
        debugPrint('Font load error: $e');
      }
    });

    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioPlayerServiceProvider
              .overrideWithValue(DummyAudioPlayerService()),
        ],
        child: RepaintBoundary(
          key: boundaryKey,
          child: const SetelApp(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      final screenshotFile = File('../homescreen.png');
      await screenshotFile.writeAsBytes(byteData!.buffer.asUint8List());
      debugPrint('Screenshot saved to: ${screenshotFile.absolute.path}');
    });

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
