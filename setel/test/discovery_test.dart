import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/core/discovery_categories.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/models/song_chapter.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:setel/state/providers.dart';
import 'package:setel/ui/screens/home_search_screen.dart';

class DummyYouTubeService implements YouTubeService {
  @override
  Future<List<Song>> search(String query, {int limit = 25}) async => [];
  @override
  Future<AudioStreamResult> resolveStreamUrl(String videoId,
          {int clientStartIndex = 0}) async =>
      AudioStreamResult(
          url: Uri.parse('https://example.com/audio.m4a'), headers: {});
  @override
  Future<List<String>> getSuggestions(String query) async => [];
  @override
  Future<List<SongChapter>> getChapters(String videoId) async => [];
  @override
  Future<List<Song>> getRelatedSongs(String videoId, {int limit = 20}) async =>
      [];
  @override
  Future<Song> fetchMetadata(String videoId) async => const Song(
        videoId: 's1',
        title: 'Title',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );
}

class DummyAudioPlayerService implements AudioPlayerService {
  @override
  Stream<PlayerState> get playerState => const Stream<PlayerState>.empty();

  @override
  Future<void> addToQueueNext(Song song) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> playQueue(List<Song> songs,
      {int startIndex = 0, Duration? initialPosition}) async {}

  @override
  Future<void> playSong(Song song,
      {Duration? initialPosition, bool autoMix = false}) async {}

  @override
  void saveCurrentPosition({bool resetToZero = false}) {}

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
    tempDir = await Directory.systemTemp.createTemp('setel_discovery_test_');
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
    await Hive.openBox(BOX_SETTINGS);
    await Hive.openBox<int>(BOX_PLAY_COUNTS);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Fase 5 - Discovery UX Tests', () {
    testWidgets(
        'HomeSearchScreen menampilkan 2 section discovery saat search kosong',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerServiceProvider
                .overrideWithValue(DummyAudioPlayerService()),
            youtubeServiceProvider
                .overrideWithValue(DummyYouTubeService()),
          ],
          child: const MaterialApp(
            home: HomeSearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifikasi kedua header discovery tampil di halaman utama
      expect(find.text('Playlist Indo Terbaik 🇮🇩'), findsOneWidget);
      expect(find.text('Playlist Manca Terbaik 🌍'), findsOneWidget);

      // Verifikasi kartu kategori tampil
      expect(find.text('Top Hits Indonesia'), findsOneWidget);
      expect(find.text('Top Hits Global'), findsOneWidget);
    });

    test('DiscoveryCategory data model memiliki query dan gradien lengkap', () {
      expect(indoCategories.length, greaterThanOrEqualTo(8));
      expect(mancaCategories.length, greaterThanOrEqualTo(8));

      for (final cat in [...indoCategories, ...mancaCategories]) {
        expect(cat.id.isNotEmpty, isTrue);
        expect(cat.title.isNotEmpty, isTrue);
        expect(cat.searchQuery.isNotEmpty, isTrue);
        expect(cat.gradientColors.length, 2);
      }
    });
  });
}
