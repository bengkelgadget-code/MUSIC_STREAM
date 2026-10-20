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
    await historyBox.add(
      HistoryEntry(
        videoId: song.videoId,
        playedAt: DateTime.now(),
      ),
    );

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
