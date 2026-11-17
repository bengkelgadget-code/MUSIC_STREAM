import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class StreamChunkException implements Exception {
  final String? videoId;
  final String range;
  final int? statusCode;
  final String message;

  StreamChunkException({
    this.videoId,
    required this.range,
    this.statusCode,
    required this.message,
  });

  @override
  String toString() =>
      'StreamChunkException(videoId: $videoId, range: $range, status: $statusCode, message: $message)';
}

/// Custom [StreamAudioSource] untuk memutar YouTube audio stream tanpa hambatan.
///
/// Melalui kelas ini, just_audio menjalankan proxy lokal (127.0.0.1) sehingga ExoPlayer
/// meminta range ke localhost, dan kelas ini mengambil byte audio dari YouTube CDN
/// dalam chunk aman (512KB) dengan User-Agent yang sesuai serta retry otomatis bila ada gangguan jaringan.
class YouTubeAudioSource extends StreamAudioSource {
  Uri uri;
  Map<String, String> headers;
  final int totalBytes;
  final String contentType;
  final String? videoId;
  final Future<({Uri url, Map<String, String> headers})> Function()? onReResolveUrl;
  final HttpClient? httpClient;

  YouTubeAudioSource({
    required this.uri,
    required this.headers,
    required this.totalBytes,
    required this.contentType,
    this.videoId,
    this.onReResolveUrl,
    this.httpClient,
    super.tag,
  });

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final startByte = start ?? 0;
    // Bila totalBytes <= 0 (tidak diketahui): JANGAN batasi stream ke 512KB pertama.
    // sourceLength = null dan endByte mengikuti end yang diminta ExoPlayer.
    final int? requestedEnd = (end != null && end > startByte)
        ? end
        : (totalBytes > 0 ? totalBytes : null);

    Stream<List<int>> byteStream() async* {
      final client = httpClient ?? HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      const chunkSize = 512 * 1024; // 512 KB chunk aman & responsif
      var current = startByte;
      bool hasReResolved416 = false;

      try {
        while (requestedEnd == null || current < requestedEnd) {
          final to = requestedEnd != null
              ? min(current + chunkSize - 1, requestedEnd - 1)
              : current + chunkSize - 1;
          int expectedBytes = to - current + 1;
          int retryCount = 0;
          bool chunkSuccess = false;

          while (retryCount < 3 && !chunkSuccess) {
            try {
              final req = await client.getUrl(uri);
              headers.forEach((k, v) => req.headers.set(k, v));
              req.headers.set('Range', 'bytes=$current-$to');
              final resp = await req.close();

              // Status 416 (Range Not Satisfiable)
              if (resp.statusCode == 416) {
                debugPrint(
                    '[YouTubeAudioSource] Status 416 diterima (current: $current, totalBytes: $totalBytes, videoId: $videoId)');
                if (totalBytes > 0 && current >= totalBytes) {
                  debugPrint(
                      '[YouTubeAudioSource] current ($current) >= totalBytes ($totalBytes), stream berakhir normal.');
                  return;
                }
                // Bila belum mencapai totalBytes, coba resolve ulang URL stream 1x lalu lanjutkan
                if (onReResolveUrl != null && !hasReResolved416) {
                  hasReResolved416 = true;
                  debugPrint(
                      '[YouTubeAudioSource] Mencoba re-resolve URL stream untuk 416 pada videoId: $videoId...');
                  try {
                    final fresh = await onReResolveUrl!();
                    uri = fresh.url;
                    headers = fresh.headers;
                    continue;
                  } catch (e) {
                    debugPrint(
                        '[YouTubeAudioSource] Gagal re-resolve URL stream untuk 416: $e');
                  }
                }
                if (totalBytes <= 0) {
                  debugPrint(
                      '[YouTubeAudioSource] totalBytes <= 0 dan server membalas 416, stream berakhir normal.');
                  return;
                }
                throw StreamChunkException(
                  videoId: videoId,
                  range: '$current-$to',
                  statusCode: 416,
                  message: 'Range Not Satisfiable di tengah pemutaran',
                );
              }

              // Status harus 206 (Partial Content) atau 200 (OK)
              if (resp.statusCode != 206 && resp.statusCode != 200) {
                debugPrint(
                    '[YouTubeAudioSource] Chunk $current-$to gagal (status: ${resp.statusCode}, retry: ${retryCount + 1}/3, videoId: $videoId)');
                retryCount++;
                if (retryCount < 3) {
                  await Future.delayed(const Duration(milliseconds: 250));
                  continue;
                }
                debugPrint(
                    '[YouTubeAudioSource] Stream berakhir prematur / gagal setelah 3x retry pada range $current-$to (status: ${resp.statusCode}, videoId: $videoId)');
                throw StreamChunkException(
                  videoId: videoId,
                  range: '$current-$to',
                  statusCode: resp.statusCode,
                  message: 'Gagal streaming chunk setelah 3 percobaan (status: ${resp.statusCode})',
                );
              }

              // Periksa Content-Range untuk menentukan apakah server memotong ke EOF asli
              final contentRange = resp.headers.value('content-range');
              if (contentRange != null && contentRange.startsWith('bytes ')) {
                final rangePart = contentRange.substring(6).split('/')[0];
                final parts = rangePart.split('-');
                if (parts.length == 2) {
                  final rangeEnd = int.tryParse(parts[1]);
                  if (rangeEnd != null && rangeEnd < to) {
                    expectedBytes = rangeEnd - current + 1;
                  }
                }
              }

              final chunkBuffer = BytesBuilder(copy: false);

              if (resp.statusCode == 200) {
                debugPrint(
                    '[YouTubeAudioSource] Status 200 diterima untuk range $current-$to (videoId: $videoId), memotong hanya jendela yang diminta.');
                // Ambil hanya jendela [current, to] dari body
                int streamPos = 0;
                await for (final data in resp) {
                  final chunkStart = streamPos;
                  final chunkEnd = streamPos + data.length - 1;
                  streamPos += data.length;

                  if (chunkEnd >= current && chunkStart <= to) {
                    final sliceStart = max(0, current - chunkStart);
                    final sliceEnd = min(data.length, to - chunkStart + 1);
                    if (sliceStart < sliceEnd) {
                      chunkBuffer.add(data.sublist(sliceStart, sliceEnd));
                    }
                  }
                  if (streamPos > to) {
                    break;
                  }
                }
              } else {
                // 206 Partial Content: body langsung berisi byte range yang diminta
                await for (final chunk in resp) {
                  chunkBuffer.add(chunk);
                }
              }

              // Verifikasi integritas chunk: byte yang benar-benar diterima vs expectedBytes
              if (chunkBuffer.length < expectedBytes) {
                debugPrint(
                    '[YouTubeAudioSource] Body pendek: diterima ${chunkBuffer.length} dari $expectedBytes bytes (range: $current-$to, retry: ${retryCount + 1}/3, videoId: $videoId)');
                retryCount++;
                if (retryCount < 3) {
                  await Future.delayed(const Duration(milliseconds: 250));
                  continue;
                }
                debugPrint(
                    '[YouTubeAudioSource] Stream berakhir prematur / gagal: body pendek setelah 3x retry pada range $current-$to (videoId: $videoId)');
                throw StreamChunkException(
                  videoId: videoId,
                  range: '$current-$to',
                  statusCode: resp.statusCode,
                  message: 'Body lebih pendek dari yang diminta (${chunkBuffer.length}/$expectedBytes bytes) setelah 3x retry',
                );
              }

              // Chunk sukses: emit byte ke stream dan majukan current
              yield chunkBuffer.takeBytes();
              chunkSuccess = true;
              current = to + 1;
            } catch (e) {
              if (e is StreamChunkException) rethrow;
              debugPrint(
                  '[YouTubeAudioSource] Exception saat fetch chunk $current-$to: $e (retry: ${retryCount + 1}/3, videoId: $videoId)');
              retryCount++;
              if (retryCount >= 3) {
                debugPrint(
                    '[YouTubeAudioSource] Stream berakhir prematur / gagal setelah 3x retry pada range $current-$to (error: $e, videoId: $videoId)');
                throw StreamChunkException(
                  videoId: videoId,
                  range: '$current-$to',
                  message: 'Exception fetch chunk: $e',
                );
              }
              await Future.delayed(const Duration(milliseconds: 250));
            }
          }

          if (!chunkSuccess) {
            break;
          }
        }
      } finally {
        if (httpClient == null) {
          client.close();
        }
      }
    }

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: totalBytes > 0 ? totalBytes : null,
      contentLength: requestedEnd != null ? (requestedEnd - startByte) : null,
      offset: startByte,
      contentType: contentType,
      stream: byteStream(),
    );
  }
}
