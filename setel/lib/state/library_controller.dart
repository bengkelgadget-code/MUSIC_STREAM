import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/library_service.dart';
import 'providers.dart';

class LibraryState {
  final List<Playlist> playlists;
  final List<Song> favorites;
  final List<Song> historySongs;
  final Set<String> favoriteIds;
  final bool isLoading;

  const LibraryState({
    this.playlists = const [],
    this.favorites = const [],
    this.historySongs = const [],
    this.favoriteIds = const {},
    this.isLoading = false,
  });

  LibraryState copyWith({
    List<Playlist>? playlists,
    List<Song>? favorites,
    List<Song>? historySongs,
    Set<String>? favoriteIds,
    bool? isLoading,
  }) {
    return LibraryState(
      playlists: playlists ?? this.playlists,
      favorites: favorites ?? this.favorites,
      historySongs: historySongs ?? this.historySongs,
      favoriteIds: favoriteIds ?? this.favoriteIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LibraryController extends Notifier<LibraryState> {
  late final LibraryService _libraryService;

  @override
  LibraryState build() {
    _libraryService = ref.watch(libraryServiceProvider);
    Future.microtask(() => refresh());
    return const LibraryState(isLoading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final playlists = await _libraryService.getPlaylists();
    final favorites = await _libraryService.getFavorites();
    final historyEntries = await _libraryService.getHistory();

    final historySongs = <Song>[];
    final service = _libraryService;
    if (service is LibraryServiceImpl) {
      for (final entry in historyEntries) {
        final song = await service.getSongById(entry.videoId);
        if (song != null) {
          historySongs.add(song);
        }
      }
    }

    final favoriteIds = favorites.map((s) => s.videoId).toSet();

    state = state.copyWith(
      playlists: playlists,
      favorites: favorites,
      historySongs: historySongs,
      favoriteIds: favoriteIds,
      isLoading: false,
    );
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlist = await _libraryService.createPlaylist(name);
    await refresh();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    await _libraryService.renamePlaylist(id, name);
    await refresh();
  }

  Future<void> deletePlaylist(String id) async {
    await _libraryService.deletePlaylist(id);
    await refresh();
  }

  Future<void> addToPlaylist(String playlistId, Song song) async {
    await _libraryService.addToPlaylist(playlistId, song);
    await refresh();
  }

  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    await _libraryService.removeFromPlaylist(playlistId, videoId);
    await refresh();
  }

  Future<void> toggleFavorite(Song song) async {
    await _libraryService.toggleFavorite(song);
    await refresh();
  }

  bool isFavorite(String videoId) {
    return state.favoriteIds.contains(videoId);
  }

  Future<List<Song>> getSongsForPlaylist(String playlistId) async {
    final service = _libraryService;
    if (service is LibraryServiceImpl) {
      return service.getSongsForPlaylist(playlistId);
    }
    return [];
  }
}
