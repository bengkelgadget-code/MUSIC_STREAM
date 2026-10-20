import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_service.dart';
import '../services/youtube_service.dart';
import 'library_controller.dart';
import 'player_controller.dart';
import 'search_controller.dart';

// Services
final youtubeServiceProvider = Provider<YouTubeService>((ref) {
  throw UnimplementedError('YouTubeService not initialized yet');
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  throw UnimplementedError('AudioPlayerService not initialized yet');
});

final libraryServiceProvider = Provider<LibraryService>((ref) {
  throw UnimplementedError('LibraryService not initialized yet');
});

final cacheServiceProvider = Provider<CacheService>((ref) {
  throw UnimplementedError('CacheService not initialized yet');
});

// Controllers
final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerControllerState>(
  PlayerController.new,
);

final searchControllerProvider =
    NotifierProvider<SearchControllerNotifier, SearchState>(
  SearchControllerNotifier.new,
);

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

class SettingsController extends Notifier<int> {
  @override
  int build() => 500;

  void setCacheLimit(int limitMB) {
    state = limitMB;
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, int>(
  SettingsController.new,
);
