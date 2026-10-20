import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../core/constants.dart';
import '../models/settings.dart';
import '../services/audio_handler.dart';
import '../services/audio_player_service.dart';
import '../services/cache_service.dart';
import '../services/library_service.dart';
import '../services/youtube_service.dart';
import 'library_controller.dart';
import 'player_controller.dart';
import 'search_controller.dart';

export 'library_controller.dart';
export 'player_controller.dart';
export 'search_controller.dart';

// Services
final youtubeServiceProvider = Provider<YouTubeService>((ref) {
  return YouTubeServiceImpl();
});

final libraryServiceProvider = Provider<LibraryService>((ref) {
  return LibraryServiceImpl();
});

final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheServiceImpl();
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final ytService = ref.watch(youtubeServiceProvider);
  final libService = ref.watch(libraryServiceProvider);
  final cacheService = ref.watch(cacheServiceProvider);
  final handler = globalAudioHandler;
  final service = AudioPlayerServiceImpl(
    youTubeService: ytService,
    audioHandler: handler,
    libraryService: libService,
    cacheService: cacheService,
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
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
  int build() {
    final box = Hive.box<Settings>(BOX_SETTINGS);
    final settings = box.get(0);
    return settings?.cacheLimitMB ?? DEFAULT_CACHE_LIMIT_MB;
  }

  Future<void> setCacheLimit(int limitMB) async {
    state = limitMB;
    final box = Hive.box<Settings>(BOX_SETTINGS);
    await box.put(0, Settings(cacheLimitMB: limitMB));

    final cacheService = ref.read(cacheServiceProvider);
    await cacheService.enforceLimit();
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, int>(
  SettingsController.new,
);
