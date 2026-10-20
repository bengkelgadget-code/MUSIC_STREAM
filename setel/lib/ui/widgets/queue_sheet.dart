import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'song_tile.dart';

class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final queue = playerState.queue;
    final currentSong = playerState.currentSong;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daftar Antrean',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${queue.length} lagu',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10),

              if (queue.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Antrean masih kosong',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: queue.length,
                    separatorBuilder: (context, index) => const Divider(
                      color: Colors.white10,
                      height: 1,
                      indent: 80,
                    ),
                    itemBuilder: (context, index) {
                      final song = queue[index];
                      final isCurrent = song.videoId == currentSong?.videoId;

                      return SongTile(
                        song: song,
                        isCurrent: isCurrent,
                        isPlaying: isCurrent && playerState.isPlaying,
                        onTap: () {
                          controller.playQueue(queue, startIndex: index);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
