import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../models/history_entry.dart';
import '../models/song.dart';
import '../models/song_chapter.dart';
import 'audio_handler.dart';
import 'cache_service.dart';
import 'library_service.dart';
import 'youtube_audio_source.dart';
import 'youtube_service.dart';

enum RepeatMode { off, one, all }

class PlayerState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Song? currentSong;
  final List<Song> queue;
  final bool shuffle;
  final RepeatMode repeatMode;
  final DateTime? sleepTimerEndTime;
  final bool sleepAfterCurrentTrack;
  final List<SongChapter> chapters;
  final int chapterIndex;
  final bool isAutoMix;
  final String? mixSeedTitle;
  final String? playbackError;

  const PlayerState({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.currentSong,
    this.queue = const [],
    this.shuffle = false,
    this.repeatMode = RepeatMode.off,
    this.sleepTimerEndTime,
    this.sleepAfterCurrentTrack = false,
    this.chapters = const [],
    this.chapterIndex = -1,
    this.isAutoMix = false,
    this.mixSeedTitle,
    this.playbackError,
  });

  bool get hasChapters => chapters.length >= 2;
  SongChapter? get currentChapter =>
      (hasChapters && chapterIndex >= 0 && chapterIndex < chapters.length)
          ? chapters[chapterIndex]
          : null;

  PlayerState copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    Song? currentSong,
    List<Song>? queue,
    bool? shuffle,
    RepeatMode? repeatMode,
    DateTime? sleepTimerEndTime,
    bool? sleepAfterCurrentTrack,
    bool clearSleepTimer = false,
    bool clearMixSeed = false,
    List<SongChapter>? chapters,
    int? chapterIndex,
    bool? isAutoMix,
    String? mixSeedTitle,
    String? playbackError,
    bool clearPlaybackError = false,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      currentSong: currentSong ?? this.currentSong,
      queue: queue ?? this.queue,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      sleepTimerEndTime: clearSleepTimer
          ? null
          : (sleepTimerEndTime ?? this.sleepTimerEndTime),
      sleepAfterCurrentTrack: clearSleepTimer
          ? false
          : (sleepAfterCurrentTrack ?? this.sleepAfterCurrentTrack),
      chapters: chapters ?? this.chapters,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      isAutoMix: isAutoMix ?? this.isAutoMix,
      mixSeedTitle: clearMixSeed
          ? null
          : (mixSeedTitle ?? this.mixSeedTitle),
      playbackError: clearPlaybackError
          ? null
          : (playbackError ?? this.playbackError),
    );
  }
}

abstract class AudioPlayerService {
  /// Alur: resolveStreamUrl(videoId) → cek cache → just_audio.setUrl → play → recordPlay.
  Future<void> playSong(Song song, {Duration? initialPosition, bool autoMix = false});
  Future<void> playQueue(List<Song> songs, {int startIndex = 0, Duration? initialPosition});
  Future<void> togglePlayPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> addToQueueNext(Song song); // "play next"
  void saveCurrentPosition({bool resetToZero = false});
  void clearPlaybackError();

  Stream<PlayerState>
      get playerState; // isPlaying, position, currentSong, queue, shuffle, repeatMode
}

class AudioPlayerServiceImpl implements AudioPlayerService {
  final AudioPlayer _player;
  final YouTubeService _youTubeService;
  final SetelAudioHandler _audioHandler;
  final LibraryService? _libraryService;
  final CacheService? _cacheService;
  final Connectivity _connectivity;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _playbackEventSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _processingStateSub;

  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _shuffle = false;
  RepeatMode _repeatMode = RepeatMode.off;
  Song? _currentSong;
  List<SongChapter> _chapters = [];
  int _chapterIndex = -1;

  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  bool _sleepAfterCurrentTrack = false;
  Duration? _pendingInitialPosition;
  DateTime _lastPositionSaveTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isAutoMix = false;
  String? _mixSeedTitle;
  int _autoMixSessionId = 0;
  Song? _currentlyCachingSong;
  String? _playbackError;
  bool _isRecoveringPlayback = false;
  int _recoveryAttempts = 0;
  int _consecutiveFailures = 0;

  int _findChapterIndex(Duration pos, List<SongChapter> chapters) {
    if (chapters.isEmpty) return -1;
    final posMs = pos.inMilliseconds;
    int activeIndex = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (posMs >= chapters[i].positionMs) {
        activeIndex = i;
      } else {
        break;
      }
    }
    return activeIndex;
  }

  AudioPlayerServiceImpl({
    AudioPlayer? player,
    required YouTubeService youTubeService,
    required SetelAudioHandler audioHandler,
    LibraryService? libraryService,
    CacheService? cacheService,
    Connectivity? connectivity,
  })  : _player = player ?? AudioPlayer(),
        _youTubeService = youTubeService,
        _audioHandler = audioHandler,
        _libraryService = libraryService,
        _cacheService = cacheService,
        _connectivity = connectivity ?? Connectivity() {
    _initListeners();
    _connectAudioHandler();
  }

  void _initListeners() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      _emitState();
      _audioHandler.updatePlaybackState(
        isPlaying: state.playing,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
        processingState: state.processingState,
      );
    }, onError: (err, stackTrace) {
      _handlePlaybackError('PlayerStateStream error: $err', stackTrace);
    });

    _playbackEventSub = _player.playbackEventStream.listen((event) {
      // Stream event pemutaran normal
    }, onError: (err, stackTrace) {
      _handlePlaybackError('PlaybackEventStream error: $err', stackTrace);
    });

    _positionSub = _player.positionStream.listen((pos) {
      if (_chapters.isNotEmpty) {
        final newIdx = _findChapterIndex(pos, _chapters);
        if (newIdx != _chapterIndex) {
          _chapterIndex = newIdx;
        }
      }
      if (pos.inSeconds >= 2 &&
          DateTime.now().difference(_lastPositionSaveTime).inSeconds >= 3) {
        saveCurrentPosition();
      }
      _emitState();
    });

    _durationSub = _player.durationStream.listen((dur) {
      _emitState();
    });

    _processingStateSub =
        _player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed) {
        _handleTrackEnded();
      }
    });
  }

  void _connectAudioHandler() {
    _audioHandler.onPlayCallback = () => _player.play();
    _audioHandler.onPauseCallback = () {
      saveCurrentPosition();
      _player.pause();
    };
    _audioHandler.onSkipToNextCallback = () => next();
    _audioHandler.onSkipToPreviousCallback = () => previous();
    _audioHandler.onSeekCallback = (position) => seek(position);
    _audioHandler.onStopCallback = () async {
      saveCurrentPosition();
      if (_currentlyCachingSong != null) {
        _cacheService?.cancelCache(_currentlyCachingSong!);
        _currentlyCachingSong = null;
      }
      try {
        await _player.stop();
      } catch (e) {
        debugPrint('AudioPlayerService onStopCallback error: $e');
      }
      _audioHandler.clearMediaItem();
      _queue.clear();
      _currentIndex = -1;
      _currentSong = null;
      _isAutoMix = false;
      _mixSeedTitle = null;
      _emitState();
    };
  }

  @override
  void saveCurrentPosition({bool resetToZero = false}) {
    final song = _currentSong;
    if (song == null || _libraryService == null) return;
    final posMs = resetToZero ? 0 : _player.position.inMilliseconds;
    if (!resetToZero && posMs < 2000) return;
    try {
      _libraryService
          .savePlaybackPosition(song.videoId, posMs)
          .catchError((e) {
        debugPrint('[AudioPlayerService] savePlaybackPosition error: $e');
      });
    } catch (e) {
      debugPrint('[AudioPlayerService] saveCurrentPosition sync error: $e');
    }
    _lastPositionSaveTime = DateTime.now();
  }

  @override
  void clearPlaybackError() {
    _playbackError = null;
    _emitState();
  }

  Future<void> _handlePlaybackError(Object error, [StackTrace? stackTrace]) async {
    final song = _currentSong;
    final currentPos = _player.position;
    debugPrint(
        '[AudioPlayerService] track error: videoId: ${song?.videoId}, title: ${song?.title}, position: $currentPos, error: $error');

    if (song == null || _isRecoveringPlayback) return;

    if (_recoveryAttempts < 1) {
      _recoveryAttempts++;
      _isRecoveringPlayback = true;
      debugPrint(
          '[AudioPlayerService] Mencoba auto-resume pemutaran untuk videoId: ${song.videoId} pada posisi $currentPos...');
      try {
        final freshStream = await _youTubeService.resolveStreamUrl(
          song.videoId,
        );
        final audioSource = YouTubeAudioSource(
          uri: freshStream.url,
          headers: freshStream.headers,
          totalBytes: freshStream.totalBytes,
          contentType: freshStream.contentType,
          tag: song,
          videoId: song.videoId,
          onReResolveUrl: () async {
            final reStream = await _youTubeService.resolveStreamUrl(
              song.videoId,
            );
            return (url: reStream.url, headers: reStream.headers);
          },
        );
        await _player.setAudioSource(audioSource, initialPosition: currentPos);
        await _player.play();
        _isRecoveringPlayback = false;
        debugPrint(
            '[AudioPlayerService] Auto-resume berhasil untuk videoId: ${song.videoId} pada posisi $currentPos');
        return;
      } catch (recoveryErr) {
        debugPrint(
            '[AudioPlayerService] Auto-resume gagal untuk videoId: ${song.videoId}: $recoveryErr');
        _isRecoveringPlayback = false;
      }
    }

    _playbackError = classifyPlaybackError(error, songTitle: song.title);
    _emitState();
  }

  void _emitState() {
    if (_stateController.isClosed) return;

    final state = PlayerState(
      isPlaying: _player.playing,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      currentSong: _currentSong,
      queue: List.unmodifiable(_queue),
      shuffle: _shuffle,
      repeatMode: _repeatMode,
      sleepTimerEndTime: _sleepTimerEndTime,
      sleepAfterCurrentTrack: _sleepAfterCurrentTrack,
      chapters: List.unmodifiable(_chapters),
      chapterIndex: _chapterIndex,
      isAutoMix: _isAutoMix,
      mixSeedTitle: _mixSeedTitle,
      playbackError: _playbackError,
    );
    _stateController.add(state);
  }

  Future<void> _handleTrackEnded() async {
    try {
      debugPrint(
          '[AudioPlayerService] track ended: videoId: ${_currentSong?.videoId}, title: ${_currentSong?.title}, position: ${_player.position}, duration: ${_player.duration}');
      saveCurrentPosition(resetToZero: true);

      // Cek jika sleep timer "Habis lagu ini" aktif
      if (_sleepAfterCurrentTrack) {
        await _player.pause();
        cancelSleepTimer();
        return;
      }

      if (_repeatMode == RepeatMode.one) {
        await seek(Duration.zero);
        await _player.play();
      } else if (_currentIndex < _queue.length - 1) {
        await next();
      } else if (_repeatMode == RepeatMode.all && _queue.isNotEmpty) {
        _currentIndex = 0;
        await _playTrackAtCurrentIndex();
      } else if (_isAutoMix && _currentSong != null) {
        // Endless Autoplay: muat lagu terkait berikutnya saat antrean habis
        final more = await _youTubeService.getRelatedSongs(_currentSong!.videoId, limit: 15);
        final existingIds = _queue.map((s) => s.videoId).toSet();
        final fresh = more.where((s) => !existingIds.contains(s.videoId)).toList();
        if (fresh.isNotEmpty) {
          _queue.addAll(fresh);
          _currentIndex++;
          _emitState();
          await _playTrackAtCurrentIndex();
          return;
        }
        await _player.pause();
      } else {
        await _player.pause();
      }
    } catch (e) {
      debugPrint('Error saat transisi akhir trek: $e');
    }
  }

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Future<void> playSong(Song song, {Duration? initialPosition, bool autoMix = false}) async {
    _consecutiveFailures = 0;
    saveCurrentPosition();
    _pendingInitialPosition = initialPosition;
    _isAutoMix = autoMix;
    _mixSeedTitle = autoMix ? song.title : null;
    _queue = [song];
    _currentIndex = 0;
    _currentSong = song;
    _emitState();

    await _playTrackAtCurrentIndex();

    if (autoMix) {
      unawaited(_loadAutoMix(song));
    }
  }

  Future<void> _loadAutoMix(Song song) async {
    final sessionId = ++_autoMixSessionId;
    try {
      debugPrint('Memuat Smart Mix / Radio terkait untuk: ${song.title} - ${song.artist}...');
      final related = await _youTubeService.getRelatedSongs(song.videoId, limit: 20);

      // Pastikan sesi masih relevan
      if (_autoMixSessionId != sessionId) return;
      if (_currentSong?.videoId != song.videoId) return;

      if (related.isNotEmpty) {
        final existingIds = _queue.map((s) => s.videoId).toSet();
        final newTracks = related.where((s) => !existingIds.contains(s.videoId)).toList();

        if (newTracks.isNotEmpty) {
          _queue.addAll(newTracks);
          _emitState();
          debugPrint('Smart Mix berhasil ditambahkan ke antrean: +${newTracks.length} lagu terkait!');
        }
      }
    } catch (e) {
      debugPrint('Error _loadAutoMix: $e');
    }
  }

  @override
  Future<void> playQueue(List<Song> songs, {int startIndex = 0, Duration? initialPosition}) async {
    if (songs.isEmpty) return;
    _consecutiveFailures = 0;
    saveCurrentPosition();
    _pendingInitialPosition = initialPosition;
    _isAutoMix = false;
    _mixSeedTitle = null;

    if (!listEquals(_queue, songs)) {
      _queue = List.from(songs);
    }

    _currentIndex = (startIndex >= 0 && startIndex < _queue.length)
        ? startIndex
        : 0;
    _currentSong = _queue[_currentIndex];
    _emitState();

    await _playTrackAtCurrentIndex();
  }

  Future<void> _playTrackAtCurrentIndex() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    final song = _queue[_currentIndex];
    _currentSong = song;
    _playbackError = null;
    _recoveryAttempts = 0;

    // Reset chapter state untuk lagu baru
    _chapters = [];
    _chapterIndex = -1;
    _emitState();

    // Jika lagu merupakan kompilasi (>10 menit), muat chapters secara lazy (dari cache/box dulu)
    if (song.durationMs > 600000) {
      unawaited(_youTubeService.getChapters(song.videoId).then((ch) {
        if (_currentSong?.videoId == song.videoId && ch.isNotEmpty) {
          _chapters = ch;
          _chapterIndex = _findChapterIndex(_player.position, _chapters);
          _emitState();
        }
      }).catchError((_) {}));
    }

    // 1. Perbarui AudioService MediaItem
    _audioHandler.setMediaItemInfo(
      id: song.videoId,
      title: song.title,
      artist: song.artist,
      thumbnailUrl: song.thumbnailUrl,
      duration: song.durationMs > 0
          ? Duration(milliseconds: song.durationMs)
          : null,
    );

    final initPos = _pendingInitialPosition;
    _pendingInitialPosition = null;

    // SEBELUM resolveStreamUrl (langkah lambat), panggil updatePlaybackState
    // dengan processingState=loading + isPlaying=true, supaya audio_service
    // bisa menaikkan foreground & notifikasi dalam <1 detik setelah user tap.
    _audioHandler.updatePlaybackState(
      isPlaying: true,
      position: initPos ?? Duration.zero,
      duration: song.durationMs > 0
          ? Duration(milliseconds: song.durationMs)
          : Duration.zero,
      processingState: ProcessingState.loading,
    );

    // Batalkan background cache yang mungkin sedang berjalan untuk lagu sebelumnya
    if (_currentlyCachingSong != null &&
        _currentlyCachingSong?.videoId != song.videoId) {
      _cacheService?.cancelCache(_currentlyCachingSong!);
      _currentlyCachingSong = null;
    }

    // 2. Alur: resolveStreamUrl(videoId) → cek cache → just_audio.setUrl → play → recordPlay
    try {
      File? cachedFile;
      if (_cacheService != null) {
        cachedFile = await _cacheService.getCached(song);
      } else if (song.cachedPath != null) {
        final f = File(song.cachedPath!);
        if (f.existsSync() && f.lengthSync() > 0) cachedFile = f;
      }

      if (cachedFile != null) {
        debugPrint('Memutar dari cache lokal offline: ${cachedFile.path}');
        await _player.setFilePath(cachedFile.path, initialPosition: initPos);
      } else {
        // Cek konektivitas terlebih dahulu (Fail-fast bila offline)
        bool isOffline = false;
        try {
          final connectivityResult = await _connectivity.checkConnectivity();
          isOffline = connectivityResult.isNotEmpty &&
              connectivityResult.every((r) => r == ConnectivityResult.none);
        } catch (connErr) {
          debugPrint('[AudioPlayerService] checkConnectivity skipped: $connErr');
        }
        if (isOffline) {
          debugPrint('[AudioPlayerService] Offline terdeteksi sebelum resolve stream.');
          throw AppException(
            'Tidak ada koneksi internet. Periksa WiFi/data seluler, lalu coba lagi.',
            const SocketException('Tidak ada koneksi internet (ConnectivityResult.none)'),
          );
        }

        debugPrint(
            'Cache miss. Me-resolve stream YouTube audio untuk videoId: ${song.videoId}');

        final stream = await _youTubeService.resolveStreamUrl(song.videoId);

        final audioSource = YouTubeAudioSource(
          uri: stream.url,
          headers: stream.headers,
          totalBytes: stream.totalBytes,
          contentType: stream.contentType,
          tag: song,
          videoId: song.videoId,
          onReResolveUrl: () async {
            final reStream = await _youTubeService.resolveStreamUrl(song.videoId);
            return (url: reStream.url, headers: reStream.headers);
          },
        );

        await _player.setAudioSource(audioSource, initialPosition: initPos);

        // Cek pengaturan auto_cache_enabled (default: false untuk menghemat kuota)
        final settingsBox =
            Hive.isBoxOpen(BOX_SETTINGS) ? Hive.box(BOX_SETTINGS) : null;
        final autoCacheEnabled = (settingsBox?.get('auto_cache_enabled',
                defaultValue: false) as bool?) ??
            false;

        // Batasi auto-cache: HANYA bila diaktifkan pengguna DAN durasi <= 15 menit
        if (autoCacheEnabled && song.durationMs <= 15 * 60 * 1000) {
          if (_cacheService != null) {
            _currentlyCachingSong = song;
            unawaited(_cacheService
                .cacheSong(song, stream.url, headers: stream.headers)
                .then((_) {
              if (_currentlyCachingSong?.videoId == song.videoId) {
                _currentlyCachingSong = null;
              }
            }).catchError((e) {
              debugPrint('Background auto-cache dilewati: $e');
              if (_currentlyCachingSong?.videoId == song.videoId) {
                _currentlyCachingSong = null;
              }
            }));
          }
        } else {
          if (!autoCacheEnabled) {
            debugPrint(
                'Auto-cache dilewati: Pengaturan hemat data aktif (hanya streaming porsi yang didengar).');
          } else {
            debugPrint(
                'Auto-cache dilewati untuk kompilasi panjang (durasi: ${song.durationMs}ms > 15 menit)');
          }
        }

        // Catat pemakaian data streaming (per pemutaran baru, dari totalBytes stream)
        try {
          recordDataUsage(stream.totalBytes);
        } catch (e) {
          debugPrint('[AudioPlayerService] recordDataUsage error: $e');
        }
        debugPrint(
            'Berhasil memuat stream videoId: ${song.videoId} menggunakan klien: ${stream.clientName}');
      }

      await _player.play();
      _consecutiveFailures = 0;
      _playbackError = null;
      await _recordPlay(song);
    } catch (e) {
      // CLEANUP SAAT GAGAL TOTAL:
      // 1. Reset just_audio dari state loading/error yang nyangkut
      try {
        await _player.stop();
      } catch (stopErr) {
        debugPrint('AudioPlayerService: Error saat _player.stop(): $stopErr');
      }

      // 2. Turunkan notifikasi foreground & update playback state ke idle
      _audioHandler.updatePlaybackState(
        isPlaying: false,
        position: Duration.zero,
        duration: Duration.zero,
        processingState: ProcessingState.idle,
      );

      // 3. Batalkan auto-cache yang mungkin sedang berjalan untuk lagu ini
      if (_cacheService != null) {
        try {
          await _cacheService.cancelCache(song);
        } catch (cancelErr) {
          debugPrint('AudioPlayerService: Gagal batalkan auto-cache: $cancelErr');
        }
      }

      // 4. Klasifikasi error berdasarkan tipe
      final classifiedError = classifyPlaybackError(e, songTitle: song.title);
      _playbackError = classifiedError;
      _consecutiveFailures++;
      _emitState();

      debugPrint(
          '[AudioPlayerService] Lagu "${song.title}" (${song.videoId}) gagal diputar: $classifiedError (gagal beruntun: $_consecutiveFailures/3)');

      // 5. Batasi: bila 3 lagu BERUNTUN gagal, BERHENTI dan tampilkan error terakhir saja
      if (_consecutiveFailures >= 3) {
        debugPrint(
            '[AudioPlayerService] 3 lagu beruntun gagal diputar. Menghentikan antrean pemutaran.');
        throw AppException(classifiedError, e);
      }

      // 6. Lanjut otomatis ke lagu berikut di antrean (panggil next() internal)
      final hasNext = _currentIndex < _queue.length - 1 ||
          (_repeatMode == RepeatMode.all && _queue.isNotEmpty) ||
          (_isAutoMix && _queue.isNotEmpty);

      if (hasNext) {
        debugPrint(
            '[AudioPlayerService] Auto-skip ke lagu berikutnya di antrean...');
        await Future.delayed(const Duration(milliseconds: 300));
        await next();
      } else {
        throw AppException(classifiedError, e);
      }
    }
  }

  @override
  Future<void> togglePlayPause() async {
    if (_player.playing) {
      saveCurrentPosition();
      await _player.pause();
    } else {
      if (_currentSong != null) {
        await _player.play();
      } else if (_queue.isNotEmpty) {
        _currentIndex = 0;
        await _playTrackAtCurrentIndex();
      }
    }
  }

  @override
  Future<void> next() async {
    if (_queue.isEmpty) return;
    saveCurrentPosition();

    if (_repeatMode == RepeatMode.one) {
      await seek(Duration.zero);
      await _player.play();
      return;
    }

    // Bila ada chapters dan belum di chapter terakhir, lompat ke chapter berikutnya
    if (_chapters.isNotEmpty && _chapterIndex < _chapters.length - 1) {
      final nextChapter = _chapters[_chapterIndex + 1];
      await seek(Duration(milliseconds: nextChapter.positionMs));
      _chapterIndex++;
      _emitState();
      return;
    }

    if (_shuffle && _queue.length > 1) {
      int nextIdx;
      do {
        nextIdx = Random().nextInt(_queue.length);
      } while (nextIdx == _currentIndex && _queue.length > 1);
      _currentIndex = nextIdx;
    } else if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
    } else if (_repeatMode == RepeatMode.all) {
      _currentIndex = 0;
    } else if (_isAutoMix && _currentSong != null) {
      // Endless Autoplay: muat lagu terkait berikutnya saat user tap next di akhir antrean
      final more = await _youTubeService.getRelatedSongs(_currentSong!.videoId, limit: 15);
      final existingIds = _queue.map((s) => s.videoId).toSet();
      final fresh = more.where((s) => !existingIds.contains(s.videoId)).toList();
      if (fresh.isNotEmpty) {
        _queue.addAll(fresh);
        _currentIndex++;
        _emitState();
        await _playTrackAtCurrentIndex();
        return;
      }
      return;
    } else {
      return;
    }

    await _playTrackAtCurrentIndex();
  }

  @override
  Future<void> previous() async {
    if (_queue.isEmpty) return;
    saveCurrentPosition();

    // Bila ada chapters:
    // bila chapterIndex > 0 -> mundur satu chapter
    // bila chapterIndex == 0: jika posisi saat ini > 3 detik, lompat ke awal track (0);
    // jika <= 3 detik, lanjut ke lagu sebelumnya di antrean (perilaku lama).
    if (_chapters.isNotEmpty && _chapterIndex > 0) {
      final prevChapter = _chapters[_chapterIndex - 1];
      await seek(Duration(milliseconds: prevChapter.positionMs));
      _chapterIndex--;
      _emitState();
      return;
    } else if (_chapters.isNotEmpty && _chapterIndex == 0) {
      if (_player.position > const Duration(seconds: 3)) {
        await seek(Duration.zero);
        return;
      }
    } else if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await _playTrackAtCurrentIndex();
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
      if (_chapters.isNotEmpty) {
        _chapterIndex = _findChapterIndex(position, _chapters);
        _emitState();
      }
    } catch (e) {
      debugPrint(
          'Error saat seek: $e. Mencoba memulihkan pemutaran pada posisi $position...');
      if (_currentSong != null) {
        try {
          final freshStream = await _youTubeService.resolveStreamUrl(
            _currentSong!.videoId,
          );
          final audioSource = YouTubeAudioSource(
            uri: freshStream.url,
            headers: freshStream.headers,
            totalBytes: freshStream.totalBytes,
            contentType: freshStream.contentType,
            tag: _currentSong,
            videoId: _currentSong!.videoId,
            onReResolveUrl: () async {
              final reStream = await _youTubeService.resolveStreamUrl(
                _currentSong!.videoId,
              );
              return (url: reStream.url, headers: reStream.headers);
            },
          );
          await _player.setAudioSource(audioSource, initialPosition: position);
          await _player.play();
          if (_chapters.isNotEmpty) {
            _chapterIndex = _findChapterIndex(position, _chapters);
            _emitState();
          }
        } catch (_) {
          throw AppException('Gagal mempercepat lagu: $e', e);
        }
      } else {
        throw AppException('Gagal mempercepat lagu: $e', e);
      }
    }
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    _shuffle = enabled;
    _emitState();
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    _repeatMode = mode;
    _emitState();
  }

  @override
  Future<void> addToQueueNext(Song song) async {
    if (_queue.isEmpty) {
      _queue.add(song);
      _currentIndex = 0;
    } else {
      _queue.insert(_currentIndex + 1, song);
    }
    _emitState();
  }

  // Helper manajemen antrean (Fase 2)
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex > _queue.length) return;

    final song = _queue.removeAt(oldIndex);
    if (newIndex > oldIndex) {
      _queue.insert(newIndex - 1, song);
    } else {
      _queue.insert(newIndex, song);
    }

    if (_currentIndex == oldIndex) {
      _currentIndex = (newIndex > oldIndex) ? newIndex - 1 : newIndex;
    } else if (oldIndex < _currentIndex && newIndex > _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    _emitState();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;

    if (index == _currentIndex) {
      if (_queue.length == 1) {
        _player.stop();
        _audioHandler.clearMediaItem();
        _queue.clear();
        _currentIndex = -1;
        _currentSong = null;
        _emitState();
      } else {
        final nextIdx =
            (_currentIndex < _queue.length - 1) ? _currentIndex + 1 : 0;
        final nextSong = _queue[nextIdx];
        _queue.removeAt(index);
        _currentIndex = _queue.indexOf(nextSong);
        _playTrackAtCurrentIndex();
      }
    } else {
      if (index < _currentIndex) {
        _currentIndex--;
      }
      _queue.removeAt(index);
      if (_queue.isEmpty) {
        _player.stop();
        _audioHandler.clearMediaItem();
        _currentIndex = -1;
        _currentSong = null;
      }
      _emitState();
    }
  }

  void clearQueue() {
    if (_currentlyCachingSong != null) {
      _cacheService?.cancelCache(_currentlyCachingSong!);
      _currentlyCachingSong = null;
    }
    _player.stop();
    _audioHandler.clearMediaItem();
    _queue.clear();
    _currentIndex = -1;
    _currentSong = null;
    _isAutoMix = false;
    _mixSeedTitle = null;
    _emitState();
  }

  // Sleep Timer (Fase 4)
  void setSleepTimer(Duration? duration, {bool afterCurrentTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAfterCurrentTrack = afterCurrentTrack;

    if (afterCurrentTrack) {
      _sleepTimerEndTime = null;
    } else if (duration != null) {
      _sleepTimerEndTime = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        _player.pause();
        cancelSleepTimer();
      });
    } else {
      _sleepTimerEndTime = null;
    }

    _emitState();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAfterCurrentTrack = false;
    _sleepTimerEndTime = null;
    _emitState();
  }

  Future<void> _recordPlay(Song song) async {
    try {
      if (_libraryService != null) {
        await _libraryService.recordPlay(song);
      } else {
        final historyBox = Hive.box<HistoryEntry>(BOX_HISTORY);
        await historyBox.add(
          HistoryEntry(
            videoId: song.videoId,
            playedAt: DateTime.now(),
          ),
        );

        while (historyBox.length > MAX_HISTORY_ENTRIES) {
          await historyBox.deleteAt(0);
        }
      }
    } catch (e) {
      debugPrint('Gagal mencatat riwayat pemutaran: $e');
    }
  }

  void dispose() {
    saveCurrentPosition();
    _sleepTimer?.cancel();
    _playerStateSub?.cancel();
    _playbackEventSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _processingStateSub?.cancel();
    _player.dispose();
    if (!_stateController.isClosed) {
      _stateController.close();
    }
  }
}
