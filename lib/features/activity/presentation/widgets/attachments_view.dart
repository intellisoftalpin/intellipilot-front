import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/cubits/attachments_cubit.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:video_player/video_player.dart';

bool _isImage(String contentType) => contentType.startsWith('image/');
bool _isVideo(String contentType) => contentType.startsWith('video/');

/// Resolve a signed attachment URL to an absolute one against the API base.
String _absoluteUrl(String signedUrl) {
  final base = Uri.parse(getIt<ApiConfig>().baseUrl);
  return base.resolve(signedUrl).toString();
}

/// Reads an image (PNG/JPEG) off the system clipboard. Returns null when the
/// clipboard has no image or the platform doesn't support image reads.
Future<Uint8List?> _readClipboardImage() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();
  for (final format in [Formats.png, Formats.jpeg]) {
    if (!reader.canProvide(format)) continue;
    final completer = Completer<Uint8List?>();
    reader.getFile(
      format,
      (file) async {
        try {
          completer.complete(await file.readAll());
        } on Object {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    return completer.future;
  }
  return null;
}

class AttachmentsView extends StatelessWidget {
  const AttachmentsView({this.shrinkWrap = false, super.key});

  /// When true, the file list renders as a `Column` inline rather than an
  /// `Expanded(ListView)` — for embedding in a scrollable parent (e.g. the
  /// Jira-style entity detail page).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return BlocConsumer<AttachmentsCubit, AttachmentsState>(
      listenWhen: (prev, next) =>
          next is AttachmentsLoaded && next.error != null,
      listener: (context, state) {
        if (state is! AttachmentsLoaded || state.error == null) return;
        final messenger = ScaffoldMessenger.of(context);
        final message = switch (state.error) {
          'too_large' => t.attachmentsTooLarge(25),
          _ => state.errorMessage ?? t.attachmentsUploadFailed,
        };
        messenger.showSnackBar(SnackBar(content: Text(message)));
      },
      builder: (context, state) {
        if (state is AttachmentsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is AttachmentsFailed) {
          return Center(child: Text(t.activityLoadFailed));
        }
        if (state is! AttachmentsLoaded) return const SizedBox.shrink();
        // ⌘/Ctrl+V pastes a clipboard image when the attachments area is
        // focused.
        Widget withPaste(Widget child) => Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final isPaste =
                (HardwareKeyboard.instance.isMetaPressed ||
                    HardwareKeyboard.instance.isControlPressed) &&
                event.logicalKey == LogicalKeyboardKey.keyV;
            if (!isPaste) return KeyEventResult.ignored;
            unawaited(
              _pasteImage(context, context.read<AttachmentsCubit>()),
            );
            return KeyEventResult.handled;
          },
          child: child,
        );
        if (shrinkWrap) {
          return withPaste(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UploadBar(upload: state.upload),
                const Divider(height: 1),
                if (state.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(t.attachmentsEmpty)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < state.items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _Row(att: state.items[i]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        }
        return withPaste(
          Column(
            children: [
              _UploadBar(upload: state.upload),
              const Divider(height: 1),
              Expanded(
                child: state.items.isEmpty
                    ? Center(child: Text(t.attachmentsEmpty))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: state.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _Row(att: state.items[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reads an image off the clipboard and uploads it as a PNG. Shows a subtle
/// hint when the clipboard has no image.
Future<void> _pasteImage(BuildContext context, AttachmentsCubit cubit) async {
  final t = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final bytes = await _readClipboardImage();
  if (bytes == null) {
    messenger.showSnackBar(SnackBar(content: Text(t.attachmentsNoImage)));
    return;
  }
  final ts = DateTime.now().millisecondsSinceEpoch;
  await cubit.upload(
    filename: 'screenshot-$ts.png',
    bytes: bytes,
    contentType: 'image/png',
  );
}

class _UploadBar extends StatelessWidget {
  const _UploadBar({this.upload});
  final UploadProgress? upload;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final picker = getIt<FilePicker>();
    final canCreate = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.attachmentCreate);
    });
    if (!canCreate) return const SizedBox.shrink();
    if (upload != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.cloud_upload_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(upload!.filename),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: upload!.fraction),
                ],
              ),
            ),
            IconButton(
              tooltip: t.attachmentsCancelUpload,
              icon: const Icon(Icons.close),
              onPressed: () => context.read<AttachmentsCubit>().cancelUpload(),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.upload_file),
              onPressed: () async {
                if (!picker.isSupported) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.attachmentsUploadUnsupported)),
                  );
                  return;
                }
                final picked = await picker.pickSingleFile();
                if (picked == null || !context.mounted) return;
                await context.read<AttachmentsCubit>().upload(
                  filename: picked.name,
                  bytes: picked.bytes,
                  contentType: picked.contentType,
                );
              },
              label: Text(t.attachmentsUpload),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_paste),
              onPressed: () =>
                  _pasteImage(context, context.read<AttachmentsCubit>()),
              label: Text(t.attachmentsPasteImage),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.att});
  final Attachment att;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canDelete = context.select<ProjectDetailCubit, bool>((c) {
      final s = c.state;
      return s is ProjectDetailLoaded && s.has(Permission.attachmentDelete);
    });
    final media = _isImage(att.contentType) || _isVideo(att.contentType);
    return ListTile(
      leading: Icon(
        _isImage(att.contentType)
            ? Icons.image_outlined
            : _isVideo(att.contentType)
            ? Icons.movie_outlined
            : Icons.insert_drive_file_outlined,
      ),
      title: Text(att.filename),
      subtitle: Text(
        '${att.contentType} · ${_humanSize(att.sizeBytes)}',
      ),
      // Media rows open an in-app preview; everything else keeps the
      // download-only behaviour.
      onTap: media ? () => _preview(context) : () => _download(context),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: t.attachmentsDownload,
            onPressed: () => _download(context),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context),
            ),
        ],
      ),
    );
  }

  Future<void> _preview(BuildContext context) async {
    final cubit = context.read<AttachmentsCubit>();
    final signed = await cubit.sign(att.id);
    if (signed == null || !context.mounted) return;
    final url = _absoluteUrl(signed.url);
    await showDialog<void>(
      context: context,
      builder: (_) => _MediaPreviewDialog(
        url: url,
        filename: att.filename,
        isVideo: _isVideo(att.contentType),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    final cubit = context.read<AttachmentsCubit>();
    final signed = await cubit.sign(att.id);
    if (signed == null) return;
    // The signed URL is server-relative (`/api/v1/…`). Resolve it against the
    // API base so it opens correctly even when the SPA is hosted on a
    // different origin.
    final base = Uri.parse(getIt<ApiConfig>().baseUrl);
    final href = base.resolve(signed.url).toString();
    openExternalUrl(href);
  }

  Future<void> _delete(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final cubit = context.read<AttachmentsCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.attachmentsDeleteTitle),
        content: Text(t.attachmentsDeleteConfirm(att.filename)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDelete),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await cubit.delete(att.id);
    }
  }
}

String _humanSize(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB'];
  var b = bytes.toDouble();
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(b < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}

/// In-app preview of an image or video attachment. The signed URL
/// self-authenticates, so no Bearer header is needed.
class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({
    required this.url,
    required this.filename,
    required this.isVideo,
  });

  final String url;
  final String filename;
  final bool isVideo;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
  VideoPlayerController? _controller;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _controller = c;
      unawaited(
        c
            .initialize()
            .then((_) {
              if (!mounted) return;
              setState(() {});
              unawaited(c.play());
            })
            .catchError((Object _) {
              if (mounted) setState(() => _videoFailed = true);
            }),
      );
    }
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) unawaited(c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.filename,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: t.actionCancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: widget.isVideo ? _video(t) : _image(t),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(AppLocalizations t) => InteractiveViewer(
    child: Image.network(
      widget.url,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          Center(child: Text(t.attachmentsPreviewFailed)),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator()),
    ),
  );

  Widget _video(AppLocalizations t) {
    final c = _controller;
    if (_videoFailed) {
      return Center(child: Text(t.attachmentsPreviewFailed));
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
        VideoProgressIndicator(c, allowScrubbing: true),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              icon: Icon(
                c.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
              ),
              onPressed: () => setState(
                () => unawaited(c.value.isPlaying ? c.pause() : c.play()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
