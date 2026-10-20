import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/bengkelgadget-code/MUSIC_STREAM/main/version.json';

  static Future<void> checkUpdate(BuildContext context,
      {bool showNoUpdateToast = false}) async {
    try {
      final dio = Dio();
      final response = await dio.get<dynamic>(
        versionJsonUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal memeriksa pembaruan server.'),
              backgroundColor: Color(0xFF282828),
            ),
          );
        }
        return;
      }

      final dynamic rawData = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final Map<String, dynamic> data =
          rawData is Map<String, dynamic> ? rawData : {};

      final int serverVersionCode = (data['version_code'] as num?)?.toInt() ?? 1;
      final String serverVersionName =
          (data['version_name'] as String?) ?? '1.0.0';
      final String downloadUrl = (data['download_url'] as String?) ?? '';
      final String changelog = (data['changelog'] as String?) ??
          'Pembaruan fitur & perbaikan sistem.';
      final bool forceUpdate = (data['force_update'] as bool?) ?? false;

      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (serverVersionCode > currentBuildNumber && downloadUrl.isNotEmpty) {
        if (context.mounted) {
          _showUpdateDialog(
            context,
            serverVersionName: serverVersionName,
            downloadUrl: downloadUrl,
            changelog: changelog,
            forceUpdate: forceUpdate,
          );
        }
      } else {
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Aplikasi Setel sudah versi terbaru (v${packageInfo.version}).'),
              backgroundColor: const Color(0xFF282828),
            ),
          );
        }
      }
    } catch (e) {
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tidak dapat memeriksa pembaruan: $e'),
            backgroundColor: const Color(0xFF282828),
          ),
        );
      }
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String serverVersionName,
    required String downloadUrl,
    required String changelog,
    required bool forceUpdate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) {
        double progress = 0;
        bool isDownloading = false;
        String statusText = '';
        String errorMsg = '';

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return PopScope(
              canPop: !forceUpdate && !isDownloading,
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
                      'Versi Terbaru: v$serverVersionName',
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
                        changelog,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    if (isDownloading) ...[
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
                  if (!isDownloading && !forceUpdate)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(
                        'Nanti',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  if (!isDownloading)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        setDialogState(() {
                          isDownloading = true;
                          statusText = 'Mulai mengunduh pembaruan...';
                          errorMsg = '';
                        });

                        try {
                          OtaUpdate()
                              .execute(downloadUrl,
                                  destinationFilename: 'Setel.apk')
                              .listen((OtaEvent event) {
                            setDialogState(() {
                              switch (event.status) {
                                case OtaStatus.DOWNLOADING:
                                  statusText = 'Mengunduh file APK...';
                                  progress =
                                      double.tryParse(event.value ?? '0') ?? 0;
                                  break;
                                case OtaStatus.INSTALLING:
                                  statusText = 'Memasang pembaruan...';
                                  break;
                                case OtaStatus.ALREADY_RUNNING_ERROR:
                                  statusText =
                                      'Proses unduh sedang berjalan...';
                                  break;
                                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                                  isDownloading = false;
                                  errorMsg =
                                      'Izin memasang aplikasi dari sumber ini tidak diberikan.';
                                  break;
                                case OtaStatus.INTERNAL_ERROR:
                                case OtaStatus.DOWNLOAD_ERROR:
                                case OtaStatus.CHECKSUM_ERROR:
                                default:
                                  isDownloading = false;
                                  errorMsg =
                                      'Gagal memperbarui: ${event.status} (${event.value})';
                                  break;
                              }
                            });
                          });
                        } catch (e) {
                          setDialogState(() {
                            isDownloading = false;
                            errorMsg = 'Terjadi kesalahan: $e';
                          });
                        }
                      },
                      child: const Text('Update Sekarang'),
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
