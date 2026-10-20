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
    searchQuery: 'lagu pop indonesia terbaru official video',
    icon: Icons.trending_up,
    gradientColors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
  ),
  DiscoveryCategory(
    id: 'lagu_indo_terbaru',
    title: 'Lagu Indonesia Terbaru',
    searchQuery: 'lagu baru indonesia official music video',
    icon: Icons.new_releases_outlined,
    gradientColors: [Color(0xFF00B0FF), Color(0xFF00E676)],
  ),
  DiscoveryCategory(
    id: 'pop_indo',
    title: 'Pop Indonesia',
    searchQuery: 'pop indonesia hits official music video',
    icon: Icons.music_note,
    gradientColors: [Color(0xFFFF9100), Color(0xFFFF5252)],
  ),
  DiscoveryCategory(
    id: 'dangdut_koplo',
    title: 'Dangdut Koplo Hits',
    searchQuery: 'dangdut koplo terbaru official music video',
    icon: Icons.celebration,
    gradientColors: [Color(0xFFFFD600), Color(0xFFFF6D00)],
  ),
  DiscoveryCategory(
    id: 'indie_indo',
    title: 'Indie Indonesia',
    searchQuery: 'indie indonesia lagu official music video',
    icon: Icons.coffee,
    gradientColors: [Color(0xFF1DE9B6), Color(0xFF0091EA)],
  ),
  DiscoveryCategory(
    id: 'galau_indo',
    title: 'Lagu Galau Indonesia',
    searchQuery: 'lagu galau indonesia official music video',
    icon: Icons.favorite_border,
    gradientColors: [Color(0xFF3F51B5), Color(0xFF7986CB)],
  ),
  DiscoveryCategory(
    id: 'nostalgia_2000',
    title: 'Nostalgia Indonesia 2000-an',
    searchQuery: 'lagu indonesia 2000an hits official audio',
    icon: Icons.history,
    gradientColors: [Color(0xFF8D6E63), Color(0xFF4E342E)],
  ),
  DiscoveryCategory(
    id: 'rock_indo',
    title: 'Rock Indonesia',
    searchQuery: 'rock indonesia official video',
    icon: Icons.electric_bolt,
    gradientColors: [Color(0xFFD50000), Color(0xFF212121)],
  ),
];

const List<DiscoveryCategory> mancaCategories = [
  DiscoveryCategory(
    id: 'top_hits_global',
    title: 'Top Hits Global',
    searchQuery: 'top hits global official music video',
    icon: Icons.public,
    gradientColors: [Color(0xFF651FFF), Color(0xFF00E5FF)],
  ),
  DiscoveryCategory(
    id: 'lagu_barat_terbaru',
    title: 'Lagu Barat Terbaru',
    searchQuery: 'new english songs official music video',
    icon: Icons.flash_on,
    gradientColors: [Color(0xFFFF4081), Color(0xFFFFAB40)],
  ),
  DiscoveryCategory(
    id: 'pop_barat',
    title: 'Pop Barat',
    searchQuery: 'pop songs official music video',
    icon: Icons.audiotrack,
    gradientColors: [Color(0xFF00C853), Color(0xFF64DD17)],
  ),
  DiscoveryCategory(
    id: 'kpop_hits',
    title: 'K-Pop Hits',
    searchQuery: 'kpop latest official music video',
    icon: Icons.star_border,
    gradientColors: [Color(0xFFFF1744), Color(0xFFF50057)],
  ),
  DiscoveryCategory(
    id: 'edm_dance',
    title: 'EDM & Dance Hits',
    searchQuery: 'edm dance hits official music video',
    icon: Icons.speaker,
    gradientColors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
  ),
  DiscoveryCategory(
    id: 'hiphop_rnb',
    title: 'Hip-Hop & R&B',
    searchQuery: 'hip hop rnb hits official music video',
    icon: Icons.headset_mic,
    gradientColors: [Color(0xFFFF6F00), Color(0xFFBF360C)],
  ),
  DiscoveryCategory(
    id: 'rock_legendaris',
    title: 'Rock Legendaris',
    searchQuery: 'classic rock hits official video',
    icon: Icons.album,
    gradientColors: [Color(0xFF37474F), Color(0xFF263238)],
  ),
  DiscoveryCategory(
    id: 'akustik_santai',
    title: 'Akustik Santai',
    searchQuery: 'acoustic guitar chill official audio',
    icon: Icons.spa,
    gradientColors: [Color(0xFF26A69A), Color(0xFF00796B)],
  ),
];
