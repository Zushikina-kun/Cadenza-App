import 'package:audio_service/audio_service.dart';

import '../../models/track.dart';

/// Converts a [Track] to an [audio_service] [MediaItem] for notification/lock screen.
extension TrackMediaItem on Track {
  MediaItem toMediaItem() => MediaItem(
        id: filePath,
        title: title ?? filePath.split('/').last,
        artist: artist,
        album: album,
        artUri: artworkPath != null ? Uri.file(artworkPath!) : null,
        duration: durationMs != null ? Duration(milliseconds: durationMs!) : null,
      );
}

/// Abstract interface for all audio playback operations.
/// Platform implementations: [DesktopAudioPlayerService], [AndroidAudioPlayerService].
abstract class AudioPlayerService {
  // ── State streams ──────────────────────────────────────────────────────────
  Stream<PlaybackState> get playbackStateStream;
  Stream<Track?> get currentTrackStream;
  Stream<Duration> get positionStream;
  Stream<List<Track>> get queueStream;

  // ── Current state ──────────────────────────────────────────────────────────
  Track? get currentTrack;
  List<Track> get trackQueue;
  Duration get position;

  // ── Playback controls ──────────────────────────────────────────────────────
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0});
  Future<void> playNext(Track track);
  Future<void> pause();
  Future<void> resume();
  Future<void> skipToNext();

  /// Applies the 3-second rule:
  /// - position > 3 s → seek to beginning of current track
  /// - position ≤ 3 s → skip to previous track in queue
  Future<void> skipToPrevious();

  Future<void> seekTo(Duration position);

  // ── Queue mutation ─────────────────────────────────────────────────────────
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> removeFromQueue(int index);

  /// Releases resources. Call on app dispose.
  Future<void> dispose();
}
