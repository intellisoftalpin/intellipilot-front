import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/ui/markdown_text.dart';
import 'package:intellipilot/core/widgets/user_avatar.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Uploads a pasted/dropped image and returns the URL to reference it by, or
/// null when the upload failed.
typedef ImageUploader =
    Future<String?> Function(String filename, Uint8List bytes);

/// Markdown editor with a formatting toolbar, a live preview, `@mention`
/// autocomplete and image paste.
///
/// The renderer supports headings, lists, quotes, code, links and images, but
/// before this widget the only way to produce any of that was to know the
/// syntax and type it into a bare `TextField`.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    required this.controller,
    this.members = const {},
    this.onUploadImage,
    this.minLines = 5,
    this.autofocus = false,
    this.onSubmitShortcut,
    this.showToolbar = true,
    super.key,
  });

  final TextEditingController controller;

  /// Mention candidates keyed by lowercase handle.
  final Map<String, UserRef> members;

  /// When set, images can be pasted into the editor.
  final ImageUploader? onUploadImage;

  final int minLines;
  final bool autofocus;

  /// Cmd/Ctrl+Enter action — usually "save".
  final VoidCallback? onSubmitShortcut;
  final bool showToolbar;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  final _focus = FocusNode();
  bool _preview = false;
  bool _uploading = false;

  /// Mention autocomplete state: the `@` that opened it and the typed filter.
  int? _mentionStart;
  String _mentionQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncMentionState);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncMentionState);
    _focus.dispose();
    super.dispose();
  }

  // ---- mention autocomplete ----------------------------------------------

  /// Tracks whether the caret currently sits inside an `@handle` token.
  void _syncMentionState() {
    if (widget.members.isEmpty) return;
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return _closeMentions();
    final text = widget.controller.text;
    final caret = sel.baseOffset.clamp(0, text.length);

    var i = caret - 1;
    while (i >= 0) {
      final c = text[i];
      if (c == '@') break;
      // A mention can't span whitespace or start mid-word.
      if (RegExp(r'[\s@]').hasMatch(c)) return _closeMentions();
      if (caret - i > 64) return _closeMentions();
      i--;
    }
    if (i < 0) return _closeMentions();
    // `@` must start a word, otherwise an email address opens the picker.
    if (i > 0 && !RegExp(r'\s').hasMatch(text[i - 1])) return _closeMentions();

    final query = text.substring(i + 1, caret).toLowerCase();
    if (_mentionStart != i || _mentionQuery != query) {
      setState(() {
        _mentionStart = i;
        _mentionQuery = query;
      });
    }
  }

  void _closeMentions() {
    if (_mentionStart == null) return;
    setState(() {
      _mentionStart = null;
      _mentionQuery = '';
    });
  }

  List<UserRef> get _mentionMatches {
    if (_mentionStart == null) return const [];
    final q = _mentionQuery;
    final all = widget.members.values.toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ),
      );
    if (q.isEmpty) return all.take(6).toList();
    return all
        .where(
          (u) =>
              u.username.toLowerCase().contains(q) ||
              u.displayName.toLowerCase().contains(q),
        )
        .take(6)
        .toList();
  }

  void _insertMention(UserRef user) {
    final start = _mentionStart;
    if (start == null) return;
    final text = widget.controller.text;
    final caret = widget.controller.selection.baseOffset.clamp(0, text.length);
    final replacement = '@${user.username} ';
    final next = text.replaceRange(start, caret, replacement);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _closeMentions();
  }

  // ---- formatting toolbar -------------------------------------------------

  /// Wraps the selection (or inserts a placeholder) between [left]/[right].
  void _wrap(String left, String right) {
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    if (!sel.isValid) return;
    final selected = sel.textInside(text);
    final body = selected.isEmpty ? '' : selected;
    final next = text.replaceRange(sel.start, sel.end, '$left$body$right');
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: sel.start + left.length + body.length,
      ),
    );
    _focus.requestFocus();
  }

  /// Prefixes every selected line (or the caret's line) with [prefix].
  void _prefixLines(String prefix, {bool numbered = false}) {
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    if (!sel.isValid) return;
    var start = sel.start;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    var end = sel.end;
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    final block = text.substring(start, end);
    final lines = block.split('\n');
    final rewritten = [
      for (var i = 0; i < lines.length; i++)
        numbered ? '${i + 1}. ${lines[i]}' : '$prefix${lines[i]}',
    ].join('\n');
    final next = text.replaceRange(start, end, rewritten);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + rewritten.length),
    );
    _focus.requestFocus();
  }

  // ---- image paste --------------------------------------------------------

  Future<void> _pasteImage() async {
    final upload = widget.onUploadImage;
    if (upload == null || _uploading) return;
    final bytes = await _readClipboardImage();
    if (bytes == null || !mounted) return;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    const name = 'pasted-image.png';
    final url = await upload(name, bytes);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (url == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.editorUploadFailed)));
      return;
    }
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    final at = sel.isValid ? sel.end : text.length;
    final snippet = '\n![$name]($url)\n';
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(at, at, snippet),
      selection: TextSelection.collapsed(offset: at + snippet.length),
    );
  }

  static Future<Uint8List?> _readClipboardImage() async {
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar)
          _EditorToolbar(
            preview: _preview,
            uploading: _uploading,
            canUpload: widget.onUploadImage != null,
            onTogglePreview: () => setState(() => _preview = !_preview),
            onBold: () => _wrap('**', '**'),
            onItalic: () => _wrap('_', '_'),
            onCode: () => _wrap('`', '`'),
            onLink: () => _wrap('[', '](https://)'),
            onQuote: () => _prefixLines('> '),
            onBullet: () => _prefixLines('- '),
            onNumbered: () => _prefixLines('', numbered: true),
            onHeading: () => _prefixLines('## '),
            onPasteImage: () => unawaited(_pasteImage()),
          ),
        const SizedBox(height: 6),
        if (_preview)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.controller.text.trim().isEmpty
                ? Text(
                    t.descriptionPlaceholder,
                    style: TextStyle(color: theme.colorScheme.outline),
                  )
                : MarkdownText(
                    widget.controller.text,
                    mentions: widget.members,
                  ),
          )
        else
          Stack(
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    meta: true,
                  ): () =>
                      widget.onSubmitShortcut?.call(),
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): () =>
                      widget.onSubmitShortcut?.call(),
                  if (widget.onUploadImage != null) ...{
                    const SingleActivator(
                      LogicalKeyboardKey.keyV,
                      meta: true,
                      shift: true,
                    ): () =>
                        unawaited(_pasteImage()),
                  },
                },
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  maxLines: null,
                  minLines: widget.minLines,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (_uploading)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t.editorUploading,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        if (!_preview && _mentionMatches.isNotEmpty)
          _MentionSuggestions(
            matches: _mentionMatches,
            onPick: _insertMention,
          ),
      ],
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.preview,
    required this.uploading,
    required this.canUpload,
    required this.onTogglePreview,
    required this.onBold,
    required this.onItalic,
    required this.onCode,
    required this.onLink,
    required this.onQuote,
    required this.onBullet,
    required this.onNumbered,
    required this.onHeading,
    required this.onPasteImage,
  });

  final bool preview;
  final bool uploading;
  final bool canUpload;
  final VoidCallback onTogglePreview;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onCode;
  final VoidCallback onLink;
  final VoidCallback onQuote;
  final VoidCallback onBullet;
  final VoidCallback onNumbered;
  final VoidCallback onHeading;
  final VoidCallback onPasteImage;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
      icon: Icon(icon, size: 17),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: preview ? null : onTap,
    );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                btn(Icons.format_bold, t.editorBold, onBold),
                btn(Icons.format_italic, t.editorItalic, onItalic),
                btn(Icons.code, t.editorCode, onCode),
                btn(Icons.title, t.editorHeading, onHeading),
                btn(Icons.format_list_bulleted, t.editorBulletList, onBullet),
                btn(
                  Icons.format_list_numbered,
                  t.editorNumberedList,
                  onNumbered,
                ),
                btn(Icons.format_quote, t.editorQuote, onQuote),
                btn(Icons.link, t.editorLink, onLink),
                if (canUpload)
                  btn(Icons.image_outlined, t.editorUploading, onPasteImage),
              ],
            ),
          ),
        ),
        TextButton.icon(
          icon: Icon(
            preview ? Icons.edit_outlined : Icons.visibility_outlined,
            size: 16,
          ),
          onPressed: onTogglePreview,
          label: Text(preview ? t.editorWrite : t.editorPreview),
        ),
      ],
    );
  }
}

class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({required this.matches, required this.onPick});
  final List<UserRef> matches;
  final void Function(UserRef) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final u in matches)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: UserAvatar(user: u, size: 22),
              title: Text(u.displayName, style: theme.textTheme.bodyMedium),
              subtitle: Text(
                '@${u.username}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              onTap: () => onPick(u),
            ),
        ],
      ),
    );
  }
}

/// Opens the editor as a large focused dialog — editing markdown inside a
/// 420px side panel is miserable, and on a wide screen there is room to show
/// the source and the rendered result at once.
Future<String?> showExpandedMarkdownEditor(
  BuildContext context, {
  required String title,
  required String initialValue,
  Map<String, UserRef> members = const {},
  ImageUploader? onUploadImage,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ExpandedEditorDialog(
      title: title,
      initialValue: initialValue,
      members: members,
      onUploadImage: onUploadImage,
    ),
  );
}

class _ExpandedEditorDialog extends StatefulWidget {
  const _ExpandedEditorDialog({
    required this.title,
    required this.initialValue,
    required this.members,
    required this.onUploadImage,
  });
  final String title;
  final String initialValue;
  final Map<String, UserRef> members;
  final ImageUploader? onUploadImage;

  @override
  State<_ExpandedEditorDialog> createState() => _ExpandedEditorDialogState();
}

class _ExpandedEditorDialogState extends State<_ExpandedEditorDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _dirty => _ctrl.text != widget.initialValue;

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final t = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.editorDiscardTitle),
        content: Text(t.editorDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.actionCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.actionDiscard),
          ),
        ],
      ),
    );
    if ((discard ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: wide ? (size.width * 0.82).clamp(900.0, 1400.0) : size.width,
        height: size.height * 0.86,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: t.actionCancel,
                    onPressed: () => unawaited(_close()),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: wide
                    // Side-by-side: type on the left, see the result on the
                    // right, no tab-flipping.
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: MarkdownEditor(
                              controller: _ctrl,
                              members: widget.members,
                              onUploadImage: widget.onUploadImage,
                              autofocus: true,
                              minLines: 20,
                              onSubmitShortcut: () =>
                                  Navigator.of(context).pop(_ctrl.text),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: SingleChildScrollView(
                              child: ValueListenableBuilder(
                                valueListenable: _ctrl,
                                builder: (context, value, _) => MarkdownText(
                                  value.text,
                                  mentions: widget.members,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: MarkdownEditor(
                          controller: _ctrl,
                          members: widget.members,
                          onUploadImage: widget.onUploadImage,
                          autofocus: true,
                          minLines: 16,
                          onSubmitShortcut: () =>
                              Navigator.of(context).pop(_ctrl.text),
                        ),
                      ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => unawaited(_close()),
                    child: Text(t.actionCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_ctrl.text),
                    child: Text(t.actionSave),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
