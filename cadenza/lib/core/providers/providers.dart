import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/db_provider.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import '../models/scan_folder.dart';
import '../models/track.dart';
import '../repositories/album_repository.dart';
import '../repositories/playlist_repository.dart';
import '../repositories/scan_repository.dart';
import '../repositories/track_repository.dart';
import '../services/artwork_cache_service.dart';
import '../services/audio/android_audio_player_service.dart';
import '../services/audio/audio_player_service.dart';
import '../services/audio/desktop_audio_player_service.dart';
import '../services/metadata_reader_service.dart';
import '../services/scan/android_scan_engine.dart';
import '../services/scan/scan_engine.dart';
import '../services/scan/windows_scan_engine.dart';

// ── Database ──────────────────────────────────────────────────────────────────

final dbProvider = Provider<DbProvider>((_) => DbProvider.instance);

// ── Repositories ──────────────────────────────────────────────────────────────

final trackRepositoryProvider = Provider<TrackRepository>(
  (ref) => SqliteTrackRepository(ref.read(dbProvider)),
);

final albumRepositoryProvider = Provider<AlbumRepository>(
  (ref) => SqliteAlbumRepository(ref.read(dbProvider)),
);

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => SqlitePlaylistRepository(ref.read(dbProvider)),
);

final scanRepositoryProvider = Provider<ScanRepository>(
  (ref) => SqliteScanRepository(ref.read(dbProvider)),
);

// ── Services ──────────────────────────────────────────────────────────────────

final metadataReaderProvider = Provider<MetadataReaderService>(
  (_) => FlutterMediaMetadataReaderService(),
);

final artworkCacheProvider = Provider<ArtworkCacheService>(
  (_) => FileArtworkCacheService(),
);

/// Platform-aware scan engine. Injected once at startup.
final scanEngineProvider = Provider<ScanEngine>((ref) {
  final trackRepo = ref.read(trackRepositoryProvider);
  final albumRepo = ref.read(albumRepositoryProvider);
  final scanRepo = ref.read(scanRepositoryProvider);
  final metaReader = ref.read(metadataReaderProvider);
  final artworkCache = ref.read(artworkCacheProvider);

  if (Platform.isAndroid) {
    return AndroidScanEngine(
      trackRepo: trackRepo,
      albumRepo: albumRepo,
      scanRepo: scanRepo,
      metaReader: metaReader,
      artworkCache: artworkCache,
    );
  } else {
    return WindowsScanEngine(
      trackRepo: trackRepo,
      albumRepo: albumRepo,
      scanRepo: scanRepo,
      metaReader: metaReader,
      artworkCache: artworkCache,
    );
  }
});

/// Platform-aware audio player service.
final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  if (Platform.isAndroid) {
    return AndroidAudioPlayerService();
  } else {
    return DesktopAudioPlayerService();
  }
});

// ── Library data ──────────────────────────────────────────────────────────────

final tracksProvider = FutureProvider<List<Track>>((ref) async {
  final repo = ref.read(trackRepositoryProvider);
  return repo.getAllTracks();
});

final albumsProvider = FutureProvider<List<Album>>((ref) async {
  final repo = ref.read(albumRepositoryProvider);
  return repo.getAllAlbums();
});

final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final repo = ref.read(playlistRepositoryProvider);
  return repo.getAllPlaylists();
});

final scanFoldersProvider = FutureProvider<List<ScanFolder>>((ref) async {
  final repo = ref.read(scanRepositoryProvider);
  return repo.getScanFolders();
});

// ── Scan state ────────────────────────────────────────────────────────────────

/// Notifier that drives the current scan progress.
class ScanNotifier extends StateNotifier<ScanState> {
  final ScanEngine _engine;
  final ScanRepository _scanRepo;
  final Ref _ref;

  ScanNotifier(this._engine, this._scanRepo, this._ref)
      : super(const ScanState.idle());

  Future<void> startScan() async {
    if (state.isScanning) return;
    state = const ScanState.scanning();

    final folders = await _scanRepo.getScanFolders();
    if (folders.isEmpty) {
      state = const ScanState.idle(message: 'No folders configured. Add a folder in Settings.');
      return;
    }

    await for (final progress in _engine.scan(folders)) {
      state = ScanState.scanning(progress: progress);
      if (progress.isComplete) {
        // Invalidate library data so tabs refresh
        _ref.invalidate(tracksProvider);
        _ref.invalidate(albumsProvider);
        _ref.invalidate(playlistsProvider);
        state = ScanState.done(progress: progress);
        break;
      }
      if (progress.error != null) {
        state = ScanState.error(message: progress.error!);
        break;
      }
    }
  }
}

final scanProvider = StateNotifierProvider<ScanNotifier, ScanState>(
  (ref) => ScanNotifier(
    ref.read(scanEngineProvider),
    ref.read(scanRepositoryProvider),
    ref,
  ),
);

// ── Scan state model ──────────────────────────────────────────────────────────

class ScanState {
  final bool isScanning;
  final bool isDone;
  final bool isError;
  final String? message;
  final dynamic progress;

  const ScanState._({
    this.isScanning = false,
    this.isDone = false,
    this.isError = false,
    this.message,
    this.progress,
  });

  const ScanState.idle({String? message})
      : this._(message: message);

  const ScanState.scanning({dynamic progress})
      : this._(isScanning: true, progress: progress);

  const ScanState.done({dynamic progress})
      : this._(isDone: true, progress: progress);

  const ScanState.error({required String message})
      : this._(isError: true, message: message);
}

// ── Search ────────────────────────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((_) => '');

final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.length < 2) return [];
  final repo = ref.read(trackRepositoryProvider);
  return repo.search(query);
});

// ── Settings ──────────────────────────────────────────────────────────────────

final themeModeProvider = StateProvider<bool>((_) => false); // false = light
