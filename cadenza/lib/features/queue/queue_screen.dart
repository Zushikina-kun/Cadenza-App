import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/providers.dart';
import '../../shared/widgets/empty_state.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(audioPlayerServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Queue')),
      body: StreamBuilder<List>(
        stream: player.queueStream,
        initialData: player.trackQueue,
        builder: (context, snapshot) {
          final queue = snapshot.data ?? [];

          if (queue.isEmpty) {
            return const EmptyState(
              icon: Icons.queue_music_outlined,
              title: 'Queue is empty',
              subtitle: 'Play a song or album to fill the queue.',
            );
          }

          return ReorderableListView.builder(
            itemCount: queue.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              player.reorderQueue(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final track = queue[index];
              return ListTile(
                key: ValueKey(index),
                leading: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                title: Text(
                  track.title ?? track.filePath.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.artist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => player.removeFromQueue(index),
                    ),
                    const Icon(Icons.drag_handle),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
