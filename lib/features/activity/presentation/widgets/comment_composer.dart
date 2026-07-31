import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/app/di/injection.dart';
import 'package:intellipilot/core/models/user_ref.dart';
import 'package:intellipilot/core/storage/hive_boxes.dart';
import 'package:intellipilot/core/ui/markdown_editor.dart';
import 'package:intellipilot/features/activity/presentation/cubits/activity_stream_cubit.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// Composer that autosaves the in-progress comment to the [HiveBoxes.drafts]
/// box every 3s and restores it on mount. The draft is cleared on successful
/// post.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    required this.draftKey,
    required this.busy,
    this.members = const {},
    this.onUploadImage,
    super.key,
  });
  final String draftKey;
  final bool busy;

  /// Mention candidates keyed by lowercase handle.
  final Map<String, UserRef> members;

  /// Enables pasting screenshots straight into a comment.
  final ImageUploader? onUploadImage;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  static const _flushEvery = Duration(seconds: 3);

  late final TextEditingController _ctrl;
  late final KeyValueStorage _store;
  Timer? _flushTimer;
  bool _restoredNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _store = getIt<KeyValueStorage>(instanceName: HiveBoxes.drafts);
    final saved = _store.get<String>(widget.draftKey);
    _ctrl = TextEditingController(text: saved ?? '');
    // The editor owns its own TextField, so autosave hangs off the controller
    // rather than an onChanged callback.
    _ctrl.addListener(_scheduleFlush);
    if (saved != null && saved.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _restoredNoticeShown) return;
        _restoredNoticeShown = true;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commentDraftRestored),
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _ctrl.removeListener(_scheduleFlush);
    // Best-effort flush on dispose so the user doesn't lose the last edit.
    _flush();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushEvery, _flush);
  }

  void _flush() {
    final body = _ctrl.text;
    if (body.trim().isEmpty) {
      unawaited(_store.remove(widget.draftKey));
    } else {
      unawaited(_store.set<String>(widget.draftKey, body));
    }
  }

  Future<void> _submit() async {
    final cubit = context.read<ActivityStreamCubit>();
    final body = _ctrl.text;
    if (body.trim().isEmpty) return;
    final ok = await cubit.postComment(body);
    if (ok) {
      _ctrl.clear();
      _flushTimer?.cancel();
      await _store.remove(widget.draftKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: MarkdownEditor(
              controller: _ctrl,
              members: widget.members,
              onUploadImage: widget.onUploadImage,
              minLines: 2,
              onSubmitShortcut: widget.busy ? null : () => unawaited(_submit()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: widget.busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            onPressed: widget.busy ? null : _submit,
            label: Text(AppLocalizations.of(context).commentPostAction),
          ),
        ],
      ),
    );
  }
}
