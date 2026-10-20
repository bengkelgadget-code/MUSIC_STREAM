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
