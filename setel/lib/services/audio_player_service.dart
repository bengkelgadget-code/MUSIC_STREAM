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
import 'audio_handler.dart';
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

  const PlayerState({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.currentSong,
    this.queue = const [],
    this.shuffle = false,
    this.repeatMode = RepeatMode.off,
  });

  PlayerState copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    Song? currentSong,
    List<Song>? queue,
    bool? shuffle,
    RepeatMode? repeatMode,
  }) {
    return PlayerState(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      currentSong: currentSong ?? this.currentSong,
      queue: queue ?? this.queue,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }
}

abstract class AudioPlayerService {
  /// Alur: resolveStreamUrl(videoId) → cek cache → just_audio.setUrl → play → recordPlay.
  Future<void> playSong(Song song);
  Future<void> playQueue(List<Song> songs, {int startIndex = 0});
  Future<void> togglePlayPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> addToQueueNext(Song song); // "play next"

  Stream<PlayerState>
      get playerState; // isPlaying, position, currentSong, queue, shuffle, repeatMode
}

class AudioPlayerServiceImpl implements AudioPlayerService {
  final AudioPlayer _player;
  final YouTubeService _youTubeService;
  final SetelAudioHandler _audioHandler;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();

  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _shuffle = false;
  RepeatMode _repeatMode = RepeatMode.off;
  Song? _currentSong;

  AudioPlayerServiceImpl({
    AudioPlayer? player,
    required YouTubeService youTubeService,
    required SetelAudioHandler audioHandler,
  })  : _player = player ?? AudioPlayer(),
        _youTubeService = youTubeService,
        _audioHandler = audioHandler {
    _initListeners();
    _connectAudioHandler();
  }

  void _initListeners() {
    _player.playerStateStream.listen((state) {
      _emitState();
      _audioHandler.updatePlaybackState(
        isPlaying: state.playing,
        position: _player.position,
        duration: _player.duration ?? Duration.zero,
        isBuffering: state.processingState == ProcessingState.buffering,
      );
    });

    _player.positionStream.listen((pos) {
      _emitState();
    });

    _player.durationStream.listen((dur) {
      _emitState();
    });

    _player.processingStateStream.listen((processingState) {
      if (processingState == ProcessingState.completed) {
        _handleTrackEnded();
      }
    });
  }

  void _connectAudioHandler() {
    _audioHandler.onPlayCallback = () => _player.play();
    _audioHandler.onPauseCallback = () => _player.pause();
    _audioHandler.onSkipToNextCallback = () => next();
    _audioHandler.onSkipToPreviousCallback = () => previous();
    _audioHandler.onSeekCallback = (position) => seek(position);
  }

  void _emitState() {
    final state = PlayerState(
      isPlaying: _player.playing,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
      currentSong: _currentSong,
      queue: List.unmodifiable(_queue),
      shuffle: _shuffle,
      repeatMode: _repeatMode,
    );
    _stateController.add(state);
  }

  Future<void> _handleTrackEnded() async {
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
  }

  @override
  Stream<PlayerState> get playerState => _stateController.stream;

  @override
  Future<void> playSong(Song song) async {
    // Sesuai catatan auditor: playSong() me-reset antrean menjadi hanya [song]
    _queue = [song];
    _currentIndex = 0;
    _currentSong = song;
    _emitState();

    await _playTrackAtCurrentIndex();
  }

  @override
  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;

    // Jika antrean yang dikirim sama persis (misal dari queue_sheet), cukup update index
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
    _emitState();

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

    // 2. Alur: resolveStreamUrl(videoId) → cek cache → just_audio.setUrl → play → recordPlay
    try {
      if (song.cachedPath != null && File(song.cachedPath!).existsSync()) {
        debugPrint('Memutar dari cache lokal: ${song.cachedPath}');
        await _player.setFilePath(song.cachedPath!);
      } else {
        debugPrint('Me-resolve stream YouTube untuk videoId: ${song.videoId}');
        final streamUri =
            await _youTubeService.resolveStreamUrl(song.videoId);
        await _player.setUrl(streamUri.toString());
      }

      await _player.play();
      await _recordPlay(song);
    } catch (e) {
      throw AppException('Gagal memutar lagu: $e', e);
    }
  }

  @override
  Future<void> togglePlayPause() async {
    if (_player.playing) {
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

    if (_repeatMode == RepeatMode.one) {
      await seek(Duration.zero);
      await _player.play();
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

    if (_player.position > const Duration(seconds: 3)) {
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
    await _player.seek(position);
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

    // Koreksi index lagu yang sedang diputar
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
        _player.pause();
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
      _emitState();
    }
  }

  void clearQueue() {
    _player.pause();
    _queue.clear();
    _currentIndex = -1;
    _currentSong = null;
    _emitState();
  }

  Future<void> _recordPlay(Song song) async {
    try {
      final historyBox = Hive.box<HistoryEntry>(BOX_HISTORY);
      await historyBox.add(
        HistoryEntry(
          videoId: song.videoId,
          playedAt: DateTime.now(),
        ),
      );

      // FIFO maks 50 entri sesuai §4.3
      while (historyBox.length > MAX_HISTORY_ENTRIES) {
        await historyBox.deleteAt(0);
      }
    } catch (e) {
      debugPrint('Gagal mencatat riwayat pemutaran: $e');
    }
  }

  void dispose() {
    _player.dispose();
    _stateController.close();
  }
}
