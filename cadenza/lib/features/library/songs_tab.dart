import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/track_list_tile.dart';

class SongsTab extends ConsumerWidget {
  const SongsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(tracksProvider);
    final player = ref.read(audioPlayerServiceProvider);

    return tracksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tracks) {
        if (tracks.isEmpty) {
          return EmptyState(
            icon: Icons.library_music_outlined,
            title: 'No songs found',
            subtitle: 'Add a folder in Settings and tap Scan Now.',
            action: TextButton(
              onPressed: () => context.go('/settings'),
              child: const Text('Open Settings'),
            ),
          );
        }

        final currentTrack = ref.watch(
          audioPlayerServiceProvider.select((_) => player.currentTrack),
        );

        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return TrackListTile(
              track: track,
              isPlaying: currentTrack?.filePath == track.filePath,
              onTap: () async {
                await player.playQueue(tracks, startIndex: index);
                if (context.mounted) context.go('/now-playing');
              },
              onPlayNext: () => player.playNext(track),
            );
          },
        );
      },
    );
  }
}
