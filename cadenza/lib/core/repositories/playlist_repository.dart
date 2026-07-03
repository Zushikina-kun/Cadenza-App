import 'package:sqflite/sqflite.dart';

import '../database/db_provider.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// Thrown when a playlist name conflicts with an existing one.
class DuplicateNameException implements Exception {
  final String message;
  DuplicateNameException(this.message);
  @override
  String toString() => 'DuplicateNameException: $message';
}

abstract class PlaylistRepository {
  Future<List<Playlist>> getAllPlaylists();
  Future<Playlist?> getPlaylistById(int id);
  Future<List<Track>> getTracksForPlaylist(int playlistId);

  /// Returns the new playlist's id. Throws [DuplicateNameException] if name taken.
  Future<int> createPlaylist(String name);

  /// Throws [DuplicateNameException] if name is taken by another playlist.
  Future<void> renamePlaylist(int id, String name);

  /// Deletes the playlist and cascades to playlist_tracks.
  Future<void> deletePlaylist(int id);

  /// Appends [trackId] to the playlist at the next available position.
  /// Duplicate entries are allowed (same track can appear multiple times).
  Future<void> addTrackToPlaylist(int playlistId, int trackId);

  /// Removes the entry at [position] and reindexes subsequent entries.
  Future<void> removeTrackAtPosition(int playlistId, int position);

  /// Replaces the full position order. [newTrackIdOrder] is the ordered list
  /// of track IDs as they should appear (may contain duplicates).
  Future<void> reorderTracks(int playlistId, List<int> newTrackIdOrder);
}

class SqlitePlaylistRepository implements PlaylistRepository {
  final DbProvider _db;

  SqlitePlaylistRepository(this._db);

  @override
  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _db.database;
    final rows = await db.query('playlists', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Playlist.fromMap).toList();
  }

  @override
  Future<Playlist?> getPlaylistById(int id) async {
    final db = await _db.database;
    final rows = await db.query('playlists', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Playlist.fromMap(rows.first);
  }

  @override
  Future<List<Track>> getTracksForPlaylist(int playlistId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      '''
      SELECT t.* FROM tracks t
      INNER JOIN playlist_tracks pt ON pt.track_id = t.id
      WHERE pt.playlist_id = ?
      ORDER BY pt.position ASC
      ''',
      [playlistId],
    );
    return rows.map(Track.fromMap).toList();
  }

  @override
  Future<int> createPlaylist(String name) async {
    final db = await _db.database;
    await _assertNameUnique(db, name);
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('playlists', {
      'name': name,
      'date_created': now,
      'date_modified': now,
    });
  }

  @override
  Future<void> renamePlaylist(int id, String name) async {
    final db = await _db.database;
    await _assertNameUnique(db, name, excludeId: id);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'playlists',
      {'name': name, 'date_modified': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deletePlaylist(int id) async {
    final db = await _db.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
    // ON DELETE CASCADE in the schema handles playlist_tracks cleanup.
  }

  @override
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    final db = await _db.database;
    final maxResult = await db.rawQuery(
      'SELECT MAX(position) AS max_pos FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    final maxPos = maxResult.first['max_pos'] as int?;
    final nextPos = (maxPos ?? -1) + 1;
    await db.insert('playlist_tracks', {
      'playlist_id': playlistId,
      'track_id': trackId,
      'position': nextPos,
    });
    await _touchModified(db, playlistId);
  }

  @override
  Future<void> removeTrackAtPosition(int playlistId, int position) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // 1. Delete the specific entry
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ? AND position = ?',
        whereArgs: [playlistId, position],
      );
      // 2. Close the gap by shifting all later positions down by 1
      await txn.rawUpdate(
        'UPDATE playlist_tracks SET position = position - 1 WHERE playlist_id = ? AND position > ?',
        [playlistId, position],
      );
    });
    await _touchModified(db, playlistId);
  }

  @override
  Future<void> reorderTracks(int playlistId, List<int> newTrackIdOrder) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      // Clear existing entries and re-insert in the specified order
      await txn.delete(
        'playlist_tracks',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      for (var i = 0; i < newTrackIdOrder.length; i++) {
        await txn.insert('playlist_tracks', {
          'playlist_id': playlistId,
          'track_id': newTrackIdOrder[i],
          'position': i,
        });
      }
    });
    await _touchModified(db, playlistId);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _assertNameUnique(
    Database db,
    String name, {
    int? excludeId,
  }) async {
    final rows = excludeId != null
        ? await db.query(
            'playlists',
            where: 'name = ? AND id != ?',
            whereArgs: [name, excludeId],
            limit: 1,
          )
        : await db.query(
            'playlists',
            where: 'name = ?',
            whereArgs: [name],
            limit: 1,
          );
    if (rows.isNotEmpty) {
      throw DuplicateNameException('A playlist named "$name" already exists.');
    }
  }

  Future<void> _touchModified(Database db, int playlistId) async {
    await db.update(
      'playlists',
      {'date_modified': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }
}
