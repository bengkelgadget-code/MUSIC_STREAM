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

/// Klasifikasi penyebab error pemutaran audio berdasarkan tipe error asli (root cause).
String classifyPlaybackError(Object error, {String? songTitle}) {
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

  final allErrorsCombined =
      '$error $root ${clientErrors.join(' ')}'.toLowerCase();

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
    final title = (songTitle != null && songTitle.trim().isNotEmpty)
        ? songTitle.trim()
        : 'Lagu ini';
    return '"$title" tidak dapat diputar (video dihapus/dibatasi/diblokir wilayah).';
  }

  // c. PROTEKSI BOT
  if (allErrorsCombined.contains('403') ||
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
      allErrorsCombined.contains('source error')) {
    return 'Gagal memuat audio: sumber stream ditolak atau kedaluwarsa. Coba putar lagi atau ganti jaringan.';
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
