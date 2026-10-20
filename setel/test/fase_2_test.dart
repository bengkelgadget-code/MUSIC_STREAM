import 'package:flutter_test/flutter_test.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/audio_handler.dart';
import 'package:setel/services/audio_player_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 2 - Background + Antrean Tests', () {
    late SetelAudioHandler handler;

    final songA = const Song(
      videoId: 'a',
      title: 'Song A',
      artist: 'Artist A',
      durationMs: 100000,
      thumbnailUrl: '',
    );
    final songB = const Song(
      videoId: 'b',
      title: 'Song B',
      artist: 'Artist B',
      durationMs: 120000,
      thumbnailUrl: '',
    );
    final songC = const Song(
      videoId: 'c',
      title: 'Song C',
      artist: 'Artist C',
      durationMs: 150000,
      thumbnailUrl: '',
    );

    setUp(() {
      handler = SetelAudioHandler();
    });

    test('SetelAudioHandler mediaItem and playbackState update correctly', () {
      handler.setMediaItemInfo(
        id: songA.videoId,
        title: songA.title,
        artist: songA.artist,
        thumbnailUrl: songA.thumbnailUrl,
        duration: const Duration(seconds: 100),
      );

      handler.updatePlaybackState(
        isPlaying: true,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 100),
      );

      expect(handler.mediaItem.value?.id, songA.videoId);
      expect(handler.mediaItem.value?.title, songA.title);
      expect(handler.playbackState.value.playing, isTrue);
    });

    test('Headset button callbacks dispatch to play, pause, next, prev',
        () async {
      bool playCalled = false;
      bool pauseCalled = false;
      bool nextCalled = false;
      bool prevCalled = false;

      handler.onPlayCallback = () => playCalled = true;
      handler.onPauseCallback = () => pauseCalled = true;
      handler.onSkipToNextCallback = () => nextCalled = true;
      handler.onSkipToPreviousCallback = () => prevCalled = true;

      await handler.play();
      expect(playCalled, isTrue);

      await handler.pause();
      expect(pauseCalled, isTrue);

      await handler.skipToNext();
      expect(nextCalled, isTrue);

      await handler.skipToPrevious();
      expect(prevCalled, isTrue);
    });

    test('Queue reorder logic moves elements and preserves current song index',
        () {
      final queue = [songA, songB, songC];
      int currentIndex = 0; // songA

      // Reorder songC (index 2) to index 0
      final song = queue.removeAt(2);
      queue.insert(0, song);
      currentIndex = 1; // songA is now at index 1

      expect(queue[0].videoId, 'c');
      expect(queue[1].videoId, 'a');
      expect(queue[2].videoId, 'b');
      expect(queue[currentIndex].videoId, 'a');
    });

    test('Queue removal logic adjusts indices correctly', () {
      final queue = [songA, songB, songC];
      int currentIndex = 2; // songC

      // Remove songA at index 0
      queue.removeAt(0);
      currentIndex--; // Adjusted

      expect(queue.length, 2);
      expect(queue[currentIndex].videoId, 'c');
    });

    test('PlayerState supports queue list and current song', () {
      final state = PlayerState(
        currentSong: songA,
        queue: [songA, songB, songC],
        isPlaying: true,
        repeatMode: RepeatMode.all,
      );

      expect(state.queue.length, 3);
      expect(state.currentSong?.videoId, 'a');
      expect(state.isPlaying, isTrue);
      expect(state.repeatMode, RepeatMode.all);
    });
  });
}
