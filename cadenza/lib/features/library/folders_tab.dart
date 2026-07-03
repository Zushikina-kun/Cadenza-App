import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../shared/widgets/empty_state.dart';

class FoldersTab extends ConsumerWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(scanFoldersProvider);

    return foldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (folders) {
        if (folders.isEmpty) {
          return EmptyState(
            icon: Icons.folder_outlined,
            title: 'No folders added',
            subtitle: 'Add a folder in Settings to start scanning.',
            action: TextButton(
              onPressed: () => context.go('/settings'),
              child: const Text('Open Settings'),
            ),
          );
        }

        return ListView.builder(
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            return ListTile(
              leading: const Icon(Icons.folder),
              title: Text(
                folder.folderPath.split(RegExp(r'[/\\]')).last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                folder.folderPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: folder.lastScanned != null
                  ? Text(
                      'Last scanned\n${_formatDate(folder.lastScanned!)}',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : const Text('Not yet scanned',
                      style: TextStyle(fontSize: 11)),
            );
          },
        );
      },
    );
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
