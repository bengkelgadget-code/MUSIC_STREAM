import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../services/audio_player_service.dart';
import '../../state/providers.dart';
import '../widgets/queue_sheet.dart';
import 'settings_screen.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  double? _dragPosition;

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
    final isSleepTimerActive = playerState.sleepTimerEndTime != null ||
        playerState.sleepAfterCurrentTrack;

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
          if (playerState.hasChapters)
            IconButton(
              icon: const Icon(Icons.format_list_bulleted),
              tooltip: 'Bagian-bagian Lagu',
              onPressed: () {
                _showChaptersBottomSheet(context, playerState, controller);
              },
            ),
          IconButton(
            icon: Icon(
              isSleepTimerActive
                  ? Icons.bedtime
                  : Icons.bedtime_outlined,
              color: isSleepTimerActive
                  ? const Color(0xFF1DB954)
                  : Colors.white70,
            ),
            tooltip: 'Timer Tidur',
            onPressed: () {
              showSleepTimerBottomSheet(context, ref);
            },
          ),
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: 'Daftar Antrean',
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
                        if (playerState.hasChapters &&
                            playerState.currentChapter != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1DB954)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Bab ${playerState.chapterIndex + 1}/${playerState.chapters.length}',
                                  style: const TextStyle(
                                    color: Color(0xFF1DB954),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  playerState.currentChapter!.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF1DB954),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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

  void _showChaptersBottomSheet(
    BuildContext context,
    PlayerControllerState playerState,
    dynamic controller,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.format_list_bulleted,
                          color: Color(0xFF1DB954), size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Bagian-bagian Lagu (${playerState.chapters.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: playerState.chapters.length,
                    itemBuilder: (context, index) {
                      final ch = playerState.chapters[index];
                      final isActive = index == playerState.chapterIndex;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 2),
                        leading: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF1DB954).withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isActive
                                  ? const Color(0xFF1DB954)
                                  : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        title: Text(
                          ch.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive
                                ? const Color(0xFF1DB954)
                                : Colors.white,
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        trailing: Text(
                          formatDurationMs(ch.positionMs),
                          style: TextStyle(
                            color: isActive
                                ? const Color(0xFF1DB954)
                                : Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          controller.seek(
                              Duration(milliseconds: ch.positionMs));
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
