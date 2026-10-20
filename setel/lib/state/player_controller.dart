import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../services/audio_player_service.dart';

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
  @override
  PlayerControllerState build() => const PlayerControllerState();
}
