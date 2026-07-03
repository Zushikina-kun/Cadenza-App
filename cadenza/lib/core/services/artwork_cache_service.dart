import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class ArtworkCacheService {
  /// Writes [artworkBytes] to the cache keyed by [trackFilePath].
  /// Returns the absolute cache file path, or null when [artworkBytes] is null.
  Future<String?> cacheArtwork(String trackFilePath, Uint8List? artworkBytes);

  Future<String> artworkCacheDir();
}

class FileArtworkCacheService implements ArtworkCacheService {
  String? _cacheDirPath;

  @override
  Future<String> artworkCacheDir() async {
    if (_cacheDirPath != null) return _cacheDirPath!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'artwork_cache'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _cacheDirPath = dir.path;
    return _cacheDirPath!;
  }

  @override
  Future<String?> cacheArtwork(
    String trackFilePath,
    Uint8List? artworkBytes,
  ) async {
    if (artworkBytes == null) return null;

    final cacheDir = await artworkCacheDir();
    final key = sha1.convert(trackFilePath.codeUnits).toString();
    final filePath = p.join(cacheDir, '$key.jpg');

    // Avoid redundant writes — same album tracks share artwork via the same key
    final file = File(filePath);
    if (!file.existsSync()) {
      await file.writeAsBytes(artworkBytes);
    }

    return filePath;
  }
}
