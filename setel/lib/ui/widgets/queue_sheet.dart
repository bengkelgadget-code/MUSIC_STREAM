import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../state/providers.dart';

class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final queue = playerState.queue;
    final currentSong = playerState.currentSong;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Title Bar & Actions
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Daftar Antrean',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${queue.length} lagu diputar',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    if (queue.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent.shade100,
                        ),
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Hapus Semua',
                            style: TextStyle(fontSize: 13)),
                        onPressed: () {
                          controller.clearQueue();
                        },
                      ),
                  ],
                ),
              ),

              if (playerState.isAutoMix && playerState.mixSeedTitle != null)
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1DB954).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF1DB954).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: Color(0xFF1DB954), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mix Radio: Terkait "${playerState.mixSeedTitle}"',
                          style: const TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(color: Colors.white10, height: 16),

              // Queue List
              if (queue.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.queue_music,
                            size: 48, color: Colors.white24),
                        SizedBox(height: 12),
                        Text(
                          'Antrean masih kosong',
                          style: TextStyle(color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: scrollController,
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: queue.length,
                    onReorder: (oldIndex, newIndex) {
                      controller.reorderQueue(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final song = queue[index];
                      final isCurrent = song.videoId == currentSong?.videoId;
                      final activeColor =
                          Theme.of(context).colorScheme.primary;

                      return Dismissible(
                        key: ValueKey('queue_${song.videoId}_$index'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: Colors.redAccent.shade700,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          controller.removeFromQueue(index);
                        },
                        child: Container(
                          color: isCurrent
                              ? activeColor.withValues(alpha: 0.08)
                              : Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 2),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Drag Handle
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 8.0),
                                    child: Icon(Icons.drag_handle,
                                        color: Colors.white38, size: 22),
                                  ),
                                ),
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CachedNetworkImage(
                                          imageUrl: song.thumbnailUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                            color: Colors.grey.shade900,
                                            child: const Icon(Icons.music_note,
                                                color: Colors.white24,
                                                size: 20),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            color: Colors.grey.shade900,
                                            child: const Icon(Icons.music_note,
                                                color: Colors.white24,
                                                size: 20),
                                          ),
                                        ),
                                        if (isCurrent)
                                          Container(
                                            color: Colors.black54,
                                            child: Icon(
                                              playerState.isPlaying
                                                  ? Icons.equalizer
                                                  : Icons.pause,
                                              color: activeColor,
                                              size: 22,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrent ? activeColor : Colors.white,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isCurrent
                                          ? activeColor.withValues(alpha: 0.8)
                                          : Colors.white54,
                                    ),
                                  ),
                                ),
                                if (song.durationMs > 0)
                                  Text(
                                    formatDurationMs(song.durationMs),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white38,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close,
                                  size: 18, color: Colors.white38),
                              tooltip: 'Hapus dari antrean',
                              onPressed: () {
                                controller.removeFromQueue(index);
                              },
                            ),
                            onTap: () {
                              controller.playQueue(queue, startIndex: index);
                            },
                          ),
                        ),
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
