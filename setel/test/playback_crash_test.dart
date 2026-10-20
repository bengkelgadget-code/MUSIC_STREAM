import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:setel/core/constants.dart';
import 'package:setel/core/errors.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/search_cache.dart';
import 'package:setel/models/settings.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/audio_handler.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:setel/state/providers.dart';

class ThrottledYouTubeService implements YouTubeService {
  final Future<AudioStreamResult> resolveFuture;
  ThrottledYouTubeService(this.resolveFuture);

  @override
  Future<List<Song>> search(String query) async => [];

  @override
  Future<AudioStreamResult> resolveStreamUrl(String videoId,
          {int clientStartIndex = 0}) =>
      resolveFuture;

  @override
  Future<List<String>> getSuggestions(String query) async => [];

  @override
  Future<Song> fetchMetadata(String videoId) async => const Song(
        videoId: 'slow_net_1',
        title: 'Title',
        artist: 'Artist',
        durationMs: 0,
        thumbnailUrl: '',
      );
}

class FailingAudioPlayerService implements AudioPlayerService {
  final StreamController<PlayerState> _controller =
      StreamController<PlayerState>.broadcast();

  @override
  Stream<PlayerState> get playerState => _controller.stream;

  @override
  Future<void> playSong(Song song) async {
    throw AppException('Gagal memutar lagu: PlayerException((403) Forbidden)');
  }

  @override
  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    throw AppException('Gagal memutar lagu: PlayerException((403) Forbidden)');
  }

  @override
  Future<void> togglePlayPause() async {
    throw AppException('Gagal memutar lagu: SocketException: Failed host lookup');
  }

  @override
  Future<void> next() async {
    throw AppException('Gagal memutar lagu: TimeoutException');
  }

  @override
  Future<void> previous() async {
    throw AppException('Gagal memutar lagu: Generic playback failure');
  }

  @override
  Future<void> seek(Duration position) async {
    throw AppException('Gagal memutar lagu: Seek failed');
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {}

  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> addToQueueNext(Song song) async {
    throw AppException('Gagal memutar lagu: Queue insert failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_crash_test_');
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

  group('Playback Crash & Safe Error Handling Tests', () {
    test(
        'PlayerController menangkap AppException tanpa melempar unhandled future dan mengisi playbackError',
        () async {
      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider
              .overrideWithValue(FailingAudioPlayerService()),
        ],
      );

      final controller = container.read(playerControllerProvider.notifier);
      final testSong = Song(
        videoId: 'crash_test_1',
        title: 'Crash Test Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      // 1. playSong harus tidak throw unhandled exception
      await expectLater(
        controller.playSong(testSong),
        completes,
      );

      final stateAfterPlay = container.read(playerControllerProvider);
      expect(stateAfterPlay.playbackError, isNotNull);
      expect(
        stateAfterPlay.playbackError,
        contains('Akses stream YouTube dibatasi (403 Forbidden)'),
      );

      // 2. clearPlaybackError membersihkan error
      controller.clearPlaybackError();
      expect(container.read(playerControllerProvider).playbackError, isNull);

      // 3. togglePlayPause menangkap network error
      await expectLater(
        controller.togglePlayPause(),
        completes,
      );
      expect(
        container.read(playerControllerProvider).playbackError,
        contains('Periksa koneksi internet Anda'),
      );

      // 4. next menangkap timeout error
      controller.clearPlaybackError();
      await expectLater(
        controller.next(),
        completes,
      );
      expect(
        container.read(playerControllerProvider).playbackError,
        contains('Waktu koneksi habis'),
      );

      // 5. previous menangkap generic error
      controller.clearPlaybackError();
      await expectLater(
        controller.previous(),
        completes,
      );
      expect(
        container.read(playerControllerProvider).playbackError,
        contains('Terjadi kesalahan pemutaran'),
      );

      container.dispose();
    });

    test('runZonedGuarded menangkap unhandled error global', () async {
      Object? capturedError;
      runZonedGuarded(() {
        // Simulasi async exception di root zone
        Timer.run(() {
          throw Exception('Async uncaught error simulation');
        });
      }, (error, stack) {
        capturedError = error;
      });

      await Future.delayed(const Duration(milliseconds: 50));
      expect(capturedError, isNotNull);
      expect(capturedError.toString(), contains('Async uncaught error simulation'));
    });

    test(
        'SetelAudioHandler.updatePlaybackState memetakan ProcessingState just_audio 1:1 ke AudioProcessingState dan TIDAK menjadi idle saat loading',
        () {
      final handler = SetelAudioHandler();

      handler.updatePlaybackState(
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(seconds: 120),
        processingState: ja.ProcessingState.loading,
      );
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.loading);
      expect(handler.playbackState.value.playing, isTrue);

      handler.updatePlaybackState(
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(seconds: 120),
        processingState: ja.ProcessingState.buffering,
      );
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.buffering);

      handler.updatePlaybackState(
        isPlaying: true,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 120),
        processingState: ja.ProcessingState.ready,
      );
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.ready);

      handler.updatePlaybackState(
        isPlaying: false,
        position: const Duration(seconds: 120),
        duration: const Duration(seconds: 120),
        processingState: ja.ProcessingState.completed,
      );
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.completed);

      handler.updatePlaybackState(
        isPlaying: false,
        position: Duration.zero,
        duration: Duration.zero,
        processingState: ja.ProcessingState.idle,
      );
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
    });

    test(
        'Uji Regresi FGS: AudioPlayerServiceImpl memanggil updatePlaybackState loading seketika SEBELUM resolveStreamUrl saat jaringan lambat/throttled dan aman saat mode pesawat/error',
        () async {
      final handler = SetelAudioHandler();
      final completer = Completer<AudioStreamResult>();

      final throttledYt = ThrottledYouTubeService(completer.future);
      final playerService = AudioPlayerServiceImpl(
        youTubeService: throttledYt,
        audioHandler: handler,
      );

      const song = Song(
        videoId: 'slow_net_1',
        title: 'Slow Network Song',
        artist: 'Artist',
        durationMs: 200000,
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      // Mulai playSong (langkah resolveStreamUrl tertahan karena completer belum selesai)
      final playFuture = playerService.playSong(song);

      // Dalam mikrodetik pertama (< 1 detik, sebelum network selesai):
      // MediaItem & state loading HARUS sudah aktif di AudioHandler!
      expect(handler.mediaItem.value?.id, 'slow_net_1');
      expect(handler.mediaItem.value?.title, 'Slow Network Song');
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.loading);

      // Simulasi mode pesawat atau network gagal (misal airplane mode dinyalakan)
      completer.completeError(AppException('Network error / mode pesawat'));
      await expectLater(playFuture, throwsA(isA<AppException>()));

      // Setelah gagal, handler harus aman kembali ke idle (tidak menggantung di foreground / tidak ANR)
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
    });
  });
}
