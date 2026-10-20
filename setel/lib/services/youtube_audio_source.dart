import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Custom [StreamAudioSource] untuk memutar YouTube audio stream tanpa 403 Forbidden.
///
/// YouTube CDN memblokir request tidak terbatas (Range: bytes=0-) pada format DASH audio-only.
/// Melalui kelas ini, just_audio menjalankan proxy lokal (127.0.0.1) sehingga ExoPlayer
/// meminta range ke localhost, dan kelas ini mengambil byte audio dari YouTube CDN
/// dalam chunk terbatas (<= 256KB) dengan User-Agent yang sesuai.
class YouTubeAudioSource extends StreamAudioSource {
  final Uri uri;
  final Map<String, String> headers;
  final int totalBytes;
  final String contentType;

  YouTubeAudioSource({
    required this.uri,
    required this.headers,
    required this.totalBytes,
    required this.contentType,
    super.tag,
  });

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final startByte = start ?? 0;
    final endByte = (end != null && end > startByte)
        ? end
        : (totalBytes > 0 ? totalBytes : startByte + 256 * 1024);

    Stream<List<int>> byteStream() async* {
      final client = HttpClient();
      const chunkSize = 256 * 1024; // 256 KB chunk aman dari blokir 403
      var current = startByte;
      try {
        while (current < endByte) {
          final to = min(current + chunkSize - 1, endByte - 1);
          final req = await client.getUrl(uri);
          headers.forEach((k, v) => req.headers.set(k, v));
          req.headers.set('Range', 'bytes=$current-$to');
          final resp = await req.close();
          if (resp.statusCode != 206 && resp.statusCode != 200) {
            debugPrint(
                'YouTubeAudioSource: Gagal streaming chunk $current-$to, status: ${resp.statusCode}');
            if (current > startByte) {
              // Sudah ada sebagian chunk yang terkirim; akhiri stream dengan aman agar player tidak crash
              break;
            }
            throw HttpException('Gagal streaming chunk: ${resp.statusCode}');
          }
          await for (final chunk in resp) {
            yield chunk;
          }
          current = to + 1;
        }
      } finally {
        client.close();
      }
    }

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: totalBytes > 0 ? totalBytes : null,
      contentLength: endByte - startByte,
      offset: startByte,
      contentType: contentType,
      stream: byteStream(),
    );
  }
}
