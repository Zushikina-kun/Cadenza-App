import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.read(audioPlayerServiceProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.pop(),
        ),
        title: const Text('Now Playing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () => context.go('/queue'),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: player.currentTrackStream,
        initialData: player.currentTrack,
        builder: (context, trackSnapshot) {
          final track = trackSnapshot.data;

          if (track == null) {
            return const Center(
              child: Text('Nothing playing.\nTap a song to start.', textAlign: TextAlign.center),
            );
          }

          return Column(
            children: [
              // ── Album art ──────────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _ArtworkDisplay(artworkPath: track.artworkPath),
                ),
              ),

              // ── Track info ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title ?? track.filePath.split(Platform.pathSeparator).last,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist ?? 'Unknown Artist',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // ── Seek bar ───────────────────────────────────────────────
              const SizedBox(height: 16),
              _SeekBar(
                durationMs: track.durationMs,
                positionStream: player.positionStream,
                onSeek: player.seekTo,
              ),

              // ── Transport controls ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: StreamBuilder<PlaybackState>(
                  stream: player.playbackStateStream,
                  builder: (context, snapshot) {
                    final isPlaying = snapshot.data?.playing ?? false;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: player.skipToPrevious,
                        ),
                        FilledButton(
                          onPressed: isPlaying ? player.pause : player.resume,
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(16),
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 36,
                          ),
                        ),
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_next),
                          onPressed: player.skipToNext,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

// ── Artwork widget ─────────────────────────────────────────────────────────────

class _ArtworkDisplay extends StatelessWidget {
  final String? artworkPath;
  const _ArtworkDisplay({this.artworkPath});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.music_note,
        size: 96,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );

    if (artworkPath == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        File(artworkPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

// ── Seek bar ───────────────────────────────────────────────────────────────────

class _SeekBar extends StatefulWidget {
  final int? durationMs;
  final Stream<Duration> positionStream;
  final Future<void> Function(Duration) onSeek;

  const _SeekBar({
    required this.durationMs,
    required this.positionStream,
    required this.onSeek,
  });

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _draggingValue;

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.durationMs ?? 0;

    return StreamBuilder<Duration>(
      stream: widget.positionStream,
      builder: (context, snapshot) {
        final posMs = snapshot.data?.inMilliseconds ?? 0;
        final sliderValue = _draggingValue ??
            (totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0);

        return Column(
          children: [
            Slider(
              value: sliderValue,
              onChanged: (v) => setState(() => _draggingValue = v),
              onChangeEnd: (v) {
                setState(() => _draggingValue = null);
                widget.onSeek(Duration(milliseconds: (v * totalMs).round()));
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatMs(posMs), style: Theme.of(context).textTheme.bodySmall),
                  Text(_formatMs(totalMs), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
