import 'dart:async';
import 'dart:io';
import 'dart:math';

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
    List<SongChapter>? chapters,
    int? chapterIndex,
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
    );
  }
}

abstract class AudioPlayerService {
  /// Alur: resolveStreamUrl(videoId) → cek cache → just_audio.setUrl → play → recordPlay.
  Future<void> playSong(Song song, {Duration? initialPosition});
  Future<void> playQueue(List<Song> songs, {int startIndex = 0, Duration? initialPosition});
  Future<void> togglePlayPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> addToQueueNext(Song song); // "play next"
  void saveCurrentPosition({bool resetToZero = false});

  Stream<PlayerState>
      get playerState; // isPlaying, position, currentSong, queue, shuffle, repeatMode
}

class AudioPlayerServiceImpl implements AudioPlayerService {
  final AudioPlayer _player;
  final YouTubeService _youTubeService;
  final SetelAudioHandler _audioHandler;
  final LibraryService? _libraryService;
  final CacheService? _cacheService;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  StreamSubscription? _playerStateSub;
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
  })  : _player = player ?? AudioPlayer(),
        _youTubeService = youTubeService,
        _audioHandler = audioHandler,
        _libraryService = libraryService,
        _cacheService = cacheService {
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
      try {
        await _player.stop();
      } catch (e) {
        debugPrint('AudioPlayerService onStopCallback error: $e');
      }
      _audioHandler.clearMediaItem();
      _queue.clear();
      _currentIndex = -1;
      _currentSong = null;
      _emitState();
    };
  }

  @override
  void saveCurrentPosition({bool resetToZero = false}) {
    final song = _currentSong;
    if (song == null || _libraryService == null) return;
    final posMs = resetToZero ? 0 : _player.position.inMilliseconds;
    if (!resetToZero && posMs < 2000) return;
    _libraryService.savePlaybackPosition(song.videoId, posMs);
    _lastPositionSaveTime = DateTime.now();
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
    );
    _stateController.add(state);
  }

  Future<void> _handleTrackEnded() async {
    try {
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
  Future<void> playSong(Song song, {Duration? initialPosition}) async {
    // Sesuai catatan auditor: playSong() me-reset antrean menjadi hanya [song]
    saveCurrentPosition();
    _pendingInitialPosition = initialPosition;
    _queue = [song];
    _currentIndex = 0;
    _currentSong = song;
    _emitState();

    await _playTrackAtCurrentIndex();
  }

  @override
  Future<void> playQueue(List<Song> songs, {int startIndex = 0, Duration? initialPosition}) async {
    if (songs.isEmpty) return;
    saveCurrentPosition();
    _pendingInitialPosition = initialPosition;

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
        debugPrint(
            'Cache miss. Me-resolve stream YouTube audio untuk videoId: ${song.videoId}');
        
        final clients = YouTubeServiceImpl.streamClients;
        final totalClients = clients.isNotEmpty ? clients.length : 1;
        bool playSuccess = false;
        Object? lastError;
        String lastClientName = 'unknown';
        bool allAre403 = true;
        int errorCount = 0;

        for (int attempt = 0; attempt < totalClients; attempt++) {
          final candidate = clients.isNotEmpty ? clients[attempt] : null;
          final candidateName = candidate?.name ?? 'klien_$attempt';
          lastClientName = candidateName;

          try {
            debugPrint(
                'Mencoba putar stream videoId: ${song.videoId} dengan klien: $candidateName (percobaan ${attempt + 1}/$totalClients)...');
            final stream = await _youTubeService.resolveStreamUrl(
              song.videoId,
              clientStartIndex: attempt,
            );
            lastClientName = stream.clientName;

            final audioSource = YouTubeAudioSource(
              uri: stream.url,
              headers: stream.headers,
              totalBytes: stream.totalBytes,
              contentType: stream.contentType,
              tag: song,
            );

            await _player.setAudioSource(audioSource, initialPosition: initPos);

            // Batasi auto-cache: JANGAN auto-cache di background bila durasi > 15 menit (kompilasi panjang)
            if (song.durationMs <= 15 * 60 * 1000) {
              if (_cacheService != null) {
                unawaited(_cacheService
                    .cacheSong(song, stream.url, headers: stream.headers)
                    .catchError((e) {
                  debugPrint('Background auto-cache dilewati: $e');
                  return File('');
                }));
              }
            } else {
              debugPrint(
                  'Auto-cache dilewati untuk kompilasi panjang (durasi: ${song.durationMs}ms > 15 menit)');
            }

            playSuccess = true;
            debugPrint(
                'Berhasil memuat stream videoId: ${song.videoId} menggunakan klien: ${stream.clientName}');
            break; // BERHENTI di klien pertama yang berhasil
          } catch (e) {
            errorCount++;
            lastError = e;
            final errStr = e.toString();
            final is403 =
                errStr.contains('403') || errStr.contains('Forbidden');
            if (!is403) {
              allAre403 = false;
            }
            debugPrint(
                'Klien $candidateName gagal memutar videoId: ${song.videoId} (error: $errStr). Melanjutkan ke klien berikutnya...');
          }
        }

        if (!playSuccess) {
          // Hanya bila SEMUA klien gagal, lempar AppException
          final isForbidden = (errorCount > 0 && allAre403);
          final errorMsg = isForbidden
              ? 'server menolak akses stream (kemungkinan proteksi bot di jaringan ini).'
              : 'tidak dapat mengambil data stream.';
          debugPrint(
              '[AudioPlayerService] Gagal total memutar videoId: ${song.videoId} di SEMUA klien. '
              'Klien terakhir: $lastClientName, Error terakhir: $lastError');
          throw AppException('Gagal memutar lagu: $errorMsg', lastError);
        }
      }

      await _player.play();
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

      // Emit state agar UI terupdate dan tidak stuck loading
      _emitState();

      if (e is AppException) {
        rethrow;
      }
      throw AppException('Gagal memutar lagu: $e', e);
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
            clientStartIndex: 1,
          );
          final audioSource = YouTubeAudioSource(
            uri: freshStream.url,
            headers: freshStream.headers,
            totalBytes: freshStream.totalBytes,
            contentType: freshStream.contentType,
            tag: _currentSong,
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
    _player.stop();
    _audioHandler.clearMediaItem();
    _queue.clear();
    _currentIndex = -1;
    _currentSong = null;
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
    _positionSub?.cancel();
    _durationSub?.cancel();
    _processingStateSub?.cancel();
    _player.dispose();
    if (!_stateController.isClosed) {
      _stateController.close();
    }
  }
}
