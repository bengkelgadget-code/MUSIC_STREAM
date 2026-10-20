import 'package:flutter/material.dart';

class DiscoveryCategory {
  final String id;
  final String title;
  final String searchQuery;
  final IconData icon;
  final List<Color> gradientColors;

  const DiscoveryCategory({
    required this.id,
    required this.title,
    required this.searchQuery,
    required this.icon,
    required this.gradientColors,
  });
}

const List<DiscoveryCategory> indoCategories = [
  DiscoveryCategory(
    id: 'top_hits_indo',
    title: 'Top Hits Indonesia',
    searchQuery: 'Top Hits Indonesia terbaru',
    icon: Icons.trending_up,
    gradientColors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
  ),
  DiscoveryCategory(
    id: 'lagu_indo_terbaru',
    title: 'Lagu Indonesia Terbaru',
    searchQuery: 'Lagu Indonesia terbaru',
    icon: Icons.new_releases_outlined,
    gradientColors: [Color(0xFF00B0FF), Color(0xFF00E676)],
  ),
  DiscoveryCategory(
    id: 'pop_indo',
    title: 'Pop Indonesia',
    searchQuery: 'Pop Indonesia hits terbaru',
    icon: Icons.music_note,
    gradientColors: [Color(0xFFFF9100), Color(0xFFFF5252)],
  ),
  DiscoveryCategory(
    id: 'dangdut_koplo',
    title: 'Dangdut Koplo Hits',
    searchQuery: 'Dangdut Koplo hits terbaru',
    icon: Icons.celebration,
    gradientColors: [Color(0xFFFFD600), Color(0xFFFF6D00)],
  ),
  DiscoveryCategory(
    id: 'indie_indo',
    title: 'Indie Indonesia',
    searchQuery: 'Indie Indonesia lagu terbaru',
    icon: Icons.coffee,
    gradientColors: [Color(0xFF1DE9B6), Color(0xFF0091EA)],
  ),
  DiscoveryCategory(
    id: 'galau_indo',
    title: 'Lagu Galau Indonesia',
    searchQuery: 'Lagu Galau Indonesia hits sedih',
    icon: Icons.favorite_border,
    gradientColors: [Color(0xFF3F51B5), Color(0xFF7986CB)],
  ),
  DiscoveryCategory(
    id: 'nostalgia_2000',
    title: 'Nostalgia Indonesia 2000-an',
    searchQuery: 'Lagu Indonesia 2000an hits terbaik nostalgia',
    icon: Icons.history,
    gradientColors: [Color(0xFF8D6E63), Color(0xFF4E342E)],
  ),
  DiscoveryCategory(
    id: 'rock_indo',
    title: 'Rock Indonesia',
    searchQuery: 'Rock Indonesia lagu terbaik hits',
    icon: Icons.electric_bolt,
    gradientColors: [Color(0xFFD50000), Color(0xFF212121)],
  ),
];

const List<DiscoveryCategory> mancaCategories = [
  DiscoveryCategory(
    id: 'top_hits_global',
    title: 'Top Hits Global',
    searchQuery: 'Top Hits Global Billboard terbaru',
    icon: Icons.public,
    gradientColors: [Color(0xFF651FFF), Color(0xFF00E5FF)],
  ),
  DiscoveryCategory(
    id: 'lagu_barat_terbaru',
    title: 'Lagu Barat Terbaru',
    searchQuery: 'Lagu Barat terbaru hits billboard',
    icon: Icons.flash_on,
    gradientColors: [Color(0xFFFF4081), Color(0xFFFFAB40)],
  ),
  DiscoveryCategory(
    id: 'pop_barat',
    title: 'Pop Barat',
    searchQuery: 'Pop music hits terbaru',
    icon: Icons.audiotrack,
    gradientColors: [Color(0xFF00C853), Color(0xFF64DD17)],
  ),
  DiscoveryCategory(
    id: 'kpop_hits',
    title: 'K-Pop Hits',
    searchQuery: 'K-Pop hits terbaru',
    icon: Icons.star_border,
    gradientColors: [Color(0xFFFF1744), Color(0xFFF50057)],
  ),
  DiscoveryCategory(
    id: 'edm_dance',
    title: 'EDM & Dance Hits',
    searchQuery: 'EDM Dance hits terbaru',
    icon: Icons.speaker,
    gradientColors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
  ),
  DiscoveryCategory(
    id: 'hiphop_rnb',
    title: 'Hip-Hop & R&B',
    searchQuery: 'Hip Hop R&B hits terbaru',
    icon: Icons.headset_mic,
    gradientColors: [Color(0xFFFF6F00), Color(0xFFBF360C)],
  ),
  DiscoveryCategory(
    id: 'rock_legendaris',
    title: 'Rock Legendaris',
    searchQuery: 'Classic Rock hits best legendary songs',
    icon: Icons.album,
    gradientColors: [Color(0xFF37474F), Color(0xFF263238)],
  ),
  DiscoveryCategory(
    id: 'akustik_santai',
    title: 'Akustik Santai',
    searchQuery: 'Acoustic chill songs relaxing santai',
    icon: Icons.spa,
    gradientColors: [Color(0xFF26A69A), Color(0xFF00796B)],
  ),
];
