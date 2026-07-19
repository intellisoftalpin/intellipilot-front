import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/io/file_picker.dart';
import 'package:intellipilot/core/io/url_opener.dart';
import 'package:intellipilot/core/network/api_client.dart';
import 'package:intellipilot/core/network/api_config.dart';
import 'package:intellipilot/core/ui/blob_view.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/features/activity/data/dtos/activity_dtos.dart';
import 'package:intellipilot/features/activity/presentation/cubits/attachments_cubit.dart';
import 'package:intellipilot/features/projects/domain/permission.dart';
import 'package:intellipilot/features/projects/presentation/cubits/project_detail_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:video_player/video_player.dart';

bool _isImage(String contentType) => contentType.startsWith('image/');
bool _isVideo(String contentType) => contentType.startsWith('video/');

/// What kind of in-app preview an attachment gets.
enum _AttKind { image, video, pdf, markdown, text, html, other }

/// Extensions that typically contain plain text — previewed monospace.
const _textExtensions = {
  'txt', 'log', 'csv', 'tsv', 'json', 'yaml', 'yml', 'xml', 'toml', 'ini',
  'conf', 'cfg', 'env', 'properties', 'sh', 'bash', 'zsh', 'fish', 'bat',
  'ps1', 'sql', 'dart', 'rs', 'py', 'js', 'ts', 'java', 'kt', 'swift',
  'c', 'h', 'cc', 'cpp', 'hpp', 'go', 'rb', 'php', 'diff', 'patch',
  'gitignore', 'dockerfile', 'lock', //
};

String _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return '';
  return filename.substring(dot + 1).toLowerCase();
}

/// Classify by content type first, then by file extension — uploads passed
/// through generic pipelines often arrive as `application/octet-stream`.
_AttKind _kindOf(Attachment att) {
  final ct = att.contentType;
  if (_isImage(ct)) return _AttKind.image;
  if (_isVideo(ct)) return _AttKind.video;
  if (ct == 'application/pdf') return _AttKind.pdf;
  if (ct == 'text/markdown') return _AttKind.markdown;
  if (ct == 'text/html') return _AttKind.html;
  final ext = _extensionOf(att.filename);
  if (ext == 'pdf') return _AttKind.pdf;
  if (ext == 'md' || ext == 'markdown') return _AttKind.markdown;
  if (ext == 'html' || ext == 'htm') return _AttKind.html;
  if (ct.startsWith('text/') || _textExtensions.contains(ext)) {
    return _AttKind.text;
  }
  return _AttKind.other;
}

IconData _kindIcon(_AttKind kind) => switch (kind) {
  _AttKind.image => Icons.image_outlined,
  _AttKind.video => Icons.movie_outlined,
  _AttKind.pdf => Icons.picture_as_pdf_outlined,
  _AttKind.markdown || _AttKind.text => Icons.description_outlined,
  _AttKind.html => Icons.code_outlined,
  _AttKind.other => Icons.insert_drive_file_outlined,
};

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
    final kind = _kindOf(att);
    return ListTile(
      leading: _AttachmentLeading(att: att, kind: kind),
      title: Text(att.filename),
      subtitle: Text(
        '${att.contentType} · ${_humanSize(att.sizeBytes)}',
      ),
      // Previewable rows open an in-app preview; everything else keeps the
      // download-only behaviour.
      onTap: kind == _AttKind.other
          ? () => _download(context)
          : () => _preview(context, kind),
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

  Future<void> _preview(BuildContext context, _AttKind kind) async {
    final cubit = context.read<AttachmentsCubit>();
    final signed = await cubit.sign(att.id);
    if (signed == null || !context.mounted) return;
    final url = _absoluteUrl(signed.url);
    switch (kind) {
      case _AttKind.image:
      case _AttKind.video:
        await showDialog<void>(
          context: context,
          builder: (_) => _MediaPreviewDialog(
            url: url,
            filename: att.filename,
            isVideo: kind == _AttKind.video,
          ),
        );
      case _AttKind.markdown:
      case _AttKind.text:
        await showDialog<void>(
          context: context,
          builder: (_) => _TextPreviewDialog(
            url: url,
            att: att,
            markdown: kind == _AttKind.markdown,
          ),
        );
      case _AttKind.pdf:
      case _AttKind.html:
        if (!inlineBlobPreviewSupported) {
          // Native targets have no browser frame — degrade to download.
          await _download(context);
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (_) => _BlobPreviewDialog(
            url: url,
            att: att,
            isHtml: kind == _AttKind.html,
          ),
        );
      case _AttKind.other:
        await _download(context);
    }
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

/// Leading cell for an attachment row: a real thumbnail for images (signed
/// URL, loaded lazily), a type icon for everything else — with a small play
/// badge for videos.
class _AttachmentLeading extends StatefulWidget {
  const _AttachmentLeading({required this.att, required this.kind});
  final Attachment att;
  final _AttKind kind;

  @override
  State<_AttachmentLeading> createState() => _AttachmentLeadingState();
}

class _AttachmentLeadingState extends State<_AttachmentLeading> {
  Future<String?>? _url;

  @override
  Widget build(BuildContext context) {
    if (widget.kind != _AttKind.image) {
      if (widget.kind == _AttKind.video) {
        return SizedBox.square(
          dimension: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.movie_outlined),
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(
                  Icons.play_circle_fill,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      }
      return SizedBox.square(
        dimension: 40,
        child: Icon(_kindIcon(widget.kind)),
      );
    }
    _url ??= context
        .read<AttachmentsCubit>()
        .sign(widget.att.id)
        .then((s) => s == null ? null : _absoluteUrl(s.url));
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) {
          return SizedBox.square(
            dimension: 40,
            child: Icon(_kindIcon(widget.kind)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox.square(
            dimension: 40,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(_kindIcon(widget.kind)),
            ),
          ),
        );
      },
    );
  }
}

/// Text-preview cap: bigger files degrade to download to keep the UI snappy.
const _kTextPreviewMaxBytes = 2 * 1024 * 1024;

/// Fetches the attachment bytes and shows them as formatted Markdown or as
/// scrollable monospace text with a copy action.
class _TextPreviewDialog extends StatefulWidget {
  const _TextPreviewDialog({
    required this.url,
    required this.att,
    required this.markdown,
  });

  final String url;
  final Attachment att;
  final bool markdown;

  @override
  State<_TextPreviewDialog> createState() => _TextPreviewDialogState();
}

class _TextPreviewDialogState extends State<_TextPreviewDialog> {
  String? _content;
  bool _failed = false;
  bool _tooLarge = false;

  @override
  void initState() {
    super.initState();
    if (widget.att.sizeBytes > _kTextPreviewMaxBytes) {
      _tooLarge = true;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final res = await getIt<ApiClient>().dio.get<List<int>>(
        widget.url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (!mounted) return;
      setState(
        () => _content = utf8.decode(res.data ?? [], allowMalformed: true),
      );
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final content = _content;
    final Widget body;
    if (_tooLarge) {
      body = Center(child: Text(t.attachmentsPreviewTooLarge));
    } else if (_failed) {
      body = Center(child: Text(t.attachmentsPreviewFailed));
    } else if (content == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (widget.markdown) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownText(content),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectionArea(
          child: Text(
            content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      );
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewHeader(
              filename: widget.att.filename,
              actions: [
                if (content != null)
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: t.actionCopy,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: content));
                      messenger.showSnackBar(
                        SnackBar(content: Text(t.copiedToClipboard)),
                      );
                    },
                  ),
              ],
            ),
            const Divider(height: 1),
            Flexible(child: SizedBox(width: 900, child: body)),
          ],
        ),
      ),
    );
  }
}

/// HTML / PDF preview: fetches the bytes and renders them in an inline
/// browser frame (sandboxed for HTML). HTML offers a raw-source toggle.
class _BlobPreviewDialog extends StatefulWidget {
  const _BlobPreviewDialog({
    required this.url,
    required this.att,
    required this.isHtml,
  });

  final String url;
  final Attachment att;
  final bool isHtml;

  @override
  State<_BlobPreviewDialog> createState() => _BlobPreviewDialogState();
}

class _BlobPreviewDialogState extends State<_BlobPreviewDialog> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _showSource = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final res = await getIt<ApiClient>().dio.get<List<int>>(
        widget.url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (!mounted) return;
      setState(() => _bytes = Uint8List.fromList(res.data ?? []));
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final bytes = _bytes;
    final Widget body;
    if (_failed) {
      body = Center(child: Text(t.attachmentsPreviewFailed));
    } else if (bytes == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (widget.isHtml && _showSource) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectionArea(
          child: Text(
            utf8.decode(bytes, allowMalformed: true),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      );
    } else {
      body = buildBlobView(
        bytes: bytes,
        mime: widget.isHtml ? 'text/html' : 'application/pdf',
        sandboxed: widget.isHtml,
      );
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewHeader(
              filename: widget.att.filename,
              actions: [
                if (widget.isHtml && bytes != null)
                  TextButton.icon(
                    icon: Icon(
                      _showSource
                          ? Icons.visibility_outlined
                          : Icons.code_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _showSource
                          ? t.attachmentsViewRendered
                          : t.attachmentsViewSource,
                    ),
                    onPressed: () => setState(() => _showSource = !_showSource),
                  ),
              ],
            ),
            const Divider(height: 1),
            Flexible(child: SizedBox(width: 1100, height: 800, child: body)),
          ],
        ),
      ),
    );
  }
}

/// Shared dialog header: filename + custom actions + close.
class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.filename, this.actions = const []});
  final String filename;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              filename,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...actions,
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: t.actionCancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
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
