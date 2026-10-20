import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery_categories.dart';
import '../../models/song.dart';
import '../../state/providers.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

class DiscoveryPlaylistScreen extends ConsumerStatefulWidget {
  final DiscoveryCategory category;

  const DiscoveryPlaylistScreen({
    super.key,
    required this.category,
  });

  @override
  ConsumerState<DiscoveryPlaylistScreen> createState() =>
      _DiscoveryPlaylistScreenState();
}

class _DiscoveryPlaylistScreenState
    extends ConsumerState<DiscoveryPlaylistScreen> {
  bool _isLoading = true;
  String? _error;
  List<Song> _songs = [];

  @override
  void initState() {
    super.initState();
    _fetchCategorySongs();
  }

  Future<void> _fetchCategorySongs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ytService = ref.read(youtubeServiceProvider);
      final results =
          await ytService.search(widget.category.searchQuery, limit: 50);

      const bannedKeywords = [
        'full album',
        'kompilasi',
        'nonstop',
        'non stop',
        '1 jam',
        '2 jam',
        '3 jam',
        '24 jam',
        'spotify',
        'playlist',
        'kumpulan lagu',
        'kumpulan musik',
        'lagu santai viral',
        'top 100',
        'top 50',
        'mix lagu',
        'remix nonstop',
      ];

      bool hasBannedKeyword(Song song) {
        final titleLower = song.title.toLowerCase();
        for (final kw in bannedKeywords) {
          if (titleLower.contains(kw)) {
            return true;
          }
        }
        return false;
      }

      // Filter bertingkat:
      // Tahap 1 (ketat): buang durasi > 10 menit (600000 ms) + keyword kompilasi.
      final stage1 = results.where((song) {
        if (hasBannedKeyword(song)) return false;
        if (song.durationMs > 0 && song.durationMs > 600000) return false;
        return true;
      }).toList();

      List<Song> finalSongs = stage1;

      // Bila hasil tahap 1 < 5 lagu: Tahap 2 — longgarkan cap durasi jadi 15 menit (900000 ms).
      // Filter keyword TETAP berlaku.
      if (stage1.length < 5) {
        final stage2 = results.where((song) {
          if (hasBannedKeyword(song)) return false;
          if (song.durationMs > 0 && song.durationMs > 900000) return false;
          return true;
        }).toList();
        finalSongs = stage2;
      }

      if (mounted) {
        setState(() {
          _songs = finalSongs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat lagu: $e';
          _isLoading = false;
        });
      }
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

    final playerState = ref.watch(playerControllerProvider);
    final playerController = ref.read(playerControllerProvider.notifier);
    final libraryState = ref.watch(libraryControllerProvider);
    final libraryController = ref.read(libraryControllerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.category.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      bottomNavigationBar: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Header Banner
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.category.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: widget.category.gradientColors.first
                        .withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.category.icon,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.category.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Kompilasi streaming YouTube terpopuler',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Tombol Putar Semua & Acak
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow, size: 22),
                          label: const Text(
                            'Putar Semua',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _songs.isEmpty
                              ? null
                              : () {
                                  playerController.setShuffle(false);
                                  playerController.playQueue(
                                    _songs,
                                    startIndex: 0,
                                  );
                                },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          icon: const Icon(Icons.shuffle, size: 20),
                          label: const Text(
                            'Acak',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: _songs.isEmpty
                              ? null
                              : () {
                                  playerController.setShuffle(true);
                                  final startIdx =
                                      Random().nextInt(_songs.length);
                                  playerController.playQueue(
                                    _songs,
                                    startIndex: startIdx,
                                  );
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Content States
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1DB954)),
                ),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
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
                        onPressed: _fetchCategorySongs,
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_songs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Tidak ada lagu di kategori ini',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = _songs[index];
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
                          _songs,
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
                  childCount: _songs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
