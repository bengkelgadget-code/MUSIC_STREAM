import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils.dart';
import '../../models/song.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final bool isFavorite;
  final String? playCountText;
  final VoidCallback? onTap;
  final VoidCallback? onPlayNext;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onAddToPlaylist;

  const SongTile({
    super.key,
    required this.song,
    this.isCurrent = false,
    this.isPlaying = false,
    this.isFavorite = false,
    this.playCountText,
    this.onTap,
    this.onPlayNext,
    this.onToggleFavorite,
    this.onAddToPlaylist,
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
          if (playCountText != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                playCountText!,
                style: const TextStyle(
                  color: Color(0xFF1DB954),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (song.durationMs > 600000) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Kompilasi',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleFavorite != null)
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.redAccent : Colors.white38,
                size: 20,
              ),
              tooltip: isFavorite ? 'Hapus dari Favorit' : 'Tambah ke Favorit',
              onPressed: onToggleFavorite,
            ),
          if (onPlayNext != null || onAddToPlaylist != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
              color: const Color(0xFF282828),
              onSelected: (val) {
                if (val == 'play_next') onPlayNext?.call();
                if (val == 'add_playlist') onAddToPlaylist?.call();
              },
              itemBuilder: (context) => [
                if (onPlayNext != null)
                  const PopupMenuItem(
                    value: 'play_next',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_play, color: Colors.white70, size: 20),
                        SizedBox(width: 10),
                        Text('Putar Berikutnya',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                if (onAddToPlaylist != null)
                  const PopupMenuItem(
                    value: 'add_playlist',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_add, color: Colors.white70, size: 20),
                        SizedBox(width: 10),
                        Text('Tambah ke Playlist',
                            style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
