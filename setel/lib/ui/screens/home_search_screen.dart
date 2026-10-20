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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        UpdateService.checkUpdate(context, showNoUpdateToast: false);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onSearch() {
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
                                      backgroundColor:
                                          const Color(0xFF282828),
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
    final textController = TextEditingController();
    final libraryController = ref.read(libraryControllerProvider.notifier);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Buat Playlist Baru',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nama Playlist',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: const UnderlineInputBorder(
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
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                final playlist =
                    await libraryController.createPlaylist(name);
                if (songToAdd != null) {
                  await libraryController.addToPlaylist(
                      playlist.id, songToAdd);
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

  Widget _buildDiscoverySection() {
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 80),
      children: [
        _buildSectionHeader('Playlist Indo Terbaik 🇮🇩'),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: indoCategories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _DiscoveryCategoryCard(category: indoCategories[index]);
            },
          ),
        ),
        const SizedBox(height: 28),
        _buildSectionHeader('Playlist Manca Terbaik 🌍'),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: mancaCategories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _DiscoveryCategoryCard(category: mancaCategories[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
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
                        setState(() {
                          _textController.clear();
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
              setState(() {});
              if (text.isEmpty) {
                ref.read(searchControllerProvider.notifier).clear();
              }
            },
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (searchState.isLoading) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
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
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14),
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

          if (searchState.results.isEmpty && searchState.query.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 54, color: Colors.white24),
                  const SizedBox(height: 12),
                  Text(
                    'Tidak ditemukan hasil untuk "${searchState.query}"',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
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
