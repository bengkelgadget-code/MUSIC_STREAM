import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:setel/core/errors.dart';
import 'package:setel/models/song.dart';
import 'package:setel/models/song_chapter.dart';
import 'package:setel/services/audio_handler.dart';
import 'package:setel/services/audio_player_service.dart';
import 'package:setel/services/youtube_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class FakeConnectivity implements Connectivity {
  final List<ConnectivityResult> results;
  FakeConnectivity(this.results);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value(results);
}

class TrackingYouTubeService implements YouTubeService {
  int resolveCallCount = 0;
  int resolveNonOpusCallCount = 0;
  final List<int> clientStartIndices = [];
  final Future<AudioStreamResult> Function(String videoId, int clientStartIndex)? onResolve;
  final Future<AudioStreamResult> Function(String videoId, int clientStartIndex)? onResolveNonOpus;

  TrackingYouTubeService({this.onResolve, this.onResolveNonOpus});

  @override
  Future<AudioStreamResult> resolveStreamUrl(String videoId,
      {int clientStartIndex = 0}) async {
    resolveCallCount++;
    clientStartIndices.add(clientStartIndex);
    if (onResolve != null) {
      return onResolve!(videoId, clientStartIndex);
    }
    throw AppException(
      'Gagal memuat stream audio untuk video $videoId: 403 Forbidden',
      const HttpException('403 Forbidden'),
      ['androidSdkless: 403 Forbidden', 'ios: 403 Forbidden'],
    );
  }

  @override
  Future<AudioStreamResult> resolveNonOpusStream(String videoId,
      {int clientStartIndex = 0}) async {
    resolveNonOpusCallCount++;
    if (onResolveNonOpus != null) {
      return onResolveNonOpus!(videoId, clientStartIndex);
    }
    return AudioStreamResult(
      url: Uri.parse('https://example.com/audio.m4a'),
      headers: {'User-Agent': 'test'},
      tag: 140,
      codec: 'mp4a.40.2',
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

class MockAudioPlayer extends AudioPlayer {
  int setAudioSourceCallCount = 0;
  int playCallCount = 0;
  int pauseCallCount = 0;
  int stopCallCount = 0;
  Duration _mockPosition = Duration.zero;
  Duration? _mockDuration;
  final _mockProcessingStateController = StreamController<ProcessingState>.broadcast();
  Future<Duration?> Function(AudioSource source)? onSetAudioSource;

  @override
  Duration get position => _mockPosition;

  @override
  Duration? get duration => _mockDuration;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _mockProcessingStateController.stream;

  void emitProcessingState(ProcessingState state) {
    _mockProcessingStateController.add(state);
  }

  void setMockPosition(Duration pos) {
    _mockPosition = pos;
  }

  void setMockDuration(Duration? dur) {
    _mockDuration = dur;
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    Duration? initialPosition,
    int? initialIndex,
  }) async {
    setAudioSourceCallCount++;
    if (onSetAudioSource != null) {
      return onSetAudioSource!(source);
    }
    return Duration.zero;
  }

  @override
  Future<void> play() async {
    playCallCount++;
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Poin 2: Klasifikasi Penyebab Error Pemutaran Berdasarkan Tipe', () {
    test('Kategori (a) TIDAK ADA INTERNET dipetakan dengan benar', () {
      // 1. SocketException langsung
      final msg1 = classifyPlaybackError(
        const SocketException('Failed host lookup: "rr1---sn.googlevideo.com"'),
      );
      expect(
        msg1,
        'Tidak ada koneksi internet. Periksa WiFi/data seluler, lalu coba lagi.',
      );

      // 2. TimeoutException
      final msg2 = classifyPlaybackError(
        TimeoutException('Connection timed out after 15s'),
      );
      expect(
        msg2,
        'Tidak ada koneksi internet. Periksa WiFi/data seluler, lalu coba lagi.',
      );

      // 3. AppException membungkus SocketException
      final msg3 = classifyPlaybackError(
        AppException(
          'Network failure',
          const SocketException('Network is unreachable'),
        ),
      );
      expect(
        msg3,
        'Tidak ada koneksi internet. Periksa WiFi/data seluler, lalu coba lagi.',
      );
    });

    test('Kategori (b) VIDEO TIDAK DAPAT DIPUTAR dipetakan dengan benar', () {
      // 1. VideoUnplayableException
      final msg1 = classifyPlaybackError(
        VideoUnplayableException('This video is not available in your region'),
        songTitle: 'Lagu Daerah',
      );
      expect(
        msg1,
        '"Lagu Daerah" tidak dapat diputar (video dihapus/dibatasi/diblokir wilayah).',
      );

      // 2. Pesan mengandung unplayable / private / removed
      final msg2 = classifyPlaybackError(
        Exception('Video is private or removed by uploader'),
        songTitle: 'Lagu Langka',
      );
      expect(
        msg2,
        '"Lagu Langka" tidak dapat diputar (video dihapus/dibatasi/diblokir wilayah).',
      );

      // 3. Fallback judul lagu jika null
      final msg3 = classifyPlaybackError(
        VideoUnavailableException('Video unavailable'),
      );
      expect(
        msg3,
        '"Lagu ini" tidak dapat diputar (video dihapus/dibatasi/diblokir wilayah).',
      );
    });

    test('Kategori (c) PROTEKSI BOT dipetakan dengan benar', () {
      // 1. Status 403 Forbidden
      final msg1 = classifyPlaybackError(
        AppException(
          'Gagal memuat stream: 403 Forbidden',
          const HttpException('403 Forbidden'),
        ),
      );
      expect(
        msg1,
        'Server menolak akses stream (kemungkinan proteksi bot di jaringan ini). Coba ganti jaringan (WiFi lain / data seluler).',
      );

      // 2. Pesan Sign in to confirm you\'re not a bot
      final msg2 = classifyPlaybackError(
        Exception("Sign in to confirm you're not a bot"),
      );
      expect(
        msg2,
        'Server menolak akses stream (kemungkinan proteksi bot di jaringan ini). Coba ganti jaringan (WiFi lain / data seluler).',
      );

      // 3. Client errors berisi manifest kosong
      final msg3 = classifyPlaybackError(
        AppException(
          'Gagal',
          null,
          ['androidSdkless: Manifest kosong', 'ios: Manifest kosong'],
        ),
      );
      expect(
        msg3,
        'Server menolak akses stream (kemungkinan proteksi bot di jaringan ini). Coba ganti jaringan (WiFi lain / data seluler).',
      );
    });

    test('Kategori SOURCE ERROR dipetakan ke pesan manusiawi yang benar', () {
      // 1. PlatformException('0', 'Source error')
      final msg1 = classifyPlaybackError(
        PlatformException(code: '0', message: 'Source error'),
      );
      expect(
        msg1,
        'Gagal memuat audio: sumber stream ditolak atau kedaluwarsa. Coba putar lagi atau ganti jaringan.',
      );

      // 2. AppException membungkus PlatformException('0')
      final msg2 = classifyPlaybackError(
        AppException(
          'Stream failed',
          PlatformException(code: '0', message: 'Source error details'),
        ),
      );
      expect(
        msg2,
        'Gagal memuat audio: sumber stream ditolak atau kedaluwarsa. Coba putar lagi atau ganti jaringan.',
      );

      // 3. String mengandung 'source error'
      final msg3 = classifyPlaybackError(
        Exception('ExoPlayer TYPE_SOURCE: Source error encountered'),
      );
      expect(
        msg3,
        'Gagal memuat audio: sumber stream ditolak atau kedaluwarsa. Coba putar lagi atau ganti jaringan.',
      );
    });

    test('Kategori (d) LAINNYA: wrapper PlatformException terkupas bersih tanpa kata PlatformException(', () {
      // 1. PlatformException lain dengan pesan
      final msg1 = classifyPlaybackError(
        PlatformException(
            code: 'ERROR_AUDIO_TRACK', message: 'AudioTrack write failed'),
      );
      expect(msg1, 'Gagal memutar lagu: AudioTrack write failed.');
      expect(msg1, isNot(contains('PlatformException')));
      expect(msg1, isNot(contains('ERROR_AUDIO_TRACK')));

      // 2. PlatformException dengan pesan kosong/null -> fallback ramah
      final msg2 = classifyPlaybackError(
        PlatformException(code: '99', message: null),
      );
      expect(msg2, 'Gagal memutar lagu, coba lagi.');
      expect(msg2, isNot(contains('PlatformException')));
      expect(msg2, isNot(contains('99')));

      // 3. String mentah Exception mengandung 'PlatformException(code, message)'
      final msg3 = classifyPlaybackError(
        Exception('PlatformException(12, Hardware decoder failed, null, null)'),
      );
      expect(msg3, 'Gagal memutar lagu: Hardware decoder failed.');
      expect(msg3, isNot(contains('PlatformException')));
    });

    test('Kategori (d) LAINNYA menampilkan ringkasan error asli tanpa pesan generik', () {
      final msg1 = classifyPlaybackError(
        Exception('Media codec initialization failed during hardware decoding'),
      );
      expect(
        msg1,
        'Gagal memutar lagu: Media codec initialization failed during hardware decoding.',
      );
      expect(msg1, isNot(contains('tidak dapat mengambil data stream')));

      // Truncation bila pesan melebihi 120 karakter
      final longMsg = 'A' * 200;
      final msg2 = classifyPlaybackError(Exception(longMsg));
      expect(msg2.length, lessThanOrEqualTo(140)); // prefix + 120 chars
      expect(msg2, endsWith('...'));
    });
  });

  group('Poin 1 & 3: Resolve Efisien (1x Panggil) & Fail-Fast Offline', () {
    test('SEBELUM resolve: Fail-fast saat offline tanpa memanggil resolveStreamUrl sama sekali', () async {
      final trackingYt = TrackingYouTubeService();
      final offlineConn = FakeConnectivity([ConnectivityResult.none]);
      final handler = SetelAudioHandler();

      final player = AudioPlayerServiceImpl(
        youTubeService: trackingYt,
        audioHandler: handler,
        connectivity: offlineConn,
      );

      const song = Song(
        videoId: 'vid_offline_1',
        title: 'Offline Test Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      try {
        await player.playSong(song);
      } catch (_) {}

      // resolveStreamUrl TIDAK PERNAH dipanggil karena fail-fast langsung di awal
      expect(trackingYt.resolveCallCount, 0);

      // State harus langsung memancarkan error kategori (a)
      final state = await player.playerState.first;
      expect(
        state.playbackError,
        'Tidak ada koneksi internet. Periksa WiFi/data seluler, lalu coba lagi.',
      );
    });

    test('Hapus loop ganda: resolveStreamUrl hanya dipanggil 1x saat pemutaran gagal total', () async {
      final trackingYt = TrackingYouTubeService();
      final onlineConn = FakeConnectivity([ConnectivityResult.wifi]);
      final handler = SetelAudioHandler();

      final player = AudioPlayerServiceImpl(
        youTubeService: trackingYt,
        audioHandler: handler,
        connectivity: onlineConn,
      );

      const song = Song(
        videoId: 'vid_single_call',
        title: 'Single Call Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      try {
        await player.playSong(song);
      } catch (_) {}

      // Tepat 1x pemanggilan (tidak ada loop 5x dari luar)
      expect(trackingYt.resolveCallCount, 1);
    });
  });

  group('Poin 4: Auto-Skip dan Batas 3x Gagal Beruntun', () {
    test('Lagu gagal total auto-skip ke lagu berikutnya dalam antrean', () async {
      int resolveAttempt = 0;
      final trackingYt = TrackingYouTubeService(
        onResolve: (videoId, clientStartIndex) async {
          resolveAttempt++;
          if (videoId == 'bad_vid_1') {
            throw VideoUnplayableException('Video unavailable');
          }
          // Lagu kedua juga dicoba dan melempar error unplayable
          throw VideoUnplayableException('Video 2 unavailable');
        },
      );

      final onlineConn = FakeConnectivity([ConnectivityResult.wifi]);
      final handler = SetelAudioHandler();

      final player = AudioPlayerServiceImpl(
        youTubeService: trackingYt,
        audioHandler: handler,
        connectivity: onlineConn,
      );

      const songs = [
        Song(
          videoId: 'bad_vid_1',
          title: 'Rusak 1',
          artist: 'Artist',
          durationMs: 180000,
          thumbnailUrl: '',
        ),
        Song(
          videoId: 'good_vid_2',
          title: 'Bagus 2',
          artist: 'Artist',
          durationMs: 180000,
          thumbnailUrl: '',
        ),
      ];

      try {
        await player.playQueue(songs, startIndex: 0);
      } catch (_) {}

      // Beri jeda auto-skip
      await Future.delayed(const Duration(milliseconds: 500));

      // Harus sudah mencoba lagu 1 lalu auto-skip ke lagu 2
      expect(resolveAttempt, greaterThanOrEqualTo(2));
      expect(trackingYt.resolveCallCount, greaterThanOrEqualTo(2));
    });

    test('3 lagu beruntun gagal -> BERHENTI dan tidak melanjutkan loop', () async {
      int calls = 0;
      final trackingYt = TrackingYouTubeService(
        onResolve: (videoId, clientStartIndex) async {
          calls++;
          throw VideoUnplayableException('Video removed');
        },
      );

      final onlineConn = FakeConnectivity([ConnectivityResult.wifi]);
      final handler = SetelAudioHandler();

      final player = AudioPlayerServiceImpl(
        youTubeService: trackingYt,
        audioHandler: handler,
        connectivity: onlineConn,
      );

      const queue = [
        Song(videoId: 'fail_1', title: 'F1', artist: 'A', durationMs: 1000, thumbnailUrl: ''),
        Song(videoId: 'fail_2', title: 'F2', artist: 'A', durationMs: 1000, thumbnailUrl: ''),
        Song(videoId: 'fail_3', title: 'F3', artist: 'A', durationMs: 1000, thumbnailUrl: ''),
        Song(videoId: 'fail_4', title: 'F4', artist: 'A', durationMs: 1000, thumbnailUrl: ''),
      ];

      try {
        await player.playQueue(queue, startIndex: 0);
      } catch (_) {}

      // Tunggu jeda auto-skip antar trek
      await Future.delayed(const Duration(milliseconds: 1200));

      // Berhenti tepat setelah 3 lagu beruntun gagal (lagu 4 tidak diputar)
      expect(calls, 3);
    });
  });

  group('Poin 2: Retry 1x setAudioSource dengan URL Segar', () {
    test(
        'setAudioSource throw source error memicu tepat 1x resolve ulang + 1x setAudioSource ulang lalu sukses',
        () async {
      int resolveCalls = 0;
      final List<int> startIndices = [];

      final trackingYt = TrackingYouTubeService(
        onResolve: (videoId, clientStartIndex) async {
          resolveCalls++;
          startIndices.add(clientStartIndex);
          return AudioStreamResult(
            url: Uri.parse(
                'https://googlevideo.com/playback_$clientStartIndex'),
            headers: {'User-Agent': 'Test'},
            clientName:
                clientStartIndex == 0 ? 'androidSdkless' : 'androidVr',
            totalBytes: 500000,
          );
        },
      );

      final mockAudioPlayer = MockAudioPlayer();
      int setSourceCount = 0;
      mockAudioPlayer.onSetAudioSource = (source) async {
        setSourceCount++;
        if (setSourceCount == 1) {
          // Panggilan pertama gagal dengan PlatformException code '0' (Source error)
          throw PlatformException(code: '0', message: 'Source error');
        }
        // Panggilan kedua (retry) sukses
        return const Duration(seconds: 180);
      };

      final onlineConn = FakeConnectivity([ConnectivityResult.wifi]);
      final handler = SetelAudioHandler();

      final player = AudioPlayerServiceImpl(
        player: mockAudioPlayer,
        youTubeService: trackingYt,
        audioHandler: handler,
        connectivity: onlineConn,
      );

      PlayerState? lastState;
      final sub = player.playerState.listen((s) => lastState = s);
      addTearDown(sub.cancel);

      const song = Song(
        videoId: 'vid_retry_success',
        title: 'Retry Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      await player.playSong(song);

      // Tepat 1x resolve pertama + 1x resolve ulang dengan clientStartIndex: 0
      expect(resolveCalls, 2);
      expect(startIndices, [0, 0]);

      // Tepat 1x setAudioSource pertama + 1x retry setAudioSource
      expect(setSourceCount, 2);
      expect(mockAudioPlayer.playCallCount, 1);

      // State tidak memiliki playbackError
      expect(lastState?.playbackError, isNull);
    });

    test(
        'Bila retry setAudioSource tetap gagal, error terklasifikasi (bukan mentah)',
        () async {
      int resolveCalls = 0;

      final trackingYt = TrackingYouTubeService(
        onResolve: (videoId, clientStartIndex) async {
          resolveCalls++;
          return AudioStreamResult(
            url: Uri.parse(
                'https://googlevideo.com/playback_$clientStartIndex'),
            headers: {'User-Agent': 'Test'},
            clientName: 'testClient',
            totalBytes: 500000,
          );
        },
      );

      final mockAudioPlayer = MockAudioPlayer();
      mockAudioPlayer.onSetAudioSource = (source) async {
        // Kedua panggilan (pertama dan retry) gagal dengan source error
        throw PlatformException(code: '0', message: 'Source error');
      };

      final onlineConn = FakeConnectivity([ConnectivityResult.wifi]);
      final handler = SetelAudioHandler();

      final player = AudioPlayerServiceImpl(
        player: mockAudioPlayer,
        youTubeService: trackingYt,
        audioHandler: handler,
        connectivity: onlineConn,
      );

      final states = <PlayerState>[];
      final sub = player.playerState.listen(states.add);
      addTearDown(sub.cancel);

      const song = Song(
        videoId: 'vid_retry_fail',
        title: 'Retry Fail Song',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      try {
        await player.playSong(song);
      } catch (_) {}

      await pumpEventQueue();

      // Tepat 1x resolve awal + 1x resolve ulang
      expect(resolveCalls, 2);
      expect(mockAudioPlayer.setAudioSourceCallCount, 2);

      // Error harus terklasifikasi ke pesan manusiawi yang bersih, bukan mentah 'PlatformException(0, ...)'
      final errorStates = states.where((s) => s.playbackError != null).toList();
      expect(errorStates, isNotEmpty,
          reason: 'All emitted playbackErrors: ${states.map((s) => s.playbackError).toList()}');
      final lastErrState = errorStates.last;
      expect(
        lastErrState.playbackError,
        'Gagal memuat audio: sumber stream ditolak atau kedaluwarsa. Coba putar lagi atau ganti jaringan.',
      );
      expect(lastErrState.playbackError, isNot(contains('PlatformException')));
      expect(lastErrState.playbackError, isNot(contains('(0)')));
    });
  });

  group('v1.3.12: Diagnostic Holder, Opus Fallback, and Chapter Auto-skip', () {
    test('ChunkErrorInfo 403 maps to bot protection message', () {
      final chunkErr = ChunkErrorInfo(
        videoId: 'v_chunk_403',
        statusCode: 403,
        range: 'bytes=0-524287',
        clientName: 'androidSdkless',
        at: DateTime.now(),
      );
      final msg = classifyPlaybackError(
        PlatformException(code: '0', message: 'Source error'),
        songTitle: 'Test Song',
        lastChunkError: chunkErr,
      );
      expect(msg, contains('proteksi bot'));
      expect(msg, isNot(contains('kedaluwarsa')));
    });

    test('ChunkErrorInfo 404 maps to stream audio not found message', () {
      final chunkErr = ChunkErrorInfo(
        videoId: 'v_chunk_404',
        statusCode: 404,
        range: 'bytes=0-524287',
        clientName: 'androidSdkless',
        at: DateTime.now(),
      );
      final msg = classifyPlaybackError(
        PlatformException(code: '0', message: 'Source error'),
        songTitle: 'Test Song',
        lastChunkError: chunkErr,
      );
      expect(msg, '"Test Song" tidak dapat diputar (stream audio video ini tidak ditemukan).');
      expect(msg, isNot(contains('kedaluwarsa')));
    });

    test('hasSuccessfulPlayThisSession: true appends helpful suggestion', () {
      final msg = classifyPlaybackError(
        PlatformException(code: '0', message: 'Source error'),
        songTitle: 'Test Song',
        hasSuccessfulPlayThisSession: true,
      );
      expect(msg, contains('Lagu lain di sesi ini berhasil diputar — kemungkinan videonya yang bermasalah, coba lagu lain.'));
    });

    test('Compilation song: auto-skip advances track index, ignoring chapters', () async {
      final mockAudioPlayer = MockAudioPlayer();
      final youTubeService = TrackingYouTubeService(
        onResolve: (id, start) async => AudioStreamResult(
          url: Uri.parse('https://example.com/audio.m4a'),
          headers: {},
        ),
      );
      final player = AudioPlayerServiceImpl(
        player: mockAudioPlayer,
        audioHandler: SetelAudioHandler(),
        youTubeService: youTubeService,
        connectivity: FakeConnectivity([ConnectivityResult.wifi]),
      );

      PlayerState? lastState;
      final sub = player.playerState.listen((s) => lastState = s);
      addTearDown(sub.cancel);

      const song1 = Song(
        videoId: 'compilation_1',
        title: 'Compilation 1',
        artist: 'Artist',
        durationMs: 900000,
        thumbnailUrl: '',
      );
      const song2 = Song(
        videoId: 'normal_2',
        title: 'Normal Song 2',
        artist: 'Artist',
        durationMs: 180000,
        thumbnailUrl: '',
      );

      await player.playQueue([song1, song2]);

      await player.next(fromAutoSkip: true);
      expect(lastState?.currentSong?.videoId, 'normal_2');
    });

    test('Opus stream failure triggers fallback 1x to resolveNonOpusStream', () async {
      final mockAudioPlayer = MockAudioPlayer();
      int opusResolveCount = 0;
      int nonOpusResolveCount = 0;

      final youTubeService = TrackingYouTubeService(
        onResolve: (id, start) async {
          opusResolveCount++;
          return AudioStreamResult(
            url: Uri.parse('https://example.com/audio.webm'),
            headers: {},
            tag: 249,
            codec: 'opus',
          );
        },
        onResolveNonOpus: (id, start) async {
          nonOpusResolveCount++;
          return AudioStreamResult(
            url: Uri.parse('https://example.com/audio.m4a'),
            headers: {},
            tag: 140,
            codec: 'mp4a.40.2',
          );
        },
      );

      int setSourceCount = 0;
      mockAudioPlayer.onSetAudioSource = (source) async {
        setSourceCount++;
        if (setSourceCount == 1) {
          throw PlatformException(code: '0', message: 'Source error');
        }
        return Duration.zero;
      };

      final player = AudioPlayerServiceImpl(
        player: mockAudioPlayer,
        audioHandler: SetelAudioHandler(),
        youTubeService: youTubeService,
        connectivity: FakeConnectivity([ConnectivityResult.wifi]),
      );

      PlayerState? lastState;
      final sub = player.playerState.listen((s) => lastState = s);
      addTearDown(sub.cancel);

      const song = Song(
        videoId: 'raim_laode_album',
        title: 'Raim Laode Full Album',
        artist: 'Raim Laode',
        durationMs: 1800000,
        thumbnailUrl: '',
      );

      await player.playSong(song);

      expect(opusResolveCount, 1);
      expect(nonOpusResolveCount, 1);
      expect(setSourceCount, 2);
      expect(lastState?.playbackError, isNull);
    });

    test('completed saat position 5 detik dari 240 detik memicu jalur kegagalan (auto-skip jika resume gagal)', () async {
      int earlyResolveCalls = 0;
      final mockAudioPlayer = MockAudioPlayer();
      final youTubeService = TrackingYouTubeService(
        onResolve: (id, start) async {
          if (id == 'early_1') {
            earlyResolveCalls++;
            if (earlyResolveCalls > 1) {
              // Gagalkan auto-resume agar masuk ke auto-skip
              throw Exception('Gagal auto-resume');
            }
          }
          return AudioStreamResult(
            url: Uri.parse('https://example.com/audio.m4a'),
            headers: {},
          );
        },
      );
      final player = AudioPlayerServiceImpl(
        player: mockAudioPlayer,
        audioHandler: SetelAudioHandler(),
        youTubeService: youTubeService,
        connectivity: FakeConnectivity([ConnectivityResult.wifi]),
      );

      PlayerState? lastState;
      final sub = player.playerState.listen((s) => lastState = s);
      addTearDown(sub.cancel);

      const song1 = Song(
        videoId: 'early_1',
        title: 'Early Song 1',
        artist: 'Artist',
        durationMs: 240000,
        thumbnailUrl: '',
      );
      const song2 = Song(
        videoId: 'song_2',
        title: 'Song 2',
        artist: 'Artist',
        durationMs: 240000,
        thumbnailUrl: '',
      );

      await player.playQueue([song1, song2]);

      // Set position 5s dari 240s (< 90%)
      mockAudioPlayer.setMockPosition(const Duration(seconds: 5));
      mockAudioPlayer.setMockDuration(const Duration(seconds: 240));

      // Simulasikan completed prematur
      mockAudioPlayer.emitProcessingState(ProcessingState.completed);
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 400));

      // Karena auto-resume gagal, harus auto-skip ke song2 (BUKAN pause diam-diam di song1)
      expect(lastState?.currentSong?.videoId, 'song_2');
    });

    test('completed saat position 238 detik dari 240 detik berperilaku normal (lagu habis)', () async {
      final mockAudioPlayer = MockAudioPlayer();
      final youTubeService = TrackingYouTubeService(
        onResolve: (id, start) async => AudioStreamResult(
          url: Uri.parse('https://example.com/audio.m4a'),
          headers: {},
        ),
      );
      final player = AudioPlayerServiceImpl(
        player: mockAudioPlayer,
        audioHandler: SetelAudioHandler(),
        youTubeService: youTubeService,
        connectivity: FakeConnectivity([ConnectivityResult.wifi]),
      );

      PlayerState? lastState;
      final sub = player.playerState.listen((s) => lastState = s);
      addTearDown(sub.cancel);

      const song1 = Song(
        videoId: 'normal_end_1',
        title: 'Normal End Song',
        artist: 'Artist',
        durationMs: 240000,
        thumbnailUrl: '',
      );

      await player.playSong(song1);

      // Set position 238s dari 240s (>= 90%)
      mockAudioPlayer.setMockPosition(const Duration(seconds: 238));
      mockAudioPlayer.setMockDuration(const Duration(seconds: 240));

      mockAudioPlayer.emitProcessingState(ProcessingState.completed);
      await pumpEventQueue();

      // Pause normal karena lagu memang habis
      expect(mockAudioPlayer.pauseCallCount, greaterThanOrEqualTo(1));
      expect(lastState?.playbackError, isNull);
    });
  });
}
