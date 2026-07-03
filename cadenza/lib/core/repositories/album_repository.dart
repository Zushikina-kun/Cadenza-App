import 'package:sqflite/sqflite.dart';

import '../database/db_provider.dart';
import '../models/album.dart';
import '../models/track.dart';

abstract class AlbumRepository {
  Future<List<Album>> getAllAlbums();
  Future<List<Track>> getTracksForAlbum(int albumId);

  /// Derives an Album record from the given Track using INSERT OR IGNORE.
  /// Only inserts when [track.album] is non-null.
  Future<void> upsertAlbumFromTrack(Track track);
}

class SqliteAlbumRepository implements AlbumRepository {
  final DbProvider _db;

  SqliteAlbumRepository(this._db);

  @override
  Future<List<Album>> getAllAlbums() async {
    final db = await _db.database;
    final rows = await db.query(
      'albums',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Album.fromMap).toList();
  }

  @override
  Future<List<Track>> getTracksForAlbum(int albumId) async {
    final db = await _db.database;
    final albumRows = await db.query(
      'albums',
      where: 'id = ?',
      whereArgs: [albumId],
      limit: 1,
    );
    if (albumRows.isEmpty) return [];

    final albumName = albumRows.first['name'] as String;
    final albumArtist = albumRows.first['album_artist'] as String?;

    final List<Map<String, Object?>> trackRows;
    if (albumArtist != null) {
      trackRows = await db.query(
        'tracks',
        where: 'album = ? AND album_artist = ? AND is_missing = 0',
        whereArgs: [albumName, albumArtist],
        orderBy: 'disc_number ASC, track_number ASC',
      );
    } else {
      trackRows = await db.query(
        'tracks',
        where: 'album = ? AND is_missing = 0',
        whereArgs: [albumName],
        orderBy: 'disc_number ASC, track_number ASC',
      );
    }

    return trackRows.map(Track.fromMap).toList();
  }

  @override
  Future<void> upsertAlbumFromTrack(Track track) async {
    if (track.album == null) return;
    final db = await _db.database;
    await db.insert(
      'albums',
      {
        'name': track.album,
        'album_artist': track.albumArtist,
        'year': track.year,
        'artwork_path': track.artworkPath,
      },
      // IGNORE keeps the first-inserted row intact; artwork updates handled separately
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
