import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/errors.dart';

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
  static ChunkErrorInfo? lastChunkError;
  static void resetLastChunkError() => lastChunkError = null;

  final Uri uri;
  final Map<String, String> headers;
  final int totalBytes;
  final String contentType;
  final String? videoId;
  final String? clientName;
  final bool isOpus;
  final Future<({Uri url, Map<String, String> headers, int totalBytes})> Function(
      {bool fallbackNonOpus})? onReResolveUrl;
  final HttpClient? httpClient;
  final Duration chunkTimeout;

  YouTubeAudioSource({
    required this.uri,
    required this.headers,
    required this.totalBytes,
    required this.contentType,
    this.videoId,
    this.clientName,
    this.isOpus = false,
    this.onReResolveUrl,
    this.httpClient,
    this.chunkTimeout = const Duration(seconds: 15),
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
      var client = httpClient ?? HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      const chunkSize = 512 * 1024; // 512 KB chunk aman & responsif
      var currentUri = uri;
      var currentHeaders = Map<String, String>.of(headers);
      var currentTotalBytes = totalBytes;
      var current = startByte;
      int? effectiveEnd = requestedEnd;
      bool hasReResolved416 = false;
      bool hasReResolvedMidStream = false;
      bool hasCorrectedTotalBytes = false;
      int totalStreamedBytes = 0;

      try {
        while (effectiveEnd == null || current < effectiveEnd) {
          var to = effectiveEnd != null
              ? min(current + chunkSize - 1, effectiveEnd - 1)
              : current + chunkSize - 1;
          int expectedBytes = to - current + 1;
          int retryCount = 0;
          bool chunkSuccess = false;

          while (retryCount < 3 && !chunkSuccess) {
            HttpClientRequest? req;
            HttpClientResponse? resp;
            try {
              req = await client.getUrl(currentUri);
              currentHeaders.forEach((k, v) => req!.headers.set(k, v));
              req.headers.set('Range', 'bytes=$current-$to');
              resp = await req.close().timeout(chunkTimeout);

              // Status 416 (Range Not Satisfiable)
              if (resp.statusCode == 416) {
                debugPrint(
                    '[YouTubeAudioSource] Status 416 diterima (current: $current, totalBytes: $currentTotalBytes, videoId: $videoId)');
                if (currentTotalBytes > 0 && current >= currentTotalBytes) {
                  debugPrint(
                      '[YouTubeAudioSource] current ($current) >= totalBytes ($currentTotalBytes), stream berakhir normal.');
                  return;
                }
                // Bila belum mencapai totalBytes, coba resolve ulang URL stream 1x lalu lanjutkan
                if (onReResolveUrl != null && !hasReResolved416) {
                  hasReResolved416 = true;
                  debugPrint(
                      '[YouTubeAudioSource] Mencoba re-resolve URL stream untuk 416 pada videoId: $videoId...');
                  try {
                    final fresh = await onReResolveUrl!();
                    currentUri = fresh.url;
                    currentHeaders = Map<String, String>.of(fresh.headers);
                    if (fresh.totalBytes > 0 && fresh.totalBytes != currentTotalBytes) {
                      debugPrint(
                          '[YouTubeAudioSource] totalBytes diperbarui via re-resolve 416: lama=$currentTotalBytes baru=${fresh.totalBytes} (videoId: $videoId)');
                      currentTotalBytes = fresh.totalBytes;
                      if (requestedEnd == null || requestedEnd == totalBytes) {
                        effectiveEnd = fresh.totalBytes;
                      }
                    }
                    continue;
                  } catch (e) {
                    debugPrint(
                        '[YouTubeAudioSource] Gagal re-resolve URL stream untuk 416: $e');
                  }
                }
                if (currentTotalBytes <= 0) {
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

                // 1A: Self-healing untuk SEMUA chunk bila status 403, 404, atau 429 (maks 1x per byteStream)
                if ((resp.statusCode == 403 ||
                        resp.statusCode == 404 ||
                        resp.statusCode == 429) &&
                    onReResolveUrl != null &&
                    !hasReResolvedMidStream) {
                  hasReResolvedMidStream = true;
                  lastChunkError = ChunkErrorInfo(
                    videoId: videoId,
                    statusCode: resp.statusCode,
                    range: '$current-$to',
                    clientName: clientName,
                  );
                  debugPrint(
                      '[YouTubeAudioSource] Chunk $current-$to gagal status ${resp.statusCode} (videoId: $videoId). Mencoba self-healing re-resolve 1x (fallbackNonOpus: $isOpus)...');
                  try {
                    final fresh =
                        await onReResolveUrl!(fallbackNonOpus: isOpus);
                    currentUri = fresh.url;
                    currentHeaders = Map<String, String>.of(fresh.headers);
                    if (fresh.totalBytes > 0 && fresh.totalBytes != currentTotalBytes) {
                      debugPrint(
                          '[YouTubeAudioSource] totalBytes diperbarui via self-healing: lama=$currentTotalBytes baru=${fresh.totalBytes} (videoId: $videoId)');
                      currentTotalBytes = fresh.totalBytes;
                      if (requestedEnd == null || requestedEnd == totalBytes) {
                        effectiveEnd = fresh.totalBytes;
                      }
                    }
                    debugPrint(
                        '[YouTubeAudioSource] Self-healing re-resolve berhasil untuk range $current-$to (status: ${resp.statusCode}, URL baru: ${fresh.url})');
                    continue; // Coba chunk yang SAMA lagi dengan URL baru
                  } catch (reErr) {
                    debugPrint(
                        '[YouTubeAudioSource] Self-healing re-resolve gagal: $reErr');
                  }
                }

                retryCount++;
                if (retryCount < 3) {
                  await Future.delayed(const Duration(milliseconds: 250));
                  continue;
                }

                lastChunkError = ChunkErrorInfo(
                  videoId: videoId,
                  statusCode: resp.statusCode,
                  range: '$current-$to',
                  clientName: clientName,
                );

                debugPrint(
                    '[YouTubeAudioSource] Stream berakhir prematur / gagal setelah 3x retry pada range $current-$to (status: ${resp.statusCode}, videoId: $videoId)');
                throw StreamChunkException(
                  videoId: videoId,
                  range: '$current-$to',
                  statusCode: resp.statusCode,
                  message:
                      'Gagal streaming chunk setelah 3 percobaan (status: ${resp.statusCode})',
                );
              }

              // 1C: Pada respons 206 PERTAMA tiap byteStream, parse TOTAL dari Content-Range (bytes a-b/TOTAL)
              final contentRange = resp.headers.value('content-range');
              if (contentRange != null && contentRange.startsWith('bytes ')) {
                final slashIdx = contentRange.indexOf('/');
                if (slashIdx != -1) {
                  final rangePart = contentRange.substring(6, slashIdx);
                  final totalPart = contentRange.substring(slashIdx + 1).trim();
                  final parts = rangePart.split('-');
                  if (parts.length == 2) {
                    final rangeEnd = int.tryParse(parts[1]);
                    if (rangeEnd != null) {
                      expectedBytes = rangeEnd - current + 1;
                      to = rangeEnd;
                    }
                  }
                  final serverTotal = int.tryParse(totalPart);
                  if (serverTotal != null && serverTotal > 0 && !hasCorrectedTotalBytes) {
                    hasCorrectedTotalBytes = true;
                    if (serverTotal != currentTotalBytes) {
                      debugPrint(
                          '[YouTubeAudioSource] totalBytes dikoreksi manifest=$currentTotalBytes server=$serverTotal videoId=$videoId');
                      currentTotalBytes = serverTotal;
                      if (requestedEnd == null || requestedEnd == totalBytes) {
                        effectiveEnd = serverTotal;
                      }
                    }
                  }
                }
              }

              final chunkBuffer = BytesBuilder(copy: false);
              final timedStream = resp.timeout(chunkTimeout);

              if (resp.statusCode == 200) {
                debugPrint(
                    '[YouTubeAudioSource] Status 200 diterima untuk range $current-$to (videoId: $videoId), memotong hanya jendela yang diminta.');
                // Ambil hanya jendela [current, to] dari body
                int streamPos = 0;
                await for (final data in timedStream) {
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
                // 1D: Tutup respons 200 agar koneksi tidak menggantung & reset client
                try {
                  final socket = await resp.detachSocket();
                  socket.destroy();
                } catch (_) {}
                if (httpClient == null) {
                  try {
                    client.close(force: true);
                  } catch (_) {}
                  client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
                }
              } else {
                // 206 Partial Content: body langsung berisi byte range yang diminta dengan timeout
                await for (final chunk in timedStream) {
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
                lastChunkError = ChunkErrorInfo(
                  videoId: videoId,
                  statusCode: resp.statusCode,
                  range: '$current-$to',
                  clientName: clientName,
                );
                debugPrint(
                    '[YouTubeAudioSource] Stream berakhir prematur / gagal: body pendek setelah 3x retry pada range $current-$to (videoId: $videoId)');
                throw StreamChunkException(
                  videoId: videoId,
                  range: '$current-$to',
                  statusCode: resp.statusCode,
                  message:
                      'Body lebih pendek dari yang diminta (${chunkBuffer.length}/$expectedBytes bytes) setelah 3x retry',
                );
              }

              // Chunk sukses: emit byte ke stream dan majukan current
              final chunkLen = chunkBuffer.length;
              yield chunkBuffer.takeBytes();
              chunkSuccess = true;
              totalStreamedBytes += chunkLen;
              current = to + 1;
            } catch (e) {
              if (e is StreamChunkException) rethrow;

              // Bersihkan request / response yang gagal
              try {
                req?.abort();
              } catch (_) {}
              if (resp != null) {
                try {
                  final socket = await resp.detachSocket();
                  socket.destroy();
                } catch (_) {}
              }

              // 1B: Timeout handling per chunk
              if (e is TimeoutException) {
                debugPrint(
                    '[YouTubeAudioSource] Timeout baca chunk $current-$to (tidak ada byte dalam ${chunkTimeout.inSeconds} detik, retry: ${retryCount + 1}/3, videoId: $videoId)');
                retryCount++;
                if (retryCount >= 3) {
                  lastChunkError = ChunkErrorInfo(
                    videoId: videoId,
                    statusCode: null,
                    range: '$current-$to',
                    clientName: clientName,
                  );
                  debugPrint(
                      '[YouTubeAudioSource] Stream berakhir prematur / gagal: timeout baca chunk setelah 3x retry pada range $current-$to (videoId: $videoId)');
                  throw StreamChunkException(
                    videoId: videoId,
                    range: '$current-$to',
                    statusCode: null,
                    message:
                        'Timeout baca chunk (tidak ada byte ${chunkTimeout.inSeconds} detik)',
                  );
                }
                await Future.delayed(const Duration(milliseconds: 250));
                continue;
              }

              debugPrint(
                  '[YouTubeAudioSource] Exception saat fetch chunk $current-$to: $e (retry: ${retryCount + 1}/3, videoId: $videoId)');
              retryCount++;
              if (retryCount >= 3) {
                lastChunkError = ChunkErrorInfo(
                  videoId: videoId,
                  statusCode: null,
                  range: '$current-$to',
                  clientName: clientName,
                );
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

        // Stream selesai normal
        final finalTotal = effectiveEnd ?? currentTotalBytes;
        debugPrint(
            '[YouTubeAudioSource] Stream selesai normal videoId=$videoId totalBytes=$finalTotal totalStreamed=$totalStreamedBytes');
      } finally {
        if (httpClient == null) {
          client.close(force: true);
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
