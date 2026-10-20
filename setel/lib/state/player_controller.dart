import 'dart:async';

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

  const PlayerControllerState({
    this.currentSong,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.shuffle = false,
    this.repeatMode = RepeatMode.off,
  });

  PlayerControllerState copyWith({
    Song? currentSong,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<Song>? queue,
    bool? shuffle,
    RepeatMode? repeatMode,
  }) {
    return PlayerControllerState(
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      shuffle: shuffle ?? this.shuffle,
      repeatMode: repeatMode ?? this.repeatMode,
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
      state = PlayerControllerState(
        currentSong: playerState.currentSong,
        isPlaying: playerState.isPlaying,
        position: playerState.position,
        duration: playerState.duration,
        queue: playerState.queue,
        shuffle: playerState.shuffle,
        repeatMode: playerState.repeatMode,
      );
    });

    ref.onDispose(() {
      _subscription?.cancel();
    });

    return const PlayerControllerState();
  }

  Future<void> playSong(Song song) => _audioPlayerService.playSong(song);

  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) =>
      _audioPlayerService.playQueue(songs, startIndex: startIndex);

  Future<void> togglePlayPause() => _audioPlayerService.togglePlayPause();

  Future<void> next() => _audioPlayerService.next();

  Future<void> previous() => _audioPlayerService.previous();

  Future<void> seek(Duration position) => _audioPlayerService.seek(position);

  Future<void> setShuffle(bool enabled) =>
      _audioPlayerService.setShuffle(enabled);

  Future<void> setRepeatMode(RepeatMode mode) =>
      _audioPlayerService.setRepeatMode(mode);

  Future<void> addToQueueNext(Song song) =>
      _audioPlayerService.addToQueueNext(song);
}
