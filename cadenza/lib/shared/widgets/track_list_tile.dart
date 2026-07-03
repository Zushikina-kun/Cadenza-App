import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/track.dart';

/// Reusable list tile for a single track. Used in Songs tab, search results,
/// playlist detail, and queue screen.
class TrackListTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToPlaylist;
  final bool isPlaying;

  const TrackListTile({
    super.key,
    required this.track,
    this.onTap,
    this.onPlayNext,
    this.onAddToPlaylist,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: _Artwork(artworkPath: track.artworkPath, isPlaying: isPlaying),
      title: Text(
        track.title ?? track.filePath.split(Platform.pathSeparator).last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isPlaying
            ? TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      subtitle: Text(
        [track.artist, track.album].whereType<String>().join(' — '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<_TrackAction>(
        onSelected: (action) {
          switch (action) {
            case _TrackAction.playNext:
              onPlayNext?.call();
            case _TrackAction.addToPlaylist:
              onAddToPlaylist?.call();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: _TrackAction.playNext,
            child: Text('Play next'),
          ),
          const PopupMenuItem(
            value: _TrackAction.addToPlaylist,
            child: Text('Add to playlist'),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

enum _TrackAction { playNext, addToPlaylist }

class _Artwork extends StatelessWidget {
  final String? artworkPath;
  final bool isPlaying;

  const _Artwork({this.artworkPath, this.isPlaying = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        isPlaying ? Icons.music_note : Icons.audio_file,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    if (artworkPath == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(artworkPath!),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
