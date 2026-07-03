import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/database/db_provider.dart';
import 'core/providers/providers.dart';
import 'features/library/library_screen.dart';
import 'features/now_playing/now_playing_screen.dart';
import 'features/playlists/playlist_detail_screen.dart';
import 'features/playlists/playlist_list_screen.dart';
import 'features/queue/queue_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'shared/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Platform-specific init ────────────────────────────────────────────────
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Required before any sqflite_common_ffi usage on desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Route just_audio through libmpv on Windows for reliable format support
    JustAudioMediaKit.ensureInitialized();
  }

  // ── Restore persisted theme preference ────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('dark_mode') ?? false;

  // ── Database smoke-check ───────────────────────────────────────────────────
  // Attempt DB init early; if it fails the error screen shows instead of library.
  bool dbInitFailed = false;
  String dbInitError = '';
  try {
    await DbProvider.instance.database;
  } on DatabaseInitException catch (e) {
    dbInitFailed = true;
    dbInitError = e.message;
  } catch (e) {
    dbInitFailed = true;
    dbInitError = e.toString();
  }

  runApp(
    ProviderScope(
      overrides: [
        // Seed the theme state from persisted prefs
        themeModeProvider.overrideWith((_) => isDark),
      ],
      child: dbInitFailed
          ? _DbErrorApp(message: dbInitError)
          : const CadenzaApp(),
    ),
  );
}

// ── Router ─────────────────────────────────────────────────────────────────────

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
    GoRoute(path: '/now-playing', builder: (_, __) => const NowPlayingScreen()),
    GoRoute(path: '/queue', builder: (_, __) => const QueueScreen()),
    GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/playlists', builder: (_, __) => const PlaylistListScreen()),
    GoRoute(
      path: '/playlist/:id',
      builder: (_, state) => PlaylistDetailScreen(
        playlistId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/album/:id',
      builder: (_, state) => _AlbumDetailPlaceholder(
        albumId: int.parse(state.pathParameters['id']!),
      ),
    ),
  ],
);

// ── Root app ───────────────────────────────────────────────────────────────────

class CadenzaApp extends ConsumerWidget {
  const CadenzaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Cadenza',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ── DB error fallback ─────────────────────────────────────────────────────────

class _DbErrorApp extends StatelessWidget {
  final String message;
  const _DbErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Database could not be initialized.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Album detail placeholder (Phase 1 — just shows tracks list) ──────────────

class _AlbumDetailPlaceholder extends ConsumerWidget {
  final int albumId;
  const _AlbumDetailPlaceholder({required this.albumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumRepo = ref.read(albumRepositoryProvider);
    final player = ref.read(audioPlayerServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Album')),
      body: FutureBuilder(
        future: albumRepo.getTracksForAlbum(albumId),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tracks = snapshot.data!;
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (ctx, i) {
              final t = tracks[i];
              return ListTile(
                leading: Text(t.trackNumber?.toString() ?? '—'),
                title: Text(t.title ?? t.filePath.split('/').last),
                subtitle: Text(t.artist ?? ''),
                onTap: () async {
                  await player.playQueue(tracks, startIndex: i);
                  if (ctx.mounted) context.go('/now-playing');
                },
              );
            },
          );
        },
      ),
    );
  }
}
