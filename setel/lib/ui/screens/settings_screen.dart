import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants.dart';
import '../../services/update_service.dart';
import '../../state/providers.dart';

void showSleepTimerBottomSheet(BuildContext context, WidgetRef ref) {
  final playerState = ref.read(playerControllerProvider);
  final controller = ref.read(playerControllerProvider.notifier);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final isTimerActive = playerState.sleepTimerEndTime != null;
      final isTrackEndActive = playerState.sleepAfterCurrentTrack;

      String statusText = 'Tidak aktif';
      if (isTimerActive) {
        final remaining =
            playerState.sleepTimerEndTime!.difference(DateTime.now());
        final mins = remaining.inMinutes;
        statusText = 'Aktif ($mins menit tersisa)';
      } else if (isTrackEndActive) {
        statusText = 'Aktif (berhenti setelah lagu ini selesai)';
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Timer Tidur (Sleep Timer)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Status: $statusText',
                style: TextStyle(
                  fontSize: 13,
                  color: (isTimerActive || isTrackEndActive)
                      ? const Color(0xFF1DB954)
                      : Colors.white38,
                ),
              ),
              const Divider(color: Colors.white10, height: 20),
              _buildTimerOption(ctx, controller, '15 Menit',
                  const Duration(minutes: 15)),
              _buildTimerOption(ctx, controller, '30 Menit',
                  const Duration(minutes: 30)),
              _buildTimerOption(ctx, controller, '45 Menit',
                  const Duration(minutes: 45)),
              _buildTimerOption(ctx, controller, '60 Menit (1 Jam)',
                  const Duration(minutes: 60)),
              ListTile(
                leading: const Icon(Icons.music_off, color: Colors.white70),
                title: const Text('Habis Lagu Ini',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  controller.setSleepTimer(null, afterCurrentTrack: true);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Timer tidur disetel: berhenti setelah lagu ini selesai'),
                      backgroundColor: Color(0xFF282828),
                    ),
                  );
                },
              ),
              if (isTimerActive || isTrackEndActive)
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.redAccent),
                  title: const Text('Matikan Timer',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    controller.cancelSleepTimer();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Timer tidur dimatikan'),
                        backgroundColor: Color(0xFF282828),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildTimerOption(BuildContext context, dynamic controller, String label,
    Duration duration) {
  return ListTile(
    leading: const Icon(Icons.timer_outlined, color: Colors.white70),
    title: Text(label, style: const TextStyle(color: Colors.white)),
    onTap: () {
      controller.setSleepTimer(duration);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Timer tidur disetel untuk $label'),
          backgroundColor: const Color(0xFF282828),
        ),
      );
    },
  );
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _cacheSizeBytes = 0;
  bool _isLoadingCache = true;
  String _appVersion = '1.2.0+13';

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCacheSize() async {
    final cacheService = ref.read(cacheServiceProvider);
    final size = await cacheService.cacheSizeBytes();
    if (mounted) {
      setState(() {
        _cacheSizeBytes = size;
        _isLoadingCache = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _showChangeLimitDialog(BuildContext context, int currentLimitMB) {
    const limits = [250, 500, 1000, 2000, 5000];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Batas Kapasitas Cache',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: limits.map((limit) {
            final label = (limit >= 1000)
                ? '${limit ~/ 1000} GB'
                : '$limit MB';

            return RadioListTile<int>(
              value: limit,
              // ignore: deprecated_member_use
              groupValue: currentLimitMB,
              title: Text(label, style: const TextStyle(color: Colors.white)),
              activeColor: const Color(0xFF1DB954),
              // ignore: deprecated_member_use
              onChanged: (val) async {
                await ref
                    .read(settingsControllerProvider.notifier)
                    .setCacheLimit(limit);
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadCacheSize();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Batas cache diubah menjadi $label'),
                      backgroundColor: const Color(0xFF282828),
                    ),
                  );
                }
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Tutup', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Hapus Semua Cache?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Semua file audio yang telah di-cache untuk pemutaran offline akan dihapus secara permanen. Anda tetap dapat memutar lagu ini secara streaming saat online.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final cacheService = ref.read(cacheServiceProvider);
              await cacheService.clearCache();
              await _loadCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Seluruh cache offline berhasil dihapus'),
                    backgroundColor: Color(0xFF282828),
                  ),
                );
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showCatalogModeDialog(BuildContext context) {
    final box =
        Hive.isBoxOpen(BOX_SETTINGS) ? Hive.box(BOX_SETTINGS) : null;
    final currentMode =
        (box?.get('catalog_mode', defaultValue: 'Otomatis') as String?) ??
            'Otomatis';

    const modes = [
      (
        'Otomatis',
        'Otomatis (Default)',
        'Gunakan Data API jika ada kunci, atau Explode'
      ),
      (
        'Data API',
        'Data API',
        'Wajib YouTube Data API Key di constants.dart'
      ),
      (
        'Explode',
        'Explode',
        'YouTube Explode Engine (Bebas kuota API)'
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Mode Akses Katalog',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: modes.map((m) {
            return RadioListTile<String>(
              value: m.$1,
              // ignore: deprecated_member_use
              groupValue: currentMode,
              title: Text(m.$2,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(m.$3,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              activeColor: const Color(0xFF1DB954),
              // ignore: deprecated_member_use
              onChanged: (val) async {
                if (val == null) return;
                if (val == 'Data API' &&
                    (YOUTUBE_API_KEY.isEmpty ||
                        YOUTUBE_API_KEY == 'ISI_DI_SINI')) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Peringatan: Kunci YouTube API belum dikonfigurasi di constants.dart.'),
                        backgroundColor: Colors.orangeAccent,
                      ),
                    );
                  }
                }
                if (Hive.isBoxOpen(BOX_SETTINGS)) {
                  await Hive.box(BOX_SETTINGS).put('catalog_mode', val);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Tutup', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showStreamFormatDialog(BuildContext context) {
    final box =
        Hive.isBoxOpen(BOX_SETTINGS) ? Hive.box(BOX_SETTINGS) : null;
    final currentFormat =
        (box?.get('stream_format', defaultValue: 'Tertinggi') as String?) ??
            'Tertinggi';

    const formats = [
      (
        'Tertinggi',
        'Tertinggi (Default)',
        'Audio-only kualitas terbaik'
      ),
      (
        'Seimbang',
        'Seimbang',
        'Audio-only ≤ 128 kbps (Hemat kuota & jernih)'
      ),
      (
        'Hemat Data',
        'Hemat Data',
        'Audio-only bitrate terendah'
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Format Stream',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: formats.map((f) {
            return RadioListTile<String>(
              value: f.$1,
              // ignore: deprecated_member_use
              groupValue: currentFormat,
              title: Text(f.$2,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(f.$3,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              activeColor: const Color(0xFF1DB954),
              // ignore: deprecated_member_use
              onChanged: (val) async {
                if (val == null) return;
                if (Hive.isBoxOpen(BOX_SETTINGS)) {
                  await Hive.box(BOX_SETTINGS).put('stream_format', val);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Tutup', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  String _getCatalogModeSubtitle(String mode) {
    switch (mode) {
      case 'Data API':
        return 'Data API (YouTube Data API v3 aktif)';
      case 'Explode':
        return 'Explode (Bebas kuota API via Explode Engine)';
      case 'Otomatis':
      default:
        return YOUTUBE_API_KEY != 'ISI_DI_SINI' && YOUTUBE_API_KEY.isNotEmpty
            ? 'Otomatis (Kunci API aktif)'
            : 'Otomatis (Explode Engine aktif)';
    }
  }

  String _getStreamFormatSubtitle(String format) {
    switch (format) {
      case 'Hemat Data':
        return 'Hemat Data (Bitrate terendah)';
      case 'Seimbang':
        return 'Seimbang (Audio-only ≤ 128 kbps)';
      case 'Tertinggi':
      default:
        return 'Tertinggi (Audio-only kualitas terbaik)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerControllerProvider);
    final cacheLimitMB = ref.watch(settingsControllerProvider);

    final box =
        Hive.isBoxOpen(BOX_SETTINGS) ? Hive.box(BOX_SETTINGS) : null;
    final catalogMode =
        (box?.get('catalog_mode', defaultValue: 'Otomatis') as String?) ??
            'Otomatis';
    final streamFormat =
        (box?.get('stream_format', defaultValue: 'Tertinggi') as String?) ??
            'Tertinggi';

    final isSleepTimerActive = playerState.sleepTimerEndTime != null ||
        playerState.sleepAfterCurrentTrack;

    String sleepTimerStatus = 'Tidak Aktif';
    if (playerState.sleepTimerEndTime != null) {
      final remaining =
          playerState.sleepTimerEndTime!.difference(DateTime.now());
      sleepTimerStatus = '${remaining.inMinutes} menit tersisa';
    } else if (playerState.sleepAfterCurrentTrack) {
      sleepTimerStatus = 'Berhenti setelah lagu ini';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text(
          'Pengaturan',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          // Section 1: Timer Tidur
          _buildSectionHeader('TIMER TIDUR (SLEEP TIMER)'),
          ListTile(
            leading: Icon(
              Icons.bedtime_outlined,
              color: isSleepTimerActive
                  ? const Color(0xFF1DB954)
                  : Colors.white70,
            ),
            title: const Text('Atur Timer Tidur',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(sleepTimerStatus,
                style: TextStyle(
                  color: isSleepTimerActive
                      ? const Color(0xFF1DB954)
                      : Colors.white38,
                  fontSize: 13,
                )),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => showSleepTimerBottomSheet(context, ref),
          ),

          const Divider(color: Colors.white10),

          // Section 2: Penyimpanan & Cache Offline
          _buildSectionHeader('PENYIMPANAN & CACHE OFFLINE'),
          ListTile(
            leading: const Icon(Icons.storage_outlined, color: Colors.white70),
            title: const Text('Total Cache Musik',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _isLoadingCache
                  ? 'Menghitung...'
                  : _formatBytes(_cacheSizeBytes),
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white38, size: 20),
              tooltip: 'Perbarui ukuran cache',
              onPressed: _loadCacheSize,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tune, color: Colors.white70),
            title: const Text('Batas Kapasitas Cache',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
                '$cacheLimitMB MB (Otomatis hapus file terlama LRU)',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _showChangeLimitDialog(context, cacheLimitMB),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined,
                color: Colors.redAccent),
            title: const Text('Hapus Cache Offline',
                style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('Kosongkan semua file musik yang tersimpan',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            onTap: () => _showClearCacheDialog(context),
          ),

          const Divider(color: Colors.white10),

          // Section 3: Katalog & Kuota
          _buildSectionHeader('KATALOG & KONEKTIVITAS'),
          ListTile(
            leading: const Icon(Icons.cloud_queue, color: Colors.white70),
            title: const Text('Mode Akses Katalog',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _getCatalogModeSubtitle(catalogMode),
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _showCatalogModeDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.bolt, color: Colors.white70),
            title: const Text('Format Stream',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _getStreamFormatSubtitle(streamFormat),
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => _showStreamFormatDialog(context),
          ),

          const Divider(color: Colors.white10),

          // Section 4: Tentang Aplikasi
          _buildSectionHeader('TENTANG SETEL'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white70),
            title: const Text('Versi Aplikasi',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(_appVersion,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          ListTile(
            leading:
                const Icon(Icons.system_update_alt, color: Colors.white70),
            title: const Text('Periksa Pembaruan',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Periksa pembaruan OTA via GitHub',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () =>
                UpdateService.checkUpdate(context, showNoUpdateToast: true),
          ),
          const ListTile(
            leading:
                Icon(Icons.verified_user_outlined, color: Colors.white70),
            title: Text('Privasi & Keamanan',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(
                'Stream URL tidak disimpan ke database. Semua data library tersimpan aman secara lokal di perangkat Anda.',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 16.0, bottom: 6.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF1DB954),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
