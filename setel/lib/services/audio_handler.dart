import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

class SetelAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  VoidCallback? onPlayCallback;
  VoidCallback? onPauseCallback;
  VoidCallback? onSkipToNextCallback;
  VoidCallback? onSkipToPreviousCallback;
  void Function(Duration position)? onSeekCallback;

  SetelAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    bool isBuffering = false,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : (isPlaying
                ? AudioProcessingState.ready
                : AudioProcessingState.idle),
        playing: isPlaying,
        updatePosition: position,
      ),
    );
  }

  void setMediaItemInfo({
    required String id,
    required String title,
    required String artist,
    required String thumbnailUrl,
    Duration? duration,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        artUri: Uri.tryParse(thumbnailUrl),
        duration: duration,
      ),
    );
  }

  @override
  Future<void> play() async {
    onPlayCallback?.call();
  }

  @override
  Future<void> pause() async {
    onPauseCallback?.call();
  }

  @override
  Future<void> skipToNext() async {
    onSkipToNextCallback?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipToPreviousCallback?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    onSeekCallback?.call(position);
  }
}

SetelAudioHandler? _globalAudioHandler;

SetelAudioHandler get globalAudioHandler {
  if (_globalAudioHandler == null) {
    throw StateError('AudioHandler has not been initialized yet');
  }
  return _globalAudioHandler!;
}

Future<SetelAudioHandler> initAudioService() async {
  if (_globalAudioHandler != null) return _globalAudioHandler!;
  final handler = await AudioService.init(
    builder: () => SetelAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bengkel.setel.channel.audio',
      androidNotificationChannelName: 'Setel Audio Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
  _globalAudioHandler = handler;
  debugPrint('AudioService initialized successfully: ${handler.runtimeType}');
  return handler;
}
