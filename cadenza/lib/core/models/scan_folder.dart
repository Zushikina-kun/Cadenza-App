import 'package:flutter/foundation.dart';

/// A filesystem path registered by the user as a root for library scanning.
@immutable
class ScanFolder {
  final int? id;
  final String folderPath;

  /// Unix timestamp (ms) of the last completed scan. NULL until first scan.
  final int? lastScanned;

  const ScanFolder({
    this.id,
    required this.folderPath,
    this.lastScanned,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'folder_path': folderPath,
        'last_scanned': lastScanned,
      };

  factory ScanFolder.fromMap(Map<String, dynamic> map) => ScanFolder(
        id: map['id'] as int?,
        folderPath: map['folder_path'] as String,
        lastScanned: map['last_scanned'] as int?,
      );

  ScanFolder copyWith({int? id, String? folderPath, int? lastScanned}) =>
      ScanFolder(
        id: id ?? this.id,
        folderPath: folderPath ?? this.folderPath,
        lastScanned: lastScanned ?? this.lastScanned,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanFolder && folderPath == other.folderPath;

  @override
  int get hashCode => folderPath.hashCode;

  @override
  String toString() => 'ScanFolder(id: $id, folderPath: $folderPath, lastScanned: $lastScanned)';
}
