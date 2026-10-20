import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
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
  });

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
    if (str.contains('403') || str.contains('Forbidden')) {
      return 'Gagal memutar lagu: Akses stream YouTube dibatasi (403 Forbidden).';
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
      return 'Gagal memutar lagu: Dibatasi verifikasi bot YouTube.';
    }
    return 'Gagal memutar lagu: Terjadi kesalahan pemutaran.';
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
