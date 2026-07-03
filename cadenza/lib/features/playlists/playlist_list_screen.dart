import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/repositories/playlist_repository.dart';
import '../../shared/widgets/empty_state.dart';

class PlaylistListScreen extends ConsumerWidget {
  const PlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final repo = ref.read(playlistRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      body: playlistsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (playlists) {
          if (playlists.isEmpty) {
            return EmptyState(
              icon: Icons.playlist_play_outlined,
              title: 'No playlists yet',
              subtitle: 'Create a playlist to organise your music.',
              action: FilledButton.icon(
                onPressed: () => _showCreateDialog(context, ref, repo),
                icon: const Icon(Icons.add),
                label: const Text('New Playlist'),
              ),
            );
          }

          return ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(playlist.name),
                trailing: PopupMenuButton<_Action>(
                  onSelected: (action) async {
                    switch (action) {
                      case _Action.rename:
                        await _showRenameDialog(context, ref, repo, playlist.id!, playlist.name);
                      case _Action.delete:
                        await _confirmDelete(context, ref, repo, playlist.id!, playlist.name);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _Action.rename, child: Text('Rename')),
                    PopupMenuItem(value: _Action.delete, child: Text('Delete')),
                  ],
                ),
                onTap: () => context.go('/playlist/${playlist.id}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref, repo),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showCreateDialog(
    BuildContext context,
    WidgetRef ref,
    PlaylistRepository repo,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              try {
                await repo.createPlaylist(name);
                ref.invalidate(playlistsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } on DuplicateNameException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    PlaylistRepository repo,
    int id,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty || name == currentName) {
                Navigator.pop(ctx);
                return;
              }
              try {
                await repo.renamePlaylist(id, name);
                ref.invalidate(playlistsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } on DuplicateNameException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PlaylistRepository repo,
    int id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repo.deletePlaylist(id);
      ref.invalidate(playlistsProvider);
    }
  }
}

enum _Action { rename, delete }
