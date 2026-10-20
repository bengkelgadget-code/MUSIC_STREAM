import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../models/search_cache.dart';
import '../models/song.dart';

class AudioStreamResult {
  final Uri url;
  final Map<String, String> headers;
  final String clientName;

  const AudioStreamResult({
    required this.url,
    required this.headers,
    this.clientName = '',
  });

  @override
  String toString() =>
      'AudioStreamResult(client: $clientName, url: $url, headers: $headers)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioStreamResult &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          clientName == other.clientName;

  @override
  int get hashCode => url.hashCode ^ clientName.hashCode;
}

abstract class YouTubeService {
  /// Cari lagu via YouTube Data API v3. WAJIB cek SearchCache dulu (TTL 24 jam).
  /// 1x search = 100 unit kuota. Error kuota → AppException('Kuota API habis...').
  Future<List<Song>> search(String query);

  /// Resolve stream URL audio-only via youtube_explode_dart.
  /// Pilih audio-only dengan bitrate tertinggi. JANGAN simpan hasilnya ke DB.
  /// Mengambil manifest dari SATU klien per percobaan, urutan tangga:
  /// (a) YoutubeApiClient.androidVr, (b) YoutubeApiClient.ios, (c) YoutubeApiClient.tv.
  /// Mengembalikan (url, headers) berisi User-Agent sesuai klien yang menghasilkan URL tsb.
  Future<AudioStreamResult> resolveStreamUrl(
    String videoId, {
    int clientStartIndex = 0,
  });

  /// Metadata cadangan via iTunes Search API (tanpa key), dipakai jika perlu.
  Future<Song> fetchMetadata(String videoId);
}

class YouTubeServiceImpl implements YouTubeService {
  final Dio _dio;

  YouTubeServiceImpl({Dio? dio}) : _dio = dio ?? Dio();

  @override
  Future<List<Song>> search(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    // 1. WAJIB cek SearchCache dulu (TTL 24 jam)
    final searchCacheBox = Hive.box<SearchCache>(BOX_SEARCH_CACHE);
    final songsBox = Hive.box<Song>(BOX_SONGS);

    final cachedEntry = searchCacheBox.get(cleanQuery);
    if (cachedEntry != null && !cachedEntry.isExpired(ttl: SEARCH_CACHE_TTL)) {
      final cachedSongs = <Song>[];
      bool allFound = true;

      for (final videoId in cachedEntry.videoIds) {
        final song = songsBox.get(videoId);
        if (song != null) {
          cachedSongs.add(song);
        } else {
          allFound = false;
          break;
        }
      }

      if (allFound && cachedSongs.isNotEmpty) {
        debugPrint(
            'SearchCache HIT: "$query" (${cachedSongs.length} songs from cache)');
        return cachedSongs;
      }
    }

    debugPrint('SearchCache MISS: "$query". Querying YouTube...');
    List<Song> songs = [];

    // 2. Jika API key diisi manual oleh user, gunakan YouTube Data API v3
    if (YOUTUBE_API_KEY.isNotEmpty && YOUTUBE_API_KEY != 'ISI_DI_SINI') {
      try {
        final response = await _dio.get(
          'https://www.googleapis.com/youtube/v3/search',
          queryParameters: {
            'part': 'snippet',
            'q': query,
            'type': 'video',
            'videoCategoryId': '10', // Kategori Musik
            'maxResults': 25,
            'key': YOUTUBE_API_KEY,
          },
        );

        final items = (response.data['items'] as List<dynamic>?) ?? [];
        songs = items.map((item) {
          final idObj = item['id'];
          final videoId = (idObj is Map ? idObj['videoId'] : idObj) as String;
          final snippet = item['snippet'] as Map<String, dynamic>;
          final title = snippet['title'] as String? ?? 'Unknown Title';
          final artist = snippet['channelTitle'] as String? ?? 'Unknown Artist';
          final thumbnails = snippet['thumbnails'] as Map<String, dynamic>?;
          final thumbnailUrl = thumbnails?['high']?['url'] as String? ??
              thumbnails?['medium']?['url'] as String? ??
              'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

          return Song(
            videoId: videoId,
            title: title,
            artist: artist,
            durationMs: 0,
            thumbnailUrl: thumbnailUrl,
          );
        }).toList();
      } on DioException catch (e) {
        if (e.response?.statusCode == 403) {
          throw AppException(
            'Kuota API YouTube habis untuk hari ini. Silakan coba lagi besok atau perbarui API Key.',
            e,
          );
        }
        throw AppException('Gagal mencari di YouTube: ${e.message}', e);
      }
    } else {
      // 3. Fallback pencarian tanpa API key via youtube_explode_dart
      final yt = YoutubeExplode();
      try {
        final searchList = await yt.search.search(query);
        songs = searchList.map((video) {
          final videoId = video.id.value;
          final title = video.title;
          final artist = video.author;
          final durationMs = video.duration?.inMilliseconds ?? 0;
          final thumbnailUrl = video.thumbnails.highResUrl.isNotEmpty
              ? video.thumbnails.highResUrl
              : 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

          return Song(
            videoId: videoId,
            title: title,
            artist: artist,
            durationMs: durationMs,
            thumbnailUrl: thumbnailUrl,
          );
        }).toList();
      } catch (e) {
        throw AppException('Gagal mencari lagu di YouTube.', e);
      } finally {
        yt.close();
      }
    }

    // 4. Simpan lagu ke songsBox dan perbarui SearchCache (TTL 24 jam)
    for (final song in songs) {
      await songsBox.put(song.videoId, song);
    }

    final cacheRecord = SearchCache(
      query: cleanQuery,
      videoIds: songs.map((s) => s.videoId).toList(),
      cachedAt: DateTime.now(),
    );
    await searchCacheBox.put(cleanQuery, cacheRecord);

    return songs;
  }

  static final List<({YoutubeApiClient client, String name, String userAgent})>
      streamClients = [
    (
      client: YoutubeApiClient.androidVr,
      name: 'androidVr',
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; Quest 3)',
    ),
    (
      client: YoutubeApiClient.ios,
      name: 'ios',
      userAgent:
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    ),
    (
      client: YoutubeApiClient.tv,
      name: 'tv',
      userAgent: 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version,gzip(gfe)',
    ),
  ];

  static int findClientIndex(String clientName) {
    return streamClients.indexWhere((c) => c.name == clientName);
  }

  @override
  Future<AudioStreamResult> resolveStreamUrl(
    String videoId, {
    int clientStartIndex = 0,
  }) async {
    // ATURAN EMAS: Resolve stream URL audio-only via youtube_explode_dart.
    // Pilih audio-only dengan bitrate tertinggi. JANGAN simpan hasilnya ke DB.
    final startIndex =
        (clientStartIndex >= 0 && clientStartIndex < streamClients.length)
            ? clientStartIndex
            : 0;

    final candidateClients = [
      ...streamClients.sublist(startIndex),
      ...streamClients.sublist(0, startIndex),
    ];

    Object? lastError;

    for (final candidate in candidateClients) {
      final yt = YoutubeExplode();
      try {
        debugPrint(
            'Mencoba resolve stream videoId: $videoId dengan klien: ${candidate.name}');
        final manifest = await yt.videos.streamsClient.getManifest(
          videoId,
          requireWatchPage: false,
          ytClients: [candidate.client],
        );
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final audioStream = audioStreams.withHighestBitrate();
          debugPrint(
              'Berhasil me-resolve stream audio untuk videoId: $videoId '
              'menggunakan ${candidate.name} (${audioStream.container.name}, ${audioStream.bitrate.kiloBitsPerSecond} kbps)');
          return AudioStreamResult(
            url: audioStream.url,
            headers: {'User-Agent': candidate.userAgent},
            clientName: candidate.name,
          );
        }
      } catch (e) {
        debugPrint('Klien ${candidate.name} gagal me-resolve video $videoId: $e');
        lastError = e;
      } finally {
        yt.close();
      }
    }

    throw AppException(
      'Gagal memuat stream audio untuk video $videoId: $lastError',
      lastError,
    );
  }

  @override
  Future<Song> fetchMetadata(String videoId) async {
    // Metadata cadangan via iTunes Search API (tanpa key)
    try {
      final response = await _dio.get(
        'https://itunes.apple.com/lookup',
        queryParameters: {'id': videoId},
      );
      final results = response.data['results'] as List<dynamic>?;
      if (results != null && results.isNotEmpty) {
        final item = results.first as Map<String, dynamic>;
        return Song(
          videoId: videoId,
          title: item['trackName'] as String? ?? 'Unknown Title',
          artist: item['artistName'] as String? ?? 'Unknown Artist',
          durationMs: item['trackTimeMillis'] as int? ?? 0,
          thumbnailUrl: item['artworkUrl100'] as String? ?? '',
        );
      }
    } catch (_) {
      // Fallback diam jika iTunes metadata gagal
    }

    // Fallback ke songsBox
    final songsBox = Hive.box<Song>(BOX_SONGS);
    final existing = songsBox.get(videoId);
    if (existing != null) return existing;

    return Song(
      videoId: videoId,
      title: 'Unknown Title',
      artist: 'Unknown Artist',
      durationMs: 0,
      thumbnailUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
    );
  }
}
