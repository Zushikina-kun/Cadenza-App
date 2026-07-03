import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

/// All the tag fields Cadenza reads from audio files.
/// Any field absent in the file is stored as null — never empty string.
class TrackMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int? durationMs;
  final int? fileSize;
  final Uint8List? artworkBytes;

  const TrackMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.durationMs,
    this.fileSize,
    this.artworkBytes,
  });

  /// Returns true when every meaningful field is null.
  bool get isEmpty =>
      title == null &&
      artist == null &&
      album == null &&
      albumArtist == null &&
      genre == null &&
      year == null &&
      trackNumber == null &&
      discNumber == null &&
      durationMs == null &&
      artworkBytes == null;
}

abstract class MetadataReaderService {
  Future<TrackMetadata> readMetadata(String filePath);
}

class FlutterMediaMetadataReaderService implements MetadataReaderService {
  @override
  Future<TrackMetadata> readMetadata(String filePath) async {
    // ── Primary: flutter_media_metadata ──────────────────────────────────
    try {
      final meta = await MetadataRetriever.fromFile(File(filePath));

      final result = TrackMetadata(
        title: _nonEmpty(meta.trackName),
        artist: _nonEmpty(meta.trackArtistNames?.join(', ')),
        album: _nonEmpty(meta.albumName),
        albumArtist: _nonEmpty(meta.albumArtistName),
        genre: _nonEmpty(meta.genre),
        year: meta.year,
        trackNumber: meta.trackNumber,
        discNumber: meta.discNumber,
        durationMs: meta.trackDuration,
        artworkBytes: meta.albumArt,
      );

      if (!result.isEmpty) return result;
    } catch (e) {
      debugPrint('[MetadataReader] flutter_media_metadata failed for $filePath: $e');
    }

    // ── Both failed: return all-null (scan continues, track is untagged) ──
    debugPrint('[MetadataReader] Reader failed for $filePath — inserting untagged track');
    return const TrackMetadata();
  }

  /// Returns null when [s] is null, empty, or whitespace-only.
  static String? _nonEmpty(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    return s.trim();
  }
}
