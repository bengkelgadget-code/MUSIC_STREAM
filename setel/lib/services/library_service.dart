import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../models/history_entry.dart';
import '../models/playlist.dart';
import '../models/song.dart';

abstract class LibraryService {
  Future<Playlist> createPlaylist(String name);
  Future<void> renamePlaylist(String id, String name);
  Future<void> deletePlaylist(String id);
  Future<List<Playlist>> getPlaylists();
  Future<void> addToPlaylist(String playlistId, Song song);
  Future<void> removeFromPlaylist(String playlistId, String videoId);

  Future<void> toggleFavorite(Song song);
  Future<bool> isFavorite(String videoId);
  Future<List<Song>> getFavorites();

  /// FIFO, maks 50 entri. Yang lama dibuang otomatis.
  Future<void> recordPlay(Song song);
  Future<List<HistoryEntry>> getHistory();

  /// Ambil lagu yang paling sering diputar terurut menurun berdasarkan play count
  Future<List<Song>> getMostPlayed({int limit = 10});

  /// Ambil jumlah putar untuk sebuah lagu
  Future<int> getPlayCount(String videoId);

  /// Simpan & ambil menit/posisi terakhir pemutaran lagu (dalam milidetik)
  Future<void> savePlaybackPosition(String videoId, int positionMs);
  Future<int> getPlaybackPosition(String videoId);
}

class LibraryServiceImpl implements LibraryService {
  final Uuid _uuid = const Uuid();

  @override
  Future<Playlist> createPlaylist(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw AppException('Nama playlist tidak boleh kosong.');
    }

    final box = Hive.box<Playlist>(BOX_PLAYLISTS);
    final playlist = Playlist(
      id: _uuid.v4(),
      name: cleanName,
      createdAt: DateTime.now(),
      songIds: const [],
    );

    await box.put(playlist.id, playlist);
    return playlist;
  }

  @override
  Future<void> renamePlaylist(String id, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw AppException('Nama playlist tidak boleh kosong.');
    }

    final box = Hive.box<Playlist>(BOX_PLAYLISTS);
    final existing = box.get(id);
    if (existing == null) {
      throw AppException('Playlist tidak ditemukan.');
    }

    final updated = existing.copyWith(name: cleanName);
    await box.put(id, updated);
  }

  @override
  Future<void> deletePlaylist(String id) async {
    final box = Hive.box<Playlist>(BOX_PLAYLISTS);
    await box.delete(id);
  }

  @override
  Future<List<Playlist>> getPlaylists() async {
    final box = Hive.box<Playlist>(BOX_PLAYLISTS);
    final list = box.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> addToPlaylist(String playlistId, Song song) async {
    final playlistBox = Hive.box<Playlist>(BOX_PLAYLISTS);
    final songsBox = Hive.box<Song>(BOX_SONGS);

    final playlist = playlistBox.get(playlistId);
    if (playlist == null) {
      throw AppException('Playlist tidak ditemukan.');
    }

    // Pastikan metadata lagu tersimpan di songsBox (tanpa streamUrl)
    await songsBox.put(song.videoId, song);

    if (!playlist.songIds.contains(song.videoId)) {
      final updatedSongIds = [...playlist.songIds, song.videoId];
      await playlistBox.put(
        playlistId,
        playlist.copyWith(songIds: updatedSongIds),
      );
    }
  }

  @override
  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    final playlistBox = Hive.box<Playlist>(BOX_PLAYLISTS);
    final playlist = playlistBox.get(playlistId);
    if (playlist == null) return;

    final updatedSongIds =
        playlist.songIds.where((id) => id != videoId).toList();
    await playlistBox.put(
      playlistId,
      playlist.copyWith(songIds: updatedSongIds),
    );
  }

  @override
  Future<void> toggleFavorite(Song song) async {
    final favBox = Hive.box<String>(BOX_FAVORITES);
    final songsBox = Hive.box<Song>(BOX_SONGS);

    if (favBox.containsKey(song.videoId)) {
      await favBox.delete(song.videoId);
    } else {
      await songsBox.put(song.videoId, song);
      await favBox.put(song.videoId, song.videoId);
    }
  }

  @override
  Future<bool> isFavorite(String videoId) async {
    final favBox = Hive.box<String>(BOX_FAVORITES);
    return favBox.containsKey(videoId);
  }

  @override
  Future<List<Song>> getFavorites() async {
    final favBox = Hive.box<String>(BOX_FAVORITES);
    final songsBox = Hive.box<Song>(BOX_SONGS);

    final favorites = <Song>[];
    for (final key in favBox.keys) {
      final song = songsBox.get(key);
      if (song != null) {
        favorites.add(song);
      }
    }
    return favorites;
  }

  @override
  Future<void> recordPlay(Song song) async {
    final songsBox = Hive.box<Song>(BOX_SONGS);
    await songsBox.put(song.videoId, song);

    final historyBox = Hive.box<HistoryEntry>(BOX_HISTORY);
    final posBox = Hive.isBoxOpen(BOX_PLAYBACK_POSITIONS)
        ? Hive.box<int>(BOX_PLAYBACK_POSITIONS)
        : await Hive.openBox<int>(BOX_PLAYBACK_POSITIONS);
    final lastPos = posBox.get(song.videoId) ?? 0;

    await historyBox.add(
      HistoryEntry(
        videoId: song.videoId,
        playedAt: DateTime.now(),
        lastPositionMs: lastPos,
      ),
    );

    // Tambah play count (+1)
    final playCountsBox = Hive.isBoxOpen(BOX_PLAY_COUNTS)
        ? Hive.box<int>(BOX_PLAY_COUNTS)
        : await Hive.openBox<int>(BOX_PLAY_COUNTS);
    final count = playCountsBox.get(song.videoId) ?? 0;
    await playCountsBox.put(song.videoId, count + 1);

    // FIFO maks 50 entri sesuai kontrak §4.3
    while (historyBox.length > MAX_HISTORY_ENTRIES) {
      await historyBox.deleteAt(0);
    }
  }

  @override
  Future<List<HistoryEntry>> getHistory() async {
    final historyBox = Hive.box<HistoryEntry>(BOX_HISTORY);
    // Kembalikan dari yang paling baru dimainkan (reverse FIFO)
    return historyBox.values.toList().reversed.toList();
  }

  @override
  Future<List<Song>> getMostPlayed({int limit = 10}) async {
    final playCountsBox = Hive.isBoxOpen(BOX_PLAY_COUNTS)
        ? Hive.box<int>(BOX_PLAY_COUNTS)
        : await Hive.openBox<int>(BOX_PLAY_COUNTS);
    final songsBox = Hive.box<Song>(BOX_SONGS);

    // Migrasi sekali jalan: jika play_counts kosong dan history ada data, isi play_counts
    if (playCountsBox.isEmpty && Hive.isBoxOpen(BOX_HISTORY)) {
      final historyBox = Hive.box<HistoryEntry>(BOX_HISTORY);
      if (historyBox.isNotEmpty) {
        final counts = <String, int>{};
        for (final entry in historyBox.values) {
          counts[entry.videoId] = (counts[entry.videoId] ?? 0) + 1;
        }
        for (final entry in counts.entries) {
          await playCountsBox.put(entry.key, entry.value);
        }
      }
    }

    if (playCountsBox.isEmpty) return [];

    final entries = playCountsBox.toMap().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final result = <Song>[];
    for (final entry in entries) {
      final song = songsBox.get(entry.key.toString());
      if (song != null) {
        result.add(song);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  @override
  Future<int> getPlayCount(String videoId) async {
    if (!Hive.isBoxOpen(BOX_PLAY_COUNTS)) return 0;
    final playCountsBox = Hive.box<int>(BOX_PLAY_COUNTS);
    return playCountsBox.get(videoId) ?? 0;
  }

  @override
  Future<void> savePlaybackPosition(String videoId, int positionMs) async {
    if (videoId.isEmpty) return;
    final posBox = Hive.isBoxOpen(BOX_PLAYBACK_POSITIONS)
        ? Hive.box<int>(BOX_PLAYBACK_POSITIONS)
        : await Hive.openBox<int>(BOX_PLAYBACK_POSITIONS);
    await posBox.put(videoId, positionMs);

    if (Hive.isBoxOpen(BOX_HISTORY)) {
      final historyBox = Hive.box<HistoryEntry>(BOX_HISTORY);
      for (int i = historyBox.length - 1; i >= 0; i--) {
        final entry = historyBox.getAt(i);
        if (entry != null && entry.videoId == videoId) {
          await historyBox.putAt(
            i,
            entry.copyWith(lastPositionMs: positionMs),
          );
          break;
        }
      }
    }
  }

  @override
  Future<int> getPlaybackPosition(String videoId) async {
    if (videoId.isEmpty) return 0;
    final posBox = Hive.isBoxOpen(BOX_PLAYBACK_POSITIONS)
        ? Hive.box<int>(BOX_PLAYBACK_POSITIONS)
        : await Hive.openBox<int>(BOX_PLAYBACK_POSITIONS);
    return posBox.get(videoId) ?? 0;
  }

  Future<List<Song>> getSongsForPlaylist(String playlistId) async {
    final playlistBox = Hive.box<Playlist>(BOX_PLAYLISTS);
    final songsBox = Hive.box<Song>(BOX_SONGS);

    final playlist = playlistBox.get(playlistId);
    if (playlist == null) return [];

    final result = <Song>[];
    for (final id in playlist.songIds) {
      final song = songsBox.get(id);
      if (song != null) result.add(song);
    }
    return result;
  }

  Future<Song?> getSongById(String videoId) async {
    final songsBox = Hive.box<Song>(BOX_SONGS);
    return songsBox.get(videoId);
  }
}
