import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchControllerProvider);
    final playerState = ref.watch(playerControllerProvider);
    final playerController = ref.read(playerControllerProvider.notifier);

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
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF1DB954),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Mencari di YouTube...',
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            );
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

              return SongTile(
                song: song,
                isCurrent: isCurrent,
                isPlaying: isPlaying,
                onTap: () {
                  playerController.playQueue(
                    searchState.results,
                    startIndex: index,
                  );
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
              );
            },
          );
        },
      ),
    );
  }
}
