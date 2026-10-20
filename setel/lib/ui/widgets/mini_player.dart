import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../screens/now_playing_screen.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final song = playerState.currentSong;

    if (song == null) {
      return const SizedBox.shrink();
    }

    final duration = playerState.duration;
    final position = playerState.position;
    final progress = (duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const NowPlayingScreen(),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thin Progress Bar
              LinearProgressIndicator(
                value: progress,
                minHeight: 2.5,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF1DB954),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10.0, vertical: 6.0),
                child: Row(
                  children: [
                    // Thumbnail
                    Hero(
                      tag: 'artwork_${song.videoId}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: CachedNetworkImage(
                            imageUrl: song.thumbnailUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.music_note,
                                  color: Colors.white24, size: 20),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade900,
                              child: const Icon(Icons.music_note,
                                  color: Colors.white24, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Title & Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause Button
                    IconButton(
                      icon: Icon(
                        playerState.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      iconSize: 28,
                      onPressed: () => controller.togglePlayPause(),
                    ),

                    // Next Button
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white70),
                      iconSize: 26,
                      onPressed: () => controller.next(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
