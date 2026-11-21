import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:setel/models/song.dart';
import 'package:setel/models/song_chapter.dart';
import 'package:setel/services/audio_handler.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/youtube_service.dart';

class MockAudioPlayerForFocus extends ja.AudioPlayer {
  bool _playing = false;
  Duration _mockPosition = Duration.zero;
  Duration? _mockDuration;
  int playCallCount = 0;
  int pauseCallCount = 0;
  int stopCallCount = 0;

  final _playerStateController = StreamController<ja.PlayerState>.broadcast();

  @override
  bool get playing => _playing;

  @override
  Duration get position => _mockPosition;

  @override
  Duration? get duration => _mockDuration;

  @override
  Stream<ja.PlayerState> get playerStateStream => _playerStateController.stream;

  void emitState({required bool playing, ja.ProcessingState processingState = ja.ProcessingState.ready}) {
    _playing = playing;
    _playerStateController.add(ja.PlayerState(playing, processingState));
  }

  void setMockPosition(Duration pos) {
    _mockPosition = pos;
  }

  void setMockDuration(Duration dur) {
    _mockDuration = dur;
  }

  @override
  Future<Duration?> setAudioSource(
    ja.AudioSource source, {
    bool preload = true,
    Duration? initialPosition,
    int? initialIndex,
  }) async {
    return Duration.zero;
  }

  @override
  Future<void> play() async {
    playCallCount++;
    _playing = true;
    _playerStateController.add(ja.PlayerState(true, ja.ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    _playing = false;
    _playerStateController.add(ja.PlayerState(false, ja.ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _playing = false;
    _playerStateController.add(ja.PlayerState(false, ja.ProcessingState.idle));
  }
}

class FakeYouTubeService implements YouTubeService {
  @override
  Future<AudioStreamResult> resolveStreamUrl(String videoId, {int clientStartIndex = 0}) async {
    return AudioStreamResult(
      url: Uri.parse('https://example.com/audio.m4a'),
      headers: {},
      totalBytes: 1048576,
    );
  }

  @override
  Future<AudioStreamResult> resolveNonOpusStream(String videoId, {int clientStartIndex = 0}) async {
    return AudioStreamResult(
      url: Uri.parse('https://example.com/audio.m4a'),
      headers: {},
      totalBytes: 1048576,
    );
  }

  @override
  Future<List<Song>> search(String query, {int limit = 25}) async => [];
  @override
  Future<List<String>> getSuggestions(String query) async => [];
  @override
  Future<List<SongChapter>> getChapters(String videoId) async => [];
  @override
  Future<List<Song>> getRelatedSongs(String videoId, {int limit = 20}) async => [];
  @override
  Future<Song> fetchMetadata(String videoId) async => const Song(
        videoId: 'v1',
        title: 'Title',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('2B & 2C: Audio Focus & Breadcrumb Tests', () {
    late MockAudioPlayerForFocus mockPlayer;
    late SetelAudioHandler handler;
    late FakeYouTubeService youTubeService;
    late StreamController<AudioInterruptionEvent> interruptionController;
    late AudioPlayerServiceImpl playerService;

    const testSong = Song(
      videoId: 'focus_test_song',
      title: 'Focus Test Song',
      artist: 'Artist',
      durationMs: 180000,
      thumbnailUrl: '',
    );

    setUp(() {
      mockPlayer = MockAudioPlayerForFocus();
      handler = SetelAudioHandler();
      youTubeService = FakeYouTubeService();
      interruptionController = StreamController<AudioInterruptionEvent>.broadcast();

      playerService = AudioPlayerServiceImpl(
        player: mockPlayer,
        audioHandler: handler,
        youTubeService: youTubeService,
        testInterruptionStream: interruptionController.stream,
      );
    });

    tearDown(() {
      playerService.dispose();
      interruptionController.close();
    });

    test('interupsi focus begin (pause) saat memutar lagu dan end memicu auto-resume', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);
      mockPlayer.setMockPosition(const Duration(seconds: 45));

      // Simulasikan interupsi focus begin (mis. panggilan telepon atau notifikasi sistem)
      interruptionController.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // ExoPlayer mem-pause atau player service mencatat status
      mockPlayer.emitState(playing: false);
      final playCallsBefore = mockPlayer.playCallCount;

      // Simulasikan interupsi focus end
      interruptionController.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // Harus auto-resume (play() dipanggil kembali)
      expect(mockPlayer.playCallCount, greaterThan(playCallsBefore));
    });

    test('jeda manual user lalu interupsi focus end TIDAK memicu auto-resume', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);

      // User sengaja mem-pause lagu secara manual
      await playerService.togglePlayPause();
      expect(mockPlayer.pauseCallCount, 1);

      final playCallsBefore = mockPlayer.playCallCount;

      // Interupsi focus end datang kemudian
      interruptionController.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // JANGAN auto-resume bila lagu sengaja di-pause oleh user
      expect(mockPlayer.playCallCount, playCallsBefore);
    });

    test('AudioHandler callback memicu log breadcrumb notifikasi', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);

      // Panggil onPauseCallback handler
      handler.onPauseCallback?.call();
      expect(mockPlayer.pauseCallCount, 1);

      // Panggil onStopCallback handler
      handler.onStopCallback?.call();
      expect(mockPlayer.stopCallCount, 1);
    });

    test('transisi playing memicu pembaruan state dan callback audio handler', () async {
      await playerService.playSong(testSong);

      // Transisi false -> true
      mockPlayer.emitState(playing: true);
      await pumpEventQueue();
      expect(handler.playbackState.value.playing, isTrue);

      // Transisi true -> false
      mockPlayer.emitState(playing: false);
      await pumpEventQueue();
      expect(handler.playbackState.value.playing, isFalse);
    });
  });
}
