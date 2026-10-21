import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Custom [StreamAudioSource] untuk memutar YouTube audio stream tanpa hambatan.
///
/// Melalui kelas ini, just_audio menjalankan proxy lokal (127.0.0.1) sehingga ExoPlayer
/// meminta range ke localhost, dan kelas ini mengambil byte audio dari YouTube CDN
/// dalam chunk aman (512KB) dengan User-Agent yang sesuai serta retry otomatis bila ada gangguan jaringan.
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
        : (totalBytes > 0 ? totalBytes : startByte + 512 * 1024);

    Stream<List<int>> byteStream() async* {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      const chunkSize = 512 * 1024; // 512 KB chunk aman & responsif
      var current = startByte;
      try {
        while (current < endByte) {
          final to = min(current + chunkSize - 1, endByte - 1);
          int retryCount = 0;
          bool chunkSuccess = false;

          while (retryCount < 3 && !chunkSuccess) {
            try {
              final req = await client.getUrl(uri);
              headers.forEach((k, v) => req.headers.set(k, v));
              req.headers.set('Range', 'bytes=$current-$to');
              final resp = await req.close();
              if (resp.statusCode != 206 && resp.statusCode != 200) {
                debugPrint(
                    'YouTubeAudioSource: Gagal streaming chunk $current-$to, status: ${resp.statusCode} (retry: $retryCount)');
                retryCount++;
                if (retryCount < 3) {
                  await Future.delayed(const Duration(milliseconds: 250));
                  continue;
                }
                if (current > startByte) {
                  // Jika sebagian audio sudah terkirim dan retry gagal, akhiri dengan aman
                  return;
                }
                throw HttpException('Gagal streaming chunk: ${resp.statusCode}');
              }
              await for (final chunk in resp) {
                yield chunk;
              }
              chunkSuccess = true;
            } catch (e) {
              if (e is HttpException) rethrow;
              retryCount++;
              if (retryCount >= 3) {
                if (current > startByte) return;
                rethrow;
              }
              await Future.delayed(const Duration(milliseconds: 250));
            }
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
