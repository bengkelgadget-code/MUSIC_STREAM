import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_handler.dart';

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;
  final String? apkChecksum;
  final int? apkSizeBytes;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.changelog,
    required this.forceUpdate,
    this.apkChecksum,
    this.apkSizeBytes,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionCode: (json['version_code'] as num?)?.toInt() ?? 1,
      versionName: (json['version_name'] as String?) ?? '1.0.0',
      downloadUrl: (json['download_url'] as String?) ?? '',
      changelog: (json['changelog'] as String?) ??
          'Pembaruan fitur & perbaikan sistem.',
      forceUpdate: (json['force_update'] as bool?) ?? false,
      apkChecksum: json['apk_checksum'] as String?,
      apkSizeBytes: (json['apk_size_bytes'] as num?)?.toInt(),
    );
  }
}

class UpdateService {
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/bengkelgadget-code/MUSIC_STREAM/main/version.json';
  static const String keyAutoDownloadUpdate = 'autoDownloadUpdate';
  static const String keyHidePlayProtectNotice = 'hidePlayProtectNotice';

  static const MethodChannel _installerChannel =
      MethodChannel('com.bengkel.setel/installer');

  static bool isDownloading = false;
  static double downloadProgress = 0.0;
  static CancelToken? _activeCancelToken;
  static UpdateInfo? pendingUpdate;
  static String? pendingApkPath;
  static StreamSubscription? _playbackWatcherSub;

  /// Pemicu instalasi file APK lokal lewat platform channel
  static Future<bool> installApk(String filePath) async {
    try {
      final res = await _installerChannel
          .invokeMethod<bool>('installApk', {'filePath': filePath});
      return res ?? false;
    } catch (e) {
      debugPrint('[UpdateService] Gagal memicu installer APK: $e');
      return false;
    }
  }

  /// Mengecek apakah audio sedang aktif diputar
  static bool isPlaybackActive() {
    try {
      return globalAudioHandler.playbackState.value.playing;
    } catch (_) {
      return false;
    }
  }

  /// Mengambil manifest version.json dengan cache-busting
  static Future<UpdateInfo?> fetchVersionInfo({Dio? client}) async {
    final dio = client ?? Dio();
    final cacheBusterUrl =
        '$versionJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    final response = await dio.get<dynamic>(
      cacheBusterUrl,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: const {
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ),
    );

    if (response.statusCode != 200 || response.data == null) {
      return null;
    }

    final dynamic rawData = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (rawData is Map<String, dynamic>) {
      return UpdateInfo.fromJson(rawData);
    }
    return null;
  }

  /// Verifikasi SHA-256 file APK terhadap checksum di manifest
  static Future<bool> verifyChecksum(File file, String expectedChecksum) async {
    if (expectedChecksum.isEmpty) return true;
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      final hash = digest.toString().toLowerCase();
      final expected = expectedChecksum.toLowerCase().trim();
      return hash == expected;
    } catch (e) {
      debugPrint('[UpdateService] Gagal menghitung checksum: $e');
      return false;
    }
  }

  static void _safeShowSnackBar(BuildContext context, SnackBar snackBar) {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    } catch (e) {
      debugPrint('[UpdateService] Tidak dapat menampilkan snackbar: $e');
    }
  }

  /// Entry point utama pengecekan update
  static Future<void> checkUpdate(
    BuildContext context, {
    bool showNoUpdateToast = false,
    Dio? client,
    bool? testIsPlaying,
    SharedPreferences? testPrefs,
  }) async {
    try {
      final updateInfo = await fetchVersionInfo(client: client);
      if (!context.mounted) return;
      if (updateInfo == null) {
        if (showNoUpdateToast) {
          _safeShowSnackBar(
            context,
            const SnackBar(
              content: Text('Gagal memeriksa pembaruan server.'),
              backgroundColor: Color(0xFF282828),
            ),
          );
        }
        return;
      }

      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (!context.mounted) return;
      final int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (updateInfo.versionCode > currentBuildNumber &&
          updateInfo.downloadUrl.isNotEmpty) {
        final prefs = testPrefs ?? await SharedPreferences.getInstance();
        if (!context.mounted) return;
        final autoDownload = prefs.getBool(keyAutoDownloadUpdate) ?? true;

        // 1. Force update: langsung tampilkan dialog modal (tanpa unduh diam-diam)
        if (updateInfo.forceUpdate) {
          if (context.mounted) {
            _showUpdateDialog(context, updateInfo: updateInfo, client: client);
          }
          return;
        }

        // 2. Non-force + Auto download NYALA: unduh otomatis di background
        if (autoDownload) {
          await _handleAutoDownloadFlow(
            context,
            updateInfo: updateInfo,
            client: client,
            testIsPlaying: testIsPlaying,
          );
          return;
        }

        // 3. Non-force + Auto download MATI: tampilkan dialog lama
        if (context.mounted) {
          _showUpdateDialog(context, updateInfo: updateInfo, client: client);
        }
      } else {
        // Sudah versi terbaru, bersihkan file update lama bila ada
        _cleanOldUpdateFiles(keepVersionCode: null);
        if (showNoUpdateToast && context.mounted) {
          _safeShowSnackBar(
            context,
            SnackBar(
              content: Text(
                  'Aplikasi Setel sudah versi terbaru (v${packageInfo.version}).'),
              backgroundColor: const Color(0xFF282828),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Error saat checkUpdate: $e');
      if (showNoUpdateToast && context.mounted) {
        _safeShowSnackBar(
          context,
          SnackBar(
            content: Text('Tidak dapat memeriksa pembaruan: $e'),
            backgroundColor: const Color(0xFF282828),
          ),
        );
      }
    }
  }

  /// Bersihkan file APK lama di direktori temporary
  static Future<void> _cleanOldUpdateFiles({int? keepVersionCode}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      for (final f in files) {
        if (f is File) {
          final name = f.uri.pathSegments.last;
          if (name.startsWith('update_Setel_') &&
              (name.endsWith('.apk') || name.endsWith('.tmp'))) {
            if (keepVersionCode != null &&
                name == 'update_Setel_v$keepVersionCode.apk') {
              continue;
            }
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Alur unduh otomatis di background ala Buku Konter
  static Future<void> _handleAutoDownloadFlow(
    BuildContext context, {
    required UpdateInfo updateInfo,
    Dio? client,
    bool? testIsPlaying,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final apkPath =
        '${tempDir.path}/update_Setel_v${updateInfo.versionCode}.apk';
    final targetFile = File(apkPath);

    // Bersihkan file update dari versi selain yang sedang diincar
    await _cleanOldUpdateFiles(keepVersionCode: updateInfo.versionCode);

    // Cek apakah file sudah pernah diunduh dan valid
    if (targetFile.existsSync()) {
      bool valid = true;
      if (updateInfo.apkChecksum != null &&
          updateInfo.apkChecksum!.isNotEmpty) {
        valid = await verifyChecksum(targetFile, updateInfo.apkChecksum!);
      }
      if (valid) {
        pendingUpdate = updateInfo;
        pendingApkPath = apkPath;
        if (context.mounted) {
          _offerInstallationWhenSafe(context,
              updateInfo: updateInfo,
              apkPath: apkPath,
              testIsPlaying: testIsPlaying);
        }
        return;
      } else {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
    }

    if (isDownloading) return;

    // Mulai unduh otomatis di background
    isDownloading = true;
    downloadProgress = 0.0;
    _activeCancelToken = CancelToken();

    final tmpPath =
        '${tempDir.path}/update_Setel_v${updateInfo.versionCode}.tmp';
    final tmpFile = File(tmpPath);
    if (tmpFile.existsSync()) {
      try {
        tmpFile.deleteSync();
      } catch (_) {}
    }

    if (!context.mounted) return;
    // Tampilkan toast kecil non-modal
    _safeShowSnackBar(
      context,
      SnackBar(
        content: Text(
            'Mengunduh pembaruan v${updateInfo.versionName} di latar belakang...'),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF1DB954),
      ),
    );

    int retryCount = 0;
    bool success = false;
    final dio = client ?? Dio();

    while (retryCount <= 1 && !success) {
      try {
        await dio.download(
          updateInfo.downloadUrl,
          tmpPath,
          cancelToken: _activeCancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              downloadProgress = (received / total) * 100;
            } else if (updateInfo.apkSizeBytes != null &&
                updateInfo.apkSizeBytes! > 0) {
              downloadProgress =
                  (received / updateInfo.apkSizeBytes!) * 100;
            }
          },
        );
        success = true;
      } catch (e) {
        retryCount++;
        if (retryCount > 1) {
          debugPrint('[UpdateService] Gagal unduh update setelah retry: $e');
          try {
            if (tmpFile.existsSync()) tmpFile.deleteSync();
          } catch (_) {}
          isDownloading = false;
          if (context.mounted) {
            _safeShowSnackBar(
              context,
              SnackBar(
                content: Text(
                    'Gagal mengunduh pembaruan v${updateInfo.versionName}. Periksa koneksi internet.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    isDownloading = false;

    if (!success || !tmpFile.existsSync()) {
      return;
    }

    // Verifikasi Checksum SHA-256
    if (updateInfo.apkChecksum != null &&
        updateInfo.apkChecksum!.isNotEmpty) {
      final isValid =
          await verifyChecksum(tmpFile, updateInfo.apkChecksum!);
      if (!isValid) {
        debugPrint(
            '[UpdateService] Checksum APK tidak cocok! Menghapus file sementara...');
        try {
          tmpFile.deleteSync();
        } catch (_) {}
        if (context.mounted) {
          _safeShowSnackBar(
            context,
            const SnackBar(
              content:
                  Text('File update rusak (checksum tidak cocok), coba lagi.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    // Rename atomik .tmp -> .apk
    try {
      if (targetFile.existsSync()) targetFile.deleteSync();
      tmpFile.renameSync(apkPath);
    } catch (e) {
      debugPrint('[UpdateService] Gagal rename file update: $e');
      return;
    }

    pendingUpdate = updateInfo;
    pendingApkPath = apkPath;

    if (context.mounted) {
      _offerInstallationWhenSafe(context,
          updateInfo: updateInfo,
          apkPath: apkPath,
          testIsPlaying: testIsPlaying);
    }
  }

  /// Menawarkan instalasi HANYA saat aman (tidak ada pemutaran lagu)
  static void _offerInstallationWhenSafe(
    BuildContext context, {
    required UpdateInfo updateInfo,
    required String apkPath,
    bool? testIsPlaying,
  }) {
    final isPlaying = testIsPlaying ?? isPlaybackActive();

    if (isPlaying) {
      // TIDAK aman: pemutaran sedang berjalan!
      debugPrint(
          '[UpdateService] Pembaruan siap tetapi lagu sedang diputar. Menunda dialog...');
      _safeShowSnackBar(
        context,
        const SnackBar(
          content: Text(
              'Pembaruan siap, akan ditawarkan saat pemutaran berhenti.'),
          duration: Duration(seconds: 4),
          backgroundColor: Color(0xFF282828),
        ),
      );

      // Pantau stream pemutaran: saat pause/stop, tawarkan pembaruan
      _playbackWatcherSub?.cancel();
      try {
        _playbackWatcherSub =
            globalAudioHandler.playbackState.listen((playbackState) {
          if (!playbackState.playing &&
              pendingApkPath != null &&
              File(pendingApkPath!).existsSync()) {
            _playbackWatcherSub?.cancel();
            _playbackWatcherSub = null;
            if (context.mounted) {
              _showReadyToInstallDialog(context,
                  updateInfo: updateInfo, apkPath: apkPath);
            }
          }
        });
      } catch (_) {}
    } else {
      // Aman: pemutar idle/paused
      _showReadyToInstallDialog(context,
          updateInfo: updateInfo, apkPath: apkPath);
    }
  }

  /// Dialog "Pembaruan Siap Dipasang" (Unduhan sudah selesai di background)
  static Future<void> _showReadyToInstallDialog(
    BuildContext context, {
    required UpdateInfo updateInfo,
    required String apkPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    bool hidePlayProtect = prefs.getBool(keyHidePlayProtectNotice) ?? false;
    bool dontShowAgainChecked = hidePlayProtect;

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF242424),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF1DB954)),
                  SizedBox(width: 8),
                  Text(
                    'Pembaruan Siap Dipasang',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Versi v${updateInfo.versionName} telah berhasil diunduh.',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1DB954),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Catatan Perubahan:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      updateInfo.changelog,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  if (!hidePlayProtect) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.security, size: 16, color: Colors.amber),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Catatan: Android mungkin menampilkan peringatan Play Protect saat memasang APK dari luar Play Store.',
                              style: TextStyle(fontSize: 11, color: Colors.amber),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Checkbox(
                          value: dontShowAgainChecked,
                          activeColor: const Color(0xFF1DB954),
                          onChanged: (val) {
                            setDialogState(() {
                              dontShowAgainChecked = val ?? false;
                            });
                            prefs.setBool(
                                keyHidePlayProtectNotice, dontShowAgainChecked);
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Jangan tampilkan pesan ini lagi',
                            style: TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text(
                    'Nanti',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    // Cek keamanan sekali lagi sebelum pasang
                    if (isPlaybackActive()) {
                      Navigator.pop(dialogCtx);
                      _safeShowSnackBar(
                        context,
                        const SnackBar(
                          content: Text(
                              'Hentikan pemutaran lagu terlebih dahulu sebelum memasang pembaruan.'),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(dialogCtx);
                    await installApk(apkPath);
                  },
                  child: const Text('Pasang Sekarang'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Dialog lama untuk Force Update atau ketika Auto-download dimatikan
  static void _showUpdateDialog(
    BuildContext context, {
    required UpdateInfo updateInfo,
    Dio? client,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (dialogContext) {
        double progress = 0;
        bool isDialogDownloading = false;
        String statusText = '';
        String errorMsg = '';

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PopScope(
              canPop: !updateInfo.forceUpdate && !isDialogDownloading,
              child: AlertDialog(
                backgroundColor: const Color(0xFF242424),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.system_update_rounded,
                        color: Color(0xFF1DB954)),
                    SizedBox(width: 8),
                    Text(
                      'Pembaruan Tersedia',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versi Terbaru: v${updateInfo.versionName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1DB954),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Catatan Perubahan:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF181818),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Text(
                        updateInfo.changelog,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    if (isDialogDownloading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: progress > 0 ? progress / 100 : null,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF1DB954),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              statusText,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (progress > 0)
                            Text(
                              '${progress.toInt()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1DB954),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (errorMsg.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMsg,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (!isDialogDownloading && !updateInfo.forceUpdate)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(
                        'Nanti',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  if (!isDialogDownloading)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        setDialogState(() {
                          isDialogDownloading = true;
                          statusText = 'Mulai mengunduh pembaruan...';
                          errorMsg = '';
                        });

                        try {
                          final tempDir = await getTemporaryDirectory();
                          final apkPath =
                              '${tempDir.path}/update_Setel_v${updateInfo.versionCode}.apk';
                          final dio = client ?? Dio();

                          await dio.download(
                            updateInfo.downloadUrl,
                            apkPath,
                            onReceiveProgress: (received, total) {
                              setDialogState(() {
                                if (total > 0) {
                                  progress = (received / total) * 100;
                                }
                                statusText = 'Mengunduh file APK...';
                              });
                            },
                          );

                          // Verifikasi checksum bila ada
                          if (updateInfo.apkChecksum != null &&
                              updateInfo.apkChecksum!.isNotEmpty) {
                            final file = File(apkPath);
                            final valid = await verifyChecksum(
                                file, updateInfo.apkChecksum!);
                            if (!valid) {
                              try {
                                file.deleteSync();
                              } catch (_) {}
                              setDialogState(() {
                                isDialogDownloading = false;
                                errorMsg =
                                    'File update rusak (checksum tidak cocok), coba lagi.';
                              });
                              return;
                            }
                          }

                          setDialogState(() {
                            statusText = 'Menyiapkan pemasangan...';
                          });

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          await installApk(apkPath);
                        } catch (e) {
                          setDialogState(() {
                            isDialogDownloading = false;
                            errorMsg = 'Terjadi kesalahan: $e';
                          });
                        }
                      },
                      child: const Text('Unduh & Pasang'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
