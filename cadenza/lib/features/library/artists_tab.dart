import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/artist.dart';
import '../../core/providers/providers.dart';
import '../../shared/widgets/empty_state.dart';

/// Loads artists directly from the DB (no dedicated ArtistRepository in Phase 1).
final _artistsProvider = FutureProvider<List<Artist>>((ref) async {
  final db = await ref.read(dbProvider).database;
  final rows = await db.query('artists', orderBy: 'name COLLATE NOCASE ASC');
  return rows.map(Artist.fromMap).toList();
});

class ArtistsTab extends ConsumerWidget {
  const ArtistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = ref.watch(_artistsProvider);

    return artistsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (artists) {
        if (artists.isEmpty) {
          return const EmptyState(
            icon: Icons.person_outline,
            title: 'No artists found',
            subtitle: 'Scan your music library to see artists here.',
          );
        }

        return ListView.builder(
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        );
      },
    );
  }
}
