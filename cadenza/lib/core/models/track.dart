import 'package:flutter/foundation.dart';

/// Represents a single audio file record in the database.
@immutable
class Track {
  final int? id;
  final String filePath;
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
  final int? dateAdded;
  final int? dateModified;
  final String? artworkPath;

  /// 0 = present, 1 = file no longer found on disk (soft-delete).
  final int isMissing;

  const Track({
    this.id,
    required this.filePath,
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
    this.dateAdded,
    this.dateModified,
    this.artworkPath,
    this.isMissing = 0,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'file_path': filePath,
        'title': title,
        'artist': artist,
        'album': album,
        'album_artist': albumArtist,
        'genre': genre,
        'year': year,
        'track_number': trackNumber,
        'disc_number': discNumber,
        'duration_ms': durationMs,
        'file_size': fileSize,
        'date_added': dateAdded,
        'date_modified': dateModified,
        'artwork_path': artworkPath,
        'is_missing': isMissing,
      };

  factory Track.fromMap(Map<String, dynamic> map) => Track(
        id: map['id'] as int?,
        filePath: map['file_path'] as String,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        albumArtist: map['album_artist'] as String?,
        genre: map['genre'] as String?,
        year: map['year'] as int?,
        trackNumber: map['track_number'] as int?,
        discNumber: map['disc_number'] as int?,
        durationMs: map['duration_ms'] as int?,
        fileSize: map['file_size'] as int?,
        dateAdded: map['date_added'] as int?,
        dateModified: map['date_modified'] as int?,
        artworkPath: map['artwork_path'] as String?,
        isMissing: (map['is_missing'] as int?) ?? 0,
      );

  Track copyWith({
    int? id,
    String? filePath,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? trackNumber,
    int? discNumber,
    int? durationMs,
    int? fileSize,
    int? dateAdded,
    int? dateModified,
    String? artworkPath,
    int? isMissing,
  }) =>
      Track(
        id: id ?? this.id,
        filePath: filePath ?? this.filePath,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        albumArtist: albumArtist ?? this.albumArtist,
        genre: genre ?? this.genre,
        year: year ?? this.year,
        trackNumber: trackNumber ?? this.trackNumber,
        discNumber: discNumber ?? this.discNumber,
        durationMs: durationMs ?? this.durationMs,
        fileSize: fileSize ?? this.fileSize,
        dateAdded: dateAdded ?? this.dateAdded,
        dateModified: dateModified ?? this.dateModified,
        artworkPath: artworkPath ?? this.artworkPath,
        isMissing: isMissing ?? this.isMissing,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track && runtimeType == other.runtimeType && filePath == other.filePath;

  @override
  int get hashCode => filePath.hashCode;

  @override
  String toString() => 'Track(id: $id, title: $title, artist: $artist, filePath: $filePath)';
}
