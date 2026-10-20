import '../models/song.dart';

abstract class YouTubeService {
  /// Cari lagu via YouTube Data API v3. WAJIB cek SearchCache dulu (TTL 24 jam).
  /// 1x search = 100 unit kuota. Error kuota → AppException('Kuota API habis...').
  Future<List<Song>> search(String query);

  /// Resolve stream URL audio-only via youtube_explode_dart.
  /// Pilih muxed/audio-only dengan bitrate tertinggi. JANGAN simpan hasilnya.
  Future<Uri> resolveStreamUrl(String videoId);

  /// Metadata cadangan via iTunes Search API (tanpa key), dipakai jika perlu.
  Future<Song> fetchMetadata(String videoId);
}
