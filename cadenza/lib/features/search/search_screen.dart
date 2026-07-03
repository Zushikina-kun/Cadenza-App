import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../shared/widgets/track_list_tile.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);
    final player = ref.read(audioPlayerServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search songs, artists, albums…',
            border: InputBorder.none,
          ),
          onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
        ),
      ),
      body: query.length < 2
          ? const Center(
              child: Text(
                'Type at least 2 characters to search.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (tracks) {
                if (tracks.isEmpty) {
                  return Center(
                    child: Text(
                      'No results for "$query".',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return TrackListTile(
                      track: track,
                      onTap: () async {
                        await player.playQueue(tracks, startIndex: index);
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
