import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../state/providers.dart';
import '../widgets/song_tile.dart';

class HomeSearchScreen extends ConsumerStatefulWidget {
  const HomeSearchScreen({super.key});

  @override
  ConsumerState<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends ConsumerState<HomeSearchScreen> {
  final TextEditingController _textController = TextEditingController();

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
                    itemBuilder: (context, idx) {
                      final pl = libraryState.playlists[idx];
                      return ListTile(
                        leading: const Icon(Icons.playlist_play,
                            color: Colors.white70),
                        title: Text(pl.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text('${pl.songIds.length} lagu',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        onTap: () async {
                          await libraryController.addToPlaylist(pl.id, song);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Ditambahkan ke "${pl.name}"'),
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
                const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, {Song? songToAdd}) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Playlist Baru',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nama playlist...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF1DB954))),
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
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                final pl = await ref
                    .read(libraryControllerProvider.notifier)
                    .createPlaylist(name);
                if (songToAdd != null) {
                  await ref
                      .read(libraryControllerProvider.notifier)
                      .addToPlaylist(pl.id, songToAdd);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Playlist "$name" berhasil dibuat'),
                      backgroundColor: const Color(0xFF282828),
                    ),
                  );
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: 8,
      separatorBuilder: (context, index) => const Divider(
        color: Colors.white10,
        height: 1,
        indent: 80,
      ),
      itemBuilder: (context, index) {
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          title: Container(
            width: double.infinity,
            height: 14,
            margin: const EdgeInsets.only(right: 60),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          subtitle: Container(
            width: 120,
            height: 12,
            margin: const EdgeInsets.only(top: 6, right: 140),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        _textController.clear();
                        setState(() {});
                        ref.read(searchControllerProvider.notifier).clear();
                      },
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward,
                          color: Color(0xFF1DB954), size: 20),
                      onPressed: _onSearch,
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (text) {
              setState(() {});
            },
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          if (searchState.isLoading) {
            return _buildShimmerLoading();
          }

          if (searchState.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(
                      searchState.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1DB954),
                        foregroundColor: Colors.black,
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
              child: Text(
                'Tidak ada hasil untuk "${searchState.query}"',
                style: const TextStyle(color: Colors.white54),
              ),
            );
          }

          if (searchState.results.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.library_music_outlined,
                      size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'Cari Musik Favoritmu',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ketik judul lagu atau artis pada kolom di atas',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            );
          }

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
