import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery_categories.dart';
import '../../models/song.dart';
import '../../services/update_service.dart';
import '../../state/providers.dart';
import '../widgets/song_tile.dart';
import 'discovery_playlist_screen.dart';

class HomeSearchScreen extends ConsumerStatefulWidget {
  const HomeSearchScreen({super.key});

  @override
  ConsumerState<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends ConsumerState<HomeSearchScreen> {
  final TextEditingController _textController = TextEditingController();
  Timer? _debounceTimer;
  List<String> _suggestions = [];
  late Future<List<DiscoveryCategory>> _categoriesFuture;
  bool _isRefreshingCategories = false;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = DiscoveryConfigService().getCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        UpdateService.checkUpdate(context, showNoUpdateToast: false);
      }
    });
  }

  Future<void> _refreshCategories() async {
    setState(() {
      _isRefreshingCategories = true;
    });
    try {
      final updated =
          await DiscoveryConfigService().getCategories(forceRefresh: true);
      if (mounted) {
        setState(() {
          _categoriesFuture = Future.value(updated);
          _isRefreshingCategories = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kategori playlist berhasil diperbarui'),
            backgroundColor: Color(0xFF282828),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isRefreshingCategories = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onSearch() {
    _debounceTimer?.cancel();
    setState(() {
      _suggestions = [];
    });
    final query = _textController.text.trim();
    if (query.isNotEmpty) {
      FocusScope.of(context).unfocus();
      ref.read(searchControllerProvider.notifier).search(query);
    }
  }

  void _showAddToPlaylistDialog(BuildContext context, Song song) {
    final libraryState = ref.read(libraryControllerProvider);
    final libraryController = ref.read(libraryControllerProvider.notifier);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Tambah ke Playlist',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add, color: Color(0xFF1DB954)),
                title: const Text('Buat Playlist Baru',
                    style: TextStyle(color: Color(0xFF1DB954))),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreatePlaylistDialog(context, songToAdd: song);
                },
              ),
              const Divider(color: Colors.white10),
              if (libraryState.playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('Belum ada playlist',
                      style: TextStyle(color: Colors.white38)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: libraryState.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = libraryState.playlists[index];
                      final isAlreadyAdded =
                          playlist.songIds.contains(song.videoId);

                      return ListTile(
                        leading: const Icon(Icons.playlist_play,
                            color: Colors.white70),
                        title: Text(playlist.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text('${playlist.songIds.length} lagu',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        trailing: isAlreadyAdded
                            ? const Icon(Icons.check,
                                color: Color(0xFF1DB954), size: 20)
                            : null,
                        onTap: isAlreadyAdded
                            ? null
                            : () async {
                                await libraryController.addToPlaylist(
                                    playlist.id, song);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      duration: const Duration(seconds: 2),
                                      content: Text(
                                          'Ditambahkan ke playlist "${playlist.name}"'),
                                      backgroundColor: const Color(0xFF282828),
                                    ),
                                  );
                                }
                              },
                      );
                    },
                  ),
                ),
            ],
          ),
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

  void _showCreatePlaylistDialog(BuildContext context, {Song? songToAdd}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Playlist Baru',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nama playlist',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final playlist = await ref
                    .read(libraryControllerProvider.notifier)
                    .createPlaylist(name);
                if (songToAdd != null) {
                  await ref
                      .read(libraryControllerProvider.notifier)
                      .addToPlaylist(playlist.id, songToAdd);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      content: Text('Playlist "$name" berhasil dibuat'),
                      backgroundColor: const Color(0xFF282828),
                    ),
                  );
                }
              }
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingSection() {
    final ytService = ref.read(youtubeServiceProvider);

    return FutureBuilder<List<Song>>(
      future: ytService
          .search('lagu pop indonesia terbaru official video', limit: 15),
      builder: (context, snapshot) {
        final trendingSongs = (snapshot.data ?? [])
            .where((s) => s.durationMs > 0 && s.durationMs <= 600000)
            .take(10)
            .toList();

        if (trendingSongs.isEmpty) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final playerState = ref.watch(playerControllerProvider);
        final playerController =
            ref.read(playerControllerProvider.notifier);
        final libraryState = ref.watch(libraryControllerProvider);
        final libraryController =
            ref.read(libraryControllerProvider.notifier);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Paling Sering Diputar di YouTube 🔥',
              onViewAll: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DiscoveryPlaylistScreen(
                      category: DiscoveryCategory(
                        id: 'paling-sering-diputar-yt',
                        title: 'Paling Sering Diputar di YouTube',
                        group: 'INDO',
                        searchQuery:
                            'top hits lagu indonesia terpopuler paling sering diputar official music video',
                        iconName: 'local_fire_department',
                        gradientColors: [
                          Color(0xFFFF9100),
                          Color(0xFFFF5252),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: trendingSongs.length,
              separatorBuilder: (context, index) => const Divider(
                color: Colors.white10,
                height: 1,
                indent: 80,
              ),
              itemBuilder: (context, index) {
                final song = trendingSongs[index];
                final isCurrent =
                    playerState.currentSong?.videoId == song.videoId;
                final isPlaying = isCurrent && playerState.isPlaying;
                final isFavorite =
                    libraryState.favoriteIds.contains(song.videoId);

                return SongTile(
                  song: song,
                  isCurrent: isCurrent,
                  isPlaying: isPlaying,
                  isFavorite: isFavorite,
                  playCountText: '#${index + 1} Trending',
                  onTap: () {
                    playerController.playQueue(
                      trendingSongs,
                      startIndex: index,
                    );
                  },
                  onToggleFavorite: () {
                    libraryController.toggleFavorite(song);
                  },
                  onPlayNext: () {
                    playerController.addToQueueNext(song);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        duration: const Duration(seconds: 2),
                        content:
                            Text('"${song.title}" diputar berikutnya'),
                        backgroundColor: const Color(0xFF282828),
                      ),
                    );
                  },
                  onAddToPlaylist: () {
                    _showAddToPlaylistDialog(context, song);
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildDiscoverySection() {
    return FutureBuilder<List<DiscoveryCategory>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final allCategories = snapshot.data ?? const [];
        final indo = allCategories.where((c) => c.group == 'INDO').toList();
        final manca = allCategories.where((c) => c.group == 'MANCA').toList();

        return ListView(
          padding: const EdgeInsets.only(top: 16, bottom: 80),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Cari musik favoritmu di Setel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            _buildSectionHeader(
              'Playlist Indo Terbaik 🇮🇩',
              onRefresh: _refreshCategories,
              isRefreshing: _isRefreshingCategories,
            ),
            const SizedBox(height: 12),
            if (indo.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: indo.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    return _DiscoveryCategoryCard(category: indo[index]);
                  },
                ),
              ),
            const SizedBox(height: 28),
            _buildSectionHeader('Playlist Manca Terbaik 🌍'),
            const SizedBox(height: 12),
            if (manca.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: manca.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    return _DiscoveryCategoryCard(category: manca[index]);
                  },
                ),
              ),
            const SizedBox(height: 28),
            _buildTrendingSection(),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(
    String title, {
    VoidCallback? onRefresh,
    bool isRefreshing = false,
    VoidCallback? onViewAll,
    String? viewAllText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                viewAllText ?? 'Lihat 50 Lagu',
                style: const TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (onRefresh != null)
            isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh,
                        color: Colors.white60, size: 20),
                    tooltip: 'Perbarui Kategori',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onRefresh,
                  ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlayerControllerState>(playerControllerProvider,
        (previous, next) {
      if (next.playbackError != null &&
          next.playbackError != previous?.playbackError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.playbackError!),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        ref.read(playerControllerProvider.notifier).clearPlaybackError();
      }
    });

    final searchState = ref.watch(searchControllerProvider);
    final playerState = ref.watch(playerControllerProvider);
    final playerController = ref.read(playerControllerProvider.notifier);
    final libraryState = ref.watch(libraryControllerProvider);
    final libraryController = ref.read(libraryControllerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(24),
          ),
          child: TextField(
            controller: _textController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _onSearch(),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Cari lagu, artis, atau album...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              suffixIcon: _textController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          color: Colors.white54, size: 20),
                      onPressed: () {
                        _debounceTimer?.cancel();
                        setState(() {
                          _textController.clear();
                          _suggestions = [];
                        });
                        ref.read(searchControllerProvider.notifier).clear();
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (text) {
              _debounceTimer?.cancel();
              final query = text.trim();
              if (query.length < 2) {
                setState(() {
                  _suggestions = [];
                });
                if (text.isEmpty) {
                  ref.read(searchControllerProvider.notifier).clear();
                }
              } else {
                setState(() {});
                _debounceTimer =
                    Timer(const Duration(milliseconds: 300), () async {
                  final q = _textController.text.trim();
                  if (q.length >= 2) {
                    final ytService = ref.read(youtubeServiceProvider);
                    final results = await ytService.getSuggestions(q);
                    if (mounted && _textController.text.trim() == q) {
                      setState(() {
                        _suggestions = results;
                      });
                    }
                  }
                });
              }
            },
          ),
        ),
      ),
      body: Stack(
        children: [
          Builder(
            builder: (context) {
              if (searchState.isLoading) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                  ),
                );
              }

              if (searchState.error != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(
                          searchState.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _onSearch,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (searchState.results.isEmpty &&
                  searchState.query.isNotEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off,
                          size: 54, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text(
                        'Tidak ditemukan hasil untuk "${searchState.query}"',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              // Saat pencarian kosong, tampilkan Discovery Categories
              if (searchState.results.isEmpty) {
                return _buildDiscoverySection();
              }

              // Hasil Pencarian Aktif
              return ListView.separated(
                padding: const EdgeInsets.only(top: 8, bottom: 80),
                itemCount: searchState.results.length,
                separatorBuilder: (context, index) => const Divider(
                  color: Colors.white10,
                  height: 1,
                  indent: 80,
                ),
                itemBuilder: (context, index) {
                  final song = searchState.results[index];
                  final isCurrent =
                      playerState.currentSong?.videoId == song.videoId;
                  final isPlaying = isCurrent && playerState.isPlaying;
                  final isFavorite =
                      libraryState.favoriteIds.contains(song.videoId);

                  return SongTile(
                    song: song,
                    isCurrent: isCurrent,
                    isPlaying: isPlaying,
                    isFavorite: isFavorite,
                    onTap: () {
                      playerController.playQueue(
                        searchState.results,
                        startIndex: index,
                      );
                    },
                    onToggleFavorite: () {
                      libraryController.toggleFavorite(song);
                    },
                    onPlayNext: () {
                      playerController.addToQueueNext(song);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          content: Text('"${song.title}" diputar berikutnya'),
                          backgroundColor: const Color(0xFF282828),
                        ),
                      );
                    },
                    onAddToPlaylist: () {
                      _showAddToPlaylistDialog(context, song);
                    },
                  );
                },
              );
            },
          ),
          if (_suggestions.isNotEmpty)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF121212),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, index) => const Divider(
                    color: Colors.white10,
                    height: 1,
                    indent: 56,
                  ),
                  itemBuilder: (context, index) {
                    final suggestion = _suggestions[index];
                    return ListTile(
                      leading: const Icon(Icons.search,
                          color: Colors.white54, size: 20),
                      title: Text(
                        suggestion,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                      trailing: const Icon(Icons.north_west,
                          color: Colors.white30, size: 16),
                      onTap: () {
                        _debounceTimer?.cancel();
                        _textController.text = suggestion;
                        _textController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: suggestion.length),
                        );
                        setState(() {
                          _suggestions = [];
                        });
                        _onSearch();
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscoveryCategoryCard extends StatelessWidget {
  final DiscoveryCategory category;

  const _DiscoveryCategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DiscoveryPlaylistScreen(category: category),
          ),
        );
      },
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: category.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: category.gradientColors.first.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              bottom: -8,
              child: Icon(
                category.icon,
                size: 56,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  category.icon,
                  size: 26,
                  color: Colors.white,
                ),
                Text(
                  category.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
