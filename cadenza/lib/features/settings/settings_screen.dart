import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(scanFoldersProvider);
    final scanState = ref.watch(scanProvider);
    final isDark = ref.watch(themeModeProvider);
    final scanRepo = ref.read(scanRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Theme ──────────────────────────────────────────────────────
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode'),
            value: isDark,
            onChanged: (v) async {
              ref.read(themeModeProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('dark_mode', v);
            },
          ),

          const Divider(),

          // ── Scan folders ───────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Music Folders'),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add folder',
              onPressed: () async {
                String? selectedPath;

                if (Platform.isAndroid) {
                  // Android: pick directory via file_picker
                  selectedPath = await FilePicker.platform.getDirectoryPath();
                } else {
                  // Windows: pick directory
                  selectedPath = await FilePicker.platform.getDirectoryPath();
                }

                if (selectedPath != null) {
                  await scanRepo.addScanFolder(selectedPath);
                  ref.invalidate(scanFoldersProvider);
                }
              },
            ),
          ),

          foldersAsync.when(
            loading: () => const ListTile(title: Text('Loading folders…')),
            error: (e, _) => ListTile(title: Text('Error: $e')),
            data: (folders) {
              if (folders.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'No folders added yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return Column(
                children: folders
                    .map(
                      (folder) => ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(
                          folder.folderPath.split(RegExp(r'[/\\]')).last,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          folder.folderPath,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Remove folder',
                          onPressed: () async {
                            if (folder.id != null) {
                              await scanRepo.removeScanFolder(folder.id!);
                              ref.invalidate(scanFoldersProvider);
                            }
                          },
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),

          const Divider(),

          // ── Scan now ───────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Scan Now'),
            subtitle: scanState.isScanning
                ? const Text('Scanning…')
                : scanState.isDone
                    ? const Text('Scan complete')
                    : scanState.isError
                        ? Text('Error: ${scanState.message}')
                        : const Text('Scan all registered folders'),
            trailing: scanState.isScanning
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: scanState.isScanning
                ? null
                : () => ref.read(scanProvider.notifier).startScan(),
          ),
        ],
      ),
    );
  }
}
