import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils.dart';
import '../../models/song.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onPlayNext;

  const SongTile({
    super.key,
    required this.song,
    this.isCurrent = false,
    this.isPlaying = false,
    this.onTap,
    this.onPlayNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: song.thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey.shade900,
                  child: const Icon(Icons.music_note, color: Colors.white24),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey.shade900,
                  child: const Icon(Icons.music_note, color: Colors.white24),
                ),
              ),
              if (isCurrent)
                Container(
                  color: Colors.black54,
                  child: Icon(
                    isPlaying ? Icons.equalizer : Icons.pause,
                    color: activeColor,
                    size: 26,
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
          color: isCurrent ? activeColor : Colors.white,
          fontSize: 15,
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
                color: isCurrent
                    ? activeColor.withValues(alpha: 0.8)
                    : Colors.white60,
                fontSize: 13,
              ),
            ),
          ),
          if (song.durationMs > 0) ...[
            const SizedBox(width: 8),
            Text(
              formatDurationMs(song.durationMs),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      trailing: onPlayNext != null
          ? IconButton(
              icon: const Icon(Icons.playlist_play, color: Colors.white70),
              tooltip: 'Putar Berikutnya',
              onPressed: onPlayNext,
            )
          : null,
      onTap: onTap,
    );
  }
}
