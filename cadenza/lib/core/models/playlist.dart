import 'package:flutter/foundation.dart';

/// A user-created named playlist.
@immutable
class Playlist {
  final int? id;
  final String name;
  final int? dateCreated;
  final int? dateModified;

  const Playlist({
    this.id,
    required this.name,
    this.dateCreated,
    this.dateModified,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'date_created': dateCreated,
        'date_modified': dateModified,
      };

  factory Playlist.fromMap(Map<String, dynamic> map) => Playlist(
        id: map['id'] as int?,
        name: map['name'] as String,
        dateCreated: map['date_created'] as int?,
        dateModified: map['date_modified'] as int?,
      );

  Playlist copyWith({
    int? id,
    String? name,
    int? dateCreated,
    int? dateModified,
  }) =>
      Playlist(
        id: id ?? this.id,
        name: name ?? this.name,
        dateCreated: dateCreated ?? this.dateCreated,
        dateModified: dateModified ?? this.dateModified,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Playlist(id: $id, name: $name)';
}

/// A single entry in the playlist_tracks join table.
@immutable
class PlaylistTrack {
  final int playlistId;
  final int trackId;
  final int position;

  const PlaylistTrack({
    required this.playlistId,
    required this.trackId,
    required this.position,
  });

  Map<String, dynamic> toMap() => {
        'playlist_id': playlistId,
        'track_id': trackId,
        'position': position,
      };

  factory PlaylistTrack.fromMap(Map<String, dynamic> map) => PlaylistTrack(
        playlistId: map['playlist_id'] as int,
        trackId: map['track_id'] as int,
        position: map['position'] as int,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistTrack &&
          playlistId == other.playlistId &&
          trackId == other.trackId &&
          position == other.position;

  @override
  int get hashCode => Object.hash(playlistId, trackId, position);

  @override
  String toString() =>
      'PlaylistTrack(playlistId: $playlistId, trackId: $trackId, position: $position)';
}
