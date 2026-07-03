import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema.dart';

/// Thrown when the database cannot be opened or created.
class DatabaseInitException implements Exception {
  final String message;
  final Object? cause;
  DatabaseInitException(this.message, {this.cause});

  @override
  String toString() => 'DatabaseInitException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Abstract database provider. Call [DbProvider.instance] to get the
/// platform-appropriate implementation. All repositories depend on this.
abstract class DbProvider {
  Future<sqflite.Database> get database;

  /// Platform-aware singleton. Initialised once; safe to call repeatedly.
  static final DbProvider instance = _createPlatformProvider();

  static DbProvider _createPlatformProvider() {
    if (Platform.isAndroid || Platform.isIOS) {
      return _MobileDbProvider();
    } else {
      return _DesktopDbProvider();
    }
  }
}

// ── Mobile (sqflite) ────────────────────────────────────────────────────────

class _MobileDbProvider implements DbProvider {
  sqflite.Database? _db;

  @override
  Future<sqflite.Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<sqflite.Database> _open() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, 'cadenza.db');
      return await sqflite.openDatabase(
        path,
        version: 1,
        onCreate: _runSchema,
      );
    } catch (e) {
      throw DatabaseInitException('Failed to open mobile database', cause: e);
    }
  }

  Future<void> _runSchema(sqflite.Database db, int version) async {
    for (final stmt in kSchemaStatements) {
      await db.execute(stmt);
    }
  }
}

// ── Desktop (sqflite_common_ffi) ─────────────────────────────────────────────

class _DesktopDbProvider implements DbProvider {
  sqflite.Database? _db;

  @override
  Future<sqflite.Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<sqflite.Database> _open() async {
    try {
      // FFI must be initialised before any sqflite calls on desktop.
      // main.dart calls sqfliteFfiInit() before runApp; this is a safety net.
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final dir = await getApplicationDocumentsDirectory();
      final dbDir = Directory(p.join(dir.path, 'cadenza'));
      if (!dbDir.existsSync()) dbDir.createSync(recursive: true);

      final path = p.join(dbDir.path, 'cadenza.db');
      return await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _runSchema,
        ),
      );
    } catch (e) {
      throw DatabaseInitException('Failed to open desktop database', cause: e);
    }
  }

  Future<void> _runSchema(sqflite.Database db, int version) async {
    for (final stmt in kSchemaStatements) {
      await db.execute(stmt);
    }
  }
}
