// ignore_for_file: constant_identifier_names

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import 'constants.dart';

class DiscoveryCategory {
  final String id;
  final String title;
  final String group; // "INDO" | "MANCA"
  final String searchQuery;
  final String iconName;
  final List<Color> gradientColors;

  const DiscoveryCategory({
    required this.id,
    required this.title,
    required this.group,
    required this.searchQuery,
    required this.iconName,
    required this.gradientColors,
  });

  IconData get icon => _resolveIcon(iconName);

  static IconData _resolveIcon(String name) {
    switch (name.toLowerCase().trim()) {
      case 'trending_up':
        return Icons.trending_up;
      case 'new_releases_outlined':
      case 'new_releases':
        return Icons.new_releases_outlined;
      case 'music_note':
        return Icons.music_note;
      case 'celebration':
        return Icons.celebration;
      case 'coffee':
        return Icons.coffee;
      case 'favorite_border':
      case 'favorite':
        return Icons.favorite_border;
      case 'history':
        return Icons.history;
      case 'electric_bolt':
        return Icons.electric_bolt;
      case 'public':
        return Icons.public;
      case 'flash_on':
        return Icons.flash_on;
      case 'audiotrack':
        return Icons.audiotrack;
      case 'star_border':
      case 'star':
        return Icons.star_border;
      case 'speaker':
        return Icons.speaker;
      case 'headset_mic':
      case 'headset':
        return Icons.headset_mic;
      case 'album':
        return Icons.album;
      case 'spa':
        return Icons.spa;
      case 'queue_music':
        return Icons.queue_music;
      case 'radio':
        return Icons.radio;
      case 'local_fire_department':
      case 'fire':
        return Icons.local_fire_department;
      default:
        return Icons.music_note;
    }
  }

  static const List<List<Color>> _curatedGradients = [
    [Color(0xFFE91E63), Color(0xFF9C27B0)],
    [Color(0xFF00B0FF), Color(0xFF00E676)],
    [Color(0xFFFF9100), Color(0xFFFF5252)],
    [Color(0xFFFFD600), Color(0xFFFF6D00)],
    [Color(0xFF1DE9B6), Color(0xFF0091EA)],
    [Color(0xFF3F51B5), Color(0xFF7986CB)],
    [Color(0xFF8D6E63), Color(0xFF4E342E)],
    [Color(0xFFD50000), Color(0xFF212121)],
    [Color(0xFF651FFF), Color(0xFF00E5FF)],
    [Color(0xFFFF4081), Color(0xFFFFAB40)],
    [Color(0xFF00C853), Color(0xFF64DD17)],
    [Color(0xFFFF1744), Color(0xFFF50057)],
    [Color(0xFF7C4DFF), Color(0xFF536DFE)],
    [Color(0xFFFF6F00), Color(0xFFBF360C)],
    [Color(0xFF37474F), Color(0xFF263238)],
    [Color(0xFF26A69A), Color(0xFF00796B)],
  ];

  static List<Color> _resolveGradient(String id) {
    final idx = id.hashCode.abs() % _curatedGradients.length;
    return _curatedGradients[idx];
  }

  factory DiscoveryCategory.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String?)?.trim() ?? '';
    final title = (json['title'] as String?)?.trim() ?? '';
    final group = (json['group'] as String?)?.trim().toUpperCase() ?? 'INDO';
    final query = (json['query'] ?? json['searchQuery'] as String?)?.trim() ?? '';
    final iconName = (json['icon'] ?? json['iconName'] as String?)?.trim() ?? 'music_note';

    return DiscoveryCategory(
      id: id,
      title: title,
      group: group == 'MANCA' ? 'MANCA' : 'INDO',
      searchQuery: query,
      iconName: iconName,
      gradientColors: _resolveGradient(id),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'group': group,
    'query': searchQuery,
    'icon': iconName,
  };
}

class DiscoveryConfigService {
  static const String REMOTE_URL =
      'https://raw.githubusercontent.com/bengkelgadget-code/MUSIC_STREAM/main/setel/assets/discovery_categories.json';

  static const String _KEY_RAW = 'categories_raw';
  static const String _KEY_FETCHED_AT = 'categories_fetched_at';

  final Dio _dio;

  DiscoveryConfigService({Dio? dio}) : _dio = dio ?? Dio();

  /// Validasi schema JSON remote / lokal
  static List<DiscoveryCategory>? validateAndParse(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return null;
      final categoriesList = decoded['categories'];
      if (categoriesList is! List) return null;

      final results = <DiscoveryCategory>[];
      for (final item in categoriesList) {
        if (item is Map) {
          final map = item.cast<String, dynamic>();
          final id = (map['id'] as String?)?.trim();
          final title = (map['title'] as String?)?.trim();
          final query = (map['query'] ?? map['searchQuery'] as String?)?.trim();

          if (id != null && id.isNotEmpty &&
              title != null && title.isNotEmpty &&
              query != null && query.isNotEmpty) {
            results.add(DiscoveryCategory.fromJson(map));
          }
        }
      }
      return results.isNotEmpty ? results : null;
    } catch (_) {
      return null;
    }
  }

  /// Ambil remote config dari GitHub dengan timeout 8 detik, simpan ke Hive box discovery_config
  Future<bool> fetchRemoteConfig() async {
    try {
      final response = await _dio.get(
        REMOTE_URL,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final rawString = response.data.toString();
        final parsed = validateAndParse(rawString);
        if (parsed != null && parsed.isNotEmpty) {
          if (Hive.isBoxOpen(BOX_DISCOVERY_CONFIG)) {
            final box = Hive.box(BOX_DISCOVERY_CONFIG);
            await box.put(_KEY_RAW, rawString);
            await box.put(_KEY_FETCHED_AT, DateTime.now().millisecondsSinceEpoch);
          }
          debugPrint('DiscoveryConfigService: Remote config berhasil diperbarui (${parsed.length} kategori)');
          return true;
        }
      }
    } catch (e) {
      debugPrint('DiscoveryConfigService: Gagal fetch remote config: $e');
    }
    return false;
  }

  /// Ambil kategori dengan urutan prioritas:
  /// (a) Cache remote bila umur < 24 jam DAN valid
  /// (b) Asset bawaan (rootBundle) sebagai fallback offline/gagal/invalid
  /// (c) Hardcoded fallback bila asset tidak dapat dimuat (misal unit test)
  Future<List<DiscoveryCategory>> getCategories({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await fetchRemoteConfig();
    }

    // 1. Cek cache Hive
    if (Hive.isBoxOpen(BOX_DISCOVERY_CONFIG)) {
      final box = Hive.box(BOX_DISCOVERY_CONFIG);
      final rawCache = box.get(_KEY_RAW) as String?;
      final fetchedAtMs = box.get(_KEY_FETCHED_AT) as int?;

      if (rawCache != null && fetchedAtMs != null) {
        final isExpired =
            DateTime.now().millisecondsSinceEpoch - fetchedAtMs > 24 * 3600 * 1000;
        if (!isExpired) {
          final parsed = validateAndParse(rawCache);
          if (parsed != null && parsed.isNotEmpty) {
            return parsed;
          }
        } else if (!forceRefresh) {
          // Expired, coba refresh di background tanpa memblokir
          fetchRemoteConfig().ignore();
          final parsed = validateAndParse(rawCache);
          if (parsed != null && parsed.isNotEmpty) {
            return parsed;
          }
        }
      }
    }

    // 2. Coba fetch remote jika belum ada cache
    if (!forceRefresh) {
      final success = await fetchRemoteConfig();
      if (success && Hive.isBoxOpen(BOX_DISCOVERY_CONFIG)) {
        final box = Hive.box(BOX_DISCOVERY_CONFIG);
        final raw = box.get(_KEY_RAW) as String?;
        if (raw != null) {
          final parsed = validateAndParse(raw);
          if (parsed != null) return parsed;
        }
      }
    }

    // 3. Fallback ke asset lokal rootBundle
    try {
      final assetJson = await rootBundle.loadString('assets/discovery_categories.json');
      final parsed = validateAndParse(assetJson);
      if (parsed != null && parsed.isNotEmpty) {
        return parsed;
      }
    } catch (e) {
      debugPrint('DiscoveryConfigService: Gagal memuat asset lokal: $e');
    }

    // 4. Fallback statis terakhir (agar tidak pernah kosong atau crash)
    return defaultHardcodedCategories;
  }

  static const List<DiscoveryCategory> defaultHardcodedCategories = [
    DiscoveryCategory(
      id: 'top-hits-indo',
      title: 'Top Hits Indonesia',
      group: 'INDO',
      searchQuery: 'lagu pop indonesia terbaru official video',
      iconName: 'trending_up',
      gradientColors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
    ),
    DiscoveryCategory(
      id: 'lagu-indo-terbaru',
      title: 'Lagu Indonesia Terbaru',
      group: 'INDO',
      searchQuery: 'lagu baru indonesia official music video',
      iconName: 'new_releases_outlined',
      gradientColors: [Color(0xFF00B0FF), Color(0xFF00E676)],
    ),
    DiscoveryCategory(
      id: 'pop-indo',
      title: 'Pop Indonesia',
      group: 'INDO',
      searchQuery: 'pop indonesia hits official music video',
      iconName: 'music_note',
      gradientColors: [Color(0xFFFF9100), Color(0xFFFF5252)],
    ),
    DiscoveryCategory(
      id: 'dangdut-koplo',
      title: 'Dangdut Koplo Hits',
      group: 'INDO',
      searchQuery: 'dangdut koplo terbaru official music video',
      iconName: 'celebration',
      gradientColors: [Color(0xFFFFD600), Color(0xFFFF6D00)],
    ),
    DiscoveryCategory(
      id: 'indie-indo',
      title: 'Indie Indonesia',
      group: 'INDO',
      searchQuery: 'indie indonesia lagu official music video',
      iconName: 'coffee',
      gradientColors: [Color(0xFF1DE9B6), Color(0xFF0091EA)],
    ),
    DiscoveryCategory(
      id: 'galau-indo',
      title: 'Lagu Galau Indonesia',
      group: 'INDO',
      searchQuery: 'lagu galau indonesia official music video',
      iconName: 'favorite_border',
      gradientColors: [Color(0xFF3F51B5), Color(0xFF7986CB)],
    ),
    DiscoveryCategory(
      id: 'nostalgia-2000',
      title: 'Nostalgia Indonesia 2000-an',
      group: 'INDO',
      searchQuery: 'lagu indonesia 2000an hits official audio',
      iconName: 'history',
      gradientColors: [Color(0xFF8D6E63), Color(0xFF4E342E)],
    ),
    DiscoveryCategory(
      id: 'rock-indo',
      title: 'Rock Indonesia',
      group: 'INDO',
      searchQuery: 'rock indonesia official video',
      iconName: 'electric_bolt',
      gradientColors: [Color(0xFFD50000), Color(0xFF212121)],
    ),
    DiscoveryCategory(
      id: 'top-hits-global',
      title: 'Top Hits Global',
      group: 'MANCA',
      searchQuery: 'billboard hot 100 official music video',
      iconName: 'public',
      gradientColors: [Color(0xFF651FFF), Color(0xFF00E5FF)],
    ),
    DiscoveryCategory(
      id: 'lagu-barat-terbaru',
      title: 'Lagu Barat Terbaru',
      group: 'MANCA',
      searchQuery: 'new english songs official music video',
      iconName: 'flash_on',
      gradientColors: [Color(0xFFFF4081), Color(0xFFFFAB40)],
    ),
    DiscoveryCategory(
      id: 'pop-barat',
      title: 'Pop Barat',
      group: 'MANCA',
      searchQuery: 'top pop hits english official music video',
      iconName: 'audiotrack',
      gradientColors: [Color(0xFF00C853), Color(0xFF64DD17)],
    ),
    DiscoveryCategory(
      id: 'kpop-hits',
      title: 'K-Pop Hits',
      group: 'MANCA',
      searchQuery: 'kpop latest official music video',
      iconName: 'star_border',
      gradientColors: [Color(0xFFFF1744), Color(0xFFF50057)],
    ),
    DiscoveryCategory(
      id: 'edm-dance',
      title: 'EDM & Dance Hits',
      group: 'MANCA',
      searchQuery: 'edm dance hits official music video',
      iconName: 'speaker',
      gradientColors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
    ),
    DiscoveryCategory(
      id: 'hiphop-rnb',
      title: 'Hip-Hop & R&B',
      group: 'MANCA',
      searchQuery: 'hip hop rnb hits official music video',
      iconName: 'headset_mic',
      gradientColors: [Color(0xFFFF6F00), Color(0xFFBF360C)],
    ),
    DiscoveryCategory(
      id: 'rock-legendaris',
      title: 'Rock Legendaris',
      group: 'MANCA',
      searchQuery: 'classic rock hits official video',
      iconName: 'album',
      gradientColors: [Color(0xFF37474F), Color(0xFF263238)],
    ),
    DiscoveryCategory(
      id: 'akustik-santai',
      title: 'Akustik Santai',
      group: 'MANCA',
      searchQuery: 'acoustic guitar chill official audio',
      iconName: 'spa',
      gradientColors: [Color(0xFF26A69A), Color(0xFF00796B)],
    ),
  ];
}
