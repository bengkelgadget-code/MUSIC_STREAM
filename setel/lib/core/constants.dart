import 'package:hive/hive.dart';

// ignore_for_file: constant_identifier_names

const String YOUTUBE_API_KEY = 'ISI_DI_SINI';
const int DEFAULT_CACHE_LIMIT_MB = 500;
const Duration SEARCH_CACHE_TTL = Duration(hours: 24);
const int MAX_HISTORY_ENTRIES = 50;

// Hive Box Names
const String BOX_SONGS = 'songs';
const String BOX_PLAYLISTS = 'playlists';
const String BOX_FAVORITES = 'favorites';
const String BOX_HISTORY = 'history';
const String BOX_SEARCH_CACHE = 'search_cache';
const String BOX_SETTINGS = 'settings';
const String BOX_PLAY_COUNTS = 'play_counts';
const String BOX_SONG_CHAPTERS = 'song_chapters';
const String BOX_DISCOVERY_CONFIG = 'discovery_config';
const String BOX_PLAYBACK_POSITIONS = 'playback_positions';

// Settings Keys
const String KEY_DATA_USED_BYTES = 'data_used_bytes';
const String KEY_CACHE_WIFI_ONLY = 'cache_wifi_only';

/// Catat akumulasi pemakaian data (streaming & cache) ke Hive box settings
void recordDataUsage(int bytes) {
  if (bytes <= 0) return;
  if (!Hive.isBoxOpen(BOX_SETTINGS)) return;
  final box = Hive.box(BOX_SETTINGS);
  final current = (box.get(KEY_DATA_USED_BYTES, defaultValue: 0) as int?) ?? 0;
  box.put(KEY_DATA_USED_BYTES, current + bytes);
}

