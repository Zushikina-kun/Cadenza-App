import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/track.dart';
import 'audio_player_service.dart';

/// Android audio player. Extends [BaseAudioHandler] so audio_service manages
/// the foreground service, notification controls, and lock screen widget.
class AndroidAudioPlayerService extends BaseAudioHandler
    implements AudioPlayerService {
  final AudioPlayer _player;
  ConcatenatingAudioSource? _source;
  List<Track> _queue = [];

  final _currentTrackController = StreamController<Track?>.broadcast();
  final _queueController = StreamController<List<Track>>.broadcast();

  AndroidAudioPlayerService() : _player = AudioPlayer() {
    _player.currentIndexStream.listen((index) {
      if (index != null && index < _queue.length) {
        final track = _queue[index];
        _currentTrackController.add(track);
        // Broadcast MediaItem so audio_service updates the notification
        mediaItem.add(track.toMediaItem());
      } else if (_queue.isEmpty) {
        _currentTrackController.add(null);
        mediaItem.add(null);
      }
    });

    _player.playbackEventStream.listen((event) {
      _broadcastState();
    });

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _currentTrackController.add(null);
      }
      _broadcastState();
    });
  }

  // ── BaseAudioHandler overrides (called by audio_service / media buttons) ──

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

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
  Future<void> onTaskRemoved() async {
    await _player.stop();
    await super.onTaskRemoved();
  }

  // ── AudioPlayerService interface ──────────────────────────────────────────

  @override
  Stream<PlaybackState> get playbackStateStream => playbackState;

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
      debugPrint('[AndroidAudioPlayerService] Error starting queue: $e');
      // Skip to next on source error
      if (_queue.length > startIndex + 1) {
        await playQueue(tracks, startIndex: startIndex + 1);
      }
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
  Future<void> resume() => _player.play();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

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

  void _broadcastState() {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }

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
