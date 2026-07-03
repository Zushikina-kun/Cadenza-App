import '../../models/scan_folder.dart';

/// Progress event emitted by a [ScanEngine] during a scan pass.
class ScanProgress {
  final int discovered;
  final int processed;
  final int inserted;
  final int updated;
  final int unchanged;
  final int missing;
  final bool isComplete;
  final String? error;

  const ScanProgress({
    this.discovered = 0,
    this.processed = 0,
    this.inserted = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.missing = 0,
    this.isComplete = false,
    this.error,
  });

  ScanProgress copyWith({
    int? discovered,
    int? processed,
    int? inserted,
    int? updated,
    int? unchanged,
    int? missing,
    bool? isComplete,
    String? error,
  }) =>
      ScanProgress(
        discovered: discovered ?? this.discovered,
        processed: processed ?? this.processed,
        inserted: inserted ?? this.inserted,
        updated: updated ?? this.updated,
        unchanged: unchanged ?? this.unchanged,
        missing: missing ?? this.missing,
        isComplete: isComplete ?? this.isComplete,
        error: error ?? this.error,
      );

  @override
  String toString() =>
      'ScanProgress(discovered: $discovered, processed: $processed, '
      'inserted: $inserted, updated: $updated, unchanged: $unchanged, '
      'missing: $missing, isComplete: $isComplete, error: $error)';
}

/// Abstract scan engine. Platform-specific implementations:
/// - [AndroidScanEngine] — uses on_audio_query / MediaStore
/// - [WindowsScanEngine] — uses dart:io recursive filesystem walk
abstract class ScanEngine {
  /// Emits [ScanProgress] events throughout the scan, ending with one
  /// where [ScanProgress.isComplete] is true (or [ScanProgress.error] is set).
  Stream<ScanProgress> scan(List<ScanFolder> folders);
}
