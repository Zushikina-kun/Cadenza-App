import '../database/db_provider.dart';
import '../models/scan_folder.dart';

abstract class ScanRepository {
  Future<List<ScanFolder>> getScanFolders();
  Future<void> addScanFolder(String path);
  Future<void> removeScanFolder(int id);
  Future<void> updateLastScanned(int folderId, int timestampMs);
}

class SqliteScanRepository implements ScanRepository {
  final DbProvider _db;

  SqliteScanRepository(this._db);

  @override
  Future<List<ScanFolder>> getScanFolders() async {
    final db = await _db.database;
    final rows = await db.query('scan_folders');
    return rows.map(ScanFolder.fromMap).toList();
  }

  @override
  Future<void> addScanFolder(String path) async {
    final db = await _db.database;
    // INSERT OR IGNORE — silently skips if folder_path already registered.
    await db.rawInsert(
      'INSERT OR IGNORE INTO scan_folders (folder_path) VALUES (?)',
      [path],
    );
  }

  @override
  Future<void> removeScanFolder(int id) async {
    final db = await _db.database;
    // Removing a folder does NOT delete associated track records.
    await db.delete('scan_folders', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> updateLastScanned(int folderId, int timestampMs) async {
    final db = await _db.database;
    await db.update(
      'scan_folders',
      {'last_scanned': timestampMs},
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }
}
