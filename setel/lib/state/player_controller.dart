import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../models/song_chapter.dart';
import '../services/audio_player_service.dart';
import 'providers.dart';

class PlayerControllerState {
  final Song? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<Song> queue;
  final bool shuffle;
  final RepeatMode repeatMode;
  final DateTime? sleepTimerEndTime;
  final bool sleepAfterCurrentTrack;
  final String? playbackError;
  final List<SongChapter> chapters;
  final int chapterIndex;

  const PlayerControllerState({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.shuffle = false,
    this.repeatMode = RepeatMode.off,
    this.sleepTimerEndTime,
    this.sleepAfterCurrentTrack = false,
    this.playbackError,
    this.chapters = const [],
    this.chapterIndex = -1,
  });

  bool get hasChapters => chapters.length >= 2;
  SongChapter? get currentChapter =>
      (hasChapters && chapterIndex >= 0 && chapterIndex < chapters.length)
          ? chapters[chapterIndex]
          : null;

  PlayerControllerState copyWith({
    Song? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<Song>? queue,
    bool? shuffle,
    RepeatMode? repeatMode,
    DateTime? sleepTimerEndTime,
    bool? sleepAfterCurrentTrack,
    bool clearSleepTimer = false,
    String? playbackError,
    bool clearPlaybackError = false,
    List<SongChapter>? chapters,
    int? chapterIndex,
  }) {
    return PlayerControllerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      sleepTimerEndTime: clearSleepTimer
          ? null
          : (sleepTimerEndTime ?? this.sleepTimerEndTime),
      sleepAfterCurrentTrack: clearSleepTimer
          ? false
          : (sleepAfterCurrentTrack ?? this.sleepAfterCurrentTrack),
      playbackError: clearPlaybackError
          ? null
          : (playbackError ?? this.playbackError),
      chapters: chapters ?? this.chapters,
      chapterIndex: chapterIndex ?? this.chapterIndex,
    );
  }
}

class PlayerController extends Notifier<PlayerControllerState> {
  late final AudioPlayerService _audioPlayerService;
  StreamSubscription<PlayerState>? _subscription;

  @override
  PlayerControllerState build() {
    _audioPlayerService = ref.watch(audioPlayerServiceProvider);

    _subscription?.cancel();
    _subscription = _audioPlayerService.playerState.listen((playerState) {
      state = state.copyWith(
        currentSong: playerState.currentSong,
        isPlaying: playerState.isPlaying,
        position: playerState.position,
        duration: playerState.duration,
        queue: playerState.queue,
        shuffle: playerState.shuffle,
        repeatMode: playerState.repeatMode,
        sleepTimerEndTime: playerState.sleepTimerEndTime,
        sleepAfterCurrentTrack: playerState.sleepAfterCurrentTrack,
        clearSleepTimer: playerState.sleepTimerEndTime == null &&
            !playerState.sleepAfterCurrentTrack,
        chapters: playerState.chapters,
        chapterIndex: playerState.chapterIndex,
      );
    });

    ref.onDispose(() {
      _subscription?.cancel();
    });

    return const PlayerControllerState();
  }

  void clearPlaybackError() {
    if (state.playbackError != null) {
      state = state.copyWith(clearPlaybackError: true);
    }
  }

  String _formatErrorMessage(Object error) {
    final str = error.toString();
    if (str.contains('403') ||
        str.contains('Forbidden') ||
        str.contains('server menolak akses stream')) {
      return 'Gagal memutar lagu: server menolak akses stream (kemungkinan proteksi bot di jaringan ini).';
    } else if (str.contains('SocketException') ||
        str.contains('Failed host lookup') ||
        str.contains('ClientException')) {
      return 'Gagal memutar lagu: Periksa koneksi internet Anda.';
    } else if (str.contains('RequestLimitExceededException') ||
        str.contains('rate limiting')) {
      return 'Gagal memutar lagu: Batas permintaan YouTube tercapai. Coba beberapa saat lagi.';
    } else if (str.contains('TimeoutException')) {
      return 'Gagal memutar lagu: Waktu koneksi habis.';
    } else if (str.contains('bot') || str.contains('Sign in to confirm')) {
      return 'Gagal memutar lagu: server menolak akses stream (kemungkinan proteksi bot di jaringan ini).';
    }
    return 'Gagal memutar lagu: tidak dapat mengambil data stream.';
  }

  Future<void> playSong(Song song) async {
    try {
      await _audioPlayerService.playSong(song);
    } catch (e, st) {
      debugPrint('PlayerController.playSong error: $e\n$st');
      state = state.copyWith(playbackError: _formatErrorMessage(e));
    }
  }

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    try {
      await _audioPlayerService.playQueue(songs, startIndex: startIndex);
    } catch (e, st) {
      debugPrint('PlayerController.playQueue error: $e\n$st');
      state = state.copyWith(playbackError: _formatErrorMessage(e));
    }
  }

  Future<void> togglePlayPause() async {
    try {
      await _audioPlayerService.togglePlayPause();
    } catch (e, st) {
      debugPrint('PlayerController.togglePlayPause error: $e\n$st');
      state = state.copyWith(playbackError: _formatErrorMessage(e));
    }
  }

  Future<void> next() async {
    try {
      await _audioPlayerService.next();
    } catch (e, st) {
      debugPrint('PlayerController.next error: $e\n$st');
      state = state.copyWith(playbackError: _formatErrorMessage(e));
    }
  }

  Future<void> previous() async {
    try {
      await _audioPlayerService.previous();
    } catch (e, st) {
      debugPrint('PlayerController.previous error: $e\n$st');
      state = state.copyWith(playbackError: _formatErrorMessage(e));
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _audioPlayerService.seek(position);
    } catch (e, st) {
      debugPrint('PlayerController.seek error: $e\n$st');
      state = state.copyWith(playbackError: _formatErrorMessage(e));
    }
  }

  Future<void> setShuffle(bool enabled) async {
    try {
      await _audioPlayerService.setShuffle(enabled);
    } catch (e, st) {
      debugPrint('PlayerController.setShuffle error: $e\n$st');
    }
  }

  Future<void> setRepeatMode(RepeatMode mode) async {
    try {
      await _audioPlayerService.setRepeatMode(mode);
    } catch (e, st) {
      debugPrint('PlayerController.setRepeatMode error: $e\n$st');
    }
  }

  Future<void> addToQueueNext(Song song) async {
    try {
      await _audioPlayerService.addToQueueNext(song);
    } catch (e, st) {
      debugPrint('PlayerController.addToQueueNext error: $e\n$st');
      state = state.copyWith(playbackError: _formatErrorMessage(e));
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    final service = _audioPlayerService;
    if (service is AudioPlayerServiceImpl) {
      service.reorderQueue(oldIndex, newIndex);
    }
  }

  void removeFromQueue(int index) {
    final service = _audioPlayerService;
    if (service is AudioPlayerServiceImpl) {
      service.removeFromQueue(index);
    }
  }

  void clearQueue() {
    final service = _audioPlayerService;
    if (service is AudioPlayerServiceImpl) {
      service.clearQueue();
    }
  }

  void setSleepTimer(Duration? duration, {bool afterCurrentTrack = false}) {
    final service = _audioPlayerService;
    if (service is AudioPlayerServiceImpl) {
      service.setSleepTimer(duration,
          afterCurrentTrack: afterCurrentTrack);
    }
  }

  void cancelSleepTimer() {
    final service = _audioPlayerService;
    if (service is AudioPlayerServiceImpl) {
      service.cancelSleepTimer();
    }
  }
}
