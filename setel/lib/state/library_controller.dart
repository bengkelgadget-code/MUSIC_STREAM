import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/history_entry.dart';
import '../models/playlist.dart';
import '../models/song.dart';

class LibraryState {
  final List<Playlist> playlists;
  final List<Song> favorites;
  final List<HistoryEntry> history;
  final bool isLoading;

  const LibraryState({
    this.playlists = const [],
    this.favorites = const [],
    this.history = const [],
    this.isLoading = false,
  });

  LibraryState copyWith({
    List<Playlist>? playlists,
    List<Song>? favorites,
    List<HistoryEntry>? history,
    bool? isLoading,
  }) {
    return LibraryState(
      playlists: playlists ?? this.playlists,
      favorites: favorites ?? this.favorites,
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LibraryController extends Notifier<LibraryState> {
  @override
  LibraryState build() => const LibraryState();

  Future<void> refresh() async {}
}
