import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/track.dart';
import 'audio_player_service.dart';

/// Desktop (Windows) audio player. Uses just_audio directly — no background
/// foreground service needed on Windows. just_audio_media_kit routes playback
/// through libmpv for reliable FLAC/OGG/OPUS/ALAC support.
class DesktopAudioPlayerService implements AudioPlayerService {
  final AudioPlayer _player;
  ConcatenatingAudioSource? _source;
  List<Track> _queue = [];

  final _currentTrackController = StreamController<Track?>.broadcast();
  final _queueController = StreamController<List<Track>>.broadcast();

  DesktopAudioPlayerService() : _player = AudioPlayer() {
    // Forward position/state to our own streams and track queue index changes
    _player.currentIndexStream.listen((index) {
      if (index != null && index < _queue.length) {
        _currentTrackController.add(_queue[index]);
      } else if (_queue.isEmpty) {
        _currentTrackController.add(null);
      }
    });

    // When the queue finishes, clear now-playing state
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _currentTrackController.add(null);
      }
    });
  }

  // ── State ──────────────────────────────────────────────────────────────────

  @override
  Stream<PlaybackState> get playbackStateStream => _player.playbackEventStream.map(
        (event) => PlaybackState(
          playing: _player.playing,
          controls: [
            MediaControl.skipToPrevious,
            _player.playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
          ],
          processingState: _mapProcessingState(_player.processingState),
          updatePosition: _player.position,
        ),
      );

  @override
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<List<Track>> get queueStream => _queueController.stream;

  @override
  Track? get currentTrack {
    final idx = _player.currentIndex;
    if (idx == null || idx >= _queue.length) return null;
    return _queue[idx];
  }

  @override
  List<Track> get trackQueue => List.unmodifiable(_queue);

  @override
  Duration get position => _player.position;

  // ── Playback controls ──────────────────────────────────────────────────────

  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _source = ConcatenatingAudioSource(
      children: tracks
          .map((t) => AudioSource.uri(
                Uri.file(t.filePath),
                tag: t.toMediaItem(),
              ))
          .toList(),
    );
    try {
      await _player.setAudioSource(_source!, initialIndex: startIndex);
      await _player.play();
      _queueController.add(List.unmodifiable(_queue));
    } catch (e) {
      debugPrint('[DesktopAudioPlayerService] Error starting queue: $e');
    }
  }

  @override
  Future<void> playNext(Track track) async {
    if (_source == null) {
      await playQueue([track]);
      return;
    }
    final insertAt = (_player.currentIndex ?? 0) + 1;
    _queue.insert(insertAt, track);
    await _source!.insert(
      insertAt,
      AudioSource.uri(Uri.file(track.filePath), tag: track.toMediaItem()),
    );
    _queueController.add(List.unmodifiable(_queue));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  // ── Queue mutation ─────────────────────────────────────────────────────────

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_source == null) return;
    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);
    await _source!.move(oldIndex, newIndex);
    _queueController.add(List.unmodifiable(_queue));
  }

  @override
  Future<void> removeFromQueue(int index) async {
    if (_source == null || index >= _queue.length) return;
    _queue.removeAt(index);
    await _source!.removeAt(index);
    _queueController.add(List.unmodifiable(_queue));
  }

  @override
  Future<void> dispose() async {
    await _currentTrackController.close();
    await _queueController.close();
    await _player.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
