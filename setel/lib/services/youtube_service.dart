import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../models/search_cache.dart';
import '../models/song.dart';
import '../models/song_chapter.dart';

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

List<SongChapter> parseChaptersFromDescription(String description) {
  if (description.isEmpty) return [];

  // Normalisasi karakter baris baru: dukung newline asli (\n, \r\n) maupun literal escaped (\n)
  final normalized = description
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  final rawChapters = <SongChapter>[];

  // Regex matching timestamp format mm:ss and hh:mm:ss
  // Mendukung: "00:00 Judul", "3:42 - Judul Lagu", "1:02:15 | Judul", "[03:45]", "(12:34)"
  final timeRegex =
      RegExp(r'(?:^|[\s\[\(])(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?:[\s\]\)]|$)');

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final match = timeRegex.firstMatch(line);
    if (match == null) continue;

    final hoursStr = match.group(1);
    final minutesStr = match.group(2);
    final secondsStr = match.group(3);

    final hours = hoursStr != null ? int.tryParse(hoursStr) ?? 0 : 0;
    final minutes = minutesStr != null ? int.tryParse(minutesStr) ?? 0 : 0;
    final seconds = secondsStr != null ? int.tryParse(secondsStr) ?? 0 : 0;

    final positionMs = ((hours * 3600) + (minutes * 60) + seconds) * 1000;

    // Ambil timestamp; teks setelahnya atau sebelumnya jadi judul chapter
    final textAfter = line.substring(match.end);
    String cleanTitle = textAfter
        .replaceFirst(RegExp(r'^[\s\-\–\—\:\|\•\.\)\]]+'), '')
        .trim();
    if (cleanTitle.isEmpty) {
      final textBefore = line.substring(0, match.start);
      cleanTitle = textBefore
          .replaceFirst(RegExp(r'[\s\-\–\—\:\|\•\.\(\[]+$'), '')
          .replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '')
          .trim();
    }

    if (cleanTitle.isNotEmpty) {
      rawChapters.add(SongChapter(title: cleanTitle, positionMs: positionMs));
    }
  }

  // Urutkan menaik berdasarkan positionMs
  rawChapters.sort((a, b) => a.positionMs.compareTo(b.positionMs));

  // Buang duplikat posisi
  final uniqueChapters = <SongChapter>[];
  final seenPositions = <int>{};
  for (final ch in rawChapters) {
    if (seenPositions.add(ch.positionMs)) {
      uniqueChapters.add(ch);
    }
  }

  // Kembalikan list KOSONG bila chapter valid < 2 (bukan kompilasi ber-chapter)
  if (uniqueChapters.length < 2) return [];

  return uniqueChapters;
}

AudioStreamInfo selectStreamByFormat(
  Iterable<AudioStreamInfo> streams,
  String format,
) {
  final list = streams.toList();
  if (list.isEmpty) throw StateError('No streams available');
  switch (format) {
    case 'Hemat Data':
      list.sort((a, b) => a.bitrate.compareTo(b.bitrate));
      return list.first;
    case 'Seimbang':
      final under128 =
          list.where((s) => s.bitrate.kiloBitsPerSecond <= 128).toList();
      if (under128.isNotEmpty) {
        under128.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        return under128.first;
      }
      list.sort((a, b) => a.bitrate.compareTo(b.bitrate));
      return list.first;
    case 'Tertinggi':
    default:
      list.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return list.first;
  }
}

MuxedStreamInfo selectMuxedStreamByFormat(
  Iterable<MuxedStreamInfo> streams,
  String format,
) {
  final list = streams.toList();
  if (list.isEmpty) throw StateError('No muxed streams available');
  switch (format) {
    case 'Hemat Data':
      list.sort((a, b) => a.bitrate.compareTo(b.bitrate));
      return list.first;
    case 'Seimbang':
      list.sort((a, b) => (a.bitrate.kiloBitsPerSecond - 600)
          .abs()
          .compareTo((b.bitrate.kiloBitsPerSecond - 600).abs()));
      return list.first;
    case 'Tertinggi':
    default:
      list.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return list.first;
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

  /// Ambil daftar chapter dari deskripsi video YouTube (cache 24 jam).
  Future<List<SongChapter>> getChapters(String videoId);

  /// Metadata cadangan via iTunes Search API (tanpa key), dipakai jika perlu.
  Future<Song> fetchMetadata(String videoId);

  /// Ambil lagu rekomendasi / mix radio terkait videoId (Smart Mix / Radio).
  Future<List<Song>> getRelatedSongs(String videoId, {int limit = 20});
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
        // Prioritaskan stream progressive muxed (MP4 itag 18) yang memiliki 'ratebypass=yes'.
        // YouTube CDN membatasi stream DASH audio-only tanpa PO-token pada tepat 1MB (403 Forbidden).
        // Stream muxed progressive tidak memiliki batasan 1MB, mendukung seek acak tanpa jeda,
        // dan ExoPlayer/just_audio hanya men-decode track AAC audio-nya.
        if (manifest.muxed.isNotEmpty) {
          final muxedStream =
              selectMuxedStreamByFormat(manifest.muxed, streamFormat);
          debugPrint(
              'Berhasil me-resolve stream muxed (ratebypass=yes) untuk videoId: $videoId '
              'menggunakan ${candidate.name} (format: $streamFormat, tag: ${muxedStream.tag}, ${muxedStream.bitrate.kiloBitsPerSecond} kbps, ${muxedStream.size.totalBytes} bytes)');
          return AudioStreamResult(
            url: muxedStream.url,
            headers: {'User-Agent': candidate.userAgent},
            clientName: candidate.name,
            totalBytes: muxedStream.size.totalBytes,
            contentType: 'audio/mp4',
          );
        }

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

    // Fallback penyelamat: jika semua klien audioOnly gagal me-resolve,
    // ambil stream progressive muxed (itag 18) yang memiliki ratebypass=yes
    // agar lagu tetap BUNYI dan tidak crash bagi user.
    final ytFallback = YoutubeExplode();
    try {
      final manifest = await ytFallback.videos.streamsClient.getManifest(
        videoId,
        requireWatchPage: false,
        ytClients: [YoutubeApiClient.androidSdkless],
      );
      if (manifest.muxed.isNotEmpty) {
        final muxed = selectMuxedStreamByFormat(manifest.muxed, streamFormat);
        debugPrint(
            'Fallback muxed berhasil untuk videoId: $videoId (tag: ${muxed.tag})');
        return AudioStreamResult(
          url: muxed.url,
          headers: {
            'User-Agent':
                'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip'
          },
          clientName: 'androidSdkless-muxed-fallback',
          totalBytes: muxed.size.totalBytes,
          contentType: 'audio/mp4',
        );
      }
      if (manifest.audioOnly.isNotEmpty) {
        final audio = selectStreamByFormat(manifest.audioOnly, streamFormat);
        return AudioStreamResult(
          url: audio.url,
          headers: {
            'User-Agent':
                'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip'
          },
          clientName: 'androidSdkless-audio-fallback',
          totalBytes: audio.size.totalBytes,
          contentType:
              audio.container.name == 'webm' ? 'audio/webm' : 'audio/mp4',
        );
      }
    } catch (_) {
    } finally {
      ytFallback.close();
    }

    throw AppException(
      'Gagal memuat stream audio untuk video $videoId: $lastError',
      lastError,
    );
  }

  @override
  Future<List<SongChapter>> getChapters(String videoId) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return [];

    // 1. Cek cache Hive song_chapters (TTL 24 jam)
    if (Hive.isBoxOpen(BOX_SONG_CHAPTERS)) {
      final box = Hive.box(BOX_SONG_CHAPTERS);
      final cached = box.get(cleanId);
      if (cached is Map) {
        final fetchedAt = cached['fetchedAt'] as int?;
        final rawChapters = cached['chapters'];
        if (fetchedAt != null && rawChapters is List) {
          final isExpired = DateTime.now().millisecondsSinceEpoch - fetchedAt >
              24 * 3600 * 1000;
          if (!isExpired) {
            return rawChapters
                .whereType<Map>()
                .map((m) => SongChapter.fromMap(m))
                .toList();
          }
        }
      }
    }

    // 2. Fetch deskripsi video via youtube_explode
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(cleanId);
      final description = video.description;
      final chapters = parseChaptersFromDescription(description);

      // 3. Simpan ke cache box song_chapters
      if (Hive.isBoxOpen(BOX_SONG_CHAPTERS)) {
        final box = Hive.box(BOX_SONG_CHAPTERS);
        await box.put(cleanId, {
          'fetchedAt': DateTime.now().millisecondsSinceEpoch,
          'chapters': chapters.map((c) => c.toMap()).toList(),
        });
      }

      return chapters;
    } catch (e) {
      debugPrint('Gagal mengambil chapter video $videoId: $e');
      return [];
    } finally {
      yt.close();
    }
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

  @override
  Future<List<Song>> getRelatedSongs(String videoId, {int limit = 20}) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return [];

    final cacheKey = 'related:$cleanId';
    // 1. Cek cache Hive search_cache (TTL 24 jam)
    if (Hive.isBoxOpen(BOX_SEARCH_CACHE)) {
      final cacheBox = Hive.box<SearchCache>(BOX_SEARCH_CACHE);
      final cached = cacheBox.get(cacheKey);
      if (cached != null && !cached.isExpired(ttl: SEARCH_CACHE_TTL)) {
        final songsBox = Hive.box<Song>(BOX_SONGS);
        final cachedSongs = <Song>[];
        for (final id in cached.videoIds) {
          final s = songsBox.get(id);
          if (s != null) cachedSongs.add(s);
        }
        if (cachedSongs.isNotEmpty) {
          debugPrint(
              'getRelatedSongs cache hit ($cacheKey): ${cachedSongs.length} lagu');
          return cachedSongs.take(limit).toList();
        }
      }
    }

    final yt = YoutubeExplode();
    final results = <Song>[];
    final seenIds = <String>{cleanId};

    try {
      final video = await yt.videos.get(cleanId);
      final relatedList = await yt.videos.getRelatedVideos(video);

      if (relatedList != null && relatedList.isNotEmpty) {
        for (final v in relatedList) {
          final id = v.id.value;
          if (seenIds.contains(id)) continue;
          seenIds.add(id);

          final durMs = v.duration?.inMilliseconds ?? 0;
          // Filter: jangan masukkan kompilasi panjang (> 15 menit) ke dalam mix radio
          if (durMs > 15 * 60 * 1000) continue;

          results.add(
            Song(
              videoId: id,
              title: v.title,
              artist: v.author,
              thumbnailUrl: v.thumbnails.highResUrl.isNotEmpty
                  ? v.thumbnails.highResUrl
                  : 'https://img.youtube.com/vi/$id/hqdefault.jpg',
              durationMs: durMs,
            ),
          );
          if (results.length >= limit) break;
        }
      }

      // 2. Jika hasil terkait rekomendasi masih sedikit (< 5 lagu),
      // lengkapi dengan pencarian artis/lagu sejenis
      if (results.length < 5) {
        final query = '${video.author} ${video.title}';
        final searchResults = await search(query, limit: limit);
        for (final s in searchResults) {
          if (!seenIds.contains(s.videoId) && s.durationMs <= 15 * 60 * 1000) {
            seenIds.add(s.videoId);
            results.add(s);
            if (results.length >= limit) break;
          }
        }
      }

      // 3. Simpan ke cache jika ada hasil
      if (results.isNotEmpty && Hive.isBoxOpen(BOX_SEARCH_CACHE)) {
        final songsBox = Hive.box<Song>(BOX_SONGS);
        for (final s in results) {
          await songsBox.put(s.videoId, s);
        }
        final cacheBox = Hive.box<SearchCache>(BOX_SEARCH_CACHE);
        await cacheBox.put(
          cacheKey,
          SearchCache(
            query: cacheKey,
            videoIds: results.map((s) => s.videoId).toList(),
            cachedAt: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Gagal mengambil related songs untuk videoId $videoId: $e');
    } finally {
      yt.close();
    }

    return results;
  }
}
