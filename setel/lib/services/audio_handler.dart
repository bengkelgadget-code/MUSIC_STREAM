import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

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

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    ProcessingState? processingState,
  }) {
    final effectiveState = processingState ??
        (isPlaying ? ProcessingState.ready : ProcessingState.idle);
    playbackState.add(
      playbackState.value.copyWith(
        controls: mediaItem.value == null
            ? const []
            : [
                MediaControl.skipToPrevious,
                isPlaying ? MediaControl.pause : MediaControl.play,
                MediaControl.skipToNext,
              ],
        systemActions: mediaItem.value == null
            ? const {}
            : const {
                MediaAction.seek,
                MediaAction.seekForward,
                MediaAction.seekBackward,
              },
        androidCompactActionIndices:
            mediaItem.value == null ? const [] : const [0, 1, 2],
        processingState: _mapProcessingState(effectiveState),
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

  void clearMediaItem() {
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        systemActions: const {},
        androidCompactActionIndices: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState.value.playing) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
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
      androidNotificationIcon: 'drawable/ic_stat_music',
      androidShowNotificationBadge: true,
    ),
  );

  _globalAudioHandler = handler;
  debugPrint('AudioService initialized successfully.');
  return handler;
}
