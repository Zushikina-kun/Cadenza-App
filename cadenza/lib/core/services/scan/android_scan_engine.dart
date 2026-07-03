import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/scan_folder.dart';
import '../../models/track.dart';
import '../../repositories/album_repository.dart';
import '../../repositories/scan_repository.dart';
import '../../repositories/track_repository.dart';
import '../artwork_cache_service.dart';
import '../metadata_reader_service.dart';
import 'scan_engine.dart';

const int _kProgressBatchSize = 100;

class AndroidScanEngine implements ScanEngine {
  final TrackRepository _trackRepo;
  final AlbumRepository _albumRepo;
  final ScanRepository _scanRepo;
  final MetadataReaderService _metaReader;
  final ArtworkCacheService _artworkCache;
  final OnAudioQuery _audioQuery;

  AndroidScanEngine({
    required TrackRepository trackRepo,
    required AlbumRepository albumRepo,
    required ScanRepository scanRepo,
    required MetadataReaderService metaReader,
    required ArtworkCacheService artworkCache,
    OnAudioQuery? audioQuery,
  })  : _trackRepo = trackRepo,
        _albumRepo = albumRepo,
        _scanRepo = scanRepo,
        _metaReader = metaReader,
        _artworkCache = artworkCache,
        _audioQuery = audioQuery ?? OnAudioQuery();

  @override
  Stream<ScanProgress> scan(List<ScanFolder> folders) async* {
    // ── Permission check ────────────────────────────────────────────────────
    final permStatus = await _requestPermission();
    if (!permStatus) {
      yield const ScanProgress(isComplete: true, error: 'permission_denied');
      return;
    }

    // Load existing path→timestamp map for incremental diff
    final existingMap = await _trackRepo.getAllTrackPathsWithTimestamps();
    final seenPaths = <String>{};

    // ── Query MediaStore ────────────────────────────────────────────────────
    List<SongModel> songs;
    try {
      songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );
    } catch (e) {
      debugPrint('[AndroidScanEngine] MediaStore query failed: $e');
      yield ScanProgress(isComplete: true, error: 'mediastore_failed: $e');
      return;
    }

    if (songs.isEmpty) {
      yield const ScanProgress(isComplete: true, error: 'no_audio_found');
      return;
    }

    var processed = 0;
    var inserted = 0;
    var updated = 0;
    var unchanged = 0;

    yield ScanProgress(discovered: songs.length);

    for (final song in songs) {
      final path = song.data;
      if (path.isEmpty) {
        processed++;
        continue;
      }
      seenPaths.add(path);

      final diskTs = song.dateModified != null
          ? song.dateModified! * 1000 // on_audio_query gives seconds
          : null;
      final storedTs = existingMap[path];

      if (existingMap.containsKey(path) && storedTs != null && diskTs == storedTs) {
        unchanged++;
      } else {
        // New or modified — read metadata via flutter_media_metadata
        final meta = await _metaReader.readMetadata(path);
        final artworkPath = await _artworkCache.cacheArtwork(path, meta.artworkBytes);

        final now = DateTime.now().millisecondsSinceEpoch;
        final track = Track(
          filePath: path,
          title: meta.title ?? song.title,
          artist: meta.artist ?? song.artist,
          album: meta.album ?? song.album,
          albumArtist: meta.albumArtist,
          genre: meta.genre,
          year: meta.year,
          trackNumber: meta.trackNumber ?? song.track,
          durationMs: meta.durationMs ?? song.duration,
          fileSize: song.size,
          dateAdded: existingMap.containsKey(path) ? null : now,
          dateModified: diskTs,
          artworkPath: artworkPath,
          isMissing: 0,
        );

        await _trackRepo.upsertTrack(track);
        await _albumRepo.upsertAlbumFromTrack(track);

        if (existingMap.containsKey(path)) {
          await _trackRepo.markFound(path);
          updated++;
        } else {
          inserted++;
        }
      }

      processed++;
      if (processed % _kProgressBatchSize == 0) {
        yield ScanProgress(
          discovered: songs.length,
          processed: processed,
          inserted: inserted,
          updated: updated,
          unchanged: unchanged,
        );
      }
    }

    // Mark missing tracks
    final missingPaths = existingMap.keys.toSet().difference(seenPaths);
    for (final path in missingPaths) {
      await _trackRepo.markMissing(path);
    }

    // Update last_scanned for all registered folders
    for (final folder in folders) {
      if (folder.id != null) {
        await _scanRepo.updateLastScanned(
          folder.id!,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    }

    yield ScanProgress(
      discovered: songs.length,
      processed: processed,
      inserted: inserted,
      updated: updated,
      unchanged: unchanged,
      missing: missingPaths.length,
      isComplete: true,
    );
  }

  Future<bool> _requestPermission() async {
    // Android 13+ uses READ_MEDIA_AUDIO; older versions use READ_EXTERNAL_STORAGE
    final status = await Permission.audio.status;
    if (status.isGranted) return true;

    final result = await Permission.audio.request();
    if (result.isGranted) return true;

    // Fallback for Android < 13
    final legacyResult = await Permission.storage.request();
    return legacyResult.isGranted;
  }
}
