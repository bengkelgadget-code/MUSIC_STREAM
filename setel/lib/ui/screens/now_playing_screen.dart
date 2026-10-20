import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../services/audio_player_service.dart';
import '../../state/providers.dart';
import '../widgets/queue_sheet.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final libraryState = ref.watch(libraryControllerProvider);
    final libraryController = ref.read(libraryControllerProvider.notifier);
    final song = playerState.currentSong;

    if (song == null) {
      return const Scaffold(
        body: Center(
          child: Text('Tidak ada lagu yang sedang diputar'),
        ),
      );
    }

    final duration = playerState.duration;
    final position = playerState.position;
    final isFavorite = libraryState.favoriteIds.contains(song.videoId);

    // Hitung posisi slider (dalam detik)
    final totalSeconds = duration.inSeconds.toDouble();
    final currentSeconds = _dragPosition ??
        (totalSeconds > 0
            ? position.inSeconds.toDouble().clamp(0.0, totalSeconds)
            : 0.0);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Sedang Memutar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: const Color(0xFF1E1E1E),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) => const QueueSheet(),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Column(
            children: [
              const Spacer(),

              // Album Artwork
              Center(
                child: Hero(
                  tag: 'artwork_${song.videoId}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.width * 0.8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: CachedNetworkImage(
                        imageUrl: song.thumbnailUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(Icons.music_note,
                              size: 80, color: Colors.white24),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(Icons.music_note,
                              size: 80, color: Colors.white24),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Song Info & Favorite Toggle
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.redAccent : Colors.white60,
                    ),
                    iconSize: 28,
                    tooltip: isFavorite
                        ? 'Hapus dari Favorit'
                        : 'Tambah ke Favorit',
                    onPressed: () {
                      libraryController.toggleFavorite(song);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress Bar & Duration
              Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF1DB954),
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12),
                    ),
                    child: Slider(
                      min: 0.0,
                      max: totalSeconds > 0 ? totalSeconds : 1.0,
                      value: totalSeconds > 0
                          ? currentSeconds.clamp(0.0, totalSeconds)
                          : 0.0,
                      onChanged: (val) {
                        setState(() {
                          _dragPosition = val;
                        });
                      },
                      onChangeEnd: (val) {
                        controller.seek(Duration(seconds: val.round()));
                        setState(() {
                          _dragPosition = null;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDuration(
                            _dragPosition != null
                                ? Duration(seconds: _dragPosition!.round())
                                : position,
                          ),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        Text(
                          formatDuration(duration),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Player Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Shuffle Button
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: playerState.shuffle
                          ? const Color(0xFF1DB954)
                          : Colors.white38,
                    ),
                    iconSize: 26,
                    onPressed: () => controller.setShuffle(!playerState.shuffle),
                  ),

                  // Previous Button
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 38,
                    color: Colors.white,
                    onPressed: () => controller.previous(),
                  ),

                  // Play / Pause Button
                  GestureDetector(
                    onTap: () => controller.togglePlayPause(),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1DB954),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playerState.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.black,
                        size: 38,
                      ),
                    ),
                  ),

                  // Next Button
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    iconSize: 38,
                    color: Colors.white,
                    onPressed: () => controller.next(),
                  ),

                  // Repeat Button
                  IconButton(
                    icon: Icon(
                      playerState.repeatMode == RepeatMode.one
                          ? Icons.repeat_one
                          : Icons.repeat,
                      color: playerState.repeatMode != RepeatMode.off
                          ? const Color(0xFF1DB954)
                          : Colors.white38,
                    ),
                    iconSize: 26,
                    onPressed: () {
                      final nextMode = switch (playerState.repeatMode) {
                        RepeatMode.off => RepeatMode.all,
                        RepeatMode.all => RepeatMode.one,
                        RepeatMode.one => RepeatMode.off,
                      };
                      controller.setRepeatMode(nextMode);
                    },
                  ),
                ],
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
