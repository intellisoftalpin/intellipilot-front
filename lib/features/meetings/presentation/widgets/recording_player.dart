import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:video_player/video_player.dart';

/// Inline audio / video player for a meeting recording.
///
/// Nothing loads until the user presses play: a meeting can hold several
/// hour-long recordings, and opening the tab must not start fetching them.
/// The signed URL streams with byte ranges, so seeking works without
/// downloading the file first. Formats the platform cannot decode fall back
/// to a download prompt.
class RecordingPlayer extends StatefulWidget {
  const RecordingPlayer({
    required this.isVideo,
    required this.resolveUrl,
    required this.onDownload,
    super.key,
  });

  final bool isVideo;

  /// Produces a fresh signed URL (they expire), or null when unavailable.
  final Future<String?> Function() resolveUrl;
  final VoidCallback onDownload;

  @override
  State<RecordingPlayer> createState() => _RecordingPlayerState();
}

class _RecordingPlayerState extends State<RecordingPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    final c = _controller;
    if (c != null) unawaited(c.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final url = await widget.resolveUrl();
    if (!mounted) return;
    if (url == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = c;
    c.addListener(_onTick);
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() => _loading = false);
      await c.play();
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    if (c.value.hasError && !_failed) {
      setState(() => _failed = true);
    } else {
      setState(() {});
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = _controller;

    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, right: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(t.meetingPlayerUnsupported)),
            TextButton(
              onPressed: widget.onDownload,
              child: Text(t.attachmentsDownload),
            ),
          ],
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _loading
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : FilledButton.tonalIcon(
                  key: const Key('recording-play'),
                  onPressed: () => unawaited(_start()),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t.meetingPlay),
                ),
        ),
      );
    }

    final v = c.value;
    final hasPicture = widget.isVideo && v.size.width > 0 && v.size.height > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasPicture)
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: AspectRatio(
                aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: VideoProgressIndicator(c, allowScrubbing: true),
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: v.isPlaying ? t.meetingPause : t.meetingPlay,
              onPressed: () => unawaited(v.isPlaying ? c.pause() : c.play()),
            ),
            Text(
              '${_fmt(v.position)} / ${_fmt(v.duration)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}
