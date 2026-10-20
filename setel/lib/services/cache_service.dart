import 'dart:io';
import '../models/song.dart';

abstract class CacheService {
  /// Kembalikan file cache jika ada & masih valid, null jika tidak.
  Future<File?> getCached(Song song);

  /// Download stream ke file lokal saat lagu diputar. Dipanggil otomatis oleh AudioPlayerService.
  Future<File> cacheSong(Song song, Uri streamUrl);

  /// Hapus file terlama (LRU) jika total > batas. Dipanggil tiap selesai cacheSong.
  Future<void> enforceLimit();

  Future<int> cacheSizeBytes();
  Future<void> clearCache();
}
