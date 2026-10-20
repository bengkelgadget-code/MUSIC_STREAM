import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../models/search_cache.dart';
import '../models/song.dart';

int parseIso8601Duration(String isoDuration) {
  if (isoDuration.isEmpty) return 0;
  final regex = RegExp(r'P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
  final match = regex.firstMatch(isoDuration);
  if (match == null) return 0;

  final days = int.tryParse(match.group(1) ?? '0') ?? 0;
  final hours = int.tryParse(match.group(2) ?? '0') ?? 0;
  final minutes = int.tryParse(match.group(3) ?? '0') ?? 0;
  final seconds = int.tryParse(match.group(4) ?? '0') ?? 0;

  return ((days * 24 * 3600) + (hours * 3600) + (minutes * 60) + seconds) *
      1000;
}

int parseDurationString(String? dur) {
  if (dur == null || dur.isEmpty) return 0;
  final parts = dur.split(':').map((p) => int.tryParse(p) ?? 0).toList();
  if (parts.length == 2) {
    return (parts[0] * 60 + parts[1]) * 1000;
  } else if (parts.length == 3) {
    return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
  }
  return 0;
}

AudioStreamInfo selectStreamByFormat(
  Iterable<AudioStreamInfo> streams,
  String format,
) {
  switch (format) {
    case 'Hemat Data':
      return streams.reduce((a, b) =>
          a.bitrate.bitsPerSecond < b.bitrate.bitsPerSecond ? a : b);
    case 'Seimbang':
      final under128 =
          streams.where((s) => s.bitrate.kiloBitsPerSecond <= 128).toList();
      if (under128.isNotEmpty) {
        return under128.reduce((a, b) =>
            a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);
      }
      return streams.reduce((a, b) =>
          a.bitrate.bitsPerSecond < b.bitrate.bitsPerSecond ? a : b);
    case 'Tertinggi':
    default:
      return streams.withHighestBitrate();
  }
}

class AudioStreamResult {
  final Uri url;
  final Map<String, String> headers;
  final String clientName;
  final int totalBytes;
  final String contentType;

  const AudioStreamResult({
    required this.url,
    required this.headers,
    this.clientName = '',
    this.totalBytes = 0,
    this.contentType = 'audio/mp4',
  });

  @override
  String toString() =>
      'AudioStreamResult(client: $clientName, url: $url, totalBytes: $totalBytes, contentType: $contentType, headers: $headers)';

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
  /// Cari lagu via YouTube Data API v3 atau Explode Engine. WAJIB cek SearchCache dulu (TTL 24 jam).
  Future<List<Song>> search(String query, {int limit = 25});

  /// Resolve stream URL audio-only via youtube_explode_dart.
  /// Memilih audio-only sesuai format stream yang aktif (Tertinggi, Seimbang, atau Hemat Data).
  /// Mengambil manifest dari SATU klien per percobaan, urutan tangga:
  /// (a) YoutubeApiClient.androidSdkless, (b) androidVr, (c) android, (d) ios, (e) tv.
  Future<AudioStreamResult> resolveStreamUrl(
    String videoId, {
    int clientStartIndex = 0,
  });

  /// Ambil saran pencarian dari endpoint YouTube Suggest API (maksimal 8 saran).
  Future<List<String>> getSuggestions(String query);

  /// Metadata cadangan via iTunes Search API (tanpa key), dipakai jika perlu.
  Future<Song> fetchMetadata(String videoId);
}

class YouTubeServiceImpl implements YouTubeService {
  final Dio _dio;

  YouTubeServiceImpl({Dio? dio}) : _dio = dio ?? Dio();

  @override
  Future<List<String>> getSuggestions(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final response = await _dio.get(
        'https://suggestqueries.google.com/complete/search',
        queryParameters: {
          'client': 'firefox',
          'ds': 'yt',
          'q': cleanQuery,
        },
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return [];
      }

      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is List && data.length > 1 && data[1] is List) {
        final suggestions = (data[1] as List)
            .map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .take(8)
            .toList();
        return suggestions;
      }
      return [];
    } catch (e) {
      debugPrint('Gagal mengambil saran pencarian: $e');
      return [];
    }
  }

  @override
  Future<List<Song>> search(String query, {int limit = 25}) async {
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
        if (cachedSongs.length >= limit) {
          debugPrint(
              'SearchCache HIT: "$query" (${cachedSongs.length} songs from cache, returning $limit)');
          return cachedSongs.take(limit).toList();
        } else {
          debugPrint(
              'SearchCache memiliki ${cachedSongs.length} lagu, tetapi dibutuhkan $limit. Mengambil ulang...');
        }
      }
    }

    debugPrint('SearchCache MISS: "$query". Querying YouTube (limit: $limit)...');
    List<Song> songs = [];

    // Mode Akses Katalog dari Settings
    final settingsBox =
        Hive.isBoxOpen(BOX_SETTINGS) ? Hive.box(BOX_SETTINGS) : null;
    final catalogMode =
        (settingsBox?.get('catalog_mode', defaultValue: 'Otomatis')
                as String?) ??
            'Otomatis';

    final hasApiKey =
        YOUTUBE_API_KEY.isNotEmpty && YOUTUBE_API_KEY != 'ISI_DI_SINI';

    final bool useDataApi;
    if (catalogMode == 'Explode') {
      useDataApi = false;
    } else if (catalogMode == 'Data API') {
      if (!hasApiKey) {
        throw AppException(
          'Kunci YouTube API belum dikonfigurasi. Silakan periksa kunci API di pengaturan atau constants.dart.',
        );
      }
      useDataApi = true;
    } else {
      // 'Otomatis'
      useDataApi = hasApiKey;
    }

    // 2. Jika useDataApi, gunakan YouTube Data API v3
    if (useDataApi) {
      try {
        final response = await _dio.get(
          'https://www.googleapis.com/youtube/v3/search',
          queryParameters: {
            'part': 'snippet',
            'q': query,
            'type': 'video',
            'videoCategoryId': '10', // Kategori Musik
            'maxResults': limit.clamp(1, 50),
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

        // Perkaya durationMs via videos.list?part=contentDetails (1 batch call)
        if (songs.isNotEmpty) {
          final videoIds = songs.map((s) => s.videoId).join(',');
          try {
            final detailsResp = await _dio.get(
              'https://www.googleapis.com/youtube/v3/videos',
              queryParameters: {
                'part': 'contentDetails',
                'id': videoIds,
                'key': YOUTUBE_API_KEY,
              },
            );
            final detailItems =
                (detailsResp.data['items'] as List<dynamic>?) ?? [];
            final durationMap = <String, int>{};
            for (final dItem in detailItems) {
              final vId = dItem['id'] as String?;
              final durStr = dItem['contentDetails']?['duration'] as String?;
              if (vId != null && durStr != null) {
                durationMap[vId] = parseIso8601Duration(durStr);
              }
            }
            songs = songs.map((s) {
              final d = durationMap[s.videoId];
              return d != null && d > 0 ? s.copyWith(durationMs: d) : s;
            }).toList();
          } catch (e) {
            debugPrint('Gagal memperkaya durasi video: $e');
          }
        }
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
        final collected = <Song>[];
        try {
          SearchList? page = await yt.search.searchContent(query);
          while (page != null && collected.length < limit) {
            for (final item in page) {
              if (item is SearchVideo) {
                final videoId = item.id.value;
                final title = item.title;
                final artist = item.author;
                final durationMs = parseDurationString(item.duration);
                final thumbnailUrl = item.thumbnails.isNotEmpty
                    ? item.thumbnails.last.url.toString()
                    : 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

                collected.add(
                  Song(
                    videoId: videoId,
                    title: title,
                    artist: artist,
                    durationMs: durationMs,
                    thumbnailUrl: thumbnailUrl,
                  ),
                );
                if (collected.length >= limit) break;
              }
            }
            if (collected.length < limit) {
              page = await page.nextPage();
            } else {
              break;
            }
          }
        } catch (scErr) {
          debugPrint('searchContent gagal: $scErr. Menggunakan search()...');
          if (collected.isEmpty) {
            VideoSearchList? searchList = await yt.search.search(query);
            while (searchList != null && collected.length < limit) {
              for (final video in searchList) {
                final videoId = video.id.value;
                final title = video.title;
                final artist = video.author;
                final durationMs = video.duration?.inMilliseconds ?? 0;
                final thumbnailUrl = video.thumbnails.highResUrl.isNotEmpty
                    ? video.thumbnails.highResUrl
                    : 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

                collected.add(
                  Song(
                    videoId: videoId,
                    title: title,
                    artist: artist,
                    durationMs: durationMs,
                    thumbnailUrl: thumbnailUrl,
                  ),
                );
                if (collected.length >= limit) break;
              }
              if (collected.length < limit) {
                searchList = await searchList.nextPage();
              } else {
                break;
              }
            }
          }
        }
        songs = collected;
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
      client: YoutubeApiClient.androidSdkless,
      name: 'androidSdkless',
      userAgent:
          'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    ),
    (
      client: YoutubeApiClient.androidVr,
      name: 'androidVr',
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; Quest 3)',
    ),
    (
      client: YoutubeApiClient.android,
      name: 'android',
      userAgent:
          'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
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
    // Format dipilih sesuai pengaturan (Tertinggi, Seimbang, atau Hemat Data).
    // JANGAN simpan hasilnya ke DB.
    final startIndex =
        (clientStartIndex >= 0 && clientStartIndex < streamClients.length)
            ? clientStartIndex
            : 0;

    final candidateClients = [
      ...streamClients.sublist(startIndex),
      ...streamClients.sublist(0, startIndex),
    ];

    final settingsBox =
        Hive.isBoxOpen(BOX_SETTINGS) ? Hive.box(BOX_SETTINGS) : null;
    final streamFormat =
        (settingsBox?.get('stream_format', defaultValue: 'Tertinggi')
                as String?) ??
            'Tertinggi';

    Object? lastError;

    for (final candidate in candidateClients) {
      final yt = YoutubeExplode();
      try {
        debugPrint(
            'Mencoba resolve stream videoId: $videoId dengan klien: ${candidate.name} (format: $streamFormat)');
        final manifest = await yt.videos.streamsClient.getManifest(
          videoId,
          requireWatchPage: false,
          ytClients: [candidate.client],
        );
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final audioStream = selectStreamByFormat(audioStreams, streamFormat);
          final contentType =
              audioStream.container.name == 'webm' ? 'audio/webm' : 'audio/mp4';
          debugPrint(
              'Berhasil me-resolve stream audio untuk videoId: $videoId '
              'menggunakan ${candidate.name} (format: $streamFormat, ${audioStream.container.name}, tag: ${audioStream.tag}, ${audioStream.bitrate.kiloBitsPerSecond} kbps, ${audioStream.size.totalBytes} bytes)');
          return AudioStreamResult(
            url: audioStream.url,
            headers: {'User-Agent': candidate.userAgent},
            clientName: candidate.name,
            totalBytes: audioStream.size.totalBytes,
            contentType: contentType,
          );
        }
      } catch (e) {
        debugPrint(
            'Klien ${candidate.name} gagal me-resolve video $videoId: $e');
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
