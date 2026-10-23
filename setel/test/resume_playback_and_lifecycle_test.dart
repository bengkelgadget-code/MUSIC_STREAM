import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:setel/core/constants.dart';
import 'package:setel/models/history_entry.dart';
import 'package:setel/models/playlist.dart';
import 'package:setel/models/song.dart';
import 'package:setel/services/audio_handler.dart';
import 'package:setel/services/library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('setel_resume_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(SongAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PlaylistAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(HistoryEntryAdapter());

    await Hive.openBox<Song>(BOX_SONGS);
    await Hive.openBox<Playlist>(BOX_PLAYLISTS);
    await Hive.openBox<String>(BOX_FAVORITES);
    await Hive.openBox<HistoryEntry>(BOX_HISTORY);
    await Hive.openBox<int>(BOX_PLAY_COUNTS);
    await Hive.openBox<int>(BOX_PLAYBACK_POSITIONS);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HistoryEntry Model & Adapter Tests', () {
    test('HistoryEntry instantiates with default lastPositionMs = 0', () {
      final now = DateTime.now();
      final entry = HistoryEntry(videoId: 'v1', playedAt: now);
      expect(entry.videoId, 'v1');
      expect(entry.playedAt, now);
      expect(entry.lastPositionMs, 0);
    });

    test('HistoryEntry instantiates with specified lastPositionMs and copyWith works', () {
      final now = DateTime.now();
      final entry = HistoryEntry(videoId: 'v2', playedAt: now, lastPositionMs: 125000);
      expect(entry.lastPositionMs, 125000);

      final updated = entry.copyWith(lastPositionMs: 250000);
      expect(updated.videoId, 'v2');
      expect(updated.lastPositionMs, 250000);
      expect(entry.lastPositionMs, 125000);
    });

    test('HistoryEntryAdapter serializes and deserializes lastPositionMs correctly', () async {
      final box = Hive.box<HistoryEntry>(BOX_HISTORY);
      final now = DateTime.now();
      final entry = HistoryEntry(videoId: 'test_save_pos', playedAt: now, lastPositionMs: 98765);
      await box.put('entry_key', entry);

      final loaded = box.get('entry_key');
      expect(loaded, isNotNull);
      expect(loaded!.videoId, 'test_save_pos');
      expect(loaded.lastPositionMs, 98765);
    });
  });

  group('LibraryService Playback Position & History Tests', () {
    late LibraryServiceImpl libService;

    setUp(() {
      libService = LibraryServiceImpl();
    });

    test('savePlaybackPosition and getPlaybackPosition work accurately', () async {
      const vid = 'vid_pos_123';
      expect(await libService.getPlaybackPosition(vid), 0);

      await libService.savePlaybackPosition(vid, 75432);
      expect(await libService.getPlaybackPosition(vid), 75432);

      await libService.savePlaybackPosition(vid, 120000);
      expect(await libService.getPlaybackPosition(vid), 120000);
    });

    test('recordPlay saves entry with lastPositionMs and updates on savePlaybackPosition', () async {
      const song = Song(
        videoId: 'song_hist_test',
        title: 'Song Hist Test',
        artist: 'Artist',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        durationMs: 300000,
      );

      // Save position first (e.g. user was playing)
      await libService.savePlaybackPosition(song.videoId, 45000);
      await libService.recordPlay(song);

      final history = await libService.getHistory();
      final match = history.firstWhere((h) => h.videoId == song.videoId);
      expect(match.lastPositionMs, 45000);

      // Now user continues listening to 60000ms
      await libService.savePlaybackPosition(song.videoId, 60000);
      final historyUpdated = await libService.getHistory();
      final matchUpdated = historyUpdated.firstWhere((h) => h.videoId == song.videoId);
      expect(matchUpdated.lastPositionMs, 60000);
    });
  });

  group('SetelAudioHandler Lifecycle & Task Removal Tests', () {
    test('SetelAudioHandler.updatePlaybackState includes stop control and action', () {
      final handler = SetelAudioHandler();
      handler.setMediaItemInfo(
        id: 'vid_dummy',
        title: 'Title',
        artist: 'Artist',
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );
      handler.updatePlaybackState(
        isPlaying: true,
        position: const Duration(seconds: 15),
        duration: const Duration(minutes: 3),
        processingState: ProcessingState.ready,
      );

      final state = handler.playbackState.value;
      expect(state.controls.contains(MediaControl.stop), isTrue);
      expect(state.systemActions.contains(MediaAction.stop), isTrue);
    });

    test('SetelAudioHandler.stop triggers onStopCallback and clears mediaItem', () async {
      final handler = SetelAudioHandler();
      bool stopCalled = false;
      handler.onStopCallback = () {
        stopCalled = true;
      };

      handler.setMediaItemInfo(
        id: 'vid_stop',
        title: 'Title',
        artist: 'Artist',
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );
      expect(handler.mediaItem.value, isNotNull);

      await handler.stop();
      expect(stopCalled, isTrue);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    });

    test('SetelAudioHandler.onTaskRemoved invokes stop and cleanly terminates', () async {
      final handler = SetelAudioHandler();
      bool stopCalled = false;
      handler.onStopCallback = () {
        stopCalled = true;
      };

      await handler.onTaskRemoved();
      expect(stopCalled, isTrue);
      expect(handler.mediaItem.value, isNull);
    });
  });
}
