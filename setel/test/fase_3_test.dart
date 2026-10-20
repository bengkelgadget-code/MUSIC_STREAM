import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:setel/core/constants.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/library_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_fase3_test_');
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
    await Hive.openBox<int>(BOX_PLAY_COUNTS);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Fase 3 - Library Lokal Tests', () {
    final service = LibraryServiceImpl();

    final song1 = const Song(
      videoId: 'v1',
      title: 'Lagu 1',
      artist: 'Artis 1',
      durationMs: 180000,
      thumbnailUrl: '',
    );
    final song2 = const Song(
      videoId: 'v2',
      title: 'Lagu 2',
      artist: 'Artis 2',
      durationMs: 200000,
      thumbnailUrl: '',
    );
    final song3 = const Song(
      videoId: 'v3',
      title: 'Lagu 3',
      artist: 'Artis 3',
      durationMs: 220000,
      thumbnailUrl: '',
    );

    test('Playlist CRUD and adding/removing songs', () async {
      final playlist = await service.createPlaylist('Favorit Senja');
      expect(playlist.name, 'Favorit Senja');
      expect(playlist.songIds, isEmpty);

      await service.addToPlaylist(playlist.id, song1);
      await service.addToPlaylist(playlist.id, song2);

      var songs = await service.getSongsForPlaylist(playlist.id);
      expect(songs.length, 2);
      expect(songs.map((s) => s.videoId), containsAll(['v1', 'v2']));

      await service.removeFromPlaylist(playlist.id, 'v1');
      songs = await service.getSongsForPlaylist(playlist.id);
      expect(songs.length, 1);
      expect(songs.first.videoId, 'v2');

      await service.renamePlaylist(playlist.id, 'Senja Sore');
      final playlists = await service.getPlaylists();
      expect(playlists.firstWhere((p) => p.id == playlist.id).name,
          'Senja Sore');
    });

    test('Favorite toggling and retrieval', () async {
      expect(await service.isFavorite(song1.videoId), isFalse);

      await service.toggleFavorite(song1);
      expect(await service.isFavorite(song1.videoId), isTrue);

      final favorites = await service.getFavorites();
      expect(favorites.any((s) => s.videoId == song1.videoId), isTrue);

      await service.toggleFavorite(song1);
      expect(await service.isFavorite(song1.videoId), isFalse);
    });

    test('History FIFO max 50 entries', () async {
      // Rekam 55 lagu
      for (int i = 1; i <= 55; i++) {
        final s = Song(
          videoId: 'vid_$i',
          title: 'Lagu $i',
          artist: 'Artis',
          durationMs: 100000,
          thumbnailUrl: '',
        );
        await service.recordPlay(s);
      }

      final history = await service.getHistory();
      expect(history.length, 50,
          reason: 'History harus dibatasi maks. 50 entri secara FIFO');
      expect(history.first.videoId, 'vid_55',
          reason: 'Entri paling baru harus di posisi pertama');
      expect(history.last.videoId, 'vid_6',
          reason: 'Entri vid_1 s.d. vid_5 sudah terbuang');
    });

    test('AC Fase 3: buat playlist -> tambah 3 lagu -> restart app -> playlist utuh',
        () async {
      // 1. Buat playlist baru
      final newPl = await service.createPlaylist('Rock Klasik');

      // 2. Tambah 3 lagu
      await service.addToPlaylist(newPl.id, song1);
      await service.addToPlaylist(newPl.id, song2);
      await service.addToPlaylist(newPl.id, song3);

      var currentSongs = await service.getSongsForPlaylist(newPl.id);
      expect(currentSongs.length, 3);

      // 3. Simulasi restart app: tutup semua box Hive dan buka kembali
      final plBox = Hive.box<Playlist>(BOX_PLAYLISTS);
      final sBox = Hive.box<Song>(BOX_SONGS);
      await plBox.close();
      await sBox.close();

      await Hive.openBox<Song>(BOX_SONGS);
      await Hive.openBox<Playlist>(BOX_PLAYLISTS);

      // 4. Verifikasi setelah restart: playlist dan isinya tetap utuh
      final restartedService = LibraryServiceImpl();
      final restoredPlaylists = await restartedService.getPlaylists();
      final targetPlaylist =
          restoredPlaylists.firstWhere((p) => p.id == newPl.id);

      expect(targetPlaylist.name, 'Rock Klasik');
      expect(targetPlaylist.songIds.length, 3);

      final restoredSongs =
          await restartedService.getSongsForPlaylist(targetPlaylist.id);
      expect(restoredSongs.length, 3);
      expect(restoredSongs[0].title, 'Lagu 1');
      expect(restoredSongs[1].title, 'Lagu 2');
      expect(restoredSongs[2].title, 'Lagu 3');
    });
  });
}
