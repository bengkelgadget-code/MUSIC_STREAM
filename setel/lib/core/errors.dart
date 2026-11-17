import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class AppException implements Exception {
  final String message;
  final dynamic cause;
  final List<String>? clientErrors;

  AppException(this.message, [this.cause, this.clientErrors]);

  @override
  String toString() => message;
}

class ChunkErrorInfo {
  final String? videoId;
  final int? statusCode;
  final String range;
  final String? clientName;
  final DateTime at;

  ChunkErrorInfo({
    this.videoId,
    this.statusCode,
    required this.range,
    this.clientName,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  @override
  String toString() =>
      'ChunkErrorInfo(videoId: $videoId, status: $statusCode, range: $range, client: $clientName, at: $at)';
}

/// Klasifikasi penyebab error pemutaran audio berdasarkan tipe error asli (root cause).
String classifyPlaybackError(
  Object error, {
  String? songTitle,
  int? httpStatusCode,
  ChunkErrorInfo? lastChunkError,
  bool hasSuccessfulPlayThisSession = false,
}) {
  Object root = error;
  final clientErrors = <String>[];

  while (root is AppException) {
    if (root.clientErrors != null && root.clientErrors!.isNotEmpty) {
      clientErrors.addAll(root.clientErrors!);
    }
    if (root.cause != null) {
      root = root.cause!;
    } else {
      break;
    }
  }

  final effectiveStatus = httpStatusCode ?? lastChunkError?.statusCode;

  final allErrorsCombined =
      '$error $root ${clientErrors.join(' ')} ${lastChunkError?.toString() ?? ''}'
          .toLowerCase();

  final title = (songTitle != null && songTitle.trim().isNotEmpty)
      ? songTitle.trim()
      : 'Lagu ini';

  // a. TIDAK ADA INTERNET
  if (root is SocketException ||
      root is TimeoutException ||
      allErrorsCombined.contains('socketexception') ||
      allErrorsCombined.contains('failed host lookup') ||
      allErrorsCombined.contains('network is unreachable') ||
      allErrorsCombined.contains('connection timed out') ||
      allErrorsCombined.contains('connectivityresult.none') ||
      allErrorsCombined.contains('timeoutexception') ||
      allErrorsCombined.contains('waktu koneksi habis')) {
    return 'Tidak ada koneksi internet. Periksa WiFi/data seluler, lalu coba lagi.';
  }

  // 404 / 410 (Stream audio tidak ditemukan / video dihapus)
  if (effectiveStatus == 404 ||
      effectiveStatus == 410 ||
      allErrorsCombined.contains('status: 404') ||
      allErrorsCombined.contains('status 404') ||
      allErrorsCombined.contains('status: 410') ||
      allErrorsCombined.contains('status 410') ||
      allErrorsCombined.contains('404 not found')) {
    return '"$title" tidak dapat diputar (stream audio video ini tidak ditemukan).';
  }

  // b. VIDEO TIDAK DAPAT DIPUTAR
  if (root is VideoUnplayableException ||
      root is VideoUnavailableException ||
      root is VideoRequiresPurchaseException ||
      allErrorsCombined.contains('unplayable') ||
      allErrorsCombined.contains('not available') ||
      allErrorsCombined.contains('unavailable') ||
      allErrorsCombined.contains('private') ||
      allErrorsCombined.contains('removed') ||
      allErrorsCombined.contains('age') ||
      allErrorsCombined.contains('region') ||
      allErrorsCombined.contains('copyright') ||
      allErrorsCombined.contains('members-only')) {
    return '"$title" tidak dapat diputar (video dihapus/dibatasi/diblokir wilayah).';
  }

  // c. PROTEKSI BOT (HTTP 403 / Forbidden / bot check)
  if (effectiveStatus == 403 ||
      allErrorsCombined.contains('403') ||
      allErrorsCombined.contains('forbidden') ||
      allErrorsCombined.contains('sign in to confirm') ||
      allErrorsCombined.contains('not a bot') ||
      allErrorsCombined.contains('bot') ||
      allErrorsCombined.contains('requestlimitexceededexception') ||
      allErrorsCombined.contains('rate limiting') ||
      allErrorsCombined.contains('manifest kosong')) {
    return 'Server menolak akses stream (kemungkinan proteksi bot di jaringan ini). Coba ganti jaringan (WiFi lain / data seluler).';
  }

  // SOURCE ERROR (ExoPlayer TYPE_SOURCE / stream load failure / googlevideo kedaluwarsa)
  if ((root is PlatformException && root.code == '0') ||
      (error is PlatformException && error.code == '0') ||
      allErrorsCombined.contains('source error') ||
      allErrorsCombined.contains('streamchunkexception')) {
    String msg =
        'Gagal memuat audio: sumber stream ditolak atau kedaluwarsa. Coba putar lagi atau ganti jaringan.';
    if (hasSuccessfulPlayThisSession) {
      msg +=
          ' Lagu lain di sesi ini berhasil diputar — kemungkinan videonya yang bermasalah, coba lagu lain.';
    }
    return msg;
  }

  // d. LAINNYA
  String cleanMsg = '';
  if (root is PlatformException) {
    cleanMsg = root.message?.trim() ?? '';
  } else if (error is PlatformException) {
    cleanMsg = error.message?.trim() ?? '';
  } else {
    cleanMsg = root
        .toString()
        .replaceAll(RegExp(r'^(Exception|AppException):\s*'), '')
        .trim();
    if (cleanMsg.isEmpty) {
      cleanMsg = error
          .toString()
          .replaceAll(RegExp(r'^(Exception|AppException):\s*'), '')
          .trim();
    }
    // Bila string masih terbungkus format PlatformException(code, message, details, ...)
    if (cleanMsg.contains('PlatformException(')) {
      final match = RegExp(r'PlatformException\([^,]*,\s*([^,)]*)')
          .firstMatch(cleanMsg);
      if (match != null && match.group(1) != null) {
        cleanMsg = match.group(1)!.trim();
        if (cleanMsg == 'null') cleanMsg = '';
      } else {
        cleanMsg = cleanMsg
            .replaceAll(RegExp(r'PlatformException\([^)]*\)'), '')
            .trim();
      }
    }
  }

  if (cleanMsg.isEmpty) {
    return 'Gagal memutar lagu, coba lagi.';
  }

  if (cleanMsg.length > 120) {
    cleanMsg = '${cleanMsg.substring(0, 117)}...';
  }
  if (cleanMsg.endsWith('.')) {
    cleanMsg = cleanMsg.substring(0, cleanMsg.length - 1).trim();
  }
  return 'Gagal memutar lagu: $cleanMsg.';
}
