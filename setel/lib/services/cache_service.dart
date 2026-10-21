import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../models/settings.dart';
import '../models/song.dart';

abstract class CacheService {
  /// Kembalikan file cache jika ada & masih valid, null jika tidak.
  Future<File?> getCached(Song song);

  /// Download stream ke file lokal saat lagu diputar. Dipanggil otomatis oleh AudioPlayerService.
  Future<File> cacheSong(Song song, Uri streamUrl,
      {Map<String, String>? headers});

  /// Hapus file terlama (LRU) jika total > batas. Dipanggil tiap selesai cacheSong.
  Future<void> enforceLimit();

  Future<int> cacheSizeBytes();
  Future<void> clearCache();
}

class CacheServiceImpl implements CacheService {
  Directory? _cacheDirectory;

  CacheServiceImpl({Dio? dio, Directory? cacheDirectory})
      : _cacheDirectory = cacheDirectory;

  Future<Directory> _getCacheDir() async {
    if (_cacheDirectory != null) return _cacheDirectory!;
    final baseDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${baseDir.path}/setel_cache');
    if (!cacheDir.existsSync()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirectory = cacheDir;
    return cacheDir;
  }

  @override
  Future<File?> getCached(Song song) async {
    // 1. Cek dari cachedPath yang tersimpan di model/DB
    if (song.cachedPath != null) {
      final file = File(song.cachedPath!);
      if (file.existsSync() && file.lengthSync() > 0) {
        try {
          await file.setLastModified(DateTime.now());
        } catch (_) {}
        return file;
      }
    }

    // 2. Cek apakah file fisik ada di folder cache
    final cacheDir = await _getCacheDir();
    final targetFile = File('${cacheDir.path}/${song.videoId}.m4a');
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      try {
        await targetFile.setLastModified(DateTime.now());
      } catch (_) {}

      // Sinkronkan cachedPath ke database lokal songsBox
      final songsBox = Hive.box<Song>(BOX_SONGS);
      final existingSong = songsBox.get(song.videoId) ?? song;
      await songsBox.put(
        song.videoId,
        existingSong.copyWith(cachedPath: targetFile.path),
      );
      return targetFile;
    }

    return null;
  }

  @override
  Future<File> cacheSong(Song song, Uri streamUrl,
      {Map<String, String>? headers}) async {
    final cacheDir = await _getCacheDir();
    final targetFile = File('${cacheDir.path}/${song.videoId}.m4a');

    // Jika sudah ada dan valid, perbarui waktu akses
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      try {
        await targetFile.setLastModified(DateTime.now());
      } catch (_) {}
      return targetFile;
    }

    // Download stream audio ke temporary file lalu rename (atomic)
    // Gunakan HttpClient dengan chunk 512KB & auto-retry untuk performa maksimal
    final tempFile = File('${cacheDir.path}/${song.videoId}.tmp');
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final sink = tempFile.openWrite();
      const chunkSize = 512 * 1024;
      var current = 0;
      int? totalLength;

      try {
        while (true) {
          final to = current + chunkSize - 1;
          int retryCount = 0;
          bool chunkSuccess = false;

          while (retryCount < 3 && !chunkSuccess) {
            try {
              final req = await client.getUrl(streamUrl);
              headers?.forEach((k, v) => req.headers.set(k, v));
              req.headers.set('Range', 'bytes=$current-$to');
              final resp = await req.close();

              if (resp.statusCode != 206 && resp.statusCode != 200) {
                retryCount++;
                if (retryCount < 3) {
                  await Future.delayed(const Duration(milliseconds: 250));
                  continue;
                }
                throw HttpException(
                    'Gagal download chunk cache: status ${resp.statusCode}');
              }

              if (totalLength == null) {
                final contentRange = resp.headers.value('content-range');
                if (contentRange != null && contentRange.contains('/')) {
                  totalLength =
                      int.tryParse(contentRange.split('/').last.trim());
                }
              }

              int chunkBytes = 0;
              await for (final data in resp) {
                sink.add(data);
                chunkBytes += data.length;
              }
              current += chunkBytes;
              chunkSuccess = true;

              if (totalLength != null && current >= totalLength) {
                break;
              }
              if (chunkBytes < chunkSize) {
                break;
              }
            } catch (e) {
              if (e is HttpException) rethrow;
              retryCount++;
              if (retryCount >= 3) rethrow;
              await Future.delayed(const Duration(milliseconds: 250));
            }
          }

          if (totalLength != null && current >= totalLength) {
            break;
          }
          if (!chunkSuccess) {
            break;
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        client.close();
      }

      if (await tempFile.exists() && await tempFile.length() > 0) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);

        // Perbarui cachedPath pada Hive box songs (HANYA simpan cachedPath lokal, TANPA streamUrl)
        final songsBox = Hive.box<Song>(BOX_SONGS);
        final existingSong = songsBox.get(song.videoId) ?? song;
        await songsBox.put(
          song.videoId,
          existingSong.copyWith(cachedPath: targetFile.path),
        );

        debugPrint('Lagu ${song.title} berhasil di-cache ke ${targetFile.path}');

        // Terapkan batasan LRU segera setelah caching
        await enforceLimit();
        return targetFile;
      } else {
        throw Exception('Ukuran file download kosong');
      }
    } catch (e) {
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      debugPrint('Gagal meng-cache lagu ${song.videoId}: $e');
      rethrow;
    }
  }

  @override
  Future<void> enforceLimit() async {
    try {
      Settings settings = const Settings(); if (Hive.isBoxOpen(BOX_SETTINGS)) { final settingsBox = Hive.box(BOX_SETTINGS); final raw = settingsBox.get(0); if (raw is Settings) settings = raw; }
      final limitBytes = settings.cacheLimitMB * 1024 * 1024;

      final cacheDir = await _getCacheDir();
      if (!cacheDir.existsSync()) return;

      final files = cacheDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a'))
          .toList();

      int currentTotal = 0;
      for (final f in files) {
        currentTotal += f.lengthSync();
      }

      if (currentTotal <= limitBytes) return;

      debugPrint(
          'Cache melebihi batas ($currentTotal > $limitBytes byte). Menerapkan pembersihan LRU...');

      // Urutkan berdasarkan waktu modifikasi terakhir (paling lama ke paling baru)
      files.sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      final songsBox = Hive.box<Song>(BOX_SONGS);

      for (final file in files) {
        if (currentTotal <= limitBytes) break;

        final size = file.lengthSync();
        final filename = file.uri.pathSegments.last;
        final videoId = filename.replaceAll('.m4a', '');

        try {
          await file.delete();
          currentTotal -= size;

          // Hapus referensi cachedPath pada songsBox
          final song = songsBox.get(videoId);
          if (song != null) {
            await songsBox.put(videoId, song.copyWith(clearCachedPath: true));
          }
          debugPrint('File cache LRU terhapus: $filename ($size bytes)');
        } catch (e) {
          debugPrint('Gagal menghapus file cache LRU $filename: $e');
        }
      }
    } catch (e) {
      debugPrint('Error saat enforceLimit LRU: $e');
    }
  }

  @override
  Future<int> cacheSizeBytes() async {
    try {
      final cacheDir = await _getCacheDir();
      if (!cacheDir.existsSync()) return 0;

      final files = cacheDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a'));

      int total = 0;
      for (final f in files) {
        total += f.lengthSync();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDir();
      if (cacheDir.existsSync()) {
        final files = cacheDir.listSync().whereType<File>();
        for (final f in files) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }

      // Bersihkan cachedPath di semua entri songsBox
      final songsBox = Hive.box<Song>(BOX_SONGS);
      for (final key in songsBox.keys) {
        final song = songsBox.get(key);
        if (song != null && song.cachedPath != null) {
          await songsBox.put(key, song.copyWith(clearCachedPath: true));
        }
      }
      debugPrint('Cache offline berhasil dibersihkan.');
    } catch (e) {
      debugPrint('Error saat membersihkan cache: $e');
    }
  }
}
