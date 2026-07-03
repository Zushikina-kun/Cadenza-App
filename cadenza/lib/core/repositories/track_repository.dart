import 'package:sqflite/sqflite.dart';

import '../database/db_provider.dart';
import '../models/track.dart';

/// Counts of rows affected during a scan pass.
class ScanStats {
  final int inserted;
  final int updated;
  final int unchanged;
  final int missing;

  const ScanStats({
    this.inserted = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.missing = 0,
  });

  ScanStats operator +(ScanStats other) => ScanStats(
        inserted: inserted + other.inserted,
        updated: updated + other.updated,
        unchanged: unchanged + other.unchanged,
        missing: missing + other.missing,
      );

  @override
  String toString() =>
      'ScanStats(inserted: $inserted, updated: $updated, unchanged: $unchanged, missing: $missing)';
}

abstract class TrackRepository {
  Future<List<Track>> getAllTracks({bool includeMissing = false});
  Future<Track?> getTrackByPath(String filePath);
  Future<int> upsertTrack(Track track);
  Future<int> markMissing(String filePath);
  Future<int> markFound(String filePath);
  Future<List<Track>> search(String query);

  /// Returns map of filePath → dateModified for all non-missing tracks.
  /// Used by the scan engine to load the full diff map in one query.
  Future<Map<String, int?>> getAllTrackPathsWithTimestamps();
}

class SqliteTrackRepository implements TrackRepository {
  final DbProvider _db;

  SqliteTrackRepository(this._db);

  @override
  Future<List<Track>> getAllTracks({bool includeMissing = false}) async {
    final db = await _db.database;
    final where = includeMissing ? null : 'is_missing = 0';
    final rows = await db.query(
      'tracks',
      where: where,
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return rows.map(Track.fromMap).toList();
  }

  @override
  Future<Track?> getTrackByPath(String filePath) async {
    final db = await _db.database;
    final rows = await db.query(
      'tracks',
      where: 'file_path = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Track.fromMap(rows.first);
  }

  @override
  Future<int> upsertTrack(Track track) async {
    final db = await _db.database;
    return db.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> markMissing(String filePath) async {
    final db = await _db.database;
    return db.update(
      'tracks',
      {'is_missing': 1},
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  @override
  Future<int> markFound(String filePath) async {
    final db = await _db.database;
    return db.update(
      'tracks',
      {'is_missing': 0},
      where: 'file_path = ?',
      whereArgs: [filePath],
    );
  }

  @override
  Future<List<Track>> search(String query) async {
    if (query.length < 2) return [];
    final db = await _db.database;
    final pattern = '%$query%';
    final rows = await db.query(
      'tracks',
      where:
          'is_missing = 0 AND (title LIKE ? OR artist LIKE ? OR album LIKE ?)',
      whereArgs: [pattern, pattern, pattern],
    );
    return rows.map(Track.fromMap).toList();
  }

  @override
  Future<Map<String, int?>> getAllTrackPathsWithTimestamps() async {
    final db = await _db.database;
    final rows = await db.query(
      'tracks',
      columns: ['file_path', 'date_modified'],
      where: 'is_missing = 0',
    );
    return {
      for (final r in rows) r['file_path'] as String: r['date_modified'] as int?
    };
  }
}
