import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/library_service.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_features_test_');
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

  group('Fitur 1 - Search Autocomplete Tests', () {
    test('getSuggestions parses Firefox JSON response correctly and caps at 8',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final mockJson =
                '["tulus", ["tulus hati-hati di jalan", "tulus monokrom", "tulus diri", "tulus labirin", "tulus pamit", "tulus sepatu", "tulus gajah", "tulus sewindu", "tulus satu kali", "tulus teman hidup"]]';
            return handler.resolve(
              Response(
                requestOptions: options,
                data: mockJson,
                statusCode: 200,
              ),
            );
          },
        ),
      );

      final ytService = YouTubeServiceImpl(dio: dio);
      final suggestions = await ytService.getSuggestions('tulus');

      expect(suggestions.length, 8);
      expect(suggestions.first, 'tulus hati-hati di jalan');
      expect(suggestions[1], 'tulus monokrom');
    });

    test('getSuggestions returns empty list on network error without throwing',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'No internet connection',
              ),
            );
          },
        ),
      );

      final ytService = YouTubeServiceImpl(dio: dio);
      final suggestions = await ytService.getSuggestions('error test');

      expect(suggestions, isEmpty);
    });

    test('getSuggestions returns empty list on blank query', () async {
      final ytService = YouTubeServiceImpl();
      expect(await ytService.getSuggestions(''), isEmpty);
      expect(await ytService.getSuggestions('   '), isEmpty);
    });
  });

  group('Fitur 2 - Filter Kompilasi & ISO 8601 Duration Tests', () {
    test('parseIso8601Duration converts various formats to milliseconds', () {
      expect(parseIso8601Duration('PT4M13S'), 253000);
      expect(parseIso8601Duration('PT1H2M3S'), 3723000);
      expect(parseIso8601Duration('PT45S'), 45000);
      expect(parseIso8601Duration('PT10M'), 600000);
      expect(parseIso8601Duration(''), 0);
    });

    test('Compilation filter excludes >10 mins and banned keywords', () {
      const bannedKeywords = [
        'full album',
        'kompilasi',
        'nonstop',
        '1 jam',
        '2 jam',
        '3 jam',
        '24 jam',
      ];

      final testSongs = [
        const Song(
          videoId: 's1',
          title: 'Tulus - Hati-Hati di Jalan',
          artist: 'Tulus',
          durationMs: 242000, // 4 menit 2 detik
          thumbnailUrl: '',
        ),
        const Song(
          videoId: 's2',
          title: 'Lagu Indo Pop Terbaik 2024 Full Album',
          artist: 'Channel Musik',
          durationMs: 3600000, // 1 jam
          thumbnailUrl: '',
        ),
        const Song(
          videoId: 's3',
          title: 'Kompilasi Lagu Galau Indonesia',
          artist: 'Mix Musik',
          durationMs: 300000, // 5 menit tapi judul kompilasi
          thumbnailUrl: '',
        ),
        const Song(
          videoId: 's4',
          title: 'Sheila On 7 - Dan',
          artist: 'Sheila On 7',
          durationMs: 0, // durasi tak diketahui -> tetap disimpan
          thumbnailUrl: '',
        ),
        const Song(
          videoId: 's5',
          title: 'Lagu Santai 1 Jam Nonstop',
          artist: 'Relaxation',
          durationMs: 4000000,
          thumbnailUrl: '',
        ),
      ];

      final filtered = testSongs.where((song) {
        if (song.durationMs > 0 && song.durationMs > 600000) {
          return false;
        }
        final titleLower = song.title.toLowerCase();
        for (final kw in bannedKeywords) {
          if (titleLower.contains(kw)) {
            return false;
          }
        }
        return true;
      }).toList();

      expect(filtered.length, 2);
      expect(filtered.map((s) => s.videoId), containsAll(['s1', 's4']));
    });
  });

  group('Fitur 3 - Pengaturan Katalog & Format Stream Tests', () {
    test('Settings box persists catalog_mode and stream_format', () async {
      final box = Hive.box(BOX_SETTINGS);

      // Default values
      expect(box.get('catalog_mode', defaultValue: 'Otomatis'), 'Otomatis');
      expect(box.get('stream_format', defaultValue: 'Tertinggi'), 'Tertinggi');

      // Change values
      await box.put('catalog_mode', 'Explode');
      await box.put('stream_format', 'Hemat Data');

      expect(box.get('catalog_mode'), 'Explode');
      expect(box.get('stream_format'), 'Hemat Data');

      // Revert to default
      await box.put('catalog_mode', 'Otomatis');
      await box.put('stream_format', 'Tertinggi');
    });
  });

  group('Fitur 4 - Play Counts & Most Played Tests', () {
    test('recordPlay increments play count and getMostPlayed sorts descending',
        () async {
      final libService = LibraryServiceImpl();
      final songsBox = Hive.box<Song>(BOX_SONGS);
      final playCountsBox = Hive.box<int>(BOX_PLAY_COUNTS);

      await playCountsBox.clear();

      final songA = const Song(
        videoId: 'song_a',
        title: 'Song Alpha',
        artist: 'Artist A',
        durationMs: 180000,
        thumbnailUrl: '',
      );
      final songB = const Song(
        videoId: 'song_b',
        title: 'Song Beta',
        artist: 'Artist B',
        durationMs: 200000,
        thumbnailUrl: '',
      );
      final songC = const Song(
        videoId: 'song_c',
        title: 'Song Gamma',
        artist: 'Artist C',
        durationMs: 210000,
        thumbnailUrl: '',
      );

      await songsBox.put(songA.videoId, songA);
      await songsBox.put(songB.videoId, songB);
      await songsBox.put(songC.videoId, songC);

      // Play song A 3 times
      await libService.recordPlay(songA);
      await libService.recordPlay(songA);
      await libService.recordPlay(songA);

      // Play song B 1 time
      await libService.recordPlay(songB);

      // Play song C 5 times
      await libService.recordPlay(songC);
      await libService.recordPlay(songC);
      await libService.recordPlay(songC);
      await libService.recordPlay(songC);
      await libService.recordPlay(songC);

      expect(await libService.getPlayCount('song_a'), 3);
      expect(await libService.getPlayCount('song_b'), 1);
      expect(await libService.getPlayCount('song_c'), 5);

      final mostPlayed = await libService.getMostPlayed(limit: 10);
      expect(mostPlayed.length, 3);
      expect(mostPlayed[0].videoId, 'song_c'); // 5x
      expect(mostPlayed[1].videoId, 'song_a'); // 3x
      expect(mostPlayed[2].videoId, 'song_b'); // 1x
    });
  });
}
