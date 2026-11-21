import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:setel/models/song.dart';
import 'package:setel/models/song_chapter.dart';
import 'package:setel/services/audio_handler.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/youtube_audio_source.dart';
import 'package:setel/services/youtube_service.dart';

class MockAudioPlayerForSeekAndFocus implements ja.AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  bool _playing = false;
  Duration _mockPosition = Duration.zero;
  Duration? _mockDuration;
  int playCallCount = 0;
  int pauseCallCount = 0;
  int stopCallCount = 0;
  int seekCallCount = 0;
  int setAudioSourceCallCount = 0;

  Duration? lastSeekPosition;
  Duration? lastSetAudioSourceInitialPosition;

  Future<void> Function(Duration position)? onSeek;
  Future<void> Function()? onPlay;
  Future<Duration?> Function(ja.AudioSource source, {bool preload, Duration? initialPosition, int? initialIndex})? onSetAudioSource;

  final _playerStateController = StreamController<ja.PlayerState>.broadcast();
  final _playbackEventController = StreamController<ja.PlaybackEvent>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _processingStateController = StreamController<ja.ProcessingState>.broadcast();

  @override
  bool get playing => _playing;

  @override
  Duration get position => _mockPosition;

  @override
  Duration? get duration => _mockDuration;

  @override
  Stream<ja.PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<ja.PlaybackEvent> get playbackEventStream => _playbackEventController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<ja.ProcessingState> get processingStateStream => _processingStateController.stream;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  ja.ProcessingState get processingState => ja.ProcessingState.ready;

  @override
  int? get currentIndex => 0;

  @override
  List<ja.IndexedAudioSource> get sequence => [];

  @override
  List<int> get shuffleIndices => [];

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setLoopMode(ja.LoopMode loopMode) async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  void emitState({required bool playing, ja.ProcessingState processingState = ja.ProcessingState.ready}) {
    _playing = playing;
    _playerStateController.add(ja.PlayerState(playing, processingState));
  }

  void emitPlaybackError(Object error) {
    _playbackEventController.addError(error);
  }

  void setMockPosition(Duration pos) {
    _mockPosition = pos;
    _positionController.add(pos);
  }

  void setMockDuration(Duration dur) {
    _mockDuration = dur;
    _durationController.add(dur);
  }

  @override
  Future<Duration?> setAudioSource(
    ja.AudioSource source, {
    bool preload = true,
    Duration? initialPosition,
    int? initialIndex,
  }) async {
    setAudioSourceCallCount++;
    lastSetAudioSourceInitialPosition = initialPosition;
    if (onSetAudioSource != null) {
      return await onSetAudioSource!(source, preload: preload, initialPosition: initialPosition, initialIndex: initialIndex);
    }
    return Duration.zero;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCallCount++;
    lastSeekPosition = position;
    if (onSeek != null && position != null) {
      await onSeek!(position);
      return;
    }
    _mockPosition = position ?? Duration.zero;
  }

  @override
  Future<void> play() async {
    playCallCount++;
    if (onPlay != null) {
      await onPlay!();
      return;
    }
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
  Future<void> dispose() async {
    await _playerStateController.close();
    await _playbackEventController.close();
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _playing = false;
    _playerStateController.add(ja.PlayerState(false, ja.ProcessingState.idle));
  }
}

class FakeConfigurableYouTubeService implements YouTubeService {
  int resolveStreamUrlCallCount = 0;
  int resolveNonOpusStreamCallCount = 0;

  bool isOpusStream = false;
  Future<AudioStreamResult> Function(String videoId, {int clientStartIndex})? onResolveStreamUrl;
  Future<AudioStreamResult> Function(String videoId, {int clientStartIndex})? onResolveNonOpusStream;

  @override
  Future<AudioStreamResult> resolveStreamUrl(String videoId, {int clientStartIndex = 0}) async {
    resolveStreamUrlCallCount++;
    if (onResolveStreamUrl != null) {
      return await onResolveStreamUrl!(videoId, clientStartIndex: clientStartIndex);
    }
    return AudioStreamResult(
      url: Uri.parse('https://example.com/audio.m4a'),
      headers: {},
      totalBytes: 1048576,
      contentType: isOpusStream ? 'audio/webm' : 'audio/mp4',
      codec: isOpusStream ? 'opus' : 'mp4a',
    );
  }

  @override
  Future<AudioStreamResult> resolveNonOpusStream(String videoId, {int clientStartIndex = 0}) async {
    resolveNonOpusStreamCallCount++;
    if (onResolveNonOpusStream != null) {
      return await onResolveNonOpusStream!(videoId, clientStartIndex: clientStartIndex);
    }
    return AudioStreamResult(
      url: Uri.parse('https://example.com/audio_aac.m4a'),
      headers: {},
      totalBytes: 1048576,
      contentType: 'audio/mp4',
      codec: 'mp4a',
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

  group('v1.3.15 Seek & Focus Recovery Tests', () {
    late MockAudioPlayerForSeekAndFocus mockPlayer;
    late SetelAudioHandler handler;
    late FakeConfigurableYouTubeService youTubeService;
    late StreamController<AudioInterruptionEvent> interruptionController;
    late AudioPlayerServiceImpl playerService;

    const testSong = Song(
      videoId: 'test_song_v15',
      title: 'Test Song v1.3.15',
      artist: 'Artist',
      durationMs: 100000, // 100 seconds
      thumbnailUrl: '',
    );

    setUp(() {
      mockPlayer = MockAudioPlayerForSeekAndFocus();
      mockPlayer.setMockDuration(const Duration(seconds: 100));
      handler = SetelAudioHandler();
      youTubeService = FakeConfigurableYouTubeService();
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
      YouTubeAudioSource.resetLastChunkError();
    });

    // 1A: Seek gagal dengan stream Opus -> recovery mencoba non-Opus (verifikasi resolveNonOpusStream dipanggil)
    test('1A: Seek gagal pada stream Opus mencoba fallback resolveNonOpusStream', () async {
      youTubeService.isOpusStream = true;
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);
      mockPlayer.setMockPosition(const Duration(seconds: 10));

      // Simulasi seek gagal pada player
      mockPlayer.onSeek = (pos) async {
        throw PlatformException(code: '0', message: 'Source error during seek');
      };

      // Mock setAudioSource pada recovery attempt 1 (resolveStreamUrl) gagal
      int setSourceCount = 0;
      mockPlayer.onSetAudioSource = (source, {preload = true, initialPosition, initialIndex}) async {
        setSourceCount++;
        if (setSourceCount == 1) {
          // Attempt 1 gagal
          throw PlatformException(code: '0', message: 'Opus source failed');
        }
        // Attempt 2 (non-Opus) sukses
        return Duration.zero;
      };

      await playerService.seek(const Duration(seconds: 50));

      // Verifikasi bahwa resolveNonOpusStream dipanggil untuk fallback
      expect(youTubeService.resolveNonOpusStreamCallCount, 1);
      expect(playerService.playbackError, isNull);
    });

    // 1A: Seek gagal pada stream non-Opus -> retry URL segar (resolveStreamUrl), bukan non-Opus
    test('1A: Seek gagal pada stream non-Opus mencoba retry resolveStreamUrl segar', () async {
      youTubeService.isOpusStream = false;
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);

      mockPlayer.onSeek = (pos) async {
        throw PlatformException(code: '0', message: 'Source error');
      };

      int setSourceCount = 0;
      mockPlayer.onSetAudioSource = (source, {preload = true, initialPosition, initialIndex}) async {
        setSourceCount++;
        if (setSourceCount == 1) {
          throw PlatformException(code: '0', message: 'Stream failed');
        }
        return Duration.zero;
      };

      await playerService.seek(const Duration(seconds: 50));

      // Verifikasi resolveNonOpusStream TIDAK dipanggil, melainkan resolveStreamUrl
      expect(youTubeService.resolveNonOpusStreamCallCount, 0);
      expect(youTubeService.resolveStreamUrlCallCount, greaterThanOrEqualTo(2));
      expect(playerService.playbackError, isNull);
    });

    // 1B: seek-beyond-eof -> posisi di-clamp ke durasi - 2 detik dan seek ulang SEKALI
    test('1B: seek-beyond-eof clamp ke duration - 2s dan coba seek ulang sekali', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);
      mockPlayer.setMockDuration(const Duration(seconds: 100));

      int seekAttempts = 0;
      mockPlayer.onSeek = (pos) async {
        seekAttempts++;
        if (seekAttempts == 1) {
          // Attempt pertama melempar SeekBeyondEofException
          throw SeekBeyondEofException(
            videoId: testSong.videoId,
            range: '1000-2000',
            statusCode: 416,
            totalBytes: 1500,
            message: 'seek-beyond-eof: Range Not Satisfiable',
          );
        }
        // Attempt kedua (clamped ke 98s) berhasil
        mockPlayer.setMockPosition(pos);
      };

      // Minta seek ke 105 detik (> durasi - 2s)
      await playerService.seek(const Duration(seconds: 105));

      // Verifikasi seek dipanggil 2x: pertama 105s, kedua di-clamp ke 98s (100 - 2)
      expect(seekAttempts, 2);
      expect(mockPlayer.lastSeekPosition, const Duration(seconds: 98));
      expect(playerService.playbackError, isNull);
    });

    // 1B: seek di 2 detik terakhir -> tidak ada error, diperlakukan sebagai akhir lagu
    test('1B: seek di 2 detik terakhir lagu diperlakukan sebagai akhir lagu tanpa error', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);
      mockPlayer.setMockDuration(const Duration(seconds: 100));

      mockPlayer.onSeek = (pos) async {
        throw SeekBeyondEofException(
          videoId: testSong.videoId,
          range: '1000-2000',
          statusCode: 416,
          totalBytes: 1500,
          message: 'seek-beyond-eof: Range Not Satisfiable',
        );
      };

      // Seek langsung ke posisi 99s (dalam 2 detik terakhir dari 100s)
      await playerService.seek(const Duration(seconds: 99));

      // Tidak ada error yang ditampilkan ke user
      expect(playerService.playbackError, isNull);
      // Pemutaran dihentikan / selesai (ProcessingState idle/completed)
      expect(mockPlayer.playing, isFalse);
    });

    // 1C: Race recovery - simulasikan kegagalan seek yang JUGA memicu _handlePlaybackError bersamaan
    test('1C: Race recovery guard mencegah setAudioSource bersamaan dan mencatat RECOVERY-SKIP', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);

      // Siapkan onSetAudioSource dengan jeda agar guard aktif selama proses berjalan
      final setAudioSourceCompleter = Completer<void>();
      int setSourceCount = 0;

      mockPlayer.onSetAudioSource = (source, {preload = true, initialPosition, initialIndex}) async {
        setSourceCount++;
        await setAudioSourceCompleter.future;
        return Duration.zero;
      };

      mockPlayer.onSeek = (pos) async {
        throw PlatformException(code: '0', message: 'Seek failed');
      };

      // Jalankan seek (yang akan memicu recovery seek)
      final seekFuture = playerService.seek(const Duration(seconds: 30));
      await pumpEventQueue();

      // Secara bersamaan, playbackEventStream memicu _handlePlaybackError
      mockPlayer.emitPlaybackError(PlatformException(code: '0', message: 'Stream error'));
      await pumpEventQueue();

      // Lepaskan delay setAudioSource
      setAudioSourceCompleter.complete();
      await seekFuture;

      // setAudioSource hanya dipanggil untuk recovery pertama yang memegang guard
      expect(setSourceCount, 1);
    });

    // 1E: (a) event begin tiba SAAT player sudah ter-pause oleh ExoPlayer (playing == false) -> end tetap resume
    test('1E (a): focus begin tiba saat player sudah ter-pause tetap menyimpan flag dan end me-resume', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);
      mockPlayer.setMockPosition(const Duration(seconds: 40));

      // ExoPlayer mem-pause LEBIH DULU
      mockPlayer.emitState(playing: false);

      // Event begin tiba sesudah playing == false
      interruptionController.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      final playCallsBefore = mockPlayer.playCallCount;

      // Event end tiba -> tetap auto-resume
      interruptionController.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      expect(mockPlayer.playCallCount, greaterThan(playCallsBefore));
    });

    // 1E: (b) user pause manual lalu interupsi begin/end -> TIDAK ada auto-resume
    test('1E (b): user pause manual lalu interupsi begin/end TIDAK auto-resume', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);

      // User mem-pause secara manual lewat togglePlayPause
      await playerService.togglePlayPause();
      expect(mockPlayer.playing, isFalse);

      final playCallsBefore = mockPlayer.playCallCount;

      // Interupsi begin tiba
      interruptionController.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // Interupsi end tiba
      interruptionController.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // Tidak boleh ada pemanggilan play()
      expect(mockPlayer.playCallCount, playCallsBefore);
    });

    // 1E: (c) end dengan play() yang throw -> recovery penuh berjalan (resolveStreamUrl + setAudioSource)
    test('1E (c): focus end dengan play() throw memicu recovery penuh auto-resume', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);
      mockPlayer.setMockPosition(const Duration(seconds: 25));

      interruptionController.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // Simulasikan play() throw saat resume
      bool playThrew = false;
      mockPlayer.onPlay = () async {
        if (!playThrew) {
          playThrew = true;
          throw PlatformException(code: '0', message: 'Player in invalid state');
        }
        mockPlayer.emitState(playing: true);
      };

      final setAudioSourceBefore = mockPlayer.setAudioSourceCallCount;

      // Event end tiba -> play() throw -> recovery penuh berjalan
      interruptionController.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await Future.delayed(const Duration(milliseconds: 400));
      await pumpEventQueue();

      // setAudioSource dipanggil dalam recovery penuh
      expect(mockPlayer.setAudioSourceCallCount, greaterThan(setAudioSourceBefore));
    });

    // 1E: (d) recovery penuh gagal -> _playbackError terisi pesan manusiawi + tombol play manual tetap bisa dipanggil
    test('1E (d): focus recovery gagal mengisi _playbackError pesan manusiawi dan play manual tetap berfungsi', () async {
      await playerService.playSong(testSong);
      mockPlayer.emitState(playing: true);
      mockPlayer.setMockPosition(const Duration(seconds: 25));

      interruptionController.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // play() throw
      mockPlayer.onPlay = () async {
        throw PlatformException(code: '0', message: 'Player state error');
      };

      // Recovery setAudioSource juga gagal
      mockPlayer.onSetAudioSource = (source, {preload = true, initialPosition, initialIndex}) async {
        throw PlatformException(code: '0', message: 'Recovery setAudioSource failed');
      };

      // Event end tiba
      interruptionController.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await Future.delayed(const Duration(milliseconds: 400));
      await pumpEventQueue();

      // _playbackError terisi pesan manusiawi
      expect(playerService.playbackError, contains('Pemutaran terhenti oleh notifikasi lain'));

      // Verifikasi user masih bisa menekan tombol play manual (tidak disabled/terblokir)
      mockPlayer.onPlay = null; // Normal kembali
      mockPlayer.onSetAudioSource = null;
      await playerService.togglePlayPause();
      expect(playerService.playbackError, isNull);
    });
  });
}
