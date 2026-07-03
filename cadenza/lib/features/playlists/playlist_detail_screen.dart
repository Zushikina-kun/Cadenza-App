import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/track_list_tile.dart';

/// Per-screen provider for tracks in a specific playlist.
final _playlistTracksProvider =
    FutureProvider.family<List, int>((ref, playlistId) async {
  final repo = ref.read(playlistRepositoryProvider);
  return repo.getTracksForPlaylist(playlistId);
});

final _playlistNameProvider =
    FutureProvider.family<String, int>((ref, playlistId) async {
  final repo = ref.read(playlistRepositoryProvider);
  final p = await repo.getPlaylistById(playlistId);
  return p?.name ?? 'Playlist';
});

class PlaylistDetailScreen extends ConsumerWidget {
  final int playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(playlistRepositoryProvider);
    final player = ref.read(audioPlayerServiceProvider);
    final nameAsync = ref.watch(_playlistNameProvider(playlistId));
    final tracksAsync = ref.watch(_playlistTracksProvider(playlistId));

    return Scaffold(
      appBar: AppBar(
        title: Text(nameAsync.value ?? 'Playlist'),
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rawTracks) {
          // FutureProvider.family returns List<dynamic>; cast safely
          final tracks = rawTracks
              .whereType<dynamic>()
              .map((t) => t)
              .toList();

          if (tracks.isEmpty) {
            return const EmptyState(
              icon: Icons.playlist_add,
              title: 'Playlist is empty',
              subtitle: 'Long-press a track to add it here.',
            );
          }

          return ReorderableListView.builder(
            itemCount: tracks.length,
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > oldIndex) newIndex--;
              final ids = tracks
                  .map<int>((t) => (t.id as int?) ?? 0)
                  .toList();
              final moved = ids.removeAt(oldIndex);
              ids.insert(newIndex, moved);
              await repo.reorderTracks(playlistId, ids);
              ref.invalidate(_playlistTracksProvider(playlistId));
            },
            itemBuilder: (context, index) {
              final track = tracks[index];
              return TrackListTile(
                key: ValueKey(index),
                track: track,
                onTap: () async {
                  await player.playQueue(
                    tracks.cast(),
                    startIndex: index,
                  );
                  if (context.mounted) context.go('/now-playing');
                },
                onPlayNext: () => player.playNext(track),
              );
            },
          );
        },
      ),
    );
  }
}
