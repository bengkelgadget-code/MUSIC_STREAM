import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../state/providers.dart';
import '../widgets/song_tile.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final textController = TextEditingController();
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
                await ref
                    .read(libraryControllerProvider.notifier)
                    .createPlaylist(name);
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
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final textController = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Ubah Nama Playlist',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nama playlist baru...',
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
                await ref
                    .read(libraryControllerProvider.notifier)
                    .renamePlaylist(playlist.id, name);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, Playlist playlist) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        title: const Text('Hapus Playlist',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Yakin ingin menghapus playlist "${playlist.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Batal', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await ref
                  .read(libraryControllerProvider.notifier)
                  .deletePlaylist(playlist.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Hapus'),
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

    final libraryState = ref.watch(libraryControllerProvider);
    final libraryController = ref.read(libraryControllerProvider.notifier);
    final playerState = ref.watch(playerControllerProvider);
    final playerController = ref.read(playerControllerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: const Text(
          'Koleksi Saya',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            tooltip: 'Tambah Playlist',
            onPressed: () => _showCreatePlaylistDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1DB954),
          indicatorWeight: 3,
          labelColor: const Color(0xFF1DB954),
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Playlist (${libraryState.playlists.length})'),
            Tab(text: 'Favorit (${libraryState.favorites.length})'),
            Tab(text: 'Riwayat (${libraryState.historySongs.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Playlist
          _buildPlaylistsTab(context, libraryState, libraryController),

          // TAB 2: Favorit
          _buildFavoritesTab(context, libraryState, libraryController,
              playerState, playerController),

          // TAB 3: Riwayat (FIFO 50)
          _buildHistoryTab(
              context, libraryState, playerState, playerController),
        ],
      ),
    );
  }

  Widget _buildPlaylistsTab(BuildContext context, LibraryState state,
      LibraryController controller) {
    if (state.playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.queue_music, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'Belum ada playlist',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              'Buat playlist pertamamu untuk mengelompokkan lagu favorit',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Buat Playlist'),
              onPressed: () => _showCreatePlaylistDialog(context),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: state.playlists.length,
      separatorBuilder: (context, index) =>
          const Divider(color: Colors.white10, height: 1),
      itemBuilder: (context, index) {
        final playlist = state.playlists[index];
        return ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF282828),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.queue_music, color: Color(0xFF1DB954)),
          ),
          title: Text(
            playlist.name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${playlist.songIds.length} lagu',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          trailing: PopupMenuButton<String>(
            icon:
                const Icon(Icons.more_vert, color: Colors.white54, size: 20),
            color: const Color(0xFF282828),
            onSelected: (val) {
              if (val == 'rename') {
                _showRenamePlaylistDialog(context, playlist);
              } else if (val == 'delete') {
                _showDeletePlaylistDialog(context, playlist);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'rename',
                child: Text('Ubah Nama',
                    style: TextStyle(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Hapus Playlist',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    PlaylistDetailScreen(playlist: playlist),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFavoritesTab(
    BuildContext context,
    LibraryState libraryState,
    LibraryController libraryController,
    PlayerControllerState playerState,
    PlayerController playerController,
  ) {
    final favorites = libraryState.favorites;
    if (favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Belum ada lagu favorit',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70),
            ),
            SizedBox(height: 8),
            Text(
              'Ketuk ikon hati pada lagu untuk menambahkannya ke sini',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${favorites.length} Lagu Favorit',
                style: const TextStyle(color: Colors.white70),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Putar Semua'),
                onPressed: () {
                  playerController.playQueue(favorites, startIndex: 0);
                },
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: favorites.length,
            separatorBuilder: (context, index) => const Divider(
              color: Colors.white10,
              height: 1,
              indent: 80,
            ),
            itemBuilder: (context, index) {
              final song = favorites[index];
              final isCurrent =
                  playerState.currentSong?.videoId == song.videoId;
              final isPlaying = isCurrent && playerState.isPlaying;

              return SongTile(
                song: song,
                isCurrent: isCurrent,
                isPlaying: isPlaying,
                isFavorite: true,
                onTap: () {
                  playerController.playQueue(favorites, startIndex: index);
                },
                onToggleFavorite: () {
                  libraryController.toggleFavorite(song);
                },
                onPlayNext: () {
                  playerController.addToQueueNext(song);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(
    BuildContext context,
    LibraryState libraryState,
    PlayerControllerState playerState,
    PlayerController playerController,
  ) {
    final historySongs = libraryState.historySongs;
    if (historySongs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Belum ada riwayat',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70),
            ),
            SizedBox(height: 8),
            Text(
              'Lagu yang kamu putar akan otomatis tercatat di sini (maks. 50)',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Terakhir Diputar (${historySongs.length})',
                style: const TextStyle(color: Colors.white70),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Putar Riwayat'),
                onPressed: () {
                  playerController.playQueue(historySongs, startIndex: 0);
                },
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: historySongs.length,
            separatorBuilder: (context, index) => const Divider(
              color: Colors.white10,
              height: 1,
              indent: 80,
            ),
            itemBuilder: (context, index) {
              final song = historySongs[index];
              final isCurrent =
                  playerState.currentSong?.videoId == song.videoId;
              final isPlaying = isCurrent && playerState.isPlaying;

              return SongTile(
                song: song,
                isCurrent: isCurrent,
                isPlaying: isPlaying,
                isFavorite: libraryState.favoriteIds.contains(song.videoId),
                onTap: () {
                  playerController.playQueue(historySongs,
                      startIndex: index);
                },
                onPlayNext: () {
                  playerController.addToQueueNext(song);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState
    extends ConsumerState<PlaylistDetailScreen> {
  List<Song> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final songs = await ref
        .read(libraryControllerProvider.notifier)
        .getSongsForPlaylist(widget.playlist.id);
    if (mounted) {
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    }
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
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Text(widget.playlist.name),
        actions: [
          if (_songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_circle_fill,
                  color: Color(0xFF1DB954), size: 36),
              tooltip: 'Putar Semua',
              onPressed: () {
                playerController.playQueue(_songs, startIndex: 0);
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : _songs.isEmpty
              ? const Center(
                  child: Text(
                    'Playlist ini belum memiliki lagu.\nTambahkan lagu dari layar pencarian.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _songs.length,
                  separatorBuilder: (context, index) => const Divider(
                    color: Colors.white10,
                    height: 1,
                    indent: 80,
                  ),
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    final isCurrent =
                        playerState.currentSong?.videoId == song.videoId;
                    final isPlaying = isCurrent && playerState.isPlaying;

                    return SongTile(
                      song: song,
                      isCurrent: isCurrent,
                      isPlaying: isPlaying,
                      isFavorite:
                          libraryState.favoriteIds.contains(song.videoId),
                      onTap: () {
                        playerController.playQueue(_songs,
                            startIndex: index);
                      },
                      onToggleFavorite: () {
                        libraryController.toggleFavorite(song);
                      },
                      onPlayNext: () {
                        playerController.addToQueueNext(song);
                      },
                    );
                  },
                ),
    );
  }
}
