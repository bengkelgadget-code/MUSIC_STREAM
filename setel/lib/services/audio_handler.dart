import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

class SetelAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
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

  @override
  Future<void> play() async {
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
      ],
    ));
  }

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
    ));
  }

  @override
  Future<void> stop() async {
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await super.stop();
  }
}

Future<AudioHandler> initAudioService() async {
  final handler = await AudioService.init(
    builder: () => SetelAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bengkel.setel.channel.audio',
      androidNotificationChannelName: 'Setel Audio Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  debugPrint('AudioService initialized successfully: ${handler.runtimeType}');
  return handler;
}
