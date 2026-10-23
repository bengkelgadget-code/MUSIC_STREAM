import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';
import '../models/history_entry.dart';
import '../models/playlist.dart';
import '../models/search_cache.dart';
import '../models/settings.dart';
import '../models/song.dart';

class HiveInit {
  static Future<void> init() async {
    await Hive.initFlutter();

    // Register all adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SongAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PlaylistAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(HistoryEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(SearchCacheAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(SettingsAdapter());
    }

    // Open required boxes
    await Hive.openBox<Song>(BOX_SONGS);
    await Hive.openBox<Playlist>(BOX_PLAYLISTS);
    await Hive.openBox<String>(BOX_FAVORITES);
    final historyBox = await Hive.openBox<HistoryEntry>(BOX_HISTORY);
    await Hive.openBox<SearchCache>(BOX_SEARCH_CACHE);
    await Hive.openBox(BOX_SETTINGS);
    final playCountsBox = await Hive.openBox<int>(BOX_PLAY_COUNTS);
    await Hive.openBox(BOX_SONG_CHAPTERS);
    await Hive.openBox(BOX_DISCOVERY_CONFIG);
    await Hive.openBox<int>(BOX_PLAYBACK_POSITIONS);

    // Migrasi sekali jalan: jika play_counts kosong dan history ada data,
    // hitung jumlah kemunculan tiap videoId dan isi play_counts.
    if (playCountsBox.isEmpty && historyBox.isNotEmpty) {
      final counts = <String, int>{};
      for (final entry in historyBox.values) {
        counts[entry.videoId] = (counts[entry.videoId] ?? 0) + 1;
      }
      for (final entry in counts.entries) {
        await playCountsBox.put(entry.key, entry.value);
      }
      debugPrint(
          'Migrasi play_counts dari BOX_HISTORY selesai: ${counts.length} lagu dihitung.');
    }

    debugPrint('Hive initialized and all boxes opened successfully.');
  }
}
