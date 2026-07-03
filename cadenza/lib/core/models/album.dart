import 'package:flutter/foundation.dart';

/// Represents a derived album record. Albums are never created directly —
/// they are populated via INSERT OR IGNORE during scan passes.
@immutable
class Album {
  final int? id;
  final String name;
  final String? albumArtist;
  final int? year;
  final String? artworkPath;

  const Album({
    this.id,
    required this.name,
    this.albumArtist,
    this.year,
    this.artworkPath,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'album_artist': albumArtist,
        'year': year,
        'artwork_path': artworkPath,
      };

  factory Album.fromMap(Map<String, dynamic> map) => Album(
        id: map['id'] as int?,
        name: map['name'] as String,
        albumArtist: map['album_artist'] as String?,
        year: map['year'] as int?,
        artworkPath: map['artwork_path'] as String?,
      );

  Album copyWith({
    int? id,
    String? name,
    String? albumArtist,
    int? year,
    String? artworkPath,
  }) =>
      Album(
        id: id ?? this.id,
        name: name ?? this.name,
        albumArtist: albumArtist ?? this.albumArtist,
        year: year ?? this.year,
        artworkPath: artworkPath ?? this.artworkPath,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Album(id: $id, name: $name, albumArtist: $albumArtist)';
}
